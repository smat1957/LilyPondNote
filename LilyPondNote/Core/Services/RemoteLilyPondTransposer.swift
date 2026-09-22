// リモートサービスを利用してLilyPondソースを移調する。

import Foundation

enum RemoteLilyPondTransposer {
    /// 認証付きでサーバーへ移調を依頼し、変換後のソースを受け取る。
    static func transpose(
        source: String,
        from sourcePitch: String,
        to destinationPitch: String,
        session: URLSession = .shared
    ) async throws -> String {
        guard let saved = RemoteLilyPondConfigurationStore.loadSession() else {
            throw LilyPondCompilationError.authenticationRequired(
                String(localized: "移調サービスを利用するにはログインしてください。")
            )
        }
        var request = URLRequest(url: saved.serverURL.appending(path: "transpose"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(saved.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(sourcePitch: sourcePitch, destinationPitch: destinationPitch, source: source)
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw LilyPondCompilationError.invalidServerResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data).message)
                ?? String(decoding: data, as: UTF8.self)
            if response.statusCode == 401 {
                throw LilyPondCompilationError.authenticationRequired(
                    String(localized: "ログインの有効期限が切れました。再ログインしてください。")
                )
            }
            throw LilyPondCompilationError.serverResponse(
                statusCode: response.statusCode,
                message: message
            )
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data).transposedSource
    }

    private struct RequestBody: Encodable {
        let sourcePitch: String
        let destinationPitch: String
        let source: String
    }

    private struct ResponseBody: Decodable { let transposedSource: String }
    private struct ErrorBody: Decodable { let message: String }
}
