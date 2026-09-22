// iPadでPackageブックマークを作成・復元する際のOS固有オプションを定義する。

import Foundation

enum PlatformPackageBookmarkOptions {
    static let creation: URL.BookmarkCreationOptions = []
    static let resolution: URL.BookmarkResolutionOptions = []
}
