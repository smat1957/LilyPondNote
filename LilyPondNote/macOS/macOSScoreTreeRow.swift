// macOSのサイドバーで楽譜階層を展開し、選択と兄弟順の変更を受け付ける行を構成する。

import Foundation
import SwiftUI

struct macOSScoreTreeRow: View {
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
                set: { expanded in
                    if expanded { expandedScoreIDs.insert(score.id) }
                    else { expandedScoreIDs.remove(score.id) }
                }
            )) {
                ForEach(score.children) {
                    macOSScoreTreeRow(
                        score: $0,
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
            HStack(spacing: 7) {
                Image(systemName: score.children.isEmpty ? "music.note" : "folder.fill")
                    .foregroundStyle(selectedScoreID == score.id ? Color.accentColor : .secondary)
                    .frame(width: 16)
                Text(score.title).font(.callout).lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.vertical, 2)
            .foregroundStyle(selectedScoreID == score.id ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selectedScoreID == score.id ? Color.accentColor.opacity(0.10) : Color.clear
        )
    }
}
