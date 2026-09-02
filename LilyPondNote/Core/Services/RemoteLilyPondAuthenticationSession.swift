// リモートLilyPondサービスのログイン状態と契約プランを保持する。

import Combine
import Foundation

/// LilyPondNoteのログイン状態を全プラットフォームで共有する状態モデルです。
@MainActor
final class RemoteLilyPondAuthenticationSession: ObservableObject {
    enum State: Equatable {
        case signedOut
        case checking
        case signedIn(RemoteLilyPondAccount)
        case failed(String)
    }

    @Published private(set) var state: State = .checking

    var account: RemoteLilyPondAccount? {
        guard case .signedIn(let account) = state else { return nil }
        return account
    }

    /// 認証状態を更新する。
    func refresh() async {
        state = .checking
        guard let saved = RemoteLilyPondConfigurationStore.loadSession() else {
            state = .signedOut
            return
        }
        do {
            let account = try await RemoteLilyPondAuthentication.currentAccount(
                serverURL: saved.serverURL,
                accessToken: saved.accessToken
            )
            state = .signedIn(account)
        } catch let error as LilyPondCompilationError {
            if case .authenticationRequired = error {
                RemoteLilyPondConfigurationStore.logout()
                state = .signedOut
            } else {
                state = .failed(error.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 認証状態を更新する。
    func didLogin(_ session: RemoteLilyPondAuthentication.Session) {
        state = .signedIn(session.account)
    }

    /// 認証状態を更新する。
    func logout() {
        RemoteLilyPondConfigurationStore.logout()
        state = .signedOut
    }
}
