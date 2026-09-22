// リモートLilyPondサービスへのログインとPDFコンパイル通信を行う。

import Foundation

actor RemoteLilyPondCompiler: LilyPondCompiling {
    private let serverURL: URL
    private let accessToken: String
    private let session: URLSession

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(serverURL: URL, accessToken: String, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.accessToken = accessToken
        self.session = session
    }

    /// 認証付きでサーバーへ版組を依頼し、PDFとログを受け取る。
    func compile(_ input: LilyPondCompilationInput) async throws
        -> LilyPondCompilationResult {
        let endpoint = serverURL.appending(path: "compile")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(
            CompileRequest(
                scoreID: input.scoreID,
                processingProgram: input.processingProgram,
                scoreData: input.scoreData
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw LilyPondCompilationError.invalidServerResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(
                ErrorResponse.self,
                from: data
            ).message) ?? String(decoding: data, as: UTF8.self)
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

        let result = try JSONDecoder().decode(CompileResponse.self, from: data)
        guard let pdfData = Data(base64Encoded: result.pdfBase64) else {
            throw LilyPondCompilationError.pdfNotProduced(log: result.log)
        }
        return LilyPondCompilationResult(
            pdfData: pdfData,
            log: result.log,
            compilerVersion: result.compilerVersion
                ?? LilyPondCompilerVersion.detected(inPDF: pdfData)
                ?? LilyPondCompilerVersion.detected(in: result.log)
                ?? String(localized: "不明")
        )
    }
}

enum RemoteLilyPondAuthentication {
    struct Session: Sendable {
        let serverURL: URL
        let accessToken: String
        let account: RemoteLilyPondAccount
    }

    /// 認証状態を更新する。
    static func login(
        serverURL: String,
        email: String,
        password: String,
        session: URLSession = .shared
    ) async throws -> Session {
        let url = try validatedServerURL(serverURL)
        var request = URLRequest(url: url.appending(path: "login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            LoginRequest(
                email: email,
                password: password,
                service: "lilypondnote"
            )
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw LilyPondCompilationError.invalidServerResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw LilyPondCompilationError.authenticationRequired(
                String(localized: "メールアドレスまたはパスワードを確認してください。")
            )
        }
        let login = try JSONDecoder().decode(LoginResponse.self, from: data)
        let account = try await currentAccount(
            serverURL: url,
            accessToken: login.accessToken,
            session: session
        )
        return Session(
            serverURL: url,
            accessToken: login.accessToken,
            account: account
        )
    }

    /// 認証済みサーバーから現在のアカウント情報を取得する。
    static func currentAccount(
        serverURL: URL,
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> RemoteLilyPondAccount {
        var request = URLRequest(url: serverURL.appending(path: "me"))
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw LilyPondCompilationError.invalidServerResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw LilyPondCompilationError.authenticationRequired(
                String(localized: "ログインの有効期限が切れました。再ログインしてください。")
            )
        }
        let account = try JSONDecoder().decode(RemoteLilyPondAccount.self, from: data)
        guard account.service == "lilypondnote" else {
            throw LilyPondCompilationError.authenticationRequired(
                String(localized: "LilyPondNote用ではないP0入口が指定されています。サーバーURLとポート番号を確認してください。")
            )
        }
        return account
    }

    /// 入力または対象の有効性を確認する。
    static func validatedServerURL(_ value: String) throws -> URL {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw LilyPondCompilationError.invalidServerURL
        }
        return url
    }
}

private struct CompileRequest: Encodable {
    let scoreID: UUID
    let processingProgram: String
    let scoreData: String
}

private struct CompileResponse: Decodable {
    let pdfBase64: String
    let log: String
    let compilerVersion: String?
}

private struct LoginRequest: Encodable {
    let email: String
    let password: String
    let service: String
}

struct RemoteLilyPondAccount: Decodable, Equatable, Sendable {
    struct UsageByService: Decodable, Equatable, Sendable {
        let typeset: Int
        let transpose: Int
    }

    let service: String
    let id: Int
    let email: String
    let plan: RemoteLilyPondPlan
    let status: String
    let used: Int
    let usageByService: UsageByService
    let limit: Int

    private enum CodingKeys: String, CodingKey {
        case service, id, email, plan, status, used, usageByService, limit
    }

    /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        service = try values.decode(String.self, forKey: .service)
        id = try values.decode(Int.self, forKey: .id)
        email = try values.decode(String.self, forKey: .email)
        plan = try values.decodeIfPresent(RemoteLilyPondPlan.self, forKey: .plan) ?? .free
        status = try values.decode(String.self, forKey: .status)
        used = try values.decode(Int.self, forKey: .used)
        usageByService = try values.decode(UsageByService.self, forKey: .usageByService)
        limit = try values.decode(Int.self, forKey: .limit)
    }
}

enum RemoteLilyPondPlan: String, Decodable, Equatable, Sendable {
    case free, standard, pro

    var displayName: String {
        switch self {
        case .free: "Free"
        case .standard: "Standard"
        case .pro: "Pro"
        }
    }
}

private struct LoginResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct ErrorResponse: Decodable {
    let message: String
}
