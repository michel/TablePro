//
//  QueryEditorView.swift
//  TablePro
//
//  SQL query editor wrapper with toolbar
//

import CodeEditSourceEditor
import SwiftUI

extension Notification.Name {
    static let formatQueryRequested = Notification.Name("formatQueryRequested")
}

/// SQL query editor view with execute button
struct QueryEditorView: View {
    @Binding var queryText: String
    @Binding var cursorPositions: [CursorPosition]
    var onExecute: () -> Void
    var schemaProvider: SQLSchemaProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Editor header with toolbar (above editor, higher z-index)
            editorToolbar
                .zIndex(1)

            Divider()

            // SQL Editor (CodeEditSourceEditor-based with tree-sitter highlighting)
            SQLEditorView(
                text: $queryText,
                cursorPositions: $cursorPositions,
                schemaProvider: schemaProvider
            )
            .frame(minHeight: 100)
            .clipped()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .formatQueryRequested)) { _ in
            formatQuery()
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack {
            Text("Query")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            // Clear button
            Button(action: { queryText = "" }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear Query (⌘+Delete)")
            .keyboardShortcut(.delete, modifiers: .command)

            // Format button
            Button(action: formatQuery) {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .help("Format Query (⌥⌘F)")
            .keyboardShortcut("f", modifiers: [.option, .command])

            Divider()
                .frame(height: 16)

            // Execute button
            Button(action: onExecute) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    Text("Execute")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func formatQuery() {
        // Get current database type from active session
        let dbType = DatabaseManager.shared.currentSession?.connection.type ?? .mysql

        // Create formatter service
        let formatter = SQLFormatterService()
        let options = SQLFormatterOptions.default

        let cursorOffset = cursorPositions.first?.range.location ?? 0

        do {
            // Format SQL with cursor preservation
            let result = try formatter.format(
                queryText,
                dialect: dbType,
                cursorOffset: cursorOffset,
                options: options
            )

            // Update text and cursor position
            queryText = result.formattedSQL
            if let newCursor = result.cursorOffset {
                cursorPositions = [CursorPosition(range: NSRange(location: newCursor, length: 0))]
            }
        } catch {
            print("SQL Formatting error: \(error.localizedDescription)")
        }
    }
}

#Preview {
    QueryEditorView(
        queryText: .constant("SELECT * FROM users\nWHERE active = true\nORDER BY created_at DESC;"),
        cursorPositions: .constant([])
    ) {}
    .frame(width: 600, height: 200)
}
