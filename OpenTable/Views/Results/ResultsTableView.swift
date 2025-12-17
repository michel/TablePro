//
//  ResultsTableView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

/// Represents a row of query results
struct QueryResultRow: Identifiable, Equatable {
    let id = UUID()
    var values: [String?]
    
    static func == (lhs: QueryResultRow, rhs: QueryResultRow) -> Bool {
        lhs.id == rhs.id
    }
}

/// Table view displaying query results
struct ResultsTableView: View {
    let columns: [String]
    let rows: [QueryResultRow]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Results header
            HStack {
                Text("Results")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Results table
            if columns.isEmpty {
                emptyState
            } else {
                resultsGrid
            }
            
            Divider()
            
            // Status bar
            HStack {
                Text("\(rows.count) row\(rows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !columns.isEmpty {
                    Text("\(columns.count) column\(columns.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    
    // MARK: - Results Grid
    
    private var resultsGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    // Data rows - limit to first 1000 to prevent memory issues
                    let displayRows = Array(rows.prefix(1000))
                    ForEach(displayRows.indices, id: \.self) { index in
                        rowView(row: displayRows[index], index: index)
                    }
                } header: {
                    // Header row
                    headerRow
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { colIndex in
                Text(columns[colIndex])
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func rowView(row: QueryResultRow, index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { colIndex in
                let value = colIndex < row.values.count ? row.values[colIndex] : nil
                Text(value ?? "NULL")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 120, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .lineLimit(1)
            }
        }
        .background(index % 2 == 0 ? Color.clear : Color(nsColor: .alternatingContentBackgroundColors[1]))
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "table")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            
            Text("No Results")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Execute a query to see results here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Sample Data for Development

extension ResultsTableView {
    static let sampleColumns = ["id", "name", "email", "active", "created_at"]
    
    static let sampleRows: [QueryResultRow] = [
        QueryResultRow(values: ["1", "Alice Johnson", "alice@example.com", "true", "2024-01-15"]),
        QueryResultRow(values: ["2", "Bob Smith", "bob@example.com", "true", "2024-02-20"]),
        QueryResultRow(values: ["3", "Charlie Brown", "charlie@example.com", "false", "2024-03-10"])
    ]
}

#Preview("With Data") {
    ResultsTableView(
        columns: ResultsTableView.sampleColumns,
        rows: ResultsTableView.sampleRows
    )
    .frame(width: 700, height: 300)
}

#Preview("Empty") {
    ResultsTableView(columns: [], rows: [])
        .frame(width: 700, height: 300)
}
