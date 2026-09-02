// macOSでPackageブックマークを作る際のプラットフォーム固有オプションを定義する。

import Foundation

enum PlatformPackageBookmarkOptions {
    static let creation: URL.BookmarkCreationOptions = [.withSecurityScope]
    static let resolution: URL.BookmarkResolutionOptions = [.withSecurityScope]
}
