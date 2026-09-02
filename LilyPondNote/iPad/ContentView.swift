// iPad向けのサイドバー、PDF表示、編集画面、ファイル操作UIを構成する。

import PDFKit
import LilyPondTransposeCore
import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    static let lilyPondSource = UTType(filenameExtension: "ly") ?? .plainText
}

struct ContentView: View {
    @StateObject private var workspace = LilyPondNoteWorkspace(
        compiler: RemoteLilyPondConfigurationStore.loadCompiler()
    )
    @StateObject private var authenticationSession =
        RemoteLilyPondAuthenticationSession()
    @State private var isEditing = false
    @State private var isShowingServerSettings = false
    @State private var isShowingAccountUsage = false
    @State private var currentPDFPage = 1
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var fileOperation: FileOperation?
    @State private var isShowingFileImporter = false
    @State private var isShowingAbout = false
    @State private var isNamingRootScore = false
    @State private var newRootTitle = ""
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
    @State private var isOpeningPackage = false
    @State private var pdfTransitionDirection = 1
    @State private var expandedScoreIDs: Set<UUID> = []
    @FocusState private var isNoteTitleFocused: Bool

    private enum FileOperation {
        case openPackage, importScore, savePackageAs, exportScore

        var contentTypes: [UTType] {
            switch self {
            case .importScore: [.lilyPondSource]
            default: [.folder]
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            scoreSidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 330)
        } detail: {
            scoreDetail
        }
        .navigationSplitViewStyle(.balanced)
        .overlay {
            if isOpeningPackage {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Noteを読み込んでいます…")
                            .font(.headline)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(radius: 12)
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .fullScreenCover(isPresented: $isEditing) {
            iPadScoreEditorView(workspace: workspace)
        }
        .sheet(isPresented: $isShowingServerSettings) {
            iPadServerSettingsView(
                workspace: workspace,
                authenticationSession: authenticationSession
            )
            //.presentationDetents([.fraction(1.65)]) // 少し低め
            //.presentationDetents([.fraction(0.70)]) // 少し高め
            //.presentationDetents([.fraction(0.75)]) // さらに高め
        }
        .sheet(isPresented: $isShowingAbout) {
            LilyPondAboutView()
                .presentationDetents([.height(350)])
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: fileOperation?.contentTypes ?? [.folder]
        ) { result in
            handleFileSelection(result)
        }
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
        )) {
            Button("OK") { operationError = "" }
        } message: {
            Text(operationError)
        }
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
        .onAppear { noteTitleDraft = workspace.document.title }
        .onChange(of: workspace.document.title) { _, title in
            noteTitleDraft = title
        }
    }

    private var scoreSidebar: some View {
        List {
            ForEach(workspace.document.scores) { score in
                iPadScoreTreeRow(
                    score: score,
                    selectedScoreID: workspace.selectedScoreID,
                    expandedScoreIDs: $expandedScoreIDs,
                    select: selectScore
                )
            }
            .onMove(perform: moveRootScores)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                authenticationButton
            }
        }
        .alert("現在の利用状況", isPresented: $isShowingAccountUsage) {
            Button("ログアウト", role: .destructive) {
                logout()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(accountUsageMessage)
        }
        .task {
            await authenticationSession.refresh()
        }
    }

    private var accountUsageMessage: String {
        guard let account = authenticationSession.account else { return "" }
        return "\(account.email)\n\n"
            + String(format: String(localized: "usage.plan"), account.plan.displayName)
            + String(format: String(localized: "usage.monthly"), Int64(account.used), Int64(account.limit))
            + String(format: String(localized: "usage.pdf"), Int64(account.usageByService.typeset))
            + String(format: String(localized: "usage.transpose"), Int64(account.usageByService.transpose))
    }

    /// 認証状態を更新する。
    private func logout() {
        authenticationSession.logout()
        workspace.configureCompiler(
            RemoteLilyPondConfigurationStore.loadCompiler()
        )
    }

