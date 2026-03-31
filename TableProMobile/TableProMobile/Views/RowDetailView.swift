//
//  RowDetailView.swift
//  TableProMobile
//

import SwiftUI
import TableProModels

struct RowDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let columns: [ColumnInfo]
    let row: [String?]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(zip(columns, row)), id: \.0.name) { column, value in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(column.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(column.typeName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            if column.isPrimaryKey {
                                Image(systemName: "key.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }

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
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Row Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
