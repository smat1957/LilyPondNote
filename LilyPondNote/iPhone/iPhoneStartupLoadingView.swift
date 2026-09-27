// iPhoneで前回Noteを非同期復元している間に表示する進捗オーバーレイを構成する。

import SwiftUI

struct iPhoneStartupLoadingView: View {
    let phase: StartupLoadingPhase

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(phase.message).font(.headline)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 12)
        }
    }
}
