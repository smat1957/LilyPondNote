// 楽譜モデルと、楽譜階層を検索・編集する共通処理を定義する。

import Foundation

struct Score: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var compilerVersion: String?
    var children: [Score]

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(
        id: UUID = UUID(),
        title: String,
        compilerVersion: String? = nil,
        children: [Score] = []
    ) {
        self.id = id
        self.title = title
        self.compilerVersion = compilerVersion
        self.children = children
    }
}

struct ScoreTreeItem: Identifiable {
    let score: Score
    let depth: Int
    var id: UUID { score.id }
}

extension Score {
    /// `flattened`が担当する処理を実行する。
    func flattened(depth: Int = 0) -> [ScoreTreeItem] {
        [ScoreTreeItem(score: self, depth: depth)]
            + children.flatMap { $0.flattened(depth: depth + 1) }
    }
}

extension LilyPondNoteDocument {
    /// `score`が担当する処理を実行する。
    func score(withID scoreID: UUID) -> Score? {
        scores.lazy.compactMap { $0.score(withID: scoreID) }.first
    }

    /// 必要なデータを作成して文書へ追加する。
    mutating func appendRootScore(_ score: Score) {
        scores.append(score)
    }

    /// 対象の選択または表示位置を変更する。
    mutating func moveRootScores(fromOffsets source: IndexSet, toOffset destination: Int) {
        scores.moveElements(fromOffsets: source, toOffset: destination)
    }

    @discardableResult
    /// 対象の選択または表示位置を変更する。
    mutating func moveChildScores(
        of parentID: UUID,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> Bool {
        Self.moveChildren(
            of: parentID,
            fromOffsets: source,
            toOffset: destination,
            in: &scores
        )
    }

    @discardableResult
    /// `renameScore`が担当する処理を実行する。
    mutating func renameScore(withID scoreID: UUID, to title: String) -> Bool {
        Self.renameScore(scoreID, to: title, in: &scores)
    }

    @discardableResult
    /// `setCompilerVersion`が担当する処理を実行する。
    mutating func setCompilerVersion(_ version: String, for scoreID: UUID) -> Bool {
        Self.setCompilerVersion(version, for: scoreID, in: &scores)
    }

    /// `parentID`が担当する処理を実行する。
    func parentID(of scoreID: UUID) -> UUID? {
        Self.parentID(of: scoreID, in: scores, currentParentID: nil)
    }

    /// `rootScore`が担当する処理を実行する。
    func rootScore(containing scoreID: UUID) -> Score? {
        scores.first { $0.score(withID: scoreID) != nil }
    }

    @discardableResult
    /// 必要なデータを作成して文書へ追加する。
    mutating func appendChildScore(_ child: Score, to parentID: UUID) -> Bool {
        Self.append(child, to: parentID, in: &scores)
    }

    @discardableResult
    /// 対象データまたは保持状態を削除する。
    mutating func removeScorePromotingChildren(withID scoreID: UUID) -> Score? {
        Self.removePromotingChildren(scoreID, from: &scores)
    }

    /// 必要なデータを作成して文書へ追加する。
    private static func append(
        _ child: Score,
        to parentID: UUID,
        in scores: inout [Score]
    ) -> Bool {
        for index in scores.indices {
            if scores[index].id == parentID {
                scores[index].children.append(child)
                return true
            }

            if append(child, to: parentID, in: &scores[index].children) {
                return true
            }
        }

        return false
    }

    /// 対象の選択または表示位置を変更する。
    private static func moveChildren(
        of parentID: UUID,
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in scores: inout [Score]
    ) -> Bool {
        for index in scores.indices {
            if scores[index].id == parentID {
                scores[index].children.moveElements(
                    fromOffsets: source,
                    toOffset: destination
                )
                return true
            }
            if moveChildren(
                of: parentID,
                fromOffsets: source,
                toOffset: destination,
                in: &scores[index].children
            ) {
                return true
            }
        }
        return false
    }

    /// `renameScore`が担当する処理を実行する。
    private static func renameScore(
        _ scoreID: UUID,
        to title: String,
        in scores: inout [Score]
    ) -> Bool {
        for index in scores.indices {
            if scores[index].id == scoreID {
                scores[index].title = title
                return true
            }
            if renameScore(scoreID, to: title, in: &scores[index].children) {
                return true
            }
        }
        return false
    }

    /// `setCompilerVersion`が担当する処理を実行する。
    private static func setCompilerVersion(
        _ version: String,
        for scoreID: UUID,
        in scores: inout [Score]
    ) -> Bool {
        for index in scores.indices {
            if scores[index].id == scoreID {
                scores[index].compilerVersion = version
                return true
            }
            if setCompilerVersion(version, for: scoreID, in: &scores[index].children) {
                return true
            }
        }
        return false
    }

    /// 対象データまたは保持状態を削除する。
    private static func removePromotingChildren(
        _ scoreID: UUID,
        from scores: inout [Score]
    ) -> Score? {
        if let index = scores.firstIndex(where: { $0.id == scoreID }) {
            let removed = scores.remove(at: index)
            scores.insert(contentsOf: removed.children, at: index)
            return removed
        }

        for index in scores.indices {
            if let removed = removePromotingChildren(
                scoreID,
                from: &scores[index].children
            ) {
                return removed
            }
        }
        return nil
    }

    /// `parentID`が担当する処理を実行する。
    private static func parentID(
        of scoreID: UUID,
        in scores: [Score],
        currentParentID: UUID?
    ) -> UUID? {
        for score in scores {
            if score.id == scoreID { return currentParentID }
            if let match = Self.parentID(
                of: scoreID,
                in: score.children,
                currentParentID: score.id
            ) {
                return match
            }
        }
        return nil
    }
}

private extension Array {
    /// 対象の選択または表示位置を変更する。
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let validSource = source.filter { indices.contains($0) }
        guard !validSource.isEmpty else { return }
        let moving = validSource.map { self[$0] }
        let sourceSet = Set(validSource)
        let remaining = enumerated().compactMap { sourceSet.contains($0.offset) ? nil : $0.element }
        let removedBeforeDestination = validSource.filter { $0 < destination }.count
        let insertion = Swift.min(
            Swift.max(0, destination - removedBeforeDestination),
            remaining.count
        )
        self = Array(remaining[..<insertion]) + moving + Array(remaining[insertion...])
    }
}

private extension Score {
    /// `score`が担当する処理を実行する。
    func score(withID scoreID: UUID) -> Score? {
        if id == scoreID {
            return self
        }

        return children.lazy.compactMap { $0.score(withID: scoreID) }.first
    }
}
