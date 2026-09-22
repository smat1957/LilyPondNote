// Note全体の名称と楽譜階層を永続化する文書モデルを定義する。

import Foundation

struct LilyPondNoteDocument: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var title: String
    var scores: [Score]

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(
        id: UUID = UUID(),
        title: String,
        scores: [Score] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.title = title
        self.scores = scores
    }
}
