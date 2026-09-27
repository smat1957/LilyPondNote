// 前回開いたPackageへ再アクセスするためのセキュリティブックマークを管理する。

import Foundation

enum PackageBookmarkStore {
    private static let bookmarkKey = "lastPackageBookmark"
    private static let relativePackageNameKey = "lastPackageRelativeName"

    /// Packageまたは親フォルダをブックマーク化し、次回起動時に同じPackageを解決できるよう保存する。
    static func save(packageURL: URL, accessRootURL: URL? = nil) throws {
        guard let accessRootURL else {
            try saveBookmark(
                for: packageURL.standardizedFileURL,
                relativePackageName: nil
            )
            return
        }
        let package = packageURL.standardizedFileURL
        let accessRoot = accessRootURL.standardizedFileURL
        guard package.deletingLastPathComponent().path == accessRoot.path else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try saveBookmark(for: accessRoot, relativePackageName: package.lastPathComponent)
    }

    /// 指定URLのブックマークデータと、必要なら親からの相対Package名をUserDefaultsへ保存する。
    private static func saveBookmark(
        for accessURL: URL,
        relativePackageName: String?
    ) throws {
        let data = try accessURL.bookmarkData(
            options: PlatformPackageBookmarkOptions.creation,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        if let relativePackageName {
            UserDefaults.standard.set(relativePackageName, forKey: relativePackageNameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: relativePackageNameKey)
        }
    }

    /// 保存済みブックマークから前回のPackageの場所を復元する。
    static func resolve() throws -> ResolvedPackageBookmark? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: PlatformPackageBookmarkOptions.resolution,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let relativeName = UserDefaults.standard.string(forKey: relativePackageNameKey)
        if isStale {
            try saveBookmark(for: url, relativePackageName: relativeName)
        }
        guard let relativeName else {
            return ResolvedPackageBookmark(packageURL: url, accessRootURL: url)
        }
        guard !relativeName.isEmpty,
              relativeName == URL(filePath: relativeName).lastPathComponent,
              relativeName != ".",
              relativeName != ".." else {
            clear()
            throw CocoaError(.fileReadInvalidFileName)
        }
        return ResolvedPackageBookmark(
            packageURL: url.appending(path: relativeName, directoryHint: .isDirectory),
            accessRootURL: url
        )
    }

    /// 前回Packageのブックマークと相対名を削除し、次回起動時の自動復元を無効にする。
    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: relativePackageNameKey)
    }
}

struct ResolvedPackageBookmark {
    let packageURL: URL
    let accessRootURL: URL
}
