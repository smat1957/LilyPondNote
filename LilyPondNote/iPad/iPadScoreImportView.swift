// iPad向けのroot・派生楽譜共通インポートUIを構成する。

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct iPadScoreImportView: View {
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
        NavigationStack {
            Form {
                Section("インポートするファイル") {
                    fileRow(
                        title: "楽譜データ",
                        detail: scoreData?.fileName ?? String(localized: "ファイルを選択"),
                        isSelected: scoreData != nil
                    ) { select(.scoreData) }
                    fileRow(
                        title: "処理手続き（任意）",
                        detail: processingProgram?.fileName ?? String(localized: "未選択"),
                        isSelected: processingProgram != nil
                    ) { select(.processingProgram) }
                }
                Section("楽譜名") {
                    TextField("楽譜名", text: $scoreTitle)
                }
            }
            .navigationTitle("既存ファイルのインポート")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("インポート") { performImport() }
                        .disabled(!canImport)
                }
            }
        }
        .fileImporter(
            isPresented: $isSelectingFile,
            allowedContentTypes: [UTType(filenameExtension: "ly") ?? .plainText]
        ) { handleSelection($0) }
        .alert("操作できません", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) { Button("OK") { errorMessage = "" } } message: { Text(errorMessage) }
        .alert("インポートしました", isPresented: Binding(
            get: { !warningMessage.isEmpty },
            set: { if !$0 { warningMessage = "" } }
        )) {
            Button("OK") { finishImport() }
        } message: {
            Text(warningMessage)
        }
    }

    private var canImport: Bool {
        scoreData != nil && !scoreTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 選択状態とファイル名を示すiPad用の行を作る。
    private func fileRow(title: LocalizedStringKey, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                Text(isSelected ? String(localized: "変更…") : String(localized: "選択…"))
            }
        }
    }

    /// 次に選ぶファイルの役割を保存してファイル選択を開く。
    private func select(_ role: FileRole) {
        selectingRole = role
        isSelectingFile = true
    }

    /// 選択したLilyPondファイルを読み、楽譜または処理手続きへ割り当てる。
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
            case .processingProgram:
                processingProgram = file
            case nil:
                break
            }
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Coreのインポート処理を実行し、警告か完了を画面へ反映する。
    private func performImport() {
        do {
            let warning = try ScoreImportService.importScore(
                title: scoreTitle,
                scoreData: scoreData,
                processingProgram: processingProgram,
                destination: destination,
                workspace: workspace
            )
            if let warning {
                warningMessage = warning
            } else {
                finishImport()
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// 警告を閉じ、親画面へ完了を通知してシートを閉じる。
    private func finishImport() {
        warningMessage = ""
        onImported()
        dismiss()
    }
}
