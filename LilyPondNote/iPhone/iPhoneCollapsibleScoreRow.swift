// iPhoneの楽譜選択一覧で階層の展開状態と選択状態を表示する行を構成する。

import Foundation
import SwiftUI

struct iPhoneCollapsibleScoreRow: View {
    let item: ScoreTreeItem
    @Binding var expandedScoreIDs: Set<UUID>
    var isSelected = false
    let select: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if item.score.children.isEmpty {
                Color.clear.frame(width: 22, height: 22)
            } else {
                Button {
                    if expandedScoreIDs.contains(item.score.id) {
                        expandedScoreIDs.remove(item.score.id)
                    } else {
                        expandedScoreIDs.insert(item.score.id)
                    }
                } label: {
                    Image(systemName: expandedScoreIDs.contains(item.score.id)
                          ? "chevron.down" : "chevron.right")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            Button(action: select) {
                Label(
                    item.score.title,
                    systemImage: item.score.children.isEmpty ? "music.note" : "folder.fill"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                .shadow(
                    color: isSelected ? Color.black.opacity(0.22) : Color.clear,
                    radius: 4,
                    y: 2
                )
        }
        .padding(.leading, CGFloat(item.depth) * 16)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .listRowSeparator(.hidden)
    }
}
