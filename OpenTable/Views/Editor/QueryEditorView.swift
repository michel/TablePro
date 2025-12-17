//
//  QueryEditorView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

/// SQL query editor view with execute button
struct QueryEditorView: View {
    @Binding var queryText: String
    var onExecute: () -> Void
    
    @State private var lineCount: Int = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Editor header with toolbar
            editorToolbar
            
            Divider()
            
            // SQL Editor with line numbers
            HStack(alignment: .top, spacing: 0) {
                // Line numbers
                lineNumbersView
                
                Divider()
                
                // Editor
                TextEditor(text: $queryText)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .frame(minHeight: 100)
                    .onChange(of: queryText) { _, newValue in
                        updateLineCount(newValue)
                    }
                    .onAppear {
                        updateLineCount(queryText)
                    }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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
            
            // Format button (future: format SQL)
            Button(action: formatQuery) {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .help("Format Query")
            
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
    
    // MARK: - Line Numbers
    
    private var lineNumbersView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(1...max(lineCount, 1), id: \.self) { line in
                    Text("\(line)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(height: 20)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
        .frame(width: 40)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Helpers
    
    private func updateLineCount(_ text: String) {
        lineCount = text.components(separatedBy: "\n").count
    }
    
    private func formatQuery() {
        // Basic formatting: uppercase keywords
        let keywords = ["SELECT", "FROM", "WHERE", "ORDER BY", "GROUP BY", "HAVING", 
                       "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
                       "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON",
                       "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN", "AS",
                       "LIMIT", "OFFSET", "DISTINCT", "COUNT", "SUM", "AVG", "MAX", "MIN",
                       "NULL", "IS", "ASC", "DESC", "SET", "VALUES", "INTO", "TABLE"]
        
        var formatted = queryText
        for keyword in keywords {
            // Match word boundaries
            let pattern = "\\b\(keyword.lowercased())\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(formatted.startIndex..., in: formatted)
                formatted = regex.stringByReplacingMatches(in: formatted, range: range, withTemplate: keyword)
            }
        }
        queryText = formatted
    }
}

#Preview {
    QueryEditorView(
        queryText: .constant("SELECT * FROM users\nWHERE active = true\nORDER BY created_at DESC;"),
        onExecute: {}
    )
    .frame(width: 600, height: 200)
}

