// 派生楽譜の生成と既存ファイルのインポートを、全プラットフォームで共通化する。

import Foundation
import LilyPondTransposeCore

enum ScoreDerivationKind: String, CaseIterable, Identifiable {
    case new = "新規作成"
    case duplicate = "複製楽譜"
    case transpose = "移調楽譜"
    case importFiles = "既存ファイルのインポート"

    /// SwiftUIの選択値として利用する識別子を返す。
    var id: Self { self }
}

@MainActor
enum ScoreDerivationService {
    /// 指定された生成方法で子楽譜を作成し、新しい楽譜を選択状態にする。
    static func create(kind: ScoreDerivationKind, title: String, scoreSource: String, processingProgram: String, sourcePitch: String = "", destinationPitch: String = "", workspace: LilyPondNoteWorkspace) async throws {
        switch kind {
        case .new:
            try workspace.saveScore(scoreSource: scoreSource, processingProgram: processingProgram)
            try workspace.createChildScore(
                title: title,
                scoreSource: LilyPondTemplates.initialScoreData,
                processingProgram: LilyPondTemplates.initialProcessingProgram
            )
        case .duplicate:
            try workspace.saveScore(scoreSource: scoreSource, processingProgram: processingProgram)
            try workspace.createChildScore(title: title, scoreSource: scoreSource, processingProgram: processingProgram)
        case .transpose:
            let transformed = try await LilyPondTransposeService.transpose(source: scoreSource, from: sourcePitch, to: destinationPitch)
            try workspace.createChildScore(title: title, scoreSource: transformed, processingProgram: processingProgram)
        case .importFiles:
            throw ScoreImportService.ImportError.scoreDataIsNotSelected
        }
    }
}

struct ScoreImportFile: Equatable {
    let fileName: String
    let source: String

    var suggestedScoreTitle: String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }
}

enum ScoreImportDestination {
    case root
    case child(parentScoreSource: String, parentProcessingProgram: String)
}

@MainActor
enum ScoreImportService {
    enum ImportError: LocalizedError {
        case scoreDataIsNotSelected

        var errorDescription: String? {
            switch self {
            case .scoreDataIsNotSelected:
                String(localized: "楽譜データを選択してください。")
            }
        }
    }

    /// セキュリティスコープへアクセスできる間に、選択されたUTF-8ファイルを読み込む。
    static func loadFile(at url: URL) throws -> ScoreImportFile {
        ScoreImportFile(
            fileName: url.lastPathComponent,
            source: try String(contentsOf: url, encoding: .utf8)
        )
    }

    /// 読み込んだ楽譜データと任意の処理手続きを、rootまたは選択楽譜の子として追加する。
    static func importScore(
        title: String,
        scoreData: ScoreImportFile?,
        processingProgram: ScoreImportFile?,
        destination: ScoreImportDestination,
        workspace: LilyPondNoteWorkspace
    ) throws -> String? {
        guard let scoreData else { throw ImportError.scoreDataIsNotSelected }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw LilyPondNoteWorkspace.WorkspaceError.invalidScoreName
        }
        let program = processingProgram?.source
            ?? LilyPondTemplates.initialProcessingProgram
        let includesScoreData = LilyPondNotePackageStore
            .includesLocalScoreData(program)

        switch destination {
        case .root:
            try workspace.importRootScore(
                title: normalizedTitle,
                scoreSource: scoreData.source,
                processingProgram: program,
                validatesProcessingProgram: includesScoreData
            )
        case .child(let parentScoreSource, let parentProcessingProgram):
            try workspace.saveScore(
                scoreSource: parentScoreSource,
                processingProgram: parentProcessingProgram
            )
            try workspace.createChildScore(
                title: normalizedTitle,
                scoreSource: scoreData.source,
                processingProgram: program,
                validatesProcessingProgram: includesScoreData
            )
        }

        guard processingProgram != nil, !includesScoreData else { return nil }
        return String(
            format: String(localized: "処理手続き（%@）には \\include \"score.ly\" がありません。インポート後、編集画面で追加してください。"),
            processingProgram?.fileName ?? "main.ly"
        )
    }
}
