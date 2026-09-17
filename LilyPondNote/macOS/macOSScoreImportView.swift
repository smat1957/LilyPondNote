// macOS向けのroot・派生楽譜共通インポートUIを構成する。

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct macOSScoreImportView: View {
    private enum FileRole { case scoreData, processingProgram }

    @Environment(\.dismiss) private var dismiss
    let workspace: LilyPondNoteWorkspace
    let destination: ScoreImportDestination
    let onImported: () -> Void

    @State private var scoreData: ScoreImportFile?
    @State private var processingProgram: ScoreImportFile?
    @State private var scoreTitle = ""
    @State private var automaticTitle = ""
    @State private var selectingRole: FileRole?
    @State private var isSelectingFile = false
    @State private var errorMessage = ""
    @State private var warningMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("既存ファイルのインポート").font(.title2.bold())
            GroupBox("インポートするファイル") {
                VStack(spacing: 12) {
                    fileRow("楽譜データ", scoreData?.fileName ?? String(localized: "ファイルを選択"), scoreData != nil) { select(.scoreData) }
                    Divider()
                    fileRow("処理手続き（任意）", processingProgram?.fileName ?? String(localized: "未選択"), processingProgram != nil) { select(.processingProgram) }
                }.padding(8)
            }
            TextField("楽譜名", text: $scoreTitle)
            Spacer()
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("インポート") { performImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canImport)
            }
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 340)
        .fileImporter(isPresented: $isSelectingFile, allowedContentTypes: [UTType(filenameExtension: "ly") ?? .plainText]) { handleSelection($0) }
        .alert("操作できません", isPresented: Binding(
            get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } }
        )) { Button("OK") { errorMessage = "" } } message: { Text(errorMessage) }
        .alert("インポートしました", isPresented: Binding(
            get: { !warningMessage.isEmpty }, set: { if !$0 { warningMessage = "" } }
        )) {
            Button("OK") { finishImport() }
        } message: { Text(warningMessage) }
    }

    private var canImport: Bool {
        scoreData != nil && !scoreTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func fileRow(_ title: LocalizedStringKey, _ detail: String, _ isSelected: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
            Button(action: action) {
                Text(isSelected ? String(localized: "変更…") : String(localized: "選択…"))
            }
        }
    }

    private func select(_ role: FileRole) { selectingRole = role; isSelectingFile = true }

    private func handleSelection(_ result: Result<URL, Error>) {
        defer { selectingRole = nil }
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let file = try ScoreImportService.loadFile(at: url)
            switch selectingRole {
            case .scoreData:
                let shouldReplaceTitle = scoreTitle.isEmpty || scoreTitle == automaticTitle
                scoreData = file
                automaticTitle = file.suggestedScoreTitle
                if shouldReplaceTitle { scoreTitle = automaticTitle }
            case .processingProgram: processingProgram = file
            case nil: break
            }
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport() {
        do {
            let warning = try ScoreImportService.importScore(title: scoreTitle, scoreData: scoreData, processingProgram: processingProgram, destination: destination, workspace: workspace)
            if let warning {
                warningMessage = warning
            } else {
                finishImport()
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func finishImport() {
        warningMessage = ""
        onImported()
        dismiss()
    }
}
