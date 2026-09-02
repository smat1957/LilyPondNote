// Noteと楽譜を書き出す際のファイル名処理を全プラットフォームで共有する。

import Foundation

enum NoteFileUtilities {
    /// ファイル名として扱えない区切り文字を安全な文字へ置換する。
    static func safeFileName(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    /// 選択楽譜を書き出すディレクトリURLを組み立てる。
    static func exportURL(for scoreTitle: String, in parentURL: URL) -> URL {
        parentURL.appendingPathComponent(safeFileName(scoreTitle), isDirectory: true)
    }
}
