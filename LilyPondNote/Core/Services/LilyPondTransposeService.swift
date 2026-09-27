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

/// 派生楽譜の移調画面で選択できる、LilyPond表記の調と初期値を共通管理する。
enum LilyPondTransposePitchSelection {
    /// 五度圏に沿った一般的な15長調。異名同音もLilyPondのオランダ式音名で保持する。
    static let availableKeys = [
        "c", "g", "d", "a", "e", "b", "fis", "cis",
        "ces", "ges", "des", "as", "es", "bes", "f",
    ]

    /// 楽譜の最初の調を移調元、その属調を移調先として返す。
    static func defaultPitches(for source: String) -> (source: String, destination: String) {
        let sourcePitch = firstKey(in: source) ?? "c"
        return (sourcePitch, dominant(of: sourcePitch))
    }

    /// 楽譜中の最初の `\key` から、選択肢に含まれる主音を取得する。
    static func firstKey(in source: String) -> String? {
        let pattern = #"\\key\s+(ces|ges|des|as|es|bes|fis|cis|c|g|d|a|e|b|f)(?=\s+\\[A-Za-z]+\b)"#
        let uncommented = sourceWithoutComments(source)
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: uncommented,
                range: NSRange(uncommented.startIndex..., in: uncommented)
              ) else { return nil }

        guard let range = Range(match.range(at: 1), in: uncommented) else { return nil }
        return String(uncommented[range])
    }

    /// 五度圏上で右隣の調を返す。Cisの属調は選択肢内の異名同音Asで表す。
    static func dominant(of pitch: String) -> String {
        let dominants = [
            "ces": "ges", "ges": "des", "des": "as", "as": "es",
            "es": "bes", "bes": "f", "f": "c", "c": "g", "g": "d",
            "d": "a", "a": "e", "e": "b", "b": "fis", "fis": "cis",
            "cis": "as",
        ]
        return dominants[pitch] ?? "g"
    }

    /// LilyPondの行コメントとブロックコメントを除外する。
    private static func sourceWithoutComments(_ source: String) -> String {
        var result = ""
        var index = source.startIndex
        var isInBlockComment = false

        while index < source.endIndex {
            let next = source.index(after: index)
            let pair = next < source.endIndex ? String(source[index...next]) : ""

            if isInBlockComment {
                if pair == "%}" {
                    isInBlockComment = false
                    index = source.index(after: next)
                } else {
                    if source[index] == "\n" { result.append("\n") }
                    index = next
                }
            } else if pair == "%{" {
                isInBlockComment = true
                index = source.index(after: next)
            } else if source[index] == "%" {
                while index < source.endIndex, source[index] != "\n" {
                    index = source.index(after: index)
                }
            } else {
                result.append(source[index])
                index = next
            }
        }
        return result
    }
}

/// 移調先へ加えるオクターブ指定をLilyPondの記法へ変換する。
enum LilyPondTransposeOctave: String, CaseIterable, Identifiable {
    case down
    case unchanged
    case up

    var id: Self { self }

    var displayName: String {
        switch self {
        case .down: String(localized: "オクターブ下げる")
        case .unchanged: String(localized: "変更なし")
        case .up: String(localized: "オクターブ上げる")
        }
    }

    /// 選択された上下方向をLilyPondのオクターブ記号へ変換し、移調先音名へ付加する。
    func applying(to pitch: String) -> String {
        switch self {
        case .down: pitch + ","
        case .unchanged: pitch
        case .up: pitch + "'"
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
