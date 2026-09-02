// 楽譜階層の表示順と並べ替え位置を、全プラットフォームで共通に計算する。

import Foundation

enum ScoreNavigation {
    /// 展開中の楽譜だけを子孫まで含め、画面に見える順序へ変換する。
    static func visibleItems(in scores: [Score], expandedScoreIDs: Set<UUID>, depth: Int = 0) -> [ScoreTreeItem] {
        scores.flatMap { score in
            [ScoreTreeItem(score: score, depth: depth)]
                + (expandedScoreIDs.contains(score.id)
                    ? visibleItems(in: score.children, expandedScoreIDs: expandedScoreIDs, depth: depth + 1)
                    : [])
        }
    }

    /// 現在の選択位置から、表示順で指定方向にある楽譜IDを返す。
    static func adjacentScoreID(in items: [ScoreTreeItem], selectedScoreID: UUID?, fallbackRootID: UUID?, offset: Int) -> UUID? {
        guard offset != 0, !items.isEmpty else { return nil }
        let currentIndex = selectedScoreID.flatMap { selectedID in
            items.firstIndex { $0.score.id == selectedID }
        } ?? fallbackRootID.flatMap { rootID in
            items.firstIndex { $0.score.id == rootID }
        }
        guard let currentIndex else { return nil }
        let targetIndex = currentIndex + offset
        guard items.indices.contains(targetIndex) else { return nil }
        return items[targetIndex].score.id
    }

    /// 平坦表示上の移動位置を、同じ親を持つ兄弟内の移動位置へ変換する。
    static func siblingMove(in document: LilyPondNoteDocument, items: [ScoreTreeItem], source: IndexSet, destination: Int) -> (parentID: UUID, source: IndexSet, destination: Int)? {
        guard source.count == 1, let sourceIndex = source.first, items.indices.contains(sourceIndex),
              let parentID = document.parentID(of: items[sourceIndex].score.id) else { return nil }
        let siblings = items.filter { document.parentID(of: $0.score.id) == parentID }
        guard let siblingSource = siblings.firstIndex(where: { $0.score.id == items[sourceIndex].score.id }) else { return nil }
        let prefixEnd = min(max(0, destination), items.count)
        let siblingDestination = items[..<prefixEnd].filter { document.parentID(of: $0.score.id) == parentID }.count
        return (parentID, IndexSet(integer: siblingSource), siblingDestination)
    }
}
