// UIKitを利用したiPhone向けLilyPondソースエディタを提供する。

import SwiftUI
import UIKit

/// iPhone固有のUITextView。構文判定はCoreへ委譲する。
struct iPhoneLilyPondSourceEditor: UIViewRepresentable {
    @Binding var text: String
    let fontSize: Double

    /// 画面部品の構築または状態反映を行う。
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// 画面部品の構築または状態反映を行う。
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        view.adjustsFontForContentSizeCategory = true
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.keyboardDismissMode = .interactive
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        context.coordinator.textView = view
        context.coordinator.setText(text)
        return view
    }

    /// 画面部品の構築または状態反映を行う。
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { context.coordinator.setText(text) }
        context.coordinator.updateConfigurationIfNeeded()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: iPhoneLilyPondSourceEditor
        weak var textView: UITextView?
        private var isHighlighting = false
        private var appliedFontSize: Double?
        private var appliedSyntaxStyle: LilyPondSyntaxStyle?

        /// 必要な依存情報と初期値を受け取り、この型の状態を初期化する。
        init(parent: iPhoneLilyPondSourceEditor) { self.parent = parent }

        /// `textViewDidChange`が担当する処理を実行する。
        func textViewDidChange(_ textView: UITextView) {
            guard !isHighlighting else { return }
            parent.text = textView.text
            applyHighlighting(to: textView)
        }

        /// `setText`が担当する処理を実行する。
        func setText(_ text: String) {
            guard let textView else { return }
            let selection = textView.selectedRange
            isHighlighting = true
            textView.text = text
            applyAttributes(to: textView)
            textView.selectedRange = clamped(selection, length: textView.textStorage.length)
            isHighlighting = false
        }

        /// 画面部品の構築または状態反映を行う。
        func updateConfigurationIfNeeded() {
            guard let textView else { return }
            let fontSize = parent.fontSize
            let syntaxStyle = LilyPondEditorConfigurationStore.syntaxStyle
            guard fontSize != appliedFontSize || syntaxStyle != appliedSyntaxStyle else { return }
            applyHighlighting(to: textView)
        }

        /// `applyHighlighting`が担当する処理を実行する。
        private func applyHighlighting(to textView: UITextView) {
            let selection = textView.selectedRange
            isHighlighting = true
            applyAttributes(to: textView)
            textView.selectedRange = clamped(selection, length: textView.textStorage.length)
            isHighlighting = false
        }

        /// `applyAttributes`が担当する処理を実行する。
        private func applyAttributes(to textView: UITextView) {
            let fontSize = parent.fontSize
            let syntaxStyle = LilyPondEditorConfigurationStore.syntaxStyle
            let storage = textView.textStorage
            let range = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular),
                .foregroundColor: UIColor.label
            ], range: range)
            for span in LilyPondSyntaxHighlighting.spans(in: textView.text) {
                storage.addAttribute(.foregroundColor, value: color(for: span.face), range: span.range)
            }
            storage.endEditing()
            textView.typingAttributes = [
                .font: UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular),
                .foregroundColor: UIColor.label
            ]
            appliedFontSize = fontSize
            appliedSyntaxStyle = syntaxStyle
        }

        /// `color`が担当する処理を実行する。
        private func color(for face: LilyPondSyntaxFace) -> UIColor {
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
