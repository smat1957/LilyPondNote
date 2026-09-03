// 新規・複製・移調による派生楽譜の生成を、全プラットフォームで共通化する。

import Foundation
import LilyPondTransposeCore

enum ScoreDerivationKind: String, CaseIterable, Identifiable {
    case new = "新規作成"
    case duplicate = "複製楽譜"
    case transpose = "移調楽譜"

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
        }
    }
}
