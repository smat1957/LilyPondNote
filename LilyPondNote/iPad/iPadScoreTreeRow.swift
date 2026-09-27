// iPadのサイドバーで楽譜階層を展開し、選択と兄弟順の変更を受け付ける行を構成する。

import Foundation
import SwiftUI

struct iPadScoreTreeRow: View {
    let score: Score
    let selectedScoreID: UUID?
    @Binding var expandedScoreIDs: Set<UUID>
    let select: (UUID) -> Void
    let moveChildren: (UUID, IndexSet, Int) -> Void

    var body: some View {
        if score.children.isEmpty {
            scoreButton
        } else {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedScoreIDs.contains(score.id) },
                set: { isExpanded in
                    if isExpanded { expandedScoreIDs.insert(score.id) }
                    else { expandedScoreIDs.remove(score.id) }
                }
            )) {
                ForEach(score.children) { child in
                    iPadScoreTreeRow(
                        score: child,
                        selectedScoreID: selectedScoreID,
                        expandedScoreIDs: $expandedScoreIDs,
                        select: select,
                        moveChildren: moveChildren
                    )
                }
                .onMove { source, destination in
                    moveChildren(score.id, source, destination)
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
                Text(score.title).font(.callout).lineLimit(1)
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
