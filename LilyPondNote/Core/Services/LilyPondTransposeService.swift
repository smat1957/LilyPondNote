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
    /// 保存済み設定に応じてローカルまたはサーバーで移調する。
    static func transpose(
        source: String,
        from sourcePitch: String,
        to destinationPitch: String
    ) async throws -> String {
        // ローカルとリモートで同じ正規化済みの指示を使用する。
        let normalizedSourcePitch = try LilyPondTransposer.normalizePitch(sourcePitch)
        let normalizedDestinationPitch = try LilyPondTransposer.normalizePitch(destinationPitch)

        switch RemoteLilyPondConfigurationStore.savedTransposeMode {
        case .local:
            return try LilyPondTransposer().transpose(
                source,
                from: normalizedSourcePitch,
                to: normalizedDestinationPitch
            )
        case .remote:
            return try await RemoteLilyPondTransposer.transpose(
                source: source,
                from: normalizedSourcePitch,
                to: normalizedDestinationPitch
            )
        }
    }
}
