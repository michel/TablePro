//
//  DataBrowserView.swift
//  TableProMobile
//

import os
import SwiftUI
import TableProDatabase
import TableProModels

struct DataBrowserView: View {
    let connection: DatabaseConnection
    let table: TableInfo
    let session: ConnectionSession?

    private static let logger = Logger(subsystem: "com.TablePro", category: "DataBrowserView")

    @State private var columns: [ColumnInfo] = []
    @State private var columnDetails: [ColumnInfo] = []
    @State private var rows: [[String?]] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var appError: AppError?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var pagination = PaginationState(pageSize: 100, currentPage: 0)
    @State private var hasMore = true
    @State private var showInsertSheet = false
    @State private var deleteTarget: [(column: String, value: String)]?
    @State private var showDeleteConfirmation = false
    @State private var operationError: AppError?
    @State private var showOperationError = false

    private let maxPreviewColumns = 4

    private var isView: Bool {
        table.type == .view || table.type == .materializedView
    }

    private var hasPrimaryKeys: Bool {
        columnDetails.contains { $0.isPrimaryKey }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let appError {
                ErrorView(error: appError) {
                    await loadData()
                }
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Data", systemImage: "tray")
                } description: {
                    Text("This table is empty.")
                } actions: {
                    if !isView {
                        Button("Insert Row") { showInsertSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                cardList
            }
        }
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .status) {
                Text(verbatim: "\(rows.count) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StructureView(
                        table: table,
                        session: session,
                        databaseType: connection.type
                    )
                } label: {
                    Image(systemName: "info.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if !isView {
                    Button {
                        showInsertSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task { await loadData(isInitial: true) }
        .sheet(isPresented: $showInsertSheet) {
            InsertRowView(
                table: table,
                columnDetails: columnDetails,
                session: session,
                databaseType: connection.type,
                onInserted: {
                    Task { await loadData() }
                }
            )
        }
        .alert("Delete Row", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let pkValues = deleteTarget {
                    Task { await deleteRow(withPKs: pkValues) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this row? This action cannot be undone.")
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ErrorToast(message: toastMessage)
                    .onAppear {
                        toastTask?.cancel()
                        toastTask = Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation { self.toastMessage = nil }
                        }
                    }
                    .onDisappear {
                        toastTask?.cancel()
                        toastTask = nil
                    }
            }
        }
        .animation(.default, value: toastMessage)
        .alert(operationError?.title ?? "Error", isPresented: $showOperationError) {
            Button("OK", role: .cancel) {}
        } message: {
            VStack {
                Text(operationError?.message ?? "An unknown error occurred.")
                if let recovery = operationError?.recovery {
                    Text(verbatim: recovery)
                }
            }
        }
    }

    private var cardList: some View {
        List {
            // Offset-based identity is acceptable here: rows don't animate/reorder
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                NavigationLink {
                    RowDetailView(
                        columns: columns,
                        rows: rows,
                        initialIndex: index,
                        table: table,
                        session: session,
                        columnDetails: columnDetails,
                        databaseType: connection.type,
                        onSaved: {
                            Task { await loadData() }
                        }
                    )
                } label: {
                    RowCard(
                        columns: columns,
                        row: row,
                        maxPreviewColumns: maxPreviewColumns
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isView && hasPrimaryKeys {
                        Button(role: .destructive) {
                            deleteTarget = primaryKeyValues(for: rows[index])
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
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

    private func loadData(isInitial: Bool = false) async {
        guard let session else {
            appError = AppError(
                category: .config,
                title: "Not Connected",
                message: "No active database session.",
                recovery: "Go back and reconnect to the database.",
                underlying: nil
            )
            isLoading = false
            return
        }

        if isInitial || rows.isEmpty {
            isLoading = true
        }
        appError = nil
        pagination.reset()

        do {
            let query = SQLBuilder.buildSelect(
                table: table.name, type: connection.type,
                limit: pagination.pageSize, offset: pagination.currentOffset
            )
            let result = try await session.driver.execute(query: query)
            self.columns = result.columns
            self.rows = result.rows
            self.hasMore = result.rows.count >= pagination.pageSize

            // columnDetails (from fetchColumns) provides PK info for edit/delete.
            // columns (from query result) only have name/type, no PK metadata.
            self.columnDetails = try await session.driver.fetchColumns(table: table.name, schema: nil)

            isLoading = false
        } catch {
            let context = ErrorContext(
                operation: "loadData",
                databaseType: connection.type,
                host: connection.host
            )
            appError = ErrorClassifier.classify(error, context: context)
            isLoading = false
        }
    }

    private func loadNextPage() async {
        guard let session else { return }

        isLoadingMore = true
        pagination.currentPage += 1

        do {
            let query = SQLBuilder.buildSelect(
                table: table.name, type: connection.type,
                limit: pagination.pageSize, offset: pagination.currentOffset
            )
            let result = try await session.driver.execute(query: query)
            rows.append(contentsOf: result.rows)
            hasMore = result.rows.count >= pagination.pageSize
        } catch {
            pagination.currentPage -= 1
            Self.logger.warning("Failed to load next page: \(error.localizedDescription, privacy: .public)")
            withAnimation { toastMessage = String(localized: "Failed to load more rows") }
        }

        isLoadingMore = false
    }

    private func deleteRow(withPKs pkValues: [(column: String, value: String)]) async {
        guard let session, !pkValues.isEmpty else { return }

        let sql = SQLBuilder.buildDelete(table: table.name, type: connection.type, primaryKeys: pkValues)

        do {
            _ = try await session.driver.execute(query: sql)
            await loadData()
        } catch {
            let context = ErrorContext(
                operation: "deleteRow",
                databaseType: connection.type,
                host: connection.host
            )
            operationError = ErrorClassifier.classify(error, context: context)
            showOperationError = true
        }
    }

    private func primaryKeyValues(for row: [String?]) -> [(column: String, value: String)] {
        columnDetails.enumerated().compactMap { index, col in
            guard col.isPrimaryKey else { return nil }
            let colIndex = columns.firstIndex(where: { $0.name == col.name })
            guard let colIndex, colIndex < row.count, let value = row[colIndex] else { return nil }
            return (column: col.name, value: value)
        }
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
                        Text(verbatim: value)
                            .font(.subheadline)
                            .fontWeight(pair.column.isPrimaryKey ? .semibold : .regular)
                            .lineLimit(1)
                    } else {
                        Text(verbatim: "NULL")
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
