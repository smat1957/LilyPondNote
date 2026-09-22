// 文書、選択楽譜、保存状態、PDF生成状態をまとめて管理する作業領域を定義する。

import Combine
import Foundation

enum StartupLoadingPhase: Sendable {
    case locating
    case validating
    case copying
    case opening

    var message: String {
        switch self {
        case .locating: String(localized: "前回のNoteを確認しています…")
        case .validating: String(localized: "Noteの内容を確認しています…")
        case .copying: String(localized: "Noteを読み込んでいます…")
        case .opening: String(localized: "楽譜を開いています…")
        }
    }
}

private struct StartupRestoreError: Error, Sendable {
    let message: String
}

private struct PreparedStartupRestore: Sendable {
    struct SelectedScore: Sendable {
        let id: UUID
        let source: String
        let processingProgram: String
        let pdfData: Data?
        let errorLog: String
    }

    let document: LilyPondNoteDocument
    let sourceURL: URL
    let workingURL: URL
    let selectedScore: SelectedScore?
}

@MainActor
final class LilyPondNoteWorkspace: ObservableObject {
    @Published private(set) var startupLoadingPhase: StartupLoadingPhase?
    @Published private(set) var document: LilyPondNoteDocument
    @Published private(set) var selectedScoreID: UUID?
    @Published private(set) var scoreSource = ""
    @Published private(set) var processingProgram = ""
    @Published private(set) var pdfData: Data?
    @Published private(set) var errorLog = ""
    @Published private(set) var isCompiling = false
    @Published private(set) var pdfNeedsRegeneration = false
    @Published private(set) var savedPackageURL: URL?
    @Published private(set) var hasUnsavedChanges = false

    private let store: LilyPondNotePackageStore
    private let fileManager: FileManager
    private var compiler: (any LilyPondCompiling)?
    private var workingPackageURL: URL
    private var hasStartedStartupRestore = false

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(
        compiler: (any LilyPondCompiling)?,
        fileManager: FileManager = .default,
        restoresOnInitialization: Bool = true
    ) {
        self.compiler = compiler
        self.fileManager = fileManager
        self.store = LilyPondNotePackageStore(fileManager: fileManager)
        let initialDocument = LilyPondNoteDocument(title: "LilyPondNote")
        self.document = initialDocument
        self.workingPackageURL = Self.workingURL(
            for: initialDocument.id,
            fileManager: fileManager
        )
        if restoresOnInitialization {
            restoreLastPackageOrCreateEmptyNote()
        } else {
            startupLoadingPhase = .locating
        }
    }

    /// iOSでは画面を表示してから、前回のNoteをバックグラウンドで復元する。
    func restoreAtLaunch() async {
        guard !hasStartedStartupRestore, startupLoadingPhase != nil else { return }
        hasStartedStartupRestore = true

        let result = await Task.detached(priority: .userInitiated) {
            do {
                return Result<PreparedStartupRestore?, StartupRestoreError>.success(
                    try await Self.prepareStartupRestore { phase in
                        await MainActor.run { self.startupLoadingPhase = phase }
                    }
                )
            } catch {
                return .failure(StartupRestoreError(message: error.localizedDescription))
            }
        }.value

        switch result {
        case .success(let prepared?):
            document = prepared.document
            workingPackageURL = prepared.workingURL
            savedPackageURL = prepared.sourceURL
            hasUnsavedChanges = false
            if let selected = prepared.selectedScore {
                selectedScoreID = selected.id
                scoreSource = selected.source
                processingProgram = selected.processingProgram
                pdfData = selected.pdfData
                errorLog = selected.errorLog
                pdfNeedsRegeneration = false
            } else {
                clearSelection()
            }
        case .success(nil):
            do {
                try createEmptyInitialNote()
            } catch {
                errorLog = error.localizedDescription
            }
        case .failure(let error):
            PackageBookmarkStore.clear()
            do {
                try createEmptyInitialNote()
                errorLog = String(localized: "最後に開いたPackageを復元できませんでした。")
                    + "\n" + error.message
            } catch {
                errorLog = error.localizedDescription
            }
        }
        startupLoadingPhase = nil
    }

