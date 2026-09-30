// macOS向けのサイドバー、PDF表示、編集画面、ファイル操作UIを構成する。

import AppKit
import PDFKit
import LilyPondTransposeCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var workspace = LilyPondNoteWorkspace(
        compiler: macOSLocalLilyPondCompiler()
    )
    @State private var isEditing = false
    @State private var currentPDFPage = 1
    @State private var fileOperation: FileOperation?
    @State private var isShowingFileImporter = false
    @State private var isShowingRootScoreImport = false
    @State private var isNamingRootScore = false
    @State private var newRootTitle = ""
    @State private var isShowingAbout = false
    @State private var isShowingServerSettings = false
    @State private var operationError = ""
    @State private var isConfirmingScoreDeletion = false
    @State private var isNamingPackage = false
    @State private var packageName = ""
    @State private var operationMessage = ""
    @State private var isConfirmingNewNote = false
    @State private var noteTitleDraft = String(localized: "名称未設定")
    @State private var pendingOverwriteDirectory: URL?
    @State private var isConfirmingOverwrite = false
    @State private var isConfirmingOpen = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var expandedScoreIDs: Set<UUID> = []
    @FocusState private var isNoteTitleFocused: Bool

    private enum FileOperation: Equatable {
        case openPackage, savePackageAs, exportScore
        var contentTypes: [UTType] { [.folder] }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List {
                    ForEach(workspace.document.scores) { score in
                        macOSScoreTreeRow(
                            score: score,
                            selectedScoreID: workspace.selectedScoreID,
                            expandedScoreIDs: $expandedScoreIDs,
                            select: selectScore,
                            moveChildren: moveChildScores
                        )
                    }
                    .onMove(perform: moveRootScores)
                }
                Divider()
                HStack {
                    Button("新規作成", systemImage: "plus") {
                        newRootTitle = ""
                        isNamingRootScore = true
                    }
                    Spacer()
                    Button("インポート", systemImage: "square.and.arrow.down.on.square") {
                        isShowingRootScoreImport = true
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle(workspace.document.title)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 310)
        } detail: {
            VStack(spacing: 0) {
                noteTitleBar
                Divider()
                scoreTitleBar
                Divider()
                pdfContent
            }
            .background(.background)
        }
        .navigationSplitViewStyle(.balanced)
        .task { await workspace.restoreAtLaunch() }
        .background {
            macOSArrowKeyMonitor(
                isEnabled: isSidebarKeyboardNavigationEnabled,
                onMove: moveSidebarSelection
            )
        }
        .overlay {
            if let phase = workspace.startupLoadingPhase {
                macOSStartupLoadingView(phase: phase)
            }
        }
        .sheet(isPresented: $isEditing) {
            macOSScoreEditorView(workspace: workspace)
                .frame(minWidth: 900, minHeight: 650)
        }
        .sheet(isPresented: $isShowingServerSettings) {
            macOSServerSettingsView()
                .frame(minWidth: 500, minHeight: 430)
        }
        .sheet(isPresented: $isShowingAbout) {
            LilyPondAboutView()
                .frame(minWidth: 460, minHeight: 340)
        }
        .sheet(isPresented: $isShowingRootScoreImport) {
            macOSScoreImportView(
                workspace: workspace,
                destination: .root,
                onImported: { currentPDFPage = 1 }
            )
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: fileOperation?.contentTypes ?? [.folder]
        ) { handleFileSelection($0) }
        .alert("新しい楽譜グループ", isPresented: $isNamingRootScore) {
            TextField("楽譜名", text: $newRootTitle)
            Button("作成") { createRootScore() }
            Button("キャンセル", role: .cancel) {}
        }
        .alert(newNoteConfirmationTitle, isPresented: $isConfirmingNewNote) {
            Button("新しいNoteにする", role: .destructive) {
                perform { try workspace.newNote() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(newNoteConfirmationMessage)
        }
        .alert("操作できません", isPresented: Binding(
            get: { !operationError.isEmpty },
            set: { if !$0 { operationError = "" } }
        )) { Button("OK") { operationError = "" } } message: { Text(operationError) }
        .alert("楽譜を削除しますか？", isPresented: $isConfirmingScoreDeletion) {
            Button("削除", role: .destructive) {
                perform { try workspace.deleteSelectedScore() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(String(
                format: String(localized: "score.delete.message"),
                workspace.selectedScore?.title ?? String(localized: "選択中の楽譜")
            ))
        }
        .alert("Note名を入力", isPresented: $isNamingPackage) {
            TextField("Note名", text: $packageName)
            Button("次へ") { continueSaveAs() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存するPackageの名前を入力してください。記号「/」と「:」は使用できません。")
        }
        .alert("同じ名前のNoteがあります", isPresented: $isConfirmingOverwrite) {
            Button("上書き保存", role: .destructive) { overwritePendingPackage() }
            Button("キャンセル", role: .cancel) {
                pendingOverwriteDirectory = nil
            }
        } message: {
            Text(String(format: String(localized: "note.overwrite.message"), packageName))
        }
        .alert("別のNoteを開きますか？", isPresented: $isConfirmingOpen) {
            Button("開く") { beginFileOperation(.openPackage) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在のNoteを閉じます。未保存の変更が必要な場合は、先に「保存…」を実行してください。")
        }
        .alert("保存しました", isPresented: Binding(
            get: { !operationMessage.isEmpty },
            set: { if !$0 { operationMessage = "" } }
        )) {
            Button("OK") { operationMessage = "" }
        } message: {
            Text(operationMessage)
        }
        .onAppear { noteTitleDraft = workspace.document.title }
        .onChange(of: workspace.document.title) { _, title in noteTitleDraft = title }
    }

    private var noteTitleBar: some View {
        ZStack {
            TextField("Note名", text: $noteTitleDraft)
                .font(.headline)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .focused($isNoteTitleFocused)
                .onSubmit { renameNote() }
                .onChange(of: isNoteTitleFocused) { _, focused in
                    if !focused { renameNote() }
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Spacer()
                if workspace.hasUnsavedChanges {
                    Label("未保存", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Menu {
                    Button("新しいNote") { requestNewNote() }
                    Button("開く…") { requestOpenPackage() }
                    Button("保存…") {
                        packageName = workspace.document.title
                        continueSaveAs()
                    }
                    Button("名前を付けて保存…") {
                        packageName = workspace.document.title
                        isNamingPackage = true
                    }
                    Divider()
                    Button("サービス設定") { isShowingServerSettings = true }
                    Button("LilyPondNoteについて", systemImage: "info.circle") {
                        isShowingAbout = true
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 56)
        .background(.bar)
    }

    private var scoreTitleBar: some View {
        ZStack {
            VStack(spacing: 3) {
                Text(workspace.selectedScore?.title ?? String(localized: "楽譜がありません"))
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: 500)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 1)
                HStack(spacing: 10) {
                    Text(workspace.pdfNeedsRegeneration
                         ? String(localized: "更新待ち")
                         : String(localized: "最新版"))
                        .foregroundStyle(workspace.pdfNeedsRegeneration ? .orange : .green)
                    Text("\(currentPDFPage) / \(pageCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.selectedRootScore?.title ?? workspace.document.title)
                    Text("LilyPond \(workspace.selectedScore?.compilerVersion ?? "—")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                if workspace.selectedScore != nil {
                    Button("編集", systemImage: "pencil") { isEditing = true }
                        .fixedSize()
                        .buttonStyle(.borderless)
                    Menu {
                        Button("印刷", systemImage: "printer") { printPDF() }
                            .disabled(workspace.pdfData == nil)
                        Button("エクスポート", systemImage: "square.and.arrow.up") {
                            beginFileOperation(.exportScore)
                        }
                        Divider()
                        Button("削除", role: .destructive) {
                            isConfirmingScoreDeletion = true
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .clipped()
        .background(.bar)
    }

    @ViewBuilder
    private var pdfContent: some View {
        if let data = workspace.pdfData {
            macOSPDFView(
                data: data,
                currentPage: $currentPDFPage,
                onVerticalSwipe: moveToAdjacentVisibleScore
            )
                .background(.background)
        } else {
            ContentUnavailableView(
                "PDFを表示できません",
                systemImage: "doc.richtext",
                description: Text(workspace.errorLog)
            )
        }
    }

    private var pageCount: Int {
        guard let data = workspace.pdfData else { return 0 }
        return PDFDocument(data: data)?.pageCount ?? 0
    }

    /// 現在表示中のPDF全ページをmacOS標準の印刷ダイアログへ渡す。
    private func printPDF() {
        guard let data = workspace.pdfData,
              let document = PDFDocument(data: data),
              let operation = document.printOperation(
                  for: NSPrintInfo.shared,
                  scalingMode: .pageScaleToFit,
                  autoRotate: true
              ) else { return }
        operation.run()
    }

    /// 入力された名前でroot楽譜を作成し、エラーを画面へ示す。
    private func createRootScore() {
        let title = newRootTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        perform { try workspace.createRootScore(title: title) }
    }

    /// 入力されたNote名を保存し、確定した名前を画面へ戻す。
    private func renameNote() {
        do {
            try workspace.renameNote(to: noteTitleDraft)
            noteTitleDraft = workspace.document.title
        } catch {
            noteTitleDraft = workspace.document.title
            operationError = error.localizedDescription
        }
    }

    /// 指定楽譜を選択し、PDFページまたはエディタ内容を更新する。
    private func selectScore(_ id: UUID) {
        perform { try workspace.selectScore(id) }
        currentPDFPage = 1
    }

    private var isSidebarKeyboardNavigationEnabled: Bool {
        columnVisibility != .detailOnly
            && !isNoteTitleFocused
            && !isEditing
            && !isShowingServerSettings
            && !isShowingAbout
            && !isShowingFileImporter
            && !isNamingRootScore
            && !isNamingPackage
            && !isConfirmingNewNote
            && !isConfirmingScoreDeletion
            && !isConfirmingOverwrite
            && !isConfirmingOpen
            && operationError.isEmpty
            && operationMessage.isEmpty
    }

    /// 上下キーに応じてサイドバーの選択楽譜を移す。
    private func moveSidebarSelection(_ direction: MoveCommandDirection) {
        let scores = workspace.document.scores.flatMap { root in
            root.flattened().map(\.score)
        }
        guard !scores.isEmpty else { return }

        let currentIndex = workspace.selectedScoreID.flatMap { selectedID in
            scores.firstIndex { $0.id == selectedID }
        }
        let destination: Int
        switch direction {
        case .up:
            destination = max(0, (currentIndex ?? 1) - 1)
        case .down:
            destination = min(scores.count - 1, (currentIndex ?? -1) + 1)
        default:
            return
        }
        guard destination != currentIndex else { return }
        selectScore(scores[destination].id)
    }

    /// 展開状態を考慮して隣の楽譜を選択する。
    private func moveToAdjacentVisibleScore(_ offset: Int) {
        let items = ScoreNavigation.visibleItems(in: workspace.document.scores, expandedScoreIDs: expandedScoreIDs)
        guard let targetID = ScoreNavigation.adjacentScoreID(
            in: items,
            selectedScoreID: workspace.selectedScoreID,
            fallbackRootID: workspace.selectedRootScore?.id,
            offset: offset
        ) else { return }
        selectScore(targetID)
    }

    /// ドラッグされたroot楽譜の順序を文書へ反映する。
    private func moveRootScores(from source: IndexSet, to destination: Int) {
        perform {
            try workspace.moveRootScores(
                fromOffsets: source,
                toOffset: destination
            )
        }
    }

    /// 同じ親を持つ子楽譜の表示順を変更する。
    private func moveChildScores(parentID: UUID, from source: IndexSet, to destination: Int) {
        perform {
            try workspace.moveScoresWithinGroup(
                parentID: parentID,
                fromOffsets: source,
                toOffset: destination
            )
        }
    }

    /// Note名を検証して保存先フォルダの選択を開始する。
    private func continueSaveAs() {
        do {
            packageName = try workspace.validatedNoteName(packageName)
            beginFileOperation(.savePackageAs)
        } catch { operationError = error.localizedDescription }
    }

    /// 選択した場所に応じてPackageの読込・保存・書出を行う。
    private func handleFileSelection(_ result: Result<URL, Error>) {
        let operation = fileOperation
        defer { fileOperation = nil }
        do {
            let url = try result.get()
            switch operation {
            case .openPackage: try workspace.openPackage(at: url)
            case .savePackageAs:
                let destination = url.appendingPathComponent(
                    NoteFileUtilities.safeFileName(packageName) + ".lilypondnote",
                    isDirectory: true
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    pendingOverwriteDirectory = url
                    isConfirmingOverwrite = true
                } else {
                    try workspace.savePackageAs(
                        to: destination,
                        noteTitle: packageName,
                        accessRootURL: url
                    )
                    operationMessage = destination.path
                }
            case .exportScore:
                try workspace.exportSelectedScore(to: NoteFileUtilities.exportURL(
                    for: workspace.selectedScore?.title ?? "Score",
                    in: url
                ))
            case nil: break
            }
            currentPDFPage = 1
        } catch { operationError = error.localizedDescription }
    }

    /// ファイル操作の種類を記録して選択画面を開く。
    private func beginFileOperation(_ operation: FileOperation) {
        fileOperation = operation
        isShowingFileImporter = true
    }

    /// 未保存の変更があれば確認し、なければPackage選択を開く。
    private func requestOpenPackage() {
        if workspace.document.scores.isEmpty || !workspace.hasUnsavedChanges {
            beginFileOperation(.openPackage)
        } else {
            isConfirmingOpen = true
        }
    }

    /// 楽譜があれば確認し、なければ空のNoteを作る。
    private func requestNewNote() {
        if workspace.document.scores.isEmpty {
            perform { try workspace.newNote() }
        } else {
            isConfirmingNewNote = true
        }
    }

    private var newNoteConfirmationTitle: String {
        workspace.hasUnsavedChanges
            ? String(localized: "未保存のNoteを白紙にしますか？")
            : String(localized: "現在のNoteを白紙にしますか？")
    }

    private var newNoteConfirmationMessage: String {
        workspace.hasUnsavedChanges
            ? String(localized: "現在のNoteには未保存の変更があります。保存せずに閉じ、楽譜がない新しいNoteにします。")
            : String(localized: "現在の保存済みNoteを閉じ、楽譜がない新しいNoteにします。")
    }

    /// 指定済みの保存先へ既存Packageを上書きする。
    private func overwritePendingPackage() {
        guard let directory = pendingOverwriteDirectory else { return }
        pendingOverwriteDirectory = nil
        let destination = directory.appendingPathComponent(
            NoteFileUtilities.safeFileName(packageName) + ".lilypondnote",
            isDirectory: true
        )
        do {
            try workspace.savePackageAs(
                to: destination,
                noteTitle: packageName,
                accessRootURL: directory,
                overwriteExisting: true
            )
            operationMessage = destination.path
        } catch {
            operationError = error.localizedDescription
        }
    }

    /// 画面操作で生じたエラーをmacOSの通知文へ反映する。
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { operationError = error.localizedDescription }
    }
}

private struct macOSArrowKeyMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onMove: (MoveCommandDirection) -> Void

    /// キー入力監視の有効状態と移動通知を保持するCoordinatorを生成する。
    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onMove: onMove)
    }

    /// 表示を持たないAppKitビューを生成し、ローカルキーイベント監視を開始する。
    func makeNSView(context: Context) -> NSView {
        context.coordinator.startMonitoring()
        return NSView(frame: .zero)
    }

    /// SwiftUI側で更新された監視可否と移動処理をCoordinatorへ反映する。
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onMove = onMove
    }

    /// 監視用ビューの破棄時にキーイベントモニターを解除する。
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onMove: (MoveCommandDirection) -> Void
        private var monitor: Any?

        /// キー監視の可否と、上下移動を通知するクロージャを保持する。
        init(isEnabled: Bool, onMove: @escaping (MoveCommandDirection) -> Void) {
            self.isEnabled = isEnabled
            self.onMove = onMove
        }

        /// 表示領域の入力イベント監視を開始する。
        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else { return event }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard modifiers.isEmpty else { return event }
                switch event.keyCode {
                case 126:
                    self.onMove(.up)
                    return nil
                case 125:
                    self.onMove(.down)
                    return nil
                default:
                    return event
                }
            }
        }

        /// サイドバーのキー入力監視を解除する。
        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct macOSPDFView: NSViewRepresentable {
    let data: Data
    @Binding var currentPage: Int
    let onVerticalSwipe: (Int) -> Void

    /// PDFページと縦スワイプをSwiftUIへ通知するCoordinatorを生成する。
    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPage: $currentPage,
            displayedData: data,
            onVerticalSwipe: onVerticalSwipe
        )
    }

    /// PDFKitビューを生成し、文書表示、ページ監視、スクロール監視を開始する。
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .horizontal
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        view.document = PDFDocument(data: data)
        view.autoScales = true
        context.coordinator.observe(view)
        context.coordinator.startMonitoring(view)
        return view
    }

    /// PDFデータが変わった場合だけ文書を差し替え、表示ページを先頭へ戻す。
    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.onVerticalSwipe = onVerticalSwipe
        if context.coordinator.shouldDisplay(data) {
            view.document = PDFDocument(data: data)
            view.autoScales = true
            currentPage = 1
        }
    }

    /// PDFKitビューの破棄時にイベント監視とページ変更通知を解除する。
    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        private var currentPage: Binding<Int>
        private var displayedData: Data
        var onVerticalSwipe: (Int) -> Void
        private weak var pdfView: PDFView?
        private var eventMonitor: Any?
        private var accumulatedVerticalDelta: CGFloat = 0
        private var didTriggerVerticalSwipe = false

        /// 現在ページ、表示中PDF、スワイプ通知を保持してPDFKitとの同期を準備する。
        init(
            currentPage: Binding<Int>,
            displayedData: Data,
            onVerticalSwipe: @escaping (Int) -> Void
        ) {
            self.currentPage = currentPage
            self.displayedData = displayedData
            self.onVerticalSwipe = onVerticalSwipe
            super.init()
        }

        /// 表示領域の入力イベント監視を開始する。
        func startMonitoring(_ view: PDFView) {
            pdfView = view
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScrollWheel(event)
                return event
            }
        }

        /// PDF表示領域のスクロール監視を解除する。
        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        /// スクロール端での操作をページ移動に変換する。
        private func handleScrollWheel(_ event: NSEvent) {
            guard let view = pdfView,
                  event.window === view.window,
                  event.hasPreciseScrollingDeltas else { return }
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point),
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return }

            if event.phase == .began || event.phase == .mayBegin {
                accumulatedVerticalDelta = 0
                didTriggerVerticalSwipe = false
            }
            accumulatedVerticalDelta += event.scrollingDeltaY
            if !didTriggerVerticalSwipe, abs(accumulatedVerticalDelta) >= 32 {
                didTriggerVerticalSwipe = true
                onVerticalSwipe(accumulatedVerticalDelta < 0 ? 1 : -1)
            }
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                accumulatedVerticalDelta = 0
                didTriggerVerticalSwipe = false
            }
        }

        /// 表示中のPDFデータが変わったかを判定する。
        func shouldDisplay(_ data: Data) -> Bool {
            guard displayedData != data else { return false }
            displayedData = data
            return true
        }

        /// PDF表示のページ変更通知を監視する。
        func observe(_ view: PDFView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageDidChange(_:)),
                name: .PDFViewPageChanged,
                object: view,
            )
        }

        @MainActor
        /// PDFKitのページ変更を現在ページの表示へ反映する。
        @objc private func pageDidChange(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage,
                  let index = view.document?.index(for: page) else { return }
            currentPage.wrappedValue = index + 1
        }
    }
}

