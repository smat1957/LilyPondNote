// 設定に応じてローカルまたはリモートで移調を実行する。

import Foundation
import LilyPondTransposeCore

enum LilyPondTransposeMode: String, CaseIterable, Identifiable {
    case local
    case remote

    var id: Self { self }

    var displayName: String {
        switch self {
        case .local: String(localized: "ローカル")
        case .remote: String(localized: "リモート")
        }
    }

    var explanation: String {
        switch self {
        case .local:
            String(localized: "この端末内で処理します。利用回数には加算されません。")
        case .remote:
            String(localized: "ログイン中のサーバーで処理し、月間利用回数に加算します。")
        }
    }
}

enum LilyPondTransposeService {
    /// 入力を処理して生成結果を返す。
    static func transpose(
        source: String,
        from sourcePitch: String,
        to destinationPitch: String
    ) async throws -> String {
        switch RemoteLilyPondConfigurationStore.savedTransposeMode {
        case .local:
            return try LilyPondTransposer().transpose(
                source,
                from: sourcePitch,
                to: destinationPitch
            )
        case .remote:
            return try await RemoteLilyPondTransposer.transpose(
                source: source,
                from: sourcePitch,
                to: destinationPitch
            )
        }
    }
}
