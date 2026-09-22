// LilyPondNote Packageの作成・検証・読書きを一元管理する。

import Foundation

struct LilyPondNotePackageStore {
    static let metadataFileName = "note.json"
    static let rootScoresDirectoryName = "Scores"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    /// Noteのディレクトリと初期ファイルを作成する。
    func createPackage(
        for document: LilyPondNoteDocument,
        at packageURL: URL
    ) throws {
        try validateDocument(document)
        try fileManager.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )

        let rootScoresURL = rootScoresDirectoryURL(in: packageURL)
        try fileManager.createDirectory(
            at: rootScoresURL,
            withIntermediateDirectories: true
        )

        try createMissingFileSets(for: document.scores, in: rootScoresURL)
        try saveMetadata(for: document, at: packageURL)
    }

    /// Package内のメタデータを読み取り、文書モデルへ復元する。
    func loadDocument(from packageURL: URL) throws -> LilyPondNoteDocument {
        let data = try Data(contentsOf: metadataURL(in: packageURL))
        let document = try decoder.decode(LilyPondNoteDocument.self, from: data)
        try validateDocument(document)
        return document
    }

    /// 文書モデルを検証し、Packageのメタデータへ保存する。
    func saveMetadata(
        for document: LilyPondNoteDocument,
        at packageURL: URL
    ) throws {
        try validateDocument(document)
        let data = try encoder.encode(document)
        try data.write(to: metadataURL(in: packageURL), options: .atomic)
    }

    /// 指定IDの楽譜に対応するファイル群の場所を探す。
    func fileSet(
        for scoreID: UUID,
        in document: LilyPondNoteDocument,
        packageURL: URL
    ) -> ScoreFileSet? {
        locateFileSet(
            for: scoreID,
            among: document.scores,
            in: rootScoresDirectoryURL(in: packageURL)
        )
    }

    /// 入力または対象の有効性を確認する。
    func validatePackage(
        for document: LilyPondNoteDocument,
        at packageURL: URL
    ) throws {
        try validateDocument(document)
        try validateFileSets(
            for: document.scores,
            in: rootScoresDirectoryURL(in: packageURL)
        )
    }

    /// 楽譜のLilyPondソースをUTF-8で読み込む。
    func readScoreData(from fileSet: ScoreFileSet) throws -> String {
        try String(contentsOf: fileSet.scoreDataURL, encoding: .utf8)
    }

    /// 楽譜の処理手続きファイルをUTF-8で読み込む。
    func readProcessingProgram(from fileSet: ScoreFileSet) throws -> String {
        try String(contentsOf: fileSet.processingProgramURL, encoding: .utf8)
    }

    /// 生成済みPDFがあればデータを読み込む。
    func readPDF(from fileSet: ScoreFileSet) throws -> Data? {
        guard fileManager.fileExists(atPath: fileSet.pdfURL.path) else {
            return nil
        }
        return try Data(contentsOf: fileSet.pdfURL)
    }

    /// 生成したPDFデータを楽譜の保存先へ書き込む。
    func writePDF(_ data: Data, to fileSet: ScoreFileSet) throws {
        try data.write(to: fileSet.pdfURL, options: .atomic)
    }

    /// 保存済みのコンパイルログを読み込む。
    func readCompileLog(from fileSet: ScoreFileSet) throws -> String {
        guard fileManager.fileExists(atPath: fileSet.compileLogURL.path) else {
            return ""
        }
        return try String(contentsOf: fileSet.compileLogURL, encoding: .utf8)
    }

    /// コンパイルログを楽譜の保存先へ書き込む。
    func writeCompileLog(_ log: String, to fileSet: ScoreFileSet) throws {
        try Data(log.utf8).write(to: fileSet.compileLogURL, options: .atomic)
    }

    /// 楽譜に必要なソース・処理手続き・子階層を作成する。
    func createFileSet(
        for score: Score,
        parentID: UUID?,
        in document: LilyPondNoteDocument,
        packageURL: URL,
        scoreData: String = LilyPondTemplates.initialScoreData,
        processingProgram: String = LilyPondTemplates.initialProcessingProgram,
        validatesProcessingProgram: Bool = true
    ) throws -> ScoreFileSet {
        let containerURL: URL
        if let parentID,
           let parent = fileSet(
               for: parentID,
               in: document,
               packageURL: packageURL
           ) {
            containerURL = parent.childrenDirectoryURL
        } else {
            containerURL = rootScoresDirectoryURL(in: packageURL)
        }

        let fileSet = ScoreFileSet(
            directoryURL: containerURL.appendingPathComponent(
                score.id.uuidString,
                isDirectory: true
            )
        )
        try fileManager.createDirectory(
            at: fileSet.childrenDirectoryURL,
            withIntermediateDirectories: true
        )
        do {
            try writeScoreData(scoreData, to: fileSet)
            if validatesProcessingProgram {
                try writeProcessingProgram(processingProgram, to: fileSet)
            } else {
                try Data(processingProgram.utf8).write(
                    to: fileSet.processingProgramURL,
                    options: .atomic
                )
            }
        } catch {
            // 文書へ未登録の不完全な楽譜フォルダをPackage内に残さない。
            try? fileManager.removeItem(at: fileSet.directoryURL)
            throw error
        }
        return fileSet
    }

    /// 対象データまたは保持状態を削除する。
    func removeFileSetPromotingChildren(
        for scoreID: UUID,
        in document: LilyPondNoteDocument,
        packageURL: URL
    ) throws {
        guard let fileSet = fileSet(
            for: scoreID,
            in: document,
            packageURL: packageURL
        ) else { return }

        let destinationDirectory = fileSet.directoryURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: fileSet.childrenDirectoryURL.path) {
            for childURL in try fileManager.contentsOfDirectory(
                at: fileSet.childrenDirectoryURL,
                includingPropertiesForKeys: nil
            ) {
                let destination = destinationDirectory.appendingPathComponent(
                    childURL.lastPathComponent,
                    isDirectory: true
                )
                try fileManager.moveItem(at: childURL, to: destination)
            }
        }
        try fileManager.removeItem(at: fileSet.directoryURL)
    }

    /// 既存の作業用Packageを置き換えて元のPackageを複製する。
    func copyPackage(from sourceURL: URL, to destinationURL: URL) throws {
        guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL
        else { return }

        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    /// 作業用Packageを持ち運べる保存先へ書き出す。
    func savePortablePackage(
        for document: LilyPondNoteDocument,
        from sourcePackageURL: URL,
        to destinationPackageURL: URL,
        overwriteExisting: Bool
    ) throws {
        try validatePackage(for: document, at: sourcePackageURL)

        if fileManager.fileExists(atPath: destinationPackageURL.path) {
            guard overwriteExisting else {
                throw PackageError.destinationAlreadyExists(destinationPackageURL)
            }
            try fileManager.removeItem(at: destinationPackageURL)
        }
        try fileManager.createDirectory(
            at: destinationPackageURL,
            withIntermediateDirectories: true
        )
        let destinationScoresURL = rootScoresDirectoryURL(
            in: destinationPackageURL
        )
        try fileManager.createDirectory(
            at: destinationScoresURL,
            withIntermediateDirectories: true
        )
        try writeFileSets(
            for: document.scores,
            from: rootScoresDirectoryURL(in: sourcePackageURL),
            to: destinationScoresURL
        )
        try saveMetadata(for: document, at: destinationPackageURL)
    }

    /// 文書階層に対応する楽譜ファイル群を書き出す。
    private func writeFileSets(
        for scores: [Score],
        from sourceScoresURL: URL,
        to destinationScoresURL: URL
    ) throws {
        for score in scores {
            let source = ScoreFileSet(
                directoryURL: sourceScoresURL.appendingPathComponent(
                    score.id.uuidString,
                    isDirectory: true
                )
            )
            let destination = ScoreFileSet(
                directoryURL: destinationScoresURL.appendingPathComponent(
                    score.id.uuidString,
                    isDirectory: true
                )
            )
            try fileManager.createDirectory(
                at: destination.childrenDirectoryURL,
                withIntermediateDirectories: true
            )
            try Data(contentsOf: source.scoreDataURL).write(
                to: destination.scoreDataURL,
                options: .atomic
            )
            try Data(contentsOf: source.processingProgramURL).write(
                to: destination.processingProgramURL,
                options: .atomic
            )
            if fileManager.fileExists(atPath: source.pdfURL.path) {
                try Data(contentsOf: source.pdfURL).write(
                    to: destination.pdfURL,
                    options: .atomic
                )
            }
            if fileManager.fileExists(atPath: source.compileLogURL.path) {
                try Data(contentsOf: source.compileLogURL).write(
                    to: destination.compileLogURL,
                    options: .atomic
                )
            }
            try writeFileSets(
                for: score.children,
                from: source.childrenDirectoryURL,
                to: destination.childrenDirectoryURL
            )
        }
    }

    /// 選択楽譜のファイル群を指定ディレクトリへ書き出す。
    func exportFileSet(_ fileSet: ScoreFileSet, to directoryURL: URL) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for source in [
            fileSet.scoreDataURL,
            fileSet.processingProgramURL,
            fileSet.pdfURL,
            fileSet.compileLogURL
        ] {
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = directoryURL.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    /// LilyPondソースを楽譜ファイルへ保存する。
    func writeScoreData(_ source: String, to fileSet: ScoreFileSet) throws {
        try Data(source.utf8).write(to: fileSet.scoreDataURL, options: .atomic)
    }

    /// 処理手続きのLilyPondソースを保存する。
    func writeProcessingProgram(
        _ source: String,
        to fileSet: ScoreFileSet
    ) throws {
        guard Self.includesLocalScoreData(source) else {
            throw PackageError.processingProgramDoesNotIncludeScoreData(
                fileSet.processingProgramURL
            )
        }

        try Data(source.utf8).write(
            to: fileSet.processingProgramURL,
            options: .atomic
        )
    }

    /// 入力または対象の有効性を確認する。
    static func includesLocalScoreData(_ processingProgram: String) -> Bool {
        processingProgram.split(separator: "\n").contains { line in
            line.trimmingCharacters(in: .whitespaces)
                == "\\include \"\(ScoreFileSet.scoreDataFileName)\""
        }
    }

    /// 文書階層に不足している楽譜ファイル群を作成する。
    private func createMissingFileSets(
        for scores: [Score],
        in scoresDirectoryURL: URL
    ) throws {
        for score in scores {
            let fileSet = ScoreFileSet(
                directoryURL: scoresDirectoryURL.appendingPathComponent(
                    score.id.uuidString,
                    isDirectory: true
                )
            )

            try fileManager.createDirectory(
                at: fileSet.childrenDirectoryURL,
                withIntermediateDirectories: true
            )

            if !fileManager.fileExists(atPath: fileSet.scoreDataURL.path) {
                try writeScoreData(
                    LilyPondTemplates.initialScoreData,
                    to: fileSet
                )
            }

            if !fileManager.fileExists(
                atPath: fileSet.processingProgramURL.path
            ) {
                try writeProcessingProgram(
                    LilyPondTemplates.initialProcessingProgram,
                    to: fileSet
                )
            }

            try createMissingFileSets(
                for: score.children,
                in: fileSet.childrenDirectoryURL
            )
        }
    }

    /// 入力または対象の有効性を確認する。
    private func locateFileSet(
        for scoreID: UUID,
        among scores: [Score],
        in scoresDirectoryURL: URL
    ) -> ScoreFileSet? {
        for score in scores {
            let fileSet = ScoreFileSet(
                directoryURL: scoresDirectoryURL.appendingPathComponent(
                    score.id.uuidString,
                    isDirectory: true
                )
            )

            if score.id == scoreID {
                return fileSet
            }

            if let match = locateFileSet(
                for: scoreID,
                among: score.children,
                in: fileSet.childrenDirectoryURL
            ) {
                return match
            }
        }

        return nil
    }

    /// 入力または対象の有効性を確認する。
    private func validateDocument(_ document: LilyPondNoteDocument) throws {
        guard document.schemaVersion == LilyPondNoteDocument.currentSchemaVersion
        else {
            throw PackageError.unsupportedSchemaVersion(document.schemaVersion)
        }

        var scoreIDs = Set<UUID>()
        try validateUniqueIDs(in: document.scores, collectedIDs: &scoreIDs)
    }

    /// 入力または対象の有効性を確認する。
    private func validateUniqueIDs(
        in scores: [Score],
        collectedIDs: inout Set<UUID>
    ) throws {
        for score in scores {
            guard collectedIDs.insert(score.id).inserted else {
                throw PackageError.duplicateScoreID(score.id)
            }
            try validateUniqueIDs(
                in: score.children,
                collectedIDs: &collectedIDs
            )
        }
    }

    /// 入力または対象の有効性を確認する。
    private func validateFileSets(
        for scores: [Score],
        in scoresDirectoryURL: URL
    ) throws {
        for score in scores {
            let fileSet = ScoreFileSet(
                directoryURL: scoresDirectoryURL.appendingPathComponent(
                    score.id.uuidString,
                    isDirectory: true
                )
            )

            try requireItem(at: fileSet.directoryURL, isDirectory: true)
            try requireItem(at: fileSet.scoreDataURL, isDirectory: false)
            try requireItem(
                at: fileSet.processingProgramURL,
                isDirectory: false
            )
            try requireItem(at: fileSet.childrenDirectoryURL, isDirectory: true)

            let program = try readProcessingProgram(from: fileSet)
            guard Self.includesLocalScoreData(program) else {
                throw PackageError.processingProgramDoesNotIncludeScoreData(
                    fileSet.processingProgramURL
                )
            }

            try validateFileSets(
                for: score.children,
                in: fileSet.childrenDirectoryURL
            )
        }
    }

    /// 入力または対象の有効性を確認する。
    private func requireItem(at url: URL, isDirectory: Bool) throws {
        var actualIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: url.path,
            isDirectory: &actualIsDirectory
        ), actualIsDirectory.boolValue == isDirectory else {
            throw PackageError.missingRequiredItem(url)
        }
    }

    /// Package内のメタデータファイルの場所を返す。
    private func metadataURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(Self.metadataFileName)
    }

    /// Package内のroot楽譜ディレクトリの場所を返す。
    private func rootScoresDirectoryURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(
            Self.rootScoresDirectoryName,
            isDirectory: true
        )
    }
}

extension LilyPondNotePackageStore {
    enum PackageError: LocalizedError, Equatable {
        case unsupportedSchemaVersion(Int)
        case duplicateScoreID(UUID)
        case missingRequiredItem(URL)
        case processingProgramDoesNotIncludeScoreData(URL)
        case destinationAlreadyExists(URL)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let version):
                String(format: String(localized: "package.schema.error"), Int64(version))
            case .duplicateScoreID(let id):
                String(format: String(localized: "package.duplicateScoreID"), id.uuidString)
            case .missingRequiredItem(let url):
                String(format: String(localized: "package.missingItem"), url.lastPathComponent)
            case .processingProgramDoesNotIncludeScoreData(let url):
                String(
                    format: String(localized: "package.missingScoreInclude"),
                    url.lastPathComponent
                )
            case .destinationAlreadyExists(let url):
                String(format: String(localized: "package.sameName"), url.lastPathComponent)
            }
        }
    }
}
