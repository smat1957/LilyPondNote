// macOS版の接続、ログイン、エディタ設定画面を構成する。

import SwiftUI

struct macOSServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var syntaxStyle = LilyPondEditorConfigurationStore.syntaxStyle
    @State private var serverURL = RemoteLilyPondConfigurationStore.savedServerURL
    @State private var email = RemoteLilyPondConfigurationStore.savedEmail
    @State private var password = ""
    @State private var message = ""
    @State private var isLoggingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section("エディタの配色") {
                    Picker("キーワード配色", selection: $syntaxStyle) {
                        ForEach(LilyPondSyntaxStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .onChange(of: syntaxStyle) { _, style in
                        LilyPondEditorConfigurationStore.syntaxStyle = style
                    }
                }

                Section("リモートサーバー") {
                    TextField("サーバーURL", text: $serverURL)
                    TextField("メールアドレス", text: $email)
                    SecureField("パスワード", text: $password)
                    Button("ログインして接続", systemImage: "person.badge.key") {
                        login()
                    }
                    .disabled(isLoggingIn)
                    if !message.isEmpty {
                        Text(message)
                            .foregroundStyle(
                                message == String(localized: "接続しました。")
                                    ? .green : .secondary
                            )
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("サービス設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .onDisappear { saveSettings() }
        }
    }

    /// 接続先とエディタ設定を保存する。
    private func saveSettings() {
        LilyPondEditorConfigurationStore.syntaxStyle = syntaxStyle
        RemoteLilyPondConfigurationStore.remember(serverURL: serverURL, email: email)
    }

    /// 入力した接続先と資格情報でログインし、成功時は共有セッションへ反映する。
    private func login() {
        saveSettings()
        isLoggingIn = true
        Task {
            defer { isLoggingIn = false }
            do {
                let session = try await RemoteLilyPondAuthentication.login(
                    serverURL: serverURL,
                    email: email,
                    password: password
                )
                try RemoteLilyPondConfigurationStore.save(session: session, email: email)
                password = ""
                message = String(localized: "接続しました。")
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
