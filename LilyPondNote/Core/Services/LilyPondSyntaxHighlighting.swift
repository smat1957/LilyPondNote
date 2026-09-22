// LilyPondソースの配色設定と構文解析結果を全エディタへ提供する。

import Foundation

enum LilyPondSyntaxStyle: String, CaseIterable, Identifiable {
    case emacs
    case vim
    case vscode

    var id: Self { self }

    var displayName: String {
        switch self {
        case .emacs: "LilyPond Emacs mode"
        case .vim: "LilyPond Vim mode"
        case .vscode: "VSCode LilyPond Syntax Highlighting"
        }
    }

    /// 構文要素に割り当てる配色上の役割を返す。
    func colorRole(for face: LilyPondSyntaxFace) -> LilyPondSyntaxColorRole {
        switch (self, face) {
        case (.emacs, .functionName): .blue
        case (.emacs, .keyword): .purple
        case (.emacs, .constant): .indigo
        case (.emacs, .variableName): .brown
        case (.emacs, .type): .green
        case (.emacs, .string): .orange
        case (.emacs, .warning), (.emacs, .comment): .red
        case (.emacs, .builtin): .teal

        case (.vim, .functionName): .cyan
        case (.vim, .keyword): .blue
        case (.vim, .constant): .purple
        case (.vim, .variableName): .teal
        case (.vim, .type): .pink
        case (.vim, .string): .brown
        case (.vim, .warning): .red
        case (.vim, .builtin): .indigo
        case (.vim, .comment): .gray

        case (.vscode, .functionName): .blue
        case (.vscode, .keyword): .pink
        case (.vscode, .constant): .purple
        case (.vscode, .variableName): .cyan
        case (.vscode, .type): .teal
        case (.vscode, .string): .orange
        case (.vscode, .warning): .red
        case (.vscode, .builtin): .indigo
        case (.vscode, .comment): .green
        }
    }
}

enum LilyPondSyntaxColorRole {
    case blue, purple, indigo, brown, green, orange, red, teal, pink, cyan, gray
}

enum LilyPondEditorConfigurationStore {
    private static let syntaxStyleKey = "lilyPondSyntaxStyle"
    private static let fontSizeKey = "lilyPondEditorFontSize"

    static let availableFontSizes: [Double] = [14, 16, 17, 18, 20, 22, 24]

    static var syntaxStyle: LilyPondSyntaxStyle {
        get {
            guard let value = UserDefaults.standard.string(forKey: syntaxStyleKey),
                  let style = LilyPondSyntaxStyle(rawValue: value) else {
                return .emacs
            }
            return style
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: syntaxStyleKey) }
    }

    /// 保存済み文字サイズを読み、無効値なら既定値を返す。
    static func fontSize(defaultValue: Double) -> Double {
        guard UserDefaults.standard.object(forKey: fontSizeKey) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.double(forKey: fontSizeKey)
    }

    /// 選択したエディタ文字サイズを設定へ保存する。
    static func saveFontSize(_ value: Double) {
        UserDefaults.standard.set(value, forKey: fontSizeKey)
    }
}

/// LilyPond公式 `elisp/lilypond-font-lock.el` のface分類に対応する。
enum LilyPondSyntaxFace: Sendable {
    case functionName
    case keyword
    case constant
    case variableName
    case type
    case string
    case warning
    case builtin
    case comment
}

struct LilyPondSyntaxSpan: Sendable {
    let range: NSRange
    let face: LilyPondSyntaxFace
}

