// AppKitを利用したmacOS向けLilyPondソースエディタを提供する。

import AppKit
import SwiftUI

/// macOS固有のNSTextView。構文判定はCoreへ委譲する。
struct macOSLilyPondSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double

    /// 画面部品の構築または状態反映を行う。
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// 画面部品の構築または状態反映を行う。
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

    /// 画面部品の構築または状態反映を行う。
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

        /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
        init(parent: macOSLilyPondSourceEditor) { self.parent = parent }

        /// `textDidChange`が担当する処理を実行する。
        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let textView else { return }
            parent.text = textView.string
            applyHighlighting(to: textView)
        }

        /// `setText`が担当する処理を実行する。
        func setText(_ text: String) {
            guard let textView else { return }
            let selection = textView.selectedRange()
            isHighlighting = true
            textView.string = text
            applyAttributes(to: textView)
            textView.setSelectedRange(clamped(selection, length: textView.textStorage?.length ?? 0))
            isHighlighting = false
        }

        /// 認証状態を更新する。
        func refreshHighlighting() {
            guard let textView else { return }
            applyHighlighting(to: textView)
        }

        /// `applyHighlighting`が担当する処理を実行する。
        private func applyHighlighting(to textView: NSTextView) {
            let selection = textView.selectedRange()
            isHighlighting = true
            applyAttributes(to: textView)
            textView.setSelectedRange(clamped(selection, length: textView.textStorage?.length ?? 0))
            isHighlighting = false
        }

        /// `applyAttributes`が担当する処理を実行する。
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

        /// `color`が担当する処理を実行する。
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

        /// `clamped`が担当する処理を実行する。
        private func clamped(_ range: NSRange, length: Int) -> NSRange {
            let location = min(max(0, range.location), length)
            return NSRange(location: location, length: min(range.length, length - location))
        }
    }
}
