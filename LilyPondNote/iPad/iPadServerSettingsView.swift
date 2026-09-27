// iPad版の接続、ログイン、移調方法、エディタ設定画面を構成する。

import SwiftUI

struct iPadServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: LilyPondNoteWorkspace
    @ObservedObject var authenticationSession: RemoteLilyPondAuthenticationSession
    @State private var serverURL = RemoteLilyPondConfigurationStore.savedServerURL
    @State private var email = RemoteLilyPondConfigurationStore.savedEmail
    @State private var password = ""
    @State private var message = ""
    @State private var isLoggingIn = false
    @State private var transposeMode = RemoteLilyPondConfigurationStore.savedTransposeMode
    @State private var syntaxStyle = LilyPondEditorConfigurationStore.syntaxStyle
    @State private var editorFontSize = LilyPondEditorConfigurationStore.fontSize(defaultValue: 18)

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
                Section("P0公開サーバー") {
                    if let account = authenticationSession.account {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ログイン済み")
                                    .font(.headline)
                                Text("\(account.email)・\(account.plan.displayName)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    TextField("サーバーURL（ポート番号を含む）", text: $serverURL)
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
                    Button(
                        authenticationSession.account == nil
                            ? String(localized: "ログインして接続")
                            : String(localized: "別のアカウントで再ログイン"),
                        systemImage: "person.badge.key"
                    ) {
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

    /// 入力した接続先と資格情報でログインし、成功時は共有セッションとWorkspaceへ反映する。
    private func login() {
        // 接続に失敗した場合でも、次回は直前の入力値から再開できるようにする。
        RemoteLilyPondConfigurationStore.remember(
            serverURL: serverURL,
            email: email
        )
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
                authenticationSession.didLogin(session)
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