/// UIや色には依存せず、公式Emacs modeと同じ順序で構文範囲を返す。
enum LilyPondSyntaxHighlighting {
    /// 文字列の変更後も選択範囲が範囲外にならないよう補正する。
    static func clampedSelection(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    private struct Rule {
        let expression: NSRegularExpression
        let captureGroup: Int
        let face: LilyPondSyntaxFace

        /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
        init(
            _ pattern: String,
            captureGroup: Int = 0,
            face: LilyPondSyntaxFace,
            options: NSRegularExpression.Options = []
        ) {
            expression = try! NSRegularExpression(pattern: pattern, options: options)
            self.captureGroup = captureGroup
            self.face = face
        }
    }

    // lilypond-font-lock.elでは小文字の組込み語をkeyword、先頭大文字を
    // identifierとして分類する。ここでは標準入力で頻出する組込み語を明示する。
    private static let keywordNames = [
        "absolute", "addlyrics", "alternative", "book", "bookpart",
        "chordmode", "chords", "context", "drummode", "figuremode",
        "header", "include", "key", "layout", "lyricmode", "lyrics",
        "markuplist", "midi", "mode", "new", "notemode", "paper",
        "relative", "repeat", "score", "set", "simultaneous", "tempo",
        "time", "transpose", "tuplet", "unfoldRepeats", "version", "with"
    ]

    private static let keywordPattern = keywordNames
        .map(NSRegularExpression.escapedPattern(for:))
        .joined(separator: "|")

    /// 公式font-lockの最終的な優先順位を表す。
    ///
    /// Emacsの通常規則は、先にfaceが付いた文字を後続規則で上書きしない。
    /// そのため通常規則は公式定義の逆順に並べ、後半の「上に重ねる」規則は
    /// 公式定義順に適用する。返却順に着色すれば公式と同じ結果になる。
    private static let rules: [Rule] = [
        // 音名・休符・スキップ。音高記号、長短音価、付点、倍率を含む。
        Rule(
            #"(?<![\p{L}\\])(?:[a-g](?:isis|eses|is|es)?|as|bes|ces|des|ees|fes|ges|r|s|R)[,']*[?!]?(?:(?:128|64|32|16|8|4|2|1)\.*(?:\s*\*\s*\d+(?:/\d+)?)?|\\(?:longa|breve|maxima)\.*)?(?![\p{L}])"#,
            face: .type
        ),
        // Staff, Voice, FiguredBass等の大文字予約語。
        Rule(#"\b[A-Z][A-Za-z_]*\b"#, face: .variableName),
        // 代入記号の左辺と単純な右辺。
        Rule(#"\b[_A-Za-z][_.A-Za-z0-9-]*(?=\s*=)"#, face: .variableName),
        Rule(#"(?<==)\s*([_A-Za-z][_.A-Za-z0-9-]*)"#, captureGroup: 1, face: .variableName),
        // ユーザー定義識別子・公式一覧外のコマンド。
        Rule(#"\\[\p{L}]+(?:[-_][\p{L}]+)*"#, face: .constant),
        // 組込みキーワード: \relative, \score など。
        Rule(#"\\(?:"# + keywordPattern + #")\b"#, face: .keyword),
        // 組込み識別子: \voiceOne など、大文字を含むバックスラッシュ名。
        Rule(#"\\[A-Za-z]*[A-Z][A-Za-z]*(?:[-_][A-Za-z]+)*"#, face: .functionName),
        // lyricsのブロック内容。
        Rule(#"\\lyrics[^\{<]*(\{[^}]*|<[^>]*>)"#, captureGroup: 1, face: .string, options: [.dotMatchesLineSeparators]),
        // 水平グループ: { } [ ] ~ \[ \]
        Rule(#"-?(?:[\[\]~{}]|\\[\[\]])"#, face: .constant),
        // 垂直グループ: < > << >> と声部区切り \\
        Rule(#"(?:<<|>>|<|>|\\\\)"#, face: .functionName),
        // 表情グループ: スラー、ヘアピン等。
        Rule(#"(?:-?\\[()<>!]|[-^_]?[()])"#, face: .builtin),
        // 埋め込みScheme。公式と同様に文字列faceで扱う。
        Rule(#"[_^-]?#(?:#[ft]|-?[0-9.]+|'?\([^\n]*\)|['`]?[A-Za-z:][A-Za-z0-9:.-]*)"#, face: .string),
        // 文字列。エスケープと改行を許容する。
        Rule(#"[_^-]?\"(?:[^\"\\]|\\.)*(?:\"|$)"#, face: .string, options: [.dotMatchesLineSeparators]),
        // 複数行コメントと行コメントを最後に適用する。
        Rule(#"%\{[\s\S]*?%\}|%[^\n]*"#, face: .comment)
    ]

    /// LilyPondソースを規則に照らして着色範囲を列挙する。
    static func spans(in text: String) -> [LilyPondSyntaxSpan] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return rules.flatMap { rule in
            rule.expression.matches(in: text, range: fullRange).compactMap { match in
                let range = match.range(at: rule.captureGroup)
                guard range.location != NSNotFound, range.length > 0 else { return nil }
                return LilyPondSyntaxSpan(range: range, face: rule.face)
            }
        }
    }
}
