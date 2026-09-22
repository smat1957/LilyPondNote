// macOS版の接続、ログイン、移調方法、エディタ設定画面を構成する。

import SwiftUI

struct macOSServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transposeMode = RemoteLilyPondConfigurationStore.savedTransposeMode
    @State private var syntaxStyle = LilyPondEditorConfigurationStore.syntaxStyle
    @State private var serverURL = RemoteLilyPondConfigurationStore.savedServerURL
    @State private var email = RemoteLilyPondConfigurationStore.savedEmail
    @State private var password = ""
    @State private var message = ""
    @State private var isLoggingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section("移調処理") {
                    Toggle("リモートで移調", isOn: usesRemoteTranspose)
                    .onChange(of: transposeMode) { _, mode in
                        RemoteLilyPondConfigurationStore.savedTransposeMode = mode
                    }
                }

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

    /// 接続先・移調方法・エディタ設定を保存する。
    private func saveSettings() {
        RemoteLilyPondConfigurationStore.savedTransposeMode = transposeMode
        LilyPondEditorConfigurationStore.syntaxStyle = syntaxStyle
        RemoteLilyPondConfigurationStore.remember(serverURL: serverURL, email: email)
    }

    private var usesRemoteTranspose: Binding<Bool> {
        Binding(
            get: { transposeMode == .remote },
            set: { transposeMode = $0 ? .remote : .local }
        )
    }

    /// 認証状態を更新する。
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
