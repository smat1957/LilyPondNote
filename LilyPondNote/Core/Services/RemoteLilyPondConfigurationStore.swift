// リモートサービスの接続先、認証情報、移調設定を保存・復元する。

import Foundation
import Security

enum RemoteLilyPondConfigurationStore {
    private static let serverURLKey = "lilyPondServerURL"
    private static let emailKey = "lilyPondServerEmail"
    private static let account = "p1-user-access-token"
    private static let transposeModeKey = "lilyPondTransposeMode"

    static var savedTransposeMode: LilyPondTransposeMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: transposeModeKey),
                  let mode = LilyPondTransposeMode(rawValue: rawValue) else {
                return .local
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: transposeModeKey)
        }
    }

    static var savedServerURL: String {
        guard let stored = UserDefaults.standard.string(forKey: serverURLKey) else {
            return ""
        }
        let normalized = stored.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized == "http://192.168.3.22" {
            let migrated = "http://192.168.3.22:8081"
            UserDefaults.standard.set(migrated, forKey: serverURLKey)
            return migrated
        }
        return stored
    }

    static var savedEmail: String {
        UserDefaults.standard.string(forKey: emailKey) ?? ""
    }

    /// 対象データを保存先へ書き込む。
    static func save(
        session: RemoteLilyPondAuthentication.Session,
        email: String
    ) throws {
        let data = Data(session.accessToken.utf8)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConfigurationError.keychain(status)
        }
        remember(serverURL: session.serverURL.absoluteString, email: email)
    }

    /// ログインの成否にかかわらず、利用者が最後に入力した接続先を保存する。
    /// URL文字列をそのまま保存するため、明示的なポート番号も次回まで保持される。
    static func remember(serverURL: String, email: String) {
        UserDefaults.standard.set(
            serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: serverURLKey
        )
        UserDefaults.standard.set(
            email.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: emailKey
        )
    }

    /// 保存済みデータを読み込み状態へ反映する。
    static func loadCompiler() -> (any LilyPondCompiling)? {
        guard let session = loadSession() else { return nil }
        return RemoteLilyPondCompiler(
            serverURL: session.serverURL,
            accessToken: session.accessToken
        )
    }

    /// 保存済みデータを読み込み状態へ反映する。
    static func loadSession() -> (serverURL: URL, accessToken: String)? {
        guard let url = try? RemoteLilyPondAuthentication.validatedServerURL(
            savedServerURL
        ) else { return nil }
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return (url, token)
    }

    /// 認証状態を更新する。
    static func logout() {
        SecItemDelete(query as CFDictionary)
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String:
                "\(Bundle.main.bundleIdentifier ?? "LilyPondNote").p1-auth",
            kSecAttrAccount as String: account
        ]
    }

    private enum ConfigurationError: LocalizedError {
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                String(format: String(localized: "login.keychain.error"), status)
            }
        }
    }
}
