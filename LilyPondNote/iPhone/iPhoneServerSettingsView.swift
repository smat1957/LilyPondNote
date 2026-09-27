// iPhone版の接続、ログイン、移調方法、エディタ設定画面を構成する。

import SwiftUI

struct iPhoneServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: LilyPondNoteWorkspace
    @State private var serverURL = RemoteLilyPondConfigurationStore.savedServerURL
    @State private var email = RemoteLilyPondConfigurationStore.savedEmail
    @State private var password = ""
    @State private var message = ""
    @State private var isLoggingIn = false
    @State private var transposeMode = RemoteLilyPondConfigurationStore.savedTransposeMode
    @State private var syntaxStyle = LilyPondEditorConfigurationStore.syntaxStyle
    @State private var editorFontSize = LilyPondEditorConfigurationStore.fontSize(defaultValue: 17)

    var body: some View {
        NavigationStack {
            Form {
                Section("移調処理") {
                    Toggle("リモートで移調", isOn: usesRemoteTranspose)
                    .onChange(of: transposeMode) { _, mode in
                        RemoteLilyPondConfigurationStore.savedTransposeMode = mode
                    }
                }
                Section("エディタ") {
                    Picker("キーワード配色", selection: $syntaxStyle) {
                        ForEach(LilyPondSyntaxStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .onChange(of: syntaxStyle) { _, style in
                        LilyPondEditorConfigurationStore.syntaxStyle = style
                    }
                    Picker("文字サイズ", selection: $editorFontSize) {
                        ForEach(LilyPondEditorConfigurationStore.availableFontSizes, id: \.self) { size in
                            Text("\(Int(size)) pt").tag(size)
                        }
                    }
                    .onChange(of: editorFontSize) { _, size in
                        LilyPondEditorConfigurationStore.saveFontSize(size)
                    }
                }
                Section("P1認証サーバー") {
                    TextField("サーバーURL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("メールアドレス", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("パスワード", text: $password)
                }
                Section {
                    Button("ログインして接続", systemImage: "person.badge.key") {
                        login()
                    }
                    .disabled(isLoggingIn)
                    if !message.isEmpty { Text(message) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .onDisappear {
                RemoteLilyPondConfigurationStore.savedTransposeMode = transposeMode
                LilyPondEditorConfigurationStore.syntaxStyle = syntaxStyle
                LilyPondEditorConfigurationStore.saveFontSize(editorFontSize)
                RemoteLilyPondConfigurationStore.remember(
                    serverURL: serverURL,
                    email: email
                )
            }
        }
    }

    private var usesRemoteTranspose: Binding<Bool> {
        Binding(
            get: { transposeMode == .remote },
            set: { transposeMode = $0 ? .remote : .local }
        )
    }

    /// 入力した接続先と資格情報でログインし、成功時はWorkspaceのコンパイラへ反映する。
    private func login() {
        isLoggingIn = true
        Task {
            defer { isLoggingIn = false }
            do {
                let session = try await RemoteLilyPondAuthentication.login(
                    serverURL: serverURL,
                    email: email,
                    password: password
                )
                try RemoteLilyPondConfigurationStore.save(
                    session: session,
                    email: email
                )
                workspace.configureCompiler(
                    RemoteLilyPondCompiler(
                        serverURL: session.serverURL,
                        accessToken: session.accessToken
                    )
                )
                password = ""
                message = String(localized: "接続しました。")
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
