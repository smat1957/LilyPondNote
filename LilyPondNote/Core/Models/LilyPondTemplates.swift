// 新規Noteと派生楽譜で使用するLilyPond雛形を一元管理する。

enum LilyPondTemplates {
    /// 新しい派生楽譜に使用する最小構成のLilyPondソース。
    static let simpleDerivedScore = """
    \\relative c' {
      c4 d e f |
      g1
    }
    """

    /// 新規Packageの初期楽譜データ。
    static let initialScoreData = """
    music = \\relative c' {
      c4 d e f | g2 g |
    }
    """

    /// 新規Packageの初期処理手続き。
    static let initialProcessingProgram = """
    \\version "2.24.0"

    \\include "score.ly"

    \\score {
      \\new Staff \\music
    }
    """
}
