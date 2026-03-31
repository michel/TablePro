//
//  DataBrowserView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels

struct DataBrowserView: View {
    let connection: DatabaseConnection
    let table: TableInfo
    let session: ConnectionSession?

    @State private var columns: [ColumnInfo] = []
    @State private var rows: [[String?]] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var pagination = PaginationState(pageSize: 100, currentPage: 0)
    @State private var hasMore = true

    private let maxPreviewColumns = 4

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Query Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await loadData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "tray",
                    description: Text("This table is empty.")
                )
            } else {
                cardList
            }
        }
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text("\(rows.count) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await loadData() }
    }

    private var cardList: some View {
        List {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                NavigationLink {
                    RowDetailView(
                        columns: columns,
                        rows: rows,
                        initialIndex: index
                    )
                } label: {
                    RowCard(
                        columns: columns,
                        row: row,
                        maxPreviewColumns: maxPreviewColumns
                    )
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            }

            if hasMore {
                Section {
                    Button {
                        Task { await loadNextPage() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading...")
                            } else {
                                Label("Load More", systemImage: "arrow.down.circle")
                            }
                            Spacer()
                        }
                        .foregroundStyle(.blue)
                    }
                    .disabled(isLoadingMore)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await loadData() }
    }

    private func loadData() async {
        guard let session else {
            errorMessage = "Not connected"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        pagination.reset()

        do {
            let query = "SELECT * FROM \(table.name) LIMIT \(pagination.pageSize) OFFSET \(pagination.currentOffset)"
            let result = try await session.driver.execute(query: query)
            self.columns = result.columns
            self.rows = result.rows
            self.hasMore = result.rows.count >= pagination.pageSize
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadNextPage() async {
        guard let session else { return }

        isLoadingMore = true
        pagination.currentPage += 1

        do {
            let query = "SELECT * FROM \(table.name) LIMIT \(pagination.pageSize) OFFSET \(pagination.currentOffset)"
            let result = try await session.driver.execute(query: query)
            rows.append(contentsOf: result.rows)
            hasMore = result.rows.count >= pagination.pageSize
        } catch {
            pagination.currentPage -= 1
        }

        isLoadingMore = false
    }
}

private struct RowCard: View {
    let columns: [ColumnInfo]
    let row: [String?]
    let maxPreviewColumns: Int

    private var sortedPairs: [(column: ColumnInfo, value: String?)] {
        let paired = zip(columns, row).map { ($0, $1) }
        let pkPairs = paired.filter { $0.0.isPrimaryKey }
        let nonPkPairs = paired.filter { !$0.0.isPrimaryKey }
        return (pkPairs + nonPkPairs).prefix(maxPreviewColumns).map { ($0.0, $0.1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sortedPairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 8) {
                    Text(pair.column.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 60, alignment: .leading)

                    if let value = pair.value {
                        Text(value)
                            .font(.subheadline)
                            .fontWeight(pair.column.isPrimaryKey ? .semibold : .regular)
                            .lineLimit(1)
                    } else {
                        Text("NULL")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
            }

            if columns.count > maxPreviewColumns {
                Text("+\(columns.count - maxPreviewColumns) more columns")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
