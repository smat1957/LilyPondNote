// アプリのアイコン、名称、バージョン、概要を表示する共通画面を定義する。

import SwiftUI

struct LilyPondAboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        return String(format: String(localized: "app.version"), version)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image("AboutIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("LilyPondNote")
                .font(.title2.bold())

            Text(versionText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("LilyPond楽譜データをNotePackageとして管理します。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("OK") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: 460)
    }
}
