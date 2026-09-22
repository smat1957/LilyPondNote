// LilyPondコンパイラの共通入出力とエラー、バージョン検出を定義する。

import Foundation
import PDFKit

struct LilyPondCompilationInput: Sendable {
    let scoreID: UUID
    let processingProgram: String
    let scoreData: String
}

struct LilyPondCompilationResult: Sendable {
    let pdfData: Data
    let log: String
    let compilerVersion: String
}

enum LilyPondCompilerVersion {
    /// 入力または対象の有効性を確認する。
    static func detected(in log: String) -> String? {
        let pattern = #"(?:GNU\s+)?LilyPond\s+([0-9]+(?:\.[0-9]+){1,3})"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: log,
                  range: NSRange(log.startIndex..<log.endIndex, in: log)
              ),
              let range = Range(match.range(at: 1), in: log) else { return nil }
        return String(log[range])
    }

    /// 入力または対象の有効性を確認する。
    static func detected(inPDF data: Data) -> String? {
        guard let document = PDFDocument(data: data),
              let creator = document.documentAttributes?[
                  PDFDocumentAttribute.creatorAttribute
              ] as? String
        else { return nil }
        return detected(in: creator)
    }
}

protocol LilyPondCompiling: Sendable {
    /// LilyPondソースをコンパイルしてPDF・ログ・バージョンを返す。
    func compile(_ input: LilyPondCompilationInput) async throws
        -> LilyPondCompilationResult
}

enum LilyPondCompilationError: LocalizedError {
    case executableNotFound
    case executionFailed(exitCode: Int32, log: String)
    case pdfNotProduced(log: String)
    case invalidServerURL
    case authenticationRequired(String)
    case invalidServerResponse
    case serverResponse(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            String(localized: "LilyPondの実行ファイルが見つかりません。")
        case .executionFailed(_, let log), .pdfNotProduced(let log):
            log.isEmpty ? String(localized: "PDFを生成できませんでした。") : log
        case .invalidServerURL:
            String(localized: "P1認証サーバーのURLが正しくありません。")
        case .authenticationRequired(let message):
            message
        case .invalidServerResponse:
            String(localized: "版組サーバーから有効な応答を受信できませんでした。")
        case .serverResponse(let statusCode, let message):
            message.isEmpty
                ? String(format: String(localized: "compiler.http.error"), Int64(statusCode))
                : message
        }
    }
}
