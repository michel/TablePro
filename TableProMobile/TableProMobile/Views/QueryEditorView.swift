//
//  QueryEditorView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels

struct QueryEditorView: View {
    let session: ConnectionSession?

    @State private var query = ""
    @State private var result: QueryResult?
    @State private var errorMessage: String?
    @State private var isExecuting = false
    @State private var executionTime: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            editorArea
            Divider()
            resultArea
        }
        .navigationTitle("Query")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await executeQuery() }
                } label: {
                    Image(systemName: isExecuting ? "stop.fill" : "play.fill")
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExecuting)
            }
        }
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            TextEditor(text: $query)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: 120, maxHeight: 200)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            HStack {
                if let time = executionTime {
                    Text(String(format: "%.2fms", time * 1000))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let result, !result.rows.isEmpty {
                    Text("\(result.rows.count) rows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    private var resultArea: some View {
        Group {
            if isExecuting {
                ProgressView("Executing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ScrollView {
                    Text(errorMessage)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let result {
                if result.columns.isEmpty {
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("\(result.rowsAffected) row(s) affected")
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if result.rows.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "tray")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    resultTable(result)
                }
            } else {
                ContentUnavailableView {
                    Label("Run a Query", systemImage: "terminal")
                } description: {
                    Text("Write SQL and tap the play button.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func resultTable(_ result: QueryResult) -> some View {
        List {
            ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(zip(result.columns, row)), id: \.0.name) { col, value in
                        HStack(spacing: 6) {
                            Text(col.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .trailing)

                            Text(value ?? "NULL")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(value == nil ? .secondary : .primary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }

    private func executeQuery() async {
        guard let session else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isExecuting = true
        errorMessage = nil
        result = nil

        do {
            let queryResult = try await session.driver.execute(query: trimmed)
            self.result = queryResult
            self.executionTime = queryResult.executionTime
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isExecuting = false
    }
}
