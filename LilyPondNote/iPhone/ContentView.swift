// iPhone向けのPDF表示、楽譜選択、編集画面、ファイル操作UIを構成する。

import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var workspace = LilyPondNoteWorkspace(
        compiler: RemoteLilyPondConfigurationStore.loadCompiler(),
        restoresOnInitialization: false
    )
    @State private var isEditing = false
    @State private var isShowingServerSettings = false
    @State private var currentPDFPage = 1
    @State private var fileOperation: FileOperation?
    @State private var isShowingFileImporter = false
    @State private var isShowingRootScoreImport = false
    @State private var isShowingRootCreationOptions = false
    @State private var isNamingRootScore = false
    @State private var newRootTitle = ""
    @State private var isSelectingScore = false
    @State private var isShowingAbout = false
    @State private var operationError = ""
    @State private var isConfirmingScoreDeletion = false
    @State private var isNamingPackage = false
    @State private var packageName = ""
    @State private var operationMessage = ""
    @State private var isConfirmingNewNote = false
    @State private var noteTitleDraft = String(localized: "名称未設定")
    @State private var pendingOverwriteDestination: URL?
    @State private var isConfirmingOverwrite = false
    @State private var isConfirmingOpen = false
    @State private var expandedScoreIDs: Set<UUID> = []
    @FocusState private var isNoteTitleFocused: Bool

    private enum FileOperation: Equatable {
        case openPackage, savePackageAs, exportScore
        var contentTypes: [UTType] { [.folder] }
    }

    var body: some View {
        dialogs
            .task { await workspace.restoreAtLaunch() }
            .onAppear { noteTitleDraft = workspace.document.title }
            .onChange(of: workspace.document.title) { _, title in noteTitleDraft = title }
    }

    private var baseContent: some View {
        VStack(spacing: 0) {
            noteTitleBar
            Divider()
            scoreTitleBar
            Divider()
            pdfContent
        }
        .background(.background)
        .overlay {
            if let phase = workspace.startupLoadingPhase {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text(phase.message)
                            .font(.headline)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(radius: 12)
                }
            }
        }
    }

    private var presentations: some View {
        baseContent
        .fullScreenCover(isPresented: $isEditing) {
            iPhoneScoreEditorView(workspace: workspace)
        }
        .sheet(isPresented: $isShowingServerSettings) {
            iPhoneServerSettingsView(workspace: workspace)
        }
        .sheet(isPresented: $isShowingAbout) {
            LilyPondAboutView()
                .presentationDetents([.height(350)])
        }
        .sheet(isPresented: $isShowingRootScoreImport) {
            iPhoneScoreImportView(
                workspace: workspace,
                destination: .root,
                onImported: { currentPDFPage = 1 }
            )
        }
        .sheet(isPresented: $isSelectingScore) {
            NavigationStack {
                List(flattenedScores) { item in
                    iPhoneCollapsibleScoreRow(
                        item: item,
                        expandedScoreIDs: $expandedScoreIDs,
                        isSelected: item.score.id == workspace.selectedScoreID
                    ) {
                        selectScore(item.score.id)
                        isSelectingScore = false
                    }
                }
                .navigationTitle("楽譜の選択")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { isSelectingScore = false }
                    }
                }
            }
        }
    }

    private var dialogs: some View {
        presentations
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: fileOperation?.contentTypes ?? [.folder]
        ) { handleFileSelection($0) }
        .alert("新しい楽譜グループ", isPresented: $isNamingRootScore) {
            TextField("楽譜名", text: $newRootTitle)
            Button("作成") { createRootScore() }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog(
            "楽譜グループの追加",
            isPresented: $isShowingRootCreationOptions,
            titleVisibility: .visible
        ) {
            Button("新規楽譜グループ") {
                newRootTitle = ""
                isNamingRootScore = true
            }
            Button("既存ファイルのインポート") {
                isShowingRootScoreImport = true
            }
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
                pendingOverwriteDestination = nil
            }
        } message: {
            Text(String(format: String(localized: "note.overwrite.message"), pendingOverwriteNoteName))
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
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button {
                    isShowingRootCreationOptions = true
                } label: {
                    Image(systemName: "plus")
                        .modifier(iPhoneGlassCircleControlModifier())
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("新規作成")
                Spacer()
                if workspace.hasUnsavedChanges {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("未保存の変更があります")
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
                    Button("インポート") { isShowingRootScoreImport = true }
                    Divider()
                    Button("設定") { isShowingServerSettings = true }
                    Button("LilyPondNoteについて", systemImage: "info.circle") {
                        isShowingAbout = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .modifier(iPhoneGlassCircleControlModifier())
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Noteの操作")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(.bar)
    }

    private var scoreTitleBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    isSelectingScore = true
                } label: {
                    Text(workspace.selectedScore?.title ?? String(localized: "楽譜がありません"))
                }
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(workspace.pdfNeedsRegeneration
                         ? String(localized: "更新待ち")
                         : String(localized: "最新版"))
                        .foregroundStyle(workspace.pdfNeedsRegeneration ? .orange : .green)
                    Text("\(currentPDFPage) / \(pageCount)")
                        .foregroundStyle(.secondary)
                    Text("LilyPond \(workspace.selectedScore?.compilerVersion ?? "—")")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer()
            if workspace.selectedScore != nil {
                HStack(spacing: 8) {
                    Button {
                        isEditing = true
                    } label: {
                        Label("編集", systemImage: "pencil")
                            .modifier(iPhoneGlassCapsuleControlModifier())
                    }
                    .buttonStyle(.plain)

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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .modifier(iPhoneGlassCircleControlModifier())
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("楽譜の操作")
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .clipped()
        .background(.bar)
    }

    @ViewBuilder
    private var pdfContent: some View {
        if let data = workspace.pdfData {
            iPhonePDFView(
                data: data,
                currentPage: $currentPDFPage,
                onVerticalSwipe: moveToAdjacentScoreGroup,
                onLeadingEdgeSwipe: { isSelectingScore = true }
            )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground))
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

    /// 現在表示中のPDF全ページをiOS標準の印刷画面へ渡す。
    private func printPDF() {
        guard let data = workspace.pdfData else { return }
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = workspace.selectedScore?.title ?? workspace.document.title
        printInfo.outputType = .general

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = data
        controller.present(animated: true, completionHandler: nil)
    }

    private var flattenedScores: [ScoreTreeItem] {
        ScoreNavigation.visibleItems(
            in: workspace.document.scores,
            expandedScoreIDs: expandedScoreIDs
        )
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

    /// 表示順で隣の楽譜グループを選び、PDFの先頭を表示する。
    private func moveToAdjacentScoreGroup(_ offset: Int) {
        do {
            let scores = flattenedScores
            guard let targetID = ScoreNavigation.adjacentScoreID(
                in: scores,
                selectedScoreID: workspace.selectedScoreID,
                fallbackRootID: workspace.selectedRootScore?.id,
                offset: offset
            ) else { return }
            try workspace.selectScore(targetID)
            currentPDFPage = 1
        } catch {
            operationError = error.localizedDescription
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
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            switch operation {
            case .openPackage: try workspace.openPackage(at: url)
            case .savePackageAs:
                let destination = url.appendingPathComponent(
                    NoteFileUtilities.safeFileName(packageName) + ".lilypondnote",
                    isDirectory: true
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    pendingOverwriteDestination = destination
                    isConfirmingOverwrite = true
                } else {
                    try workspace.savePackageAs(
                        to: destination,
                        noteTitle: packageName
                    )
                    operationMessage = destination.path
                }
            case .exportScore:
                try workspace.exportSelectedScore(
                    to: NoteFileUtilities.exportURL(
                        for: workspace.selectedScore?.title ?? "Score",
                        in: url
                    )
                )
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

    private var pendingOverwriteNoteName: String {
        pendingOverwriteDestination?.deletingPathExtension().lastPathComponent
            ?? packageName
    }

    /// 指定済みの保存先へ既存Packageを上書きする。
    private func overwritePendingPackage() {
        guard let destination = pendingOverwriteDestination else { return }
        pendingOverwriteDestination = nil
        let parent = destination.deletingLastPathComponent()
        let accessed = parent.startAccessingSecurityScopedResource()
        defer { if accessed { parent.stopAccessingSecurityScopedResource() } }
        do {
            try workspace.savePackageAs(
                to: destination,
                noteTitle: packageName,
                overwriteExisting: true
            )
            operationMessage = destination.path
        } catch {
            operationError = error.localizedDescription
        }
    }

    /// 画面操作で生じたエラーをiPhoneの通知文へ反映する。
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { operationError = error.localizedDescription }
    }
}

private struct iPhoneCollapsibleScoreRow: View {
    let item: ScoreTreeItem
    @Binding var expandedScoreIDs: Set<UUID>
    var isSelected = false
    let select: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if item.score.children.isEmpty {
                Color.clear.frame(width: 22, height: 22)
            } else {
                Button {
                    if expandedScoreIDs.contains(item.score.id) {
                        expandedScoreIDs.remove(item.score.id)
                    } else {
                        expandedScoreIDs.insert(item.score.id)
                    }
                } label: {
                    Image(systemName: expandedScoreIDs.contains(item.score.id)
                          ? "chevron.down" : "chevron.right")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            Button(action: select) {
                Label(
                    item.score.title,
                    systemImage: item.score.children.isEmpty ? "music.note" : "folder.fill"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                .shadow(
                    color: isSelected ? Color.black.opacity(0.22) : Color.clear,
                    radius: 4,
                    y: 2
                )
        }
        .padding(.leading, CGFloat(item.depth) * 16)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .listRowSeparator(.hidden)
    }
}

private struct iPhonePDFView: UIViewRepresentable {
    let data: Data
    @Binding var currentPage: Int
    let onVerticalSwipe: (Int) -> Void
    let onLeadingEdgeSwipe: () -> Void

    /// 画面部品の構築または状態反映を行う。
    func makeCoordinator() -> Coordinator {
        Coordinator(
            displayedData: data,
            currentPage: $currentPage,
            onVerticalSwipe: onVerticalSwipe,
            onLeadingEdgeSwipe: onLeadingEdgeSwipe
        )
    }

    /// 画面部品の構築または状態反映を行う。
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: [
            UIPageViewController.OptionsKey.interPageSpacing: 12
        ])
        view.displaysPageBreaks = true
        view.pageBreakMargins = .init(top: 12, left: 16, bottom: 12, right: 16)
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(data: data)
        fitDocument(in: view)
        context.coordinator.observe(view)
        context.coordinator.installSwipeRecognizers(on: view)
        return view
    }

    /// 画面部品の構築または状態反映を行う。
    func updateUIView(_ view: PDFView, context: Context) {
        if context.coordinator.shouldDisplay(data) {
            view.document = PDFDocument(data: data)
            fitDocument(in: view)
            Task { @MainActor in currentPage = 1 }
        }
    }

    /// 画面部品の構築または状態反映を行う。
    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    /// PDFの幅と倍率を表示領域へ合わせる。
    private func fitDocument(in view: PDFView) {
        view.autoScales = true
        let scale = view.scaleFactorForSizeToFit
        if scale > 0 {
            view.scaleFactor = scale
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var currentPage: Binding<Int>
        private var displayedData: Data
        private let onVerticalSwipe: (Int) -> Void
        private let onLeadingEdgeSwipe: () -> Void

        /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
        init(
            displayedData: Data,
            currentPage: Binding<Int>,
            onVerticalSwipe: @escaping (Int) -> Void,
            onLeadingEdgeSwipe: @escaping () -> Void
        ) {
            self.displayedData = displayedData
            self.currentPage = currentPage
            self.onVerticalSwipe = onVerticalSwipe
            self.onLeadingEdgeSwipe = onLeadingEdgeSwipe
        }

        /// 表示中のPDFデータが変わったかを判定する。
        func shouldDisplay(_ data: Data) -> Bool {
            guard displayedData != data else { return false }
            displayedData = data
            return true
        }

        /// 登録済みの通知やイベント監視を解除する。
        func stopObserving() {
            NotificationCenter.default.removeObserver(self)
        }

        /// PDF表示にページ端のスワイプ認識器を取り付ける。
        func installSwipeRecognizers(on view: PDFView) {
            for direction in [UISwipeGestureRecognizer.Direction.up, .down, .right] {
                let recognizer = UISwipeGestureRecognizer(
                    target: self,
                    action: #selector(didSwipe(_:))
                )
                recognizer.direction = direction
                recognizer.delegate = self
                view.addGestureRecognizer(recognizer)
            }
        }

        /// 先頭ページの右スワイプで楽譜一覧を開き、上下スワイプで楽譜を切り替える。
        @objc private func didSwipe(_ recognizer: UISwipeGestureRecognizer) {
            if recognizer.direction == .right {
                if currentPage.wrappedValue == 1 { onLeadingEdgeSwipe() }
            } else {
                onVerticalSwipe(recognizer.direction == .up ? 1 : -1)
            }
        }

        /// PDFの既存ジェスチャーとの同時認識可否を決める。
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
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
            let pageNumber = index + 1
            guard currentPage.wrappedValue != pageNumber else { return }
            Task { @MainActor [currentPage] in
                currentPage.wrappedValue = pageNumber
            }
        }
    }
}

private struct iPhoneScoreEditorView: View {
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
    @State private var sourcePitch = "c"
    @State private var destinationPitch = "a"
    @State private var isTransposing = false
    @State private var derivationKind: ScoreDerivationKind = .new
    @State private var isShowingDerivationSheet = false
    @State private var isShowingDerivedScoreImport = false
    @State private var editorFontSize: Double
    @State private var expandedScoreIDs: Set<UUID> = []

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(workspace: LilyPondNoteWorkspace) {
        self.workspace = workspace
        _scoreSource = State(initialValue: workspace.scoreSource)
        _processingProgram = State(initialValue: workspace.processingProgram)
        _scoreTitleDraft = State(initialValue: workspace.selectedScore?.title ?? "")
        _editorFontSize = State(
            initialValue: LilyPondEditorConfigurationStore.fontSize(defaultValue: 17)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("楽譜名", text: $scoreTitleDraft)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .focused($isScoreTitleFocused)
                        .onSubmit { renameScore() }
                        .onChange(of: isScoreTitleFocused) { _, focused in
                            if !focused { renameScore() }
                        }
                    Button("グループ内楽譜の選択", systemImage: "list.bullet.indent") {
                        isSelectingScore = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 6) {
                    Button("派生楽譜", systemImage: "plus.square.on.square") {
                        childTitle = ""
                        derivationKind = .new
                        isShowingDerivationSheet = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .disabled(isTransposing)
                    Button("削除", systemImage: "trash", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    Menu {
                        Picker("文字サイズ", selection: $editorFontSize) {
                            ForEach(LilyPondEditorConfigurationStore.availableFontSizes, id: \.self) { size in
                                Text("\(Int(size)) pt").tag(size)
                            }
                        }
                    } label: {
                        Label("\(Int(editorFontSize))", systemImage: "textformat.size")
                    }
                    .buttonStyle(.bordered)
                    .onChange(of: editorFontSize) { _, size in
                        LilyPondEditorConfigurationStore.saveFontSize(size)
                    }

                    Spacer(minLength: 4)

                    Button("保存", systemImage: "square.and.arrow.up") { save() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                    Button { generate() } label: {
                        if workspace.isCompiling {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                    }
                    .accessibilityLabel("PDF生成")
                    .buttonStyle(.borderedProminent)
                    .disabled(workspace.isCompiling)
                    Button("キャンセル", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
            .padding(14)
            .background(.bar)

            Picker("編集項目", selection: $selectedTab) {
                ForEach(Tab.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Divider()
            editorBody.padding(10)
        }
        .background(.background)
        .sheet(isPresented: $isShowingDerivationSheet) { derivationSheet }
        .sheet(isPresented: $isSelectingScore) {
            NavigationStack {
                List {
                    ForEach(flattenedScores) { item in
                        iPhoneCollapsibleScoreRow(
                            item: item,
                            expandedScoreIDs: $expandedScoreIDs,
                            isSelected: item.score.id == workspace.selectedScoreID
                        ) {
                            selectScore(item.score.id)
                            isSelectingScore = false
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onMove(perform: moveScoresWithinGroup)
                }
                .navigationTitle("グループ内楽譜の選択")
            }
        }
        .alert("楽譜を削除しますか？", isPresented: $isConfirmingDeletion) {
            Button("削除", role: .destructive) { deleteScore() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(String(
                format: String(localized: "score.delete.message"),
                workspace.selectedScore?.title ?? String(localized: "選択中の楽譜")
            ))
        }
    }

    private var derivationSheet: some View {
        NavigationStack {
            Form {
                Section("生成方法") {
                    ForEach(ScoreDerivationKind.allCases) { kind in
                        Button {
                            derivationKind = kind
                        } label: {
                            Label(
                                LocalizedStringKey(kind.rawValue),
                                systemImage: derivationKind == kind ? "largecircle.fill.circle" : "circle"
                            )
                        }
                        .foregroundStyle(.primary)
                    }
                }
                if derivationKind != .importFiles {
                    Section("楽譜名") { TextField("子楽譜名", text: $childTitle) }
                }
                if derivationKind == .transpose {
                    Section("移調設定") {
                        TextField("移調元（例: c）", text: $sourcePitch)
                        TextField("移調先（例: a）", text: $destinationPitch)
                        Text(String(
                            format: String(localized: "transpose.create.message"),
                            RemoteLilyPondConfigurationStore.savedTransposeMode.displayName
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("派生楽譜の生成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isShowingDerivationSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(derivationKind == .importFiles ? "ファイルを選択" : "作成") {
                        if derivationKind == .importFiles {
                            isShowingDerivedScoreImport = true
                        } else {
                            createDerivedScore()
                        }
                    }
                    .disabled(
                        (derivationKind != .importFiles
                            && childTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || isTransposing
                    )
                }
            }
            .sheet(isPresented: $isShowingDerivedScoreImport) {
                iPhoneScoreImportView(
                    workspace: workspace,
                    destination: .child(
                        parentScoreSource: scoreSource,
                        parentProcessingProgram: processingProgram
                    ),
                    onImported: {
                        reloadEditor()
                        isShowingDerivationSheet = false
                    }
                )
            }
        }
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
                    .padding(14)
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
        iPhoneLilyPondSourceEditor(text: text, fontSize: editorFontSize)
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
            if succeeded {
                dismiss()
            } else {
                selectedTab = .error
            }
        }
    }

    private var flattenedScores: [ScoreTreeItem] {
        guard let root = workspace.selectedRootScore else { return [] }
        return ScoreNavigation.visibleItems(
            in: [root],
            expandedScoreIDs: expandedScoreIDs
        )
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

    /// 選択された生成方法で派生楽譜を作成する。
    private func createDerivedScore() {
        guard derivationKind != .importFiles else {
            isShowingDerivedScoreImport = true
            return
        }
        let title = childTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let source = sourcePitch.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationPitch.trimmingCharacters(in: .whitespacesAndNewlines)
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
                isShowingDerivationSheet = false
            } catch { show(error) }
        }
    }

    /// 対象データまたは保持状態を削除する。
    private func deleteScore() {
        do {
            try workspace.deleteSelectedScore()
            dismiss()
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
