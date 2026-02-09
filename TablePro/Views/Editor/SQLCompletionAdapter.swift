//
//  SQLCompletionAdapter.swift
//  TablePro
//
//  Bridges CompletionEngine to CodeEditSourceEditor's CodeSuggestionDelegate.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI

/// Adapts the existing CompletionEngine to CodeEditSourceEditor's suggestion system
@MainActor
final class SQLCompletionAdapter: CodeSuggestionDelegate {
    // MARK: - Properties

    private var completionEngine: CompletionEngine?
    private var suppressNextCompletion = false
    private var currentCompletionContext: CompletionContext?

    // MARK: - Initialization

    init(schemaProvider: SQLSchemaProvider?) {
        if let provider = schemaProvider {
            self.completionEngine = CompletionEngine(schemaProvider: provider)
        }
    }

    /// Update the schema provider (e.g. when connection changes)
    func updateSchemaProvider(_ provider: SQLSchemaProvider) {
        self.completionEngine = CompletionEngine(schemaProvider: provider)
    }

    // MARK: - CodeSuggestionDelegate

    func completionTriggerCharacters() -> Set<String> {
        [".", " "]
    }

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        guard let completionEngine else { return nil }

        if suppressNextCompletion {
            suppressNextCompletion = false
            return nil
        }

        let text = textView.text
        let offset = cursorPosition.range.location

        // Don't show autocomplete right after semicolon or newline
        if offset > 0 {
            let nsString = text as NSString
            guard offset - 1 < nsString.length else { return nil }
            let prevChar = nsString.character(at: offset - 1)
            let semicolon = UInt16(UnicodeScalar(";").value)
            let newline = UInt16(UnicodeScalar("\n").value)

            if prevChar == semicolon || prevChar == newline {
                guard offset < nsString.length else { return nil }
                let afterCursor = nsString.substring(from: offset)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if afterCursor.isEmpty { return nil }
            }
        }

        guard let context = await completionEngine.getCompletions(
            text: text,
            cursorPosition: offset
        ) else {
            return nil
        }

        self.currentCompletionContext = context

        let entries: [CodeSuggestionEntry] = context.items.map { item in
            SQLSuggestionEntry(item: item)
        }

        return (windowPosition: cursorPosition, items: entries)
    }

    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        // Filter existing completions based on new cursor position
        guard let context = currentCompletionContext else { return nil }

        let text = textView.text
        let offset = cursorPosition.range.location
        let nsText = text as NSString

        // Extract current prefix from replacement range start to cursor
        let prefixStart = context.replacementRange.location
        guard offset >= prefixStart, offset <= nsText.length else { return nil }

        let currentPrefix = nsText.substring(
            with: NSRange(location: prefixStart, length: offset - prefixStart)
        ).lowercased()

        guard !currentPrefix.isEmpty else { return nil }

        let filtered = context.items.filter { item in
            item.filterText.lowercased().hasPrefix(currentPrefix)
        }

        return filtered.isEmpty ? nil : filtered.map { SQLSuggestionEntry(item: $0) }
    }

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let entry = item as? SQLSuggestionEntry,
              let context = currentCompletionContext else { return }

        suppressNextCompletion = true

        // Extend replacement range from original start to current cursor position,
        // since the user may have typed more characters since completions were triggered.
        let originalStart = context.replacementRange.location
        let currentEnd = cursorPosition?.range.location ?? (originalStart + context.replacementRange.length)
        let replaceRange = NSRange(location: originalStart, length: currentEnd - originalStart)
        let insertText = entry.item.insertText

        // Replace text in the text view
        textView.textView.replaceCharacters(
            in: [replaceRange],
            with: insertText
        )

        // Move cursor to end of inserted text
        let newPosition = replaceRange.location + (insertText as NSString).length
        textView.setCursorPositions([CursorPosition(range: NSRange(location: newPosition, length: 0))])
    }
}

// MARK: - SQLSuggestionEntry

/// Bridges SQLCompletionItem to CodeSuggestionEntry
final class SQLSuggestionEntry: CodeSuggestionEntry {
    let item: SQLCompletionItem

    init(item: SQLCompletionItem) {
        self.item = item
    }

    var label: String { item.label }
    var detail: String? { item.detail }
    var documentation: String? { item.documentation }
    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }
    var deprecated: Bool { false }

    var image: Image {
        Image(systemName: item.kind.iconName)
    }

    var imageColor: Color {
        Color(nsColor: item.kind.iconColor)
    }
}