    /// ブックマーク先を検証・複製し、画面へ反映するデータを別スレッドで準備する。
    nonisolated private static func prepareStartupRestore(
        progress: @Sendable (StartupLoadingPhase) async -> Void
    ) async throws -> PreparedStartupRestore? {
        guard let resolved = try PackageBookmarkStore.resolve() else { return nil }
        let accessURLs = [resolved.accessRootURL, resolved.packageURL]
        var accessedURLs: [URL] = []
        var accessedPaths: Set<String> = []
        for url in accessURLs {
            guard accessedPaths.insert(url.standardizedFileURL.path).inserted else { continue }
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
        }
        defer {
            for url in accessedURLs.reversed() {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager()
        guard fileManager.fileExists(atPath: resolved.packageURL.path) else {
            PackageBookmarkStore.clear()
            return nil
        }
        let store = LilyPondNotePackageStore(fileManager: fileManager)
        await progress(.validating)
        var document = try store.loadDocument(from: resolved.packageURL)
        try store.validatePackage(for: document, at: resolved.packageURL)
        let workingURL = workingURL(for: document.id, fileManager: fileManager)
        await progress(.copying)
        try store.copyPackage(from: resolved.packageURL, to: workingURL)
        await progress(.opening)
        let selectedScore: PreparedStartupRestore.SelectedScore?
        if let first = document.scores.first {
            guard let files = store.fileSet(
                for: first.id,
                in: document,
                packageURL: workingURL
            ) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            selectedScore = .init(
                id: first.id,
                source: try store.readScoreData(from: files),
                processingProgram: try store.readProcessingProgram(from: files),
                pdfData: try store.readPDF(from: files),
                errorLog: try store.readCompileLog(from: files)
            )
        } else {
            selectedScore = nil
        }
        if let selectedScore,
           document.score(withID: selectedScore.id)?.compilerVersion == nil,
           let pdfData = selectedScore.pdfData,
           let version = LilyPondCompilerVersion.detected(inPDF: pdfData),
           document.setCompilerVersion(version, for: selectedScore.id) {
            try store.saveMetadata(for: document, at: workingURL)
        }
        return PreparedStartupRestore(
            document: document,
            sourceURL: resolved.packageURL,
            workingURL: workingURL,
            selectedScore: selectedScore
        )
    }

    var selectedScore: Score? {
        guard let selectedScoreID else { return nil }
        return document.score(withID: selectedScoreID)
    }

    var selectedRootScore: Score? {
        guard let selectedScoreID else { return nil }
        return document.rootScore(containing: selectedScoreID)
    }

    /// ログイン時はリモートコンパイラを設定し、ログアウト時はnilへ戻す。
    func configureCompiler(_ compiler: (any LilyPondCompiling)?) {
        self.compiler = compiler
        errorLog = ""
    }

    /// 空のNoteを作成し、現在の作業対象へ切り替える。
    func newNote(title: String = String(localized: "名称未設定")) throws {
        let newDocument = LilyPondNoteDocument(title: title)
        let url = Self.workingURL(for: newDocument.id, fileManager: fileManager)
        try store.createPackage(for: newDocument, at: url)
        document = newDocument
        workingPackageURL = url
        savedPackageURL = nil
        hasUnsavedChanges = false
        clearSelection()
        PackageBookmarkStore.clear()
    }

    /// Note名を検証してメタデータへ保存する。
    func renameNote(to title: String) throws {
        let normalized = try validatedNoteName(title)
        guard normalized != document.title else { return }
        document.title = normalized
        try store.saveMetadata(for: document, at: workingPackageURL)
        hasUnsavedChanges = true
    }

    /// 選択中の楽譜名を更新し、メタデータへ保存する。
    func renameSelectedScore(to title: String) throws {
        guard let selectedScoreID else { throw WorkspaceError.scoreIsNotSelected }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw WorkspaceError.invalidScoreName }
        if document.score(withID: selectedScoreID)?.title == normalized { return }
        guard document.renameScore(withID: selectedScoreID, to: normalized) else {
            throw WorkspaceError.scoreNotFound(selectedScoreID)
        }
        try store.saveMetadata(for: document, at: workingPackageURL)
        hasUnsavedChanges = true
    }

    @discardableResult
    /// 入力または対象の有効性を確認する。
    func validatedNoteName(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.contains("/"),
              !normalized.contains(":") else {
            throw WorkspaceError.invalidNoteName
        }
        return normalized
    }

    @discardableResult
    /// 新しいroot楽譜とファイル群を作成して選択する。
    func createRootScore(title: String) throws -> UUID {
        let score = Score(title: title)
        _ = try store.createFileSet(
            for: score,
            parentID: nil,
            in: document,
            packageURL: workingPackageURL
        )
        document.appendRootScore(score)
        try store.saveMetadata(for: document, at: workingPackageURL)
        try selectScore(score.id)
        hasUnsavedChanges = true
        return score.id
    }

    @discardableResult
    /// 読み込んだ楽譜データと処理手続きをroot楽譜として追加する。
    func importRootScore(
        title: String,
        scoreSource: String,
        processingProgram: String,
        validatesProcessingProgram: Bool = true
    ) throws -> UUID {
        let score = Score(title: title)
        _ = try store.createFileSet(
            for: score,
            parentID: nil,
            in: document,
            packageURL: workingPackageURL,
            scoreData: scoreSource,
            processingProgram: processingProgram,
            validatesProcessingProgram: validatesProcessingProgram
        )
        document.appendRootScore(score)
        try store.saveMetadata(for: document, at: workingPackageURL)
        try selectScore(score.id)
        hasUnsavedChanges = true
        return score.id
    }

    @discardableResult
    /// 選択中の楽譜の下に子楽譜とファイル群を作成する。
    func createChildScore(
        title: String,
        scoreSource: String? = nil,
        processingProgram: String? = nil,
        validatesProcessingProgram: Bool = true
    ) throws -> UUID {
        guard let parentID = selectedScoreID else {
            throw WorkspaceError.scoreIsNotSelected
        }
        let child = Score(title: title)
        _ = try store.createFileSet(
            for: child,
            parentID: parentID,
            in: document,
            packageURL: workingPackageURL,
            scoreData: scoreSource ?? self.scoreSource,
            processingProgram: processingProgram ?? self.processingProgram,
            validatesProcessingProgram: validatesProcessingProgram
        )
        guard document.appendChildScore(child, to: parentID) else {
            throw WorkspaceError.scoreNotFound(parentID)
        }
        try store.saveMetadata(for: document, at: workingPackageURL)
        try selectScore(child.id)
        hasUnsavedChanges = true
        return child.id
    }

    /// 対象データまたは保持状態を削除する。
    func deleteSelectedScore() throws {
        guard let scoreID = selectedScoreID else {
            throw WorkspaceError.scoreIsNotSelected
        }
        try deleteScore(scoreID)
    }

    /// 対象データまたは保持状態を削除する。
    func deleteScore(_ scoreID: UUID) throws {
        guard document.score(withID: scoreID) != nil else {
            throw WorkspaceError.scoreNotFound(scoreID)
        }
        let previousSelection = selectedScoreID
        let oldDocument = document
        try store.removeFileSetPromotingChildren(
            for: scoreID,
            in: oldDocument,
            packageURL: workingPackageURL
        )
        guard document.removeScorePromotingChildren(withID: scoreID) != nil else {
            throw WorkspaceError.scoreNotFound(scoreID)
        }
        try store.saveMetadata(for: document, at: workingPackageURL)
        if let previousSelection,
           document.score(withID: previousSelection) != nil {
            try selectScore(previousSelection)
        } else if let first = document.scores.first {
            try selectScore(first.id)
        } else {
            clearSelection()
        }
        hasUnsavedChanges = true
    }

    /// root楽譜を指定位置へ並べ替える。
    func moveRootScores(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        document.moveRootScores(fromOffsets: source, toOffset: destination)
        try store.saveMetadata(for: document, at: workingPackageURL)
        hasUnsavedChanges = true
    }

    /// 同じ親を持つ楽譜の順序を更新して保存する。
    func moveScoresWithinGroup(
        parentID: UUID,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) throws {
        guard document.moveChildScores(
            of: parentID,
            fromOffsets: source,
            toOffset: destination
        ) else {
            throw WorkspaceError.scoreNotFound(parentID)
        }
        try store.saveMetadata(for: document, at: workingPackageURL)
        hasUnsavedChanges = true
    }

    /// 楽譜を選択し、そのソース・PDF・ログを作業状態へ読み込む。
    func selectScore(_ scoreID: UUID) throws {
        guard document.score(withID: scoreID) != nil,
              let fileSet = store.fileSet(
                for: scoreID,
                in: document,
                packageURL: workingPackageURL
              ) else {
            throw WorkspaceError.scoreNotFound(scoreID)
        }
        selectedScoreID = scoreID
        scoreSource = try store.readScoreData(from: fileSet)
        processingProgram = try store.readProcessingProgram(from: fileSet)
        pdfData = try store.readPDF(from: fileSet)
        errorLog = try store.readCompileLog(from: fileSet)
        if document.score(withID: scoreID)?.compilerVersion == nil,
           let pdfData,
           let version = LilyPondCompilerVersion.detected(inPDF: pdfData),
           document.setCompilerVersion(version, for: scoreID) {
            try store.saveMetadata(for: document, at: workingPackageURL)
        }
        pdfNeedsRegeneration = false
    }

    /// 編集した楽譜ソースと処理手続きを作業用Packageへ保存する。
    func saveScore(scoreSource: String, processingProgram: String) throws {
        let fileSet = try selectedFileSet()
        try store.writeScoreData(scoreSource, to: fileSet)
        try store.writeProcessingProgram(processingProgram, to: fileSet)
        self.scoreSource = scoreSource
        self.processingProgram = processingProgram
        pdfNeedsRegeneration = true
        errorLog = ""
        hasUnsavedChanges = true
    }

    /// 指定Packageを開き、次回復元用のブックマークを保存する。
    func openPackage(at sourceURL: URL) throws {
        try loadPackage(at: sourceURL)
        try PackageBookmarkStore.save(sourceURL)
    }

    /// Packageを検証・複製し、先頭楽譜を選択する。
    private func loadPackage(at sourceURL: URL) throws {
        let openedDocument = try store.loadDocument(from: sourceURL)
        try store.validatePackage(for: openedDocument, at: sourceURL)
        let workingURL = Self.workingURL(
            for: openedDocument.id,
            fileManager: fileManager
        )
        try store.copyPackage(from: sourceURL, to: workingURL)
        document = openedDocument
        workingPackageURL = workingURL
        savedPackageURL = sourceURL
        hasUnsavedChanges = false
        if let first = openedDocument.scores.first {
            try selectScore(first.id)
        } else {
            clearSelection()
        }
    }

    /// 作業用Packageを指定名で保存し、現在の保存先を更新する。
    func savePackageAs(
        to destinationURL: URL,
        noteTitle: String,
        overwriteExisting: Bool = false
    ) throws {
        let normalized = try validatedNoteName(noteTitle)
        let oldTitle = document.title
        document.title = normalized
        do {
            try store.saveMetadata(for: document, at: workingPackageURL)
            try store.savePortablePackage(
                for: document,
                from: workingPackageURL,
                to: destinationURL,
                overwriteExisting: overwriteExisting
            )
            savedPackageURL = destinationURL
            hasUnsavedChanges = false
            try PackageBookmarkStore.save(
                packageURL: destinationURL,
                accessRootURL: destinationURL.deletingLastPathComponent()
            )
        } catch {
            document.title = oldTitle
            try? store.saveMetadata(for: document, at: workingPackageURL)
            throw error
        }
    }

    /// 選択中の楽譜ファイル群を指定先へ書き出す。
    func exportSelectedScore(to destinationURL: URL) throws {
        let fileSet = try selectedFileSet()
        try store.exportFileSet(fileSet, to: destinationURL)
    }

    /// 現在のコンパイラでPDFを生成し、結果とログを保存する。
    func generatePDF(scoreSource: String, processingProgram: String) async -> Bool {
        guard !isCompiling else { return false }
        guard let compiler else {
            errorLog = String(localized: "LilyPondの実行設定が必要です。")
            return false
        }

        isCompiling = true
        defer { isCompiling = false }
        do {
            let scoreID = try requireSelectedScoreID()
            let result = try await compiler.compile(
                LilyPondCompilationInput(
                    scoreID: scoreID,
                    processingProgram: processingProgram,
                    scoreData: scoreSource
                )
            )
            try saveScore(
                scoreSource: scoreSource,
                processingProgram: processingProgram
            )
            let fileSet = try selectedFileSet()
            try store.writePDF(result.pdfData, to: fileSet)
            let persistentLog = result.log.isEmpty
                ? String(localized: "コンパイルは正常に完了しました。")
                : result.log
            try store.writeCompileLog(persistentLog, to: fileSet)
            guard document.setCompilerVersion(
                result.compilerVersion,
                for: scoreID
            ) else {
                throw WorkspaceError.scoreNotFound(scoreID)
            }
            try store.saveMetadata(for: document, at: workingPackageURL)
            pdfData = result.pdfData
            errorLog = persistentLog
            pdfNeedsRegeneration = false
            return true
        } catch {
            errorLog = error.localizedDescription
            if let fileSet = try? selectedFileSet() {
                try? store.writeCompileLog(errorLog, to: fileSet)
            }
            return false
        }
    }

    /// 前回のPackageを復元し、失敗時は空のNoteを用意する。
    private func restoreLastPackageOrCreateEmptyNote() {
        do {
            guard let resolved = try PackageBookmarkStore.resolve() else {
                try createEmptyInitialNote()
                return
            }
            let accessURLs = [resolved.accessRootURL, resolved.packageURL]
            var accessedURLs: [URL] = []
            var accessedPaths: Set<String> = []
            for url in accessURLs {
                let path = url.standardizedFileURL.path
                guard accessedPaths.insert(path).inserted else { continue }
                if url.startAccessingSecurityScopedResource() {
                    accessedURLs.append(url)
                }
            }
            defer {
                for url in accessedURLs.reversed() {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard fileManager.fileExists(atPath: resolved.packageURL.path) else {
                PackageBookmarkStore.clear()
                try createEmptyInitialNote()
                return
            }
            try loadPackage(at: resolved.packageURL)
        } catch {
            PackageBookmarkStore.clear()
            do {
                try createEmptyInitialNote()
                errorLog = String(localized: "最後に開いたPackageを復元できませんでした。") + "\n"
                    + error.localizedDescription
            } catch {
                errorLog = error.localizedDescription
            }
        }
    }

    /// 初期表示用の空のNoteと作業用Packageを作る。
    private func createEmptyInitialNote() throws {
        let initialDocument = LilyPondNoteDocument(title: String(localized: "名称未設定"))
        let url = Self.workingURL(for: initialDocument.id, fileManager: fileManager)
        try store.createPackage(for: initialDocument, at: url)
        document = initialDocument
        workingPackageURL = url
        savedPackageURL = nil
        hasUnsavedChanges = false
        clearSelection()
    }

    /// 選択中の楽譜に対応するファイル群を取得する。
    private func selectedFileSet() throws -> ScoreFileSet {
        let scoreID = try requireSelectedScoreID()
        guard let fileSet = store.fileSet(
            for: scoreID,
            in: document,
            packageURL: workingPackageURL
        ) else { throw WorkspaceError.scoreNotFound(scoreID) }
        return fileSet
    }

    /// 入力または対象の有効性を確認する。
    private func requireSelectedScoreID() throws -> UUID {
        guard let selectedScoreID else { throw WorkspaceError.scoreIsNotSelected }
        return selectedScoreID
    }

    /// 対象データまたは保持状態を削除する。
    private func clearSelection() {
        selectedScoreID = nil
        scoreSource = ""
        processingProgram = ""
        pdfData = nil
        errorLog = ""
        pdfNeedsRegeneration = false
    }

    /// 文書IDから作業用Packageの保存先を組み立てる。
    nonisolated private static func workingURL(
        for documentID: UUID,
        fileManager: FileManager
    ) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "LilyPondNote/Working", directoryHint: .isDirectory)
            .appending(path: documentID.uuidString, directoryHint: .isDirectory)
    }
}

extension LilyPondNoteWorkspace {
    enum WorkspaceError: LocalizedError {
        case scoreIsNotSelected
        case scoreNotFound(UUID)
        case invalidNoteName
        case invalidScoreName

        var errorDescription: String? {
            switch self {
            case .scoreIsNotSelected:
                String(localized: "楽譜が選択されていません。")
            case .scoreNotFound(let id):
                String(format: String(localized: "workspace.scoreNotFound"), id.uuidString)
            case .invalidNoteName:
                String(localized: "Note名を入力してください。記号「/」と「:」は使用できません。")
            case .invalidScoreName:
                String(localized: "楽譜名を入力してください。")
            }
        }
    }
}
