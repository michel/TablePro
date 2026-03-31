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

    @State private var searchText = ""

    private var filteredTables: [TableInfo] {
        if searchText.isEmpty { return tables }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            ForEach(filteredTables) { table in
                NavigationLink(value: table) {
                    TableRow(table: table)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search tables")
        .navigationTitle("Tables")
        .navigationDestination(for: TableInfo.self) { table in
            DataBrowserView(
                connection: connection,
                table: table,
                session: session
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

struct TableRow: View {
    let table: TableInfo

    var body: some View {
        HStack {
            Image(systemName: table.type == .view ? "eye" : "tablecells")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(table.name)
                    .font(.body)

                if let rowCount = table.rowCount {
                    Text("\(rowCount) rows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

