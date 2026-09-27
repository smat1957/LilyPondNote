// Note全体の名称と楽譜階層を永続化する文書モデルを定義する。

import Foundation

struct LilyPondNoteDocument: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var title: String
    var scores: [Score]

    /// Noteの識別子、表示名、楽譜階層、保存形式の版を受け取り文書モデルを作る。
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
