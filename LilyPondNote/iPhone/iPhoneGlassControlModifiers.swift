// iPhoneのタイトルバーで使う半透明操作ボタンの外観を定義する。

import SwiftUI

/// 押しやすい半透明の円形操作ボタンを構成する。
struct iPhoneGlassCircleControlModifier: ViewModifier {
    /// 渡されたラベルへ半透明の円形ボタン外観を適用する。
    func body(content: Content) -> some View {
        content
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.42), lineWidth: 1)
            }
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.10), radius: 7, y: 3)
    }
}

/// 押しやすい半透明のカプセル型操作ボタンを構成する。
struct iPhoneGlassCapsuleControlModifier: ViewModifier {
    /// 渡されたラベルへ半透明のカプセル型ボタン外観を適用する。
    func body(content: Content) -> some View {
        content
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.42), lineWidth: 1)
            }
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.10), radius: 7, y: 3)
    }
}