    @ViewBuilder
    private var authenticationButton: some View {
        switch authenticationSession.state {
        case .checking:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking login")
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .fixedSize()
            .background(
                Color.accentColor.opacity(0.10),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
            .accessibilityLabel("ログイン状態を確認中")
        case .signedIn:
            Button {
                Task {
                    await authenticationSession.refresh()
                    isShowingAccountUsage = authenticationSession.account != nil
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(planBadgeColor)
                    Text(String(
                        format: String(localized: "login.plan"),
                        authenticationSession.account?.plan.displayName ?? "—"
                    ))
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .fixedSize()
                .background(
                    Color.accentColor.opacity(0.10),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        case .signedOut, .failed:
            Button {
                isShowingServerSettings = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.badge.key.fill")
                    Text("Login")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .fixedSize()
                .background(
                    Color.accentColor.opacity(0.10),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var planBadgeColor: Color {
        switch authenticationSession.account?.plan {
        case .free: .gray
        case .standard: .blue
        case .pro: .purple
        case nil: .secondary
        }
    }

    private var scoreDetail: some View {
        VStack(spacing: 0) {
            noteTitleBar
            Divider()
            scoreTitleBar
            Divider()
            pdfContent
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(.background)
    }

    private var noteTitleBar: some View {
        ZStack {
            TextField("Note名", text: $noteTitleDraft)
                .font(.headline)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused($isNoteTitleFocused)
                .onSubmit { renameNote() }
                .onChange(of: isNoteTitleFocused) { _, focused in
                    if !focused { renameNote() }
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .padding(.vertical, 7)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            HStack {
                if splitViewVisibility == .detailOnly {
                    Button("Score一覧を表示", systemImage: "sidebar.leading") {
                        withAnimation { splitViewVisibility = .all }
                    }
                    .labelStyle(.iconOnly)
                }
                Spacer()
                if workspace.hasUnsavedChanges {
                    Label("未保存", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
                Button("新規作成", systemImage: "plus") {
                    newRootTitle = ""
                    isNamingRootScore = true
                }
                Menu {
                    Button("新しいNote", systemImage: "doc.badge.plus") {
                        requestNewNote()
                    }
                    Button("開く…", systemImage: "folder") {
                        requestOpenPackage()
                    }
                    Button("保存…", systemImage: "square.and.arrow.up") {
                        savePackage()
                    }
                    Button("名前を付けて保存…", systemImage: "square.and.pencil") {
                        packageName = workspace.document.title
                        isNamingPackage = true
                    }
                    Button("インポート", systemImage: "square.and.arrow.down.on.square") {
                        beginFileOperation(.importScore)
                    }
                    Divider()
                    Button("設定", systemImage: "gearshape") {
                        isShowingServerSettings = true
                    }
                    Button("LilyPondNoteについて", systemImage: "info.circle") {
                        isShowingAbout = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
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
                    Menu {
                        Button("エクスポート", systemImage: "square.and.arrow.up") {
                            beginFileOperation(.exportScore)
                        }
                        Button("削除", systemImage: "trash", role: .destructive) {
                            isConfirmingScoreDeletion = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
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
            iPadPDFPageCarousel(
                data: data,
                currentPage: $currentPDFPage,
                onVerticalSwipe: moveToAdjacentScoreGroup,
                onLeadingEdgeSwipe: {
                    withAnimation(.easeOut(duration: 0.22)) {
                        splitViewVisibility = .all
                    }
                },
                onTap: {
                    if splitViewVisibility != .detailOnly {
                        withAnimation { splitViewVisibility = .detailOnly }
                    }
                }
            )
                .id(data)
                .transition(pdfGroupTransition)
                .onAppear {
                    currentPDFPage = 1
                }
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

    /// 必要なデータを作成して文書へ追加する。
    private func createRootScore() {
        let title = newRootTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        perform { try workspace.createRootScore(title: title) }
    }

    /// `renameNote`が担当する処理を実行する。
    private func renameNote() {
        do {
            try workspace.renameNote(to: noteTitleDraft)
            noteTitleDraft = workspace.document.title
        } catch {
            noteTitleDraft = workspace.document.title
            operationError = error.localizedDescription
        }
    }

    /// 対象の選択または表示位置を変更する。
    private func selectScore(_ id: UUID) {
        perform { try workspace.selectScore(id) }
        currentPDFPage = 1
    }

    /// 対象の選択または表示位置を変更する。
    private func moveRootScores(from source: IndexSet, to destination: Int) {
        perform {
            try workspace.moveRootScores(
                fromOffsets: source,
                toOffset: destination
            )
        }
    }

    /// 対象の選択または表示位置を変更する。
    private func moveToAdjacentScoreGroup(_ offset: Int) {
        do {
            let scores = ScoreNavigation.visibleItems(
                in: workspace.document.scores,
                expandedScoreIDs: expandedScoreIDs
            )
            guard let targetID = ScoreNavigation.adjacentScoreID(
                in: scores,
                selectedScoreID: workspace.selectedScoreID,
                fallbackRootID: workspace.selectedRootScore?.id,
                offset: offset
            ) else { return }
            pdfTransitionDirection = offset
            try withAnimation(.easeInOut(duration: 0.22)) {
                try workspace.selectScore(targetID)
                currentPDFPage = 1
            }
        } catch {
            operationError = error.localizedDescription
        }
    }

    private var pdfGroupTransition: AnyTransition {
        let insertion: Edge = pdfTransitionDirection > 0 ? .bottom : .top
        let removal: Edge = pdfTransitionDirection > 0 ? .top : .bottom
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    /// 対象データを保存先へ書き込む。
    private func savePackage() {
        if let destination = workspace.savedPackageURL {
            let accessURLs = [destination.deletingLastPathComponent(), destination]
            let accessedURLs = accessURLs.filter { $0.startAccessingSecurityScopedResource() }
            defer { accessedURLs.reversed().forEach { $0.stopAccessingSecurityScopedResource() } }
            do {
                try workspace.savePackage()
                operationMessage = destination.path
            } catch {
                operationError = error.localizedDescription
            }
        } else {
            packageName = workspace.document.title
            isNamingPackage = true
        }
    }

    /// `continueSaveAs`が担当する処理を実行する。
    private func continueSaveAs() {
        do {
            packageName = try workspace.validatedNoteName(packageName)
            beginFileOperation(.savePackageAs)
        } catch {
            operationError = error.localizedDescription
        }
    }

    /// 画面から要求された操作を処理する。
    private func handleFileSelection(_ result: Result<URL, Error>) {
        let operation = fileOperation
        defer { fileOperation = nil }
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            switch operation {
            case .openPackage:
                openPackage(at: url)
                return
            case .importScore:
                try workspace.importRootScore(from: url)
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
                try workspace.exportSelectedScore(to: NoteFileUtilities.exportURL(
                    for: workspace.selectedScore?.title ?? "Score",
                    in: url
                ))
            case nil:
                break
            }
            currentPDFPage = 1
        } catch {
            operationError = error.localizedDescription
        }
    }

    /// 保存済みデータを読み込み状態へ反映する。
    private func openPackage(at url: URL) {
        withAnimation(.easeOut(duration: 0.15)) {
            isOpeningPackage = true
        }
        Task { @MainActor in
            await Task.yield()
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                try workspace.openPackage(at: url)
                currentPDFPage = 1
            } catch {
                operationError = error.localizedDescription
            }
            withAnimation(.easeIn(duration: 0.15)) {
                isOpeningPackage = false
            }
        }
    }

    /// 画面から要求された操作を処理する。
    private func beginFileOperation(_ operation: FileOperation) {
        fileOperation = operation
        isShowingFileImporter = true
    }

    /// 画面から要求された操作を処理する。
    private func requestOpenPackage() {
        if workspace.document.scores.isEmpty || !workspace.hasUnsavedChanges {
            beginFileOperation(.openPackage)
        } else {
            isConfirmingOpen = true
        }
    }

    /// 画面から要求された操作を処理する。
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

    /// `overwritePendingPackage`が担当する処理を実行する。
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

    /// 画面から要求された操作を処理する。
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { operationError = error.localizedDescription }
    }
}

private struct iPadScoreTreeRow: View {
    let score: Score
    let selectedScoreID: UUID?
    @Binding var expandedScoreIDs: Set<UUID>
    let select: (UUID) -> Void

    var body: some View {
        if score.children.isEmpty {
            scoreButton
        } else {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedScoreIDs.contains(score.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedScoreIDs.insert(score.id)
                    } else {
                        expandedScoreIDs.remove(score.id)
                    }
                }
            )) {
                ForEach(score.children) { child in
                    iPadScoreTreeRow(
                        score: child,
                        selectedScoreID: selectedScoreID,
                        expandedScoreIDs: $expandedScoreIDs,
                        select: select
                    )
                }
            } label: {
                scoreButton
            }
        }
    }

    private var scoreButton: some View {
        Button { select(score.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: score.children.isEmpty ? "music.note" : "folder.fill")
                    .foregroundStyle(selectedScoreID == score.id ? Color.accentColor : .secondary)
                    .frame(width: 18)
                Text(score.title)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.vertical, 3)
            .foregroundStyle(selectedScoreID == score.id ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selectedScoreID == score.id ? Color.accentColor.opacity(0.10) : Color.clear
        )
    }
}

private struct iPadPDFPageCarousel: View {
    private let pages: [RenderedPDFPage]
    @Binding var currentPage: Int
    let onVerticalSwipe: (Int) -> Void
    let onLeadingEdgeSwipe: () -> Void
    let onTap: () -> Void

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(
        data: Data,
        currentPage: Binding<Int>,
        onVerticalSwipe: @escaping (Int) -> Void,
        onLeadingEdgeSwipe: @escaping () -> Void,
        onTap: @escaping () -> Void
    ) {
        pages = PDFPageRenderer.render(data: data)
        _currentPage = currentPage
        self.onVerticalSwipe = onVerticalSwipe
        self.onLeadingEdgeSwipe = onLeadingEdgeSwipe
        self.onTap = onTap
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages) { page in
                        iPadZoomablePDFPage(
                            page: page,
                            size: geometry.size
                        )
                        .id(page.index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(
                get: { currentPage - 1 },
                set: { pageID in
                    let page = (pageID ?? 0) + 1
                    guard page != currentPage else { return }
                    Task { @MainActor in
                        currentPage = page
                    }
                }
            ))
            .scrollBounceBehavior(.basedOnSize)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let vertical = value.predictedEndTranslation.height
                    let horizontal = value.predictedEndTranslation.width
                    if abs(vertical) > abs(horizontal), abs(vertical) >= 70 {
                        onVerticalSwipe(vertical < 0 ? 1 : -1)
                        return
                    }
                    if currentPage == 1, horizontal >= 70 {
                        onLeadingEdgeSwipe()
                    }
                }
        )
        .onTapGesture(perform: onTap)
        .background(.background)
    }
}

private struct iPadZoomablePDFPage: View {
    let page: RenderedPDFPage
    let size: CGSize
    @State private var scale: CGFloat = 1
    @State private var image: CGImage?
    @GestureState private var gestureScale: CGFloat = 1

    private var displayedScale: CGFloat {
        min(max(scale * gestureScale, 1), 4)
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
            .frame(
                width: max(1, size.width - 48),
                height: max(1, size.height - 32)
            )
            .scaleEffect(displayedScale)
            .frame(width: size.width, height: size.height)
            .background(.background)
            .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
            .clipped()
            .gesture(
                MagnificationGesture()
                    .updating($gestureScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        scale = min(max(scale * value, 1), 4)
                    }
            )
            .onAppear {
                if image == nil {
                    image = PDFPageRenderer.renderPage(data: page.data, index: page.index)
                }
            }
            .onDisappear {
                image = nil
                scale = 1
            }
    }
}

private struct iPadScoreEditorView: View {
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
    @State private var pendingDeletionScoreID: UUID?
    @State private var pendingDeletionScoreTitle = ""
    @State private var scoreTitleDraft: String
    @FocusState private var isScoreTitleFocused: Bool
    @State private var isShowingTransposeDialog = false
    @State private var derivationKind: ScoreDerivationKind = .new
    @State private var sourcePitch = "c"
    @State private var destinationPitch = "a"
    @State private var isTransposing = false
    @State private var editorFontSize: Double

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(workspace: LilyPondNoteWorkspace) {
        self.workspace = workspace
        _scoreSource = State(initialValue: workspace.scoreSource)
        _processingProgram = State(initialValue: workspace.processingProgram)
        _scoreTitleDraft = State(initialValue: workspace.selectedScore?.title ?? "")
        _editorFontSize = State(
            initialValue: LilyPondEditorConfigurationStore.fontSize(defaultValue: 18)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Picker("編集項目", selection: $selectedTab) {
                ForEach(Tab.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            Divider()
            editorBody
                .padding(14)
        }
        .background(.background)
        .sheet(isPresented: $isShowingTransposeDialog) { derivationSheet }
        .sheet(isPresented: $isSelectingScore) {
            NavigationStack {
                List {
                    ForEach(flattenedScores) { item in
                        HStack(spacing: 0) {
                            Button {
                                selectScore(item.score.id)
                            } label: {
                                Label(
                                    item.score.title,
                                    systemImage: item.score.children.isEmpty ? "music.note" : "folder.fill"
                                )
                                .foregroundStyle(item.score.id == workspace.selectedScoreID ? Color.accentColor : Color.primary)
                                .padding(.leading, CGFloat(item.depth) * 18)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    item.score.id == workspace.selectedScoreID
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 32)
                            Divider()
                                .frame(height: 28)
                                .padding(.trailing, 16)
                            Button(role: .destructive) {
                                requestDeletion(of: item.score)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                requestDeletion(of: item.score)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onMove(perform: moveScoresWithinGroup)
                }
                .navigationTitle("グループ内楽譜の選択")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { isSelectingScore = false }
                    }
                }
            }
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

    private var editorHeader: some View {
        HStack(spacing: 12) {
            Button("派生楽譜", systemImage: "plus.square.on.square") {
                childTitle = ""
                derivationKind = .new
                isShowingTransposeDialog = true
            }
            .buttonStyle(.bordered)
            .disabled(isTransposing)
            Menu {
                Picker("文字サイズ", selection: $editorFontSize) {
                    ForEach(LilyPondEditorConfigurationStore.availableFontSizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
            } label: {
                Label("\(Int(editorFontSize)) pt", systemImage: "textformat.size")
            }
            .buttonStyle(.bordered)
            .onChange(of: editorFontSize) { _, size in
                LilyPondEditorConfigurationStore.saveFontSize(size)
            }
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
            .buttonStyle(.bordered)
            Spacer()
            Button("保存", systemImage: "square.and.arrow.up") { save() }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
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
                .buttonStyle(.bordered)
        }
        .padding(18)
        .background(.bar)
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
                Section("楽譜名") {
                    TextField("子楽譜名", text: $childTitle)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isShowingTransposeDialog = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") { createDerivedScore() }
                        .disabled(childTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTransposing)
                }
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
                    .padding(16)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator) }
        }
    }

    private var displayedError: String {
        saveError.isEmpty ? workspace.errorLog : saveError
    }

    /// `darkEditor`が担当する処理を実行する。
    private func darkEditor(text: Binding<String>) -> some View {
        iPadLilyPondSourceEditor(text: text, fontSize: editorFontSize)
            //.background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            //白系：Color(uiColor: .systemBackground)
            //灰系：Color(uiColor: .secondarySystemBackground)
            //任意の色：Color(red: 0.96, green: 0.96, blue: 0.98)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator) }
    }

    /// 対象データを保存先へ書き込む。
    private func save() {
        do {
            try workspace.saveScore(scoreSource: scoreSource, processingProgram: processingProgram)
            saveError = ""
        } catch {
            saveError = error.localizedDescription
            selectedTab = .error
        }
    }

    /// 入力を処理して生成結果を返す。
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
        return root.flattened()
    }

    /// 対象の選択または表示位置を変更する。
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
        } catch {
            saveError = error.localizedDescription
            selectedTab = .error
        }
    }

    /// 必要なデータを作成して文書へ追加する。
    private func createDerivedScore() {
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
                isShowingTransposeDialog = false
            } catch {
                saveError = error.localizedDescription
                selectedTab = .error
            }
        }
    }

    /// 画面から要求された操作を処理する。
    private func requestDeletion(of score: Score) {
        pendingDeletionScoreID = score.id
        pendingDeletionScoreTitle = score.title
        isConfirmingDeletion = true
    }

    /// 対象データまたは保持状態を削除する。
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
        } catch {
            saveError = error.localizedDescription
            selectedTab = .error
        }
    }

    /// 対象の選択または表示位置を変更する。
    private func selectScore(_ id: UUID) {
        do {
            try workspace.selectScore(id)
            reloadEditor()
        } catch {
            saveError = error.localizedDescription
            selectedTab = .error
        }
    }

    /// `reloadEditor`が担当する処理を実行する。
    private func reloadEditor() {
        scoreSource = workspace.scoreSource
        processingProgram = workspace.processingProgram
        scoreTitleDraft = workspace.selectedScore?.title ?? ""
        saveError = ""
    }

    /// `renameScore`が担当する処理を実行する。
    private func renameScore() {
        do {
            try workspace.renameSelectedScore(to: scoreTitleDraft)
            scoreTitleDraft = workspace.selectedScore?.title ?? ""
            saveError = ""
        } catch {
            scoreTitleDraft = workspace.selectedScore?.title ?? ""
            saveError = error.localizedDescription
            selectedTab = .error
        }
    }
}
