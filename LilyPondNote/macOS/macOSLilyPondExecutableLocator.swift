// macOSにインストールされたLilyPond実行ファイルを探索する。

import Foundation

struct macOSLilyPondExecutableLocator: Sendable {
    static let defaultsKey = "lilyPondExecutablePath"

    /// 既知のインストール先とPATHを順に調べ、実行可能なLilyPondコマンドのURLを返す。
    func locate() -> URL? {
        candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private var candidates: [URL] {
        var paths: [String] = []
        if let configured = UserDefaults.standard.string(forKey: Self.defaultsKey),
           !configured.isEmpty {
            paths.append(configured)
        }
        paths += [
            "/opt/homebrew/bin/lilypond",
            "/usr/local/bin/lilypond"
        ]
        if let environmentPath = ProcessInfo.processInfo.environment["PATH"] {
            paths += environmentPath.split(separator: ":").map {
                URL(filePath: String($0), directoryHint: .isDirectory)
                    .appending(path: "lilypond").path
            }
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }.map {
            URL(filePath: $0).resolvingSymlinksInPath()
        }
    }
}
