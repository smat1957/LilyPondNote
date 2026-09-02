// 1つの楽譜に対応するソース・処理手続き・PDF・ログの保存場所を表す。

import Foundation

struct ScoreFileSet: Equatable {
    static let scoreDataFileName = "score.ly"
    static let processingProgramFileName = "main.ly"
    static let pdfFileName = "output.pdf"
    static let compileLogFileName = "compile.log"
    static let childrenDirectoryName = "Scores"

    let directoryURL: URL

    var scoreDataURL: URL {
        directoryURL.appendingPathComponent(Self.scoreDataFileName)
    }

    var processingProgramURL: URL {
        directoryURL.appendingPathComponent(Self.processingProgramFileName)
    }

    var pdfURL: URL {
        directoryURL.appendingPathComponent(Self.pdfFileName)
    }

    var compileLogURL: URL {
        directoryURL.appendingPathComponent(Self.compileLogFileName)
    }

    var childrenDirectoryURL: URL {
        directoryURL.appendingPathComponent(
            Self.childrenDirectoryName,
            isDirectory: true
        )
    }
}
