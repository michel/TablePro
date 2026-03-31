//
//  RowDetailView.swift
//  TableProMobile
//

import SwiftUI
import TableProModels

struct RowDetailView: View {
    let columns: [ColumnInfo]
    let rows: [[String?]]
    @State private var currentIndex: Int

    init(columns: [ColumnInfo], rows: [[String?]], initialIndex: Int) {
        self.columns = columns
        self.rows = rows
        _currentIndex = State(initialValue: initialIndex)
    }

    private var currentRow: [String?] {
        guard currentIndex >= 0, currentIndex < rows.count else { return [] }
        return rows[currentIndex]
    }

    var body: some View {
        List {
            ForEach(Array(zip(columns, currentRow).enumerated()), id: \.offset) { _, pair in
                let (column, value) = pair
                Section {
                    fieldContent(value: value)
                        .contextMenu {
                            if let value {
                                Button {
                                    UIPasteboard.general.string = value
                                } label: {
                                    Label("Copy Value", systemImage: "doc.on.doc")
                                }
                            }
                            Button {
                                UIPasteboard.general.string = column.name
                            } label: {
                                Label("Copy Column Name", systemImage: "textformat")
                            }
                        }
                } header: {
                    HStack(spacing: 6) {
                        if column.isPrimaryKey {
                            Image(systemName: "key.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(column.name)

                        Spacer()

                        Text(column.typeName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Row \(currentIndex + 1) of \(rows.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    withAnimation { currentIndex -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentIndex <= 0)

                Spacer()

                Text("\(currentIndex + 1) / \(rows.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Button {
                    withAnimation { currentIndex += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentIndex >= rows.count - 1)
            }
        }
    }

    @ViewBuilder
    private func fieldContent(value: String?) -> some View {
        if let value {
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        } else {
            Text("NULL")
                .font(.body)
                .foregroundStyle(.secondary)
                .italic()
        }
    }
}
