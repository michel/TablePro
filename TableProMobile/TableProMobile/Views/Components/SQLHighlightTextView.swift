//
//  SQLHighlightTextView.swift
//  TableProMobile
//

import SwiftUI
import UIKit

struct SQLHighlightTextView: UIViewRepresentable {
    @Binding var text: String

    private static let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = Self.font
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.keyboardType = .asciiCapable
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.textStorage.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            context.coordinator.isUpdating = true
            textView.text = text
            let length = (text as NSString).length
            if length > 0 {
                SQLSyntaxHighlighter.highlight(textView.textStorage, in: NSRange(location: 0, length: length))
            }
            context.coordinator.isUpdating = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
        var parent: SQLHighlightTextView
        var isUpdating = false

        init(_ parent: SQLHighlightTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            parent.text = textView.text
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), !isUpdating else { return }
            // Defer to avoid re-entrant editing during processEditing
            DispatchQueue.main.async {
                SQLSyntaxHighlighter.highlight(textStorage, in: editedRange)
            }
        }
    }
}
