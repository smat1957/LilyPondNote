// 前回開いたPackageへ再アクセスするためのセキュリティブックマークを管理する。

import Foundation

enum iOSPackageBookmarkOptions {
    static let creation: URL.BookmarkCreationOptions = []
    static let resolution: URL.BookmarkResolutionOptions = []
}

enum PackageBookmarkStore {
    private static let bookmarkKey = "lastPackageBookmark"
    private static let relativePackageNameKey = "lastPackageRelativeName"

    /// 対象データを保存先へ書き込む。
    static func save(_ packageURL: URL) throws {
        try saveBookmark(for: packageURL, relativePackageName: nil)
    }

    /// 対象データを保存先へ書き込む。
    static func save(packageURL: URL, accessRootURL: URL) throws {
        let package = packageURL.standardizedFileURL
        let accessRoot = accessRootURL.standardizedFileURL
        guard package.deletingLastPathComponent().path == accessRoot.path else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try saveBookmark(for: accessRoot, relativePackageName: package.lastPathComponent)
    }

    /// 対象データを保存先へ書き込む。
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

    /// 保存済みデータを読み込み状態へ反映する。
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

    /// 対象データまたは保持状態を削除する。
    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: relativePackageNameKey)
    }
}

struct ResolvedPackageBookmark {
    let packageURL: URL
    let accessRootURL: URL
}
