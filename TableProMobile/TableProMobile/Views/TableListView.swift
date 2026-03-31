//
//  TableListView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels

struct TableListView: View {
    let connection: DatabaseConnection
    let tables: [TableInfo]
    let session: ConnectionSession?
    var onRefresh: (() async -> Void)?

    @State private var searchText = ""

    private var filteredTables: [TableInfo] {
        let filtered = searchText.isEmpty ? tables : tables.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        return filtered
    }

    private var tableSections: [(String, [TableInfo])] {
        let tableItems = filteredTables.filter { $0.type == .table || $0.type == .systemTable }
        let viewItems = filteredTables.filter { $0.type == .view || $0.type == .materializedView }

        var sections: [(String, [TableInfo])] = []
        if !tableItems.isEmpty {
            sections.append(("Tables", tableItems))
        }
        if !viewItems.isEmpty {
            sections.append(("Views", viewItems))
        }
        return sections
    }

    var body: some View {
        List {
            ForEach(tableSections, id: \.0) { sectionTitle, items in
                Section {
                    ForEach(items) { table in
                        NavigationLink(value: table) {
                            TableRow(table: table)
                        }
                        .swipeActions(edge: .leading) {
                            NavigationLink(value: QuickQuery(table: table)) {
                                Label("Query", systemImage: "terminal")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    HStack {
                        Text(sectionTitle)
                        Spacer()
                        Text("\(items.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search tables")
        .navigationTitle("Tables")
        .refreshable {
            await onRefresh?()
        }
        .navigationDestination(for: TableInfo.self) { table in
            DataBrowserView(
                connection: connection,
                table: table,
                session: session
            )
        }
        .navigationDestination(for: QuickQuery.self) { query in
            QueryEditorView(
                session: session,
                tables: tables,
                initialQuery: "SELECT * FROM \(query.table.name) LIMIT 100"
            )
        }
        .overlay {
            if filteredTables.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if tables.isEmpty {
                ContentUnavailableView(
                    "No Tables",
                    systemImage: "tablecells",
                    description: Text("This database has no tables.")
                )
            }
        }
    }
}

struct QuickQuery: Hashable {
    let table: TableInfo
}

private struct TableRow: View {
    let table: TableInfo

    var body: some View {
        HStack {
            Image(systemName: table.type == .view || table.type == .materializedView ? "eye" : "tablecells")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(table.name)
                .font(.body)

            Spacer()

            if let rowCount = table.rowCount {
                Text(formatRowCount(rowCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary)
                    .clipShape(Capsule())
            }
        }
    }

    private func formatRowCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}
