//
//  DataBrowserView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels
import TableProQuery

struct DataBrowserView: View {
    let connection: DatabaseConnection
    let table: TableInfo
    let session: ConnectionSession?

    @State private var columns: [ColumnInfo] = []
    @State private var rows: [[String?]] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedRow: IdentifiableRow?
    @State private var pagination = PaginationState(pageSize: 100, currentPage: 0)

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading data...")
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
                dataList
            }
        }
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .sheet(item: $selectedRow) { row in
            RowDetailView(columns: columns, row: row.values)
        }
    }

    private var dataList: some View {
        List {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Button {
                    selectedRow = IdentifiableRow(values: row)
                } label: {
                    RowSummaryView(columns: columns, row: row)
                }
                .foregroundStyle(.primary)
            }

            if rows.count >= pagination.pageSize {
                Button {
                    Task { await loadNextPage() }
                } label: {
                    HStack {
                        Spacer()
                        Text("Load More")
                            .foregroundStyle(.blue)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func loadData() async {
        guard let session else {
            errorMessage = "Not connected"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let query = "SELECT * FROM \(table.name) LIMIT \(pagination.pageSize) OFFSET \(pagination.currentOffset)"
            let result = try await session.driver.execute(query: query)
            self.columns = result.columns
            self.rows = result.rows
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadNextPage() async {
        guard let session else { return }

        pagination.currentPage += 1
        do {
            let query = "SELECT * FROM \(table.name) LIMIT \(pagination.pageSize) OFFSET \(pagination.currentOffset)"
            let result = try await session.driver.execute(query: query)
            rows.append(contentsOf: result.rows)
        } catch {
            pagination.currentPage -= 1
        }
    }
}

struct IdentifiableRow: Identifiable {
    let id = UUID()
    let values: [String?]
}

struct RowSummaryView: View {
    let columns: [ColumnInfo]
    let row: [String?]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Show first 3 columns as preview
            ForEach(Array(zip(columns.prefix(3), row.prefix(3))), id: \.0.name) { col, value in
                HStack(spacing: 6) {
                    Text(col.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)

                    Text(value ?? "NULL")
                        .font(.body)
                        .foregroundStyle(value == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
            }

            if columns.count > 3 {
                Text("+\(columns.count - 3) more columns")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
