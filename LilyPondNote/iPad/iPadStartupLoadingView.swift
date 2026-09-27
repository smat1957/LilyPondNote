// iPadでNoteを非同期読込みしている間に表示する進捗オーバーレイを構成する。

import SwiftUI

struct iPadStartupLoadingView: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(message).font(.headline)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 12)
        }
        .transition(.opacity)
        .zIndex(10)
    }
}
