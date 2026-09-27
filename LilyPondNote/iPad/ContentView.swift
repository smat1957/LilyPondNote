// iPad向けのサイドバー、PDF表示、編集画面、ファイル操作UIを構成する。

import PDFKit
import LilyPondTransposeCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @State private var isShowingRootScoreImport = false
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
        case openPackage, savePackageAs, exportScore

        var contentTypes: [UTType] {
            [.folder]
        }
    }

    var body: some View {
        dialogs
            .task { await workspace.restoreAtLaunch() }
            .onAppear { noteTitleDraft = workspace.document.title }
            .onChange(of: workspace.document.title) { _, title in
                noteTitleDraft = title
            }
    }

    private var baseContent: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            scoreSidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 330)
        } detail: {
            scoreDetail
        }
        .navigationSplitViewStyle(.balanced)
        .overlay {
            if isOpeningPackage || workspace.startupLoadingPhase != nil {
                iPadStartupLoadingView(
                    message: workspace.startupLoadingPhase?.message
                        ?? String(localized: "Noteを読み込んでいます…")
                )
            }
        }
    }

    private var presentations: some View {
        baseContent
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
        .sheet(isPresented: $isShowingRootScoreImport) {
            iPadScoreImportView(
                workspace: workspace,
                destination: .root,
                onImported: { currentPDFPage = 1 }
            )
        }
    }

    private var dialogs: some View {
        presentations
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
    }

    private var scoreSidebar: some View {
        VStack(spacing: 0) {
            List {
                ForEach(workspace.document.scores) { score in
                    iPadScoreTreeRow(
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
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

    /// 共有セッションをログアウトし、Workspaceのコンパイラを保存済み設定へ戻す。
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
                Menu {
                    Button("新しいNote", systemImage: "doc.badge.plus") {
                        requestNewNote()
                    }
                    Button("開く…", systemImage: "folder") {
                        requestOpenPackage()
                    }
                    Button("保存…", systemImage: "square.and.arrow.up") {
                        packageName = workspace.document.title
                        continueSaveAs()
                    }
                    Button("名前を付けて保存…", systemImage: "square.and.pencil") {
                        packageName = workspace.document.title
                        isNamingPackage = true
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
                        .modifier(iPadGlassCircleControlModifier())
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Noteの操作")
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
                    HStack(spacing: 10) {
                        Button {
                            isEditing = true
                        } label: {
                            Label("編集", systemImage: "pencil")
                                .modifier(iPadGlassCapsuleControlModifier())
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("印刷", systemImage: "printer") {
                                printPDF()
                            }
                            .disabled(workspace.pdfData == nil)
                            Button("エクスポート", systemImage: "square.and.arrow.up") {
                                beginFileOperation(.exportScore)
                            }
                            Divider()
                            Button("削除", systemImage: "trash", role: .destructive) {
                                isConfirmingScoreDeletion = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .modifier(iPadGlassCircleControlModifier())
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("楽譜の操作")
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
                        if let selectedScore = workspace.selectedScore,
                           !selectedScore.children.isEmpty {
                            expandedScoreIDs.insert(selectedScore.id)
                        }
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

    /// 現在表示中のPDF全ページをiPadOS標準の印刷画面へ渡す。
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

    /// 表示順で隣の楽譜グループを選び、PDFの先頭を表示する。
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

    /// Note名を検証して保存先フォルダの選択を開始する。
    private func continueSaveAs() {
        do {
            packageName = try workspace.validatedNoteName(packageName)
            beginFileOperation(.savePackageAs)
        } catch {
            operationError = error.localizedDescription
        }
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
            case .openPackage:
                openPackage(at: url)
                return
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

    /// 読み込み表示を出して選択Packageを開く。
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

    /// 画面操作で生じたエラーをiPadの通知文へ反映する。
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { operationError = error.localizedDescription }
    }
}

private struct iPadPDFPageCarousel: View {
    private let pages: [RenderedPDFPage]
    @Binding var currentPage: Int
    @State private var scrollPageID: Int? = 0
    let onVerticalSwipe: (Int) -> Void
    let onLeadingEdgeSwipe: () -> Void
    let onTap: () -> Void

    /// PDFをページ単位の表示データへ分解し、スワイプとタップの通知先を保持する。
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
            .scrollPosition(id: $scrollPageID)
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            let pageID = currentPage - 1
            scrollPageID = pages.indices.contains(pageID) ? pageID : 0
        }
        .onChange(of: scrollPageID) { _, pageID in
            guard let pageID, pages.indices.contains(pageID) else { return }
            let page = pageID + 1
            if currentPage != page {
                currentPage = page
            }
        }
        .onChange(of: currentPage) { _, page in
            let pageID = page - 1
            guard pages.indices.contains(pageID), scrollPageID != pageID else { return }
            scrollPageID = pageID
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
                    if currentPage == 1,
                       horizontal >= 70,
                       abs(horizontal) > abs(vertical) {
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
    @State private var destinationPitch = "g"
    @State private var destinationOctave: LilyPondTransposeOctave = .unchanged
    @State private var isTransposing = false
    @State private var isShowingDerivedScoreImport = false
    @State private var editorFontSize: Double

    /// 選択中楽譜を編集用状態へ複製し、移調元と属調の初期値も設定する。
    init(workspace: LilyPondNoteWorkspace) {
        let transposeDefaults = LilyPondTransposePitchSelection.defaultPitches(
            for: workspace.scoreSource
        )
        self.workspace = workspace
        _scoreSource = State(initialValue: workspace.scoreSource)
        _processingProgram = State(initialValue: workspace.processingProgram)
        _scoreTitleDraft = State(initialValue: workspace.selectedScore?.title ?? "")
        _editorFontSize = State(
            initialValue: LilyPondEditorConfigurationStore.fontSize(defaultValue: 18)
        )
        _sourcePitch = State(initialValue: transposeDefaults.source)
        _destinationPitch = State(initialValue: transposeDefaults.destination)
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
                .navigationBarTitleDisplayMode(.inline)
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
                resetTransposeSelection()
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
                if derivationKind != .importFiles {
                    Section("楽譜名") {
                        TextField("子楽譜名", text: $childTitle)
                    }
                }
                if derivationKind == .transpose {
                    Section("移調設定") {
                        Picker("移調元", selection: $sourcePitch) {
                            ForEach(LilyPondTransposePitchSelection.availableKeys, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        HStack {
                            Picker("移調先", selection: $destinationPitch) {
                                ForEach(LilyPondTransposePitchSelection.availableKeys, id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                            Picker("オクターブ", selection: $destinationOctave) {
                                ForEach(LilyPondTransposeOctave.allCases) { octave in
                                    Text(octave.displayName).tag(octave)
                                }
                            }
                            .labelsHidden()
                        }
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
            .onChange(of: derivationKind) { _, kind in
                if kind == .transpose { resetTransposeSelection() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isShowingTransposeDialog = false }
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
                iPadScoreImportView(
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

    /// 暗色背景に合わせたLilyPondソースエディタを構成する。
    private func darkEditor(text: Binding<String>) -> some View {
        iPadLilyPondSourceEditor(text: text, fontSize: editorFontSize)
            //.background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            //白系：Color(uiColor: .systemBackground)
            //灰系：Color(uiColor: .secondarySystemBackground)
            //任意の色：Color(red: 0.96, green: 0.96, blue: 0.98)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator) }
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
        } catch {
            saveError = error.localizedDescription
            selectedTab = .error
        }
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
                saveError = error.localizedDescription
                selectedTab = .error
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
        } catch {
            saveError = error.localizedDescription
            selectedTab = .error
        }
    }

    /// 指定楽譜を選択し、PDFページまたはエディタ内容を更新する。
    private func selectScore(_ id: UUID) {
        do {
            try workspace.selectScore(id)
            reloadEditor()
        } catch {
            saveError = error.localizedDescription
            selectedTab = .error
        }
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
            saveError = error.localizedDescription
            selectedTab = .error
        }
    }
}
