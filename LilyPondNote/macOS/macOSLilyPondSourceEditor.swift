// AppKitを利用したmacOS向けLilyPondソースエディタを提供する。

import AppKit
import SwiftUI

/// macOS固有のNSTextView。構文判定はCoreへ委譲する。
struct macOSLilyPondSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double

    /// AppKitのテキストビューとSwiftUIのBindingを接続するCoordinatorを生成する。
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// 等幅フォントとスクロールを設定したmacOS用ソース編集ビューを生成する。
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        context.coordinator.textView = textView
        context.coordinator.setText(text)
        return scrollView
    }

    /// SwiftUIから渡された本文と設定変更を既存のテキストビューへ反映する。
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { context.coordinator.setText(text) }
        else if textView.font?.pointSize != CGFloat(fontSize) { context.coordinator.refreshHighlighting() }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: macOSLilyPondSourceEditor
        weak var textView: NSTextView?
        private var isHighlighting = false

        /// 親Editorを保持し、AppKitからの編集通知をSwiftUIへ戻せる状態を作る。
        init(parent: macOSLilyPondSourceEditor) { self.parent = parent }

        /// テキスト変更を親Viewへ反映して構文着色を更新する。
        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let textView else { return }
            parent.text = textView.string
            applyHighlighting(to: textView)
        }

        /// 外部から渡されたテキストを選択範囲を保って表示する。
        func setText(_ text: String) {
            guard let textView else { return }
            let selection = textView.selectedRange()
            isHighlighting = true
            textView.string = text
            applyAttributes(to: textView)
            textView.setSelectedRange(LilyPondSyntaxHighlighting.clampedSelection(selection, length: textView.textStorage?.length ?? 0))
            isHighlighting = false
        }

        /// 現在の文字列へ構文着色を再適用し、フォント設定の変更も反映する。
        func refreshHighlighting() {
            guard let textView else { return }
            applyHighlighting(to: textView)
        }

        /// 現在の選択位置を保ちながら構文着色を適用する。
        private func applyHighlighting(to textView: NSTextView) {
            let selection = textView.selectedRange()
            isHighlighting = true
            applyAttributes(to: textView)
            textView.setSelectedRange(LilyPondSyntaxHighlighting.clampedSelection(selection, length: textView.textStorage?.length ?? 0))
            isHighlighting = false
        }

        /// 文字色と字体を初期化し、解析した構文範囲を着色する。
        private func applyAttributes(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ], range: range)
            for span in LilyPondSyntaxHighlighting.spans(in: textView.string) {
                storage.addAttribute(.foregroundColor, value: color(for: span.face), range: span.range)
            }
            storage.endEditing()
            textView.typingAttributes = [
                .font: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        }

        /// 構文色の役割をOS固有の表示色へ変換する。
        private func color(for face: LilyPondSyntaxFace) -> NSColor {
            switch LilyPondEditorConfigurationStore.syntaxStyle.colorRole(for: face) {
            case .blue: .systemBlue
            case .purple: .systemPurple
            case .indigo: .systemIndigo
            case .brown: .systemBrown
            case .green: .systemGreen
            case .orange: .systemOrange
            case .red: .systemRed
            case .teal: .systemTeal
            case .pink: .systemPink
            case .cyan: .systemCyan
            case .gray: .systemGray
            }
        }

    }
}