private struct macOSScoreEditorView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case score = "楽譜"
        case procedure = "処理手続き"
        case error = "エラー表示"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: LilyPondNoteWorkspace
    @State private var scoreSource: String
    @State private var processingProgram: String
    @State private var selectedTab: Tab = .score
    @State private var saveError = ""
    @State private var childTitle = ""
    @State private var isSelectingScore = false
    @State private var isConfirmingDeletion = false
    @State private var scoreTitleDraft: String
    @FocusState private var isScoreTitleFocused: Bool
    @State private var isShowingTransposeDialog = false
    @State private var sourcePitch = "c"
    @State private var destinationPitch = "g"
    @State private var destinationOctave: LilyPondTransposeOctave = .unchanged
    @State private var transposeMode = RemoteLilyPondConfigurationStore.savedTransposeMode
    @State private var isTransposing = false
    @State private var isShowingDerivedScoreImport = false
    @State private var derivationKind: ScoreDerivationKind = .new
    @State private var pendingDeletionScoreID: UUID?
    @State private var pendingDeletionScoreTitle = ""
    @State private var editorFontSize: Double
    @State private var hierarchySelectionID: UUID?
    @FocusState private var isHierarchyListFocused: Bool

    /// 選択中楽譜を編集用状態へ複製し、移調元と属調の初期値も設定する。
    init(workspace: LilyPondNoteWorkspace) {
        let transposeDefaults = LilyPondTransposePitchSelection.defaultPitches(
            for: workspace.scoreSource
        )
        self.workspace = workspace
        _scoreSource = State(initialValue: workspace.scoreSource)
        _processingProgram = State(initialValue: workspace.processingProgram)
        _scoreTitleDraft = State(initialValue: workspace.selectedScore?.title ?? "")
        _editorFontSize = State(initialValue: LilyPondEditorConfigurationStore.fontSize(defaultValue: 16))
        _sourcePitch = State(initialValue: transposeDefaults.source)
        _destinationPitch = State(initialValue: transposeDefaults.destination)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("派生楽譜", systemImage: "plus.square.on.square") {
                    childTitle = ""
                    derivationKind = .new
                    resetTransposeSelection()
                    isShowingTransposeDialog = true
                }
                .disabled(isTransposing)
                Menu {
                    Picker("文字サイズ", selection: $editorFontSize) {
                        ForEach(LilyPondEditorConfigurationStore.availableFontSizes, id: \.self) { size in
                            Text("\(Int(size)) pt").tag(size)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "textformat.size")
                        Text("\(Int(editorFontSize)) pt")
                    }
                    .frame(width: 76)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: editorFontSize) { _, size in LilyPondEditorConfigurationStore.saveFontSize(size) }
                Spacer()
                TextField("楽譜名", text: $scoreTitleDraft)
                    .font(.headline)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(maxWidth: 260)
                    .focused($isScoreTitleFocused)
                    .onSubmit { renameScore() }
                    .onChange(of: isScoreTitleFocused) { _, focused in
                        if !focused { renameScore() }
                    }
                Button("グループ内楽譜の選択", systemImage: "list.bullet.indent") {
                    isSelectingScore = true
                }
                .labelStyle(.iconOnly)
                Spacer()
                Button("保存", systemImage: "square.and.arrow.up") { save() }
                    .labelStyle(.iconOnly)
                Button {
                    generate()
                } label: {
                    if workspace.isCompiling {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("PDF生成", systemImage: "play.fill")
                    }
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("PDF生成")
                .buttonStyle(.borderedProminent)
                .disabled(workspace.isCompiling)
                Button("キャンセル", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
            }
            .padding(18)
            .background(.bar)

            Picker("編集項目", selection: $selectedTab) {
                ForEach(Tab.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider()
            editorBody.padding(14)
        }
        .background(.background)
        .sheet(isPresented: $isShowingTransposeDialog) { derivationSheet.frame(minWidth: 480, minHeight: 430) }
        .sheet(isPresented: $isSelectingScore) {
            VStack(spacing: 0) {
                HStack {
                    Text("グループ内楽譜の選択")
                        .font(.headline)
                    Spacer()
                    Button("閉じる") { isSelectingScore = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(16)
                Divider()
                List {
                    ForEach(flattenedScores) { item in
                        HStack(spacing: 24) {
                            Button {
                                selectScore(item.score.id)
                                hierarchySelectionID = item.score.id
                            } label: {
                                Label(
                                    item.score.title,
                                    systemImage: item.score.children.isEmpty ? "music.note" : "folder.fill"
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    item.score.id == hierarchySelectionID
                                        ? Color.accentColor.opacity(0.20)
                                        : Color.secondary.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, CGFloat(item.depth) * 18)
                            Spacer(minLength: 20)
                            Divider().frame(height: 24)
                            Button(role: .destructive) { requestDeletion(of: item.score) } label: {
                                Image(systemName: "trash").frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderless)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { hierarchySelectionID = item.score.id }
                        .listRowBackground(
                            item.score.id == hierarchySelectionID
                                ? Color.accentColor.opacity(0.08)
                                : Color.clear
                        )
                    }
                    .onMove(perform: moveScoresWithinGroup)
                }
                .focusable()
                .focused($isHierarchyListFocused)
                .onMoveCommand(perform: moveHierarchySelection)
                Button("選択") { confirmHierarchySelection() }
                    .keyboardShortcut(.return, modifiers: [])
                    .frame(width: 0, height: 0)
                    .opacity(0)
            }
            .onAppear {
                hierarchySelectionID = workspace.selectedScoreID
                isHierarchyListFocused = true
            }
            .frame(minWidth: 420, minHeight: 480)
        }
        .alert("楽譜を削除しますか？", isPresented: $isConfirmingDeletion) {
            Button("削除", role: .destructive) { deletePendingScore() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(String(
                format: String(localized: "score.delete.message"),
                pendingDeletionScoreTitle
            ))
        }
    }

    private var derivationSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("派生楽譜の生成").font(.headline)
            Picker("生成方法", selection: $derivationKind) {
                ForEach(ScoreDerivationKind.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: derivationKind) { _, kind in
                if kind == .transpose { resetTransposeSelection() }
            }
            if derivationKind != .importFiles {
                TextField("子楽譜名", text: $childTitle)
            }
            if derivationKind == .transpose {
                Toggle("リモートで移調", isOn: usesRemoteTranspose)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("移調元")
                            .fixedSize(horizontal: true, vertical: false)
                        Picker("移調元", selection: $sourcePitch) {
                            ForEach(LilyPondTransposePitchSelection.availableKeys, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Color.clear.frame(width: 160, height: 1)
                    }
                    GridRow {
                        Text("移調先")
                            .fixedSize(horizontal: true, vertical: false)
                        Picker("移調先", selection: $destinationPitch) {
                            ForEach(LilyPondTransposePitchSelection.availableKeys, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Picker("オクターブ", selection: $destinationOctave) {
                            ForEach(LilyPondTransposeOctave.allCases) { octave in
                                Text(octave.displayName).tag(octave)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
                Text(String(format: String(localized: "transpose.create.message"), RemoteLilyPondConfigurationStore.savedTransposeMode.displayName))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Spacer()
                Button("キャンセル") { isShowingTransposeDialog = false }
                Button(derivationKind == .importFiles ? "ファイルを選択" : "作成") {
                    if derivationKind == .importFiles {
                        isShowingDerivedScoreImport = true
                    } else {
                        createDerivedScore()
                    }
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        (derivationKind != .importFiles
                            && childTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || isTransposing
                    )
            }
        }
        .padding(24)
        .sheet(isPresented: $isShowingDerivedScoreImport) {
            macOSScoreImportView(
                workspace: workspace,
                destination: .child(
                    parentScoreSource: scoreSource,
                    parentProcessingProgram: processingProgram
                ),
                onImported: {
                    reloadEditor()
                    isShowingTransposeDialog = false
                }
            )
        }
    }

    /// 派生楽譜画面のスイッチを保存済み移調方式へ結び付け、変更を直ちに永続化する。
    private var usesRemoteTranspose: Binding<Bool> {
        Binding(
            get: { transposeMode == .remote },
            set: {
                transposeMode = $0 ? .remote : .local
                RemoteLilyPondConfigurationStore.savedTransposeMode = transposeMode
            }
        )
    }

    @ViewBuilder
    private var editorBody: some View {
        switch selectedTab {
        case .score:
            darkEditor(text: $scoreSource)
        case .procedure:
            darkEditor(text: $processingProgram)
        case .error:
            ScrollView {
                Text(displayedError.isEmpty ? String(localized: "エラーはありません。") : displayedError)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.separator) }
        }
    }

    private var displayedError: String {
        saveError.isEmpty ? workspace.errorLog : saveError
    }

    /// 暗色背景に合わせたLilyPondソースエディタを構成する。
    private func darkEditor(text: Binding<String>) -> some View {
        macOSLilyPondSourceEditor(text: text, fontSize: editorFontSize)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.separator) }
    }

    /// 編集した楽譜ソースと処理手続きを保存する。
    private func save() {
        do {
            try workspace.saveScore(scoreSource: scoreSource, processingProgram: processingProgram)
            saveError = ""
        } catch {
            saveError = error.localizedDescription
            selectedTab = .error
        }
    }

    /// 編集中の楽譜からPDFを生成し、結果を画面へ反映する。
    private func generate() {
        Task {
            let succeeded = await workspace.generatePDF(
                scoreSource: scoreSource,
                processingProgram: processingProgram
            )
            if !succeeded { selectedTab = .error }
        }
    }

    private var flattenedScores: [ScoreTreeItem] {
        guard let root = workspace.selectedRootScore else { return [] }
        return root.flattened()
    }

    /// 同じ親の楽譜を並べ替え、失敗時は画面に通知する。
    private func moveScoresWithinGroup(from source: IndexSet, to destination: Int) {
        guard let move = ScoreNavigation.siblingMove(
            in: workspace.document,
            items: flattenedScores,
            source: source,
            destination: destination
        ) else { return }
        do {
            try workspace.moveScoresWithinGroup(
                parentID: move.parentID,
                fromOffsets: move.source,
                toOffset: move.destination
            )
        } catch { show(error) }
    }

    /// 階層一覧で上下キーに応じて選択位置を移す。
    private func moveHierarchySelection(_ direction: MoveCommandDirection) {
        guard !flattenedScores.isEmpty else { return }
        let current = hierarchySelectionID.flatMap { id in
            flattenedScores.firstIndex { $0.score.id == id }
        }
        let target: Int
        switch direction {
        case .up: target = max(0, (current ?? 1) - 1)
        case .down: target = min(flattenedScores.count - 1, (current ?? -1) + 1)
        default: return
        }
        hierarchySelectionID = flattenedScores[target].score.id
    }

    /// 階層一覧で選択中の楽譜を確定する。
    private func confirmHierarchySelection() {
        guard let hierarchySelectionID else { return }
        selectScore(hierarchySelectionID)
    }

    /// 選択した方法で派生楽譜を作り、結果をエディタへ反映する。
    private func createDerivedScore() {
        guard derivationKind != .importFiles else {
            isShowingDerivedScoreImport = true
            return
        }
        let title = childTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let source = sourcePitch.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationOctave.applying(to: destinationPitch)
        guard derivationKind != .transpose || (!source.isEmpty && !destination.isEmpty) else {
            saveError = String(localized: "子楽譜名、移調元、移調先を入力してください。")
            selectedTab = .error
            return
        }

        isTransposing = true
        Task {
            defer { isTransposing = false }
            do {
                try await ScoreDerivationService.create(
                    kind: derivationKind,
                    title: title,
                    scoreSource: scoreSource,
                    processingProgram: processingProgram,
                    sourcePitch: source,
                    destinationPitch: destination,
                    workspace: workspace
                )
                reloadEditor()
                isShowingTransposeDialog = false
            } catch {
                show(error)
            }
        }
    }

    /// 編集中の楽譜から移調元と属調を読み取り、移調画面の初期値へ反映する。
    private func resetTransposeSelection() {
        let defaults = LilyPondTransposePitchSelection.defaultPitches(for: scoreSource)
        sourcePitch = defaults.source
        destinationPitch = defaults.destination
        destinationOctave = .unchanged
    }

    /// 削除対象の楽譜を保持し、確認画面を開く。
    private func requestDeletion(of score: Score) {
        pendingDeletionScoreID = score.id
        pendingDeletionScoreTitle = score.title
        isConfirmingDeletion = true
    }

    /// 確認済みの楽譜を削除し、選択可能な楽譜がなければ編集画面を閉じる。
    private func deletePendingScore() {
        guard let scoreID = pendingDeletionScoreID else { return }
        pendingDeletionScoreID = nil
        do {
            try workspace.deleteScore(scoreID)
            if workspace.selectedScore == nil {
                isSelectingScore = false
                dismiss()
            } else {
                reloadEditor()
            }
        } catch { show(error) }
    }

    /// 指定楽譜を選択し、PDFページまたはエディタ内容を更新する。
    private func selectScore(_ id: UUID) {
        do {
            try workspace.selectScore(id)
            reloadEditor()
        } catch { show(error) }
    }

    /// 選択楽譜のソースとタイトルをエディタの入力状態へ読み込む。
    private func reloadEditor() {
        scoreSource = workspace.scoreSource
        processingProgram = workspace.processingProgram
        scoreTitleDraft = workspace.selectedScore?.title ?? ""
        saveError = ""
    }

    /// 編集した楽譜名を保存し、確定したタイトルを表示する。
    private func renameScore() {
        do {
            try workspace.renameSelectedScore(to: scoreTitleDraft)
            scoreTitleDraft = workspace.selectedScore?.title ?? ""
            saveError = ""
        } catch {
            scoreTitleDraft = workspace.selectedScore?.title ?? ""
            show(error)
        }
    }

    /// 発生したエラーの説明を画面へ表示する。
    private func show(_ error: Error) {
        saveError = error.localizedDescription
        selectedTab = .error
    }
}
