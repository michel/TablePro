//
//  ExportMQLOptionsView.swift
//  TablePro
//
//  Options panel for MQL (MongoDB Query Language) export format.
//

import SwiftUI

/// Options panel for MQL export
struct ExportMQLOptionsView: View {
    @Binding var options: MQLExportOptions

    /// Available batch size options
    private static let batchSizeOptions = [100, 500, 1_000, 5_000]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.xs) {
            Text("Exports data as mongosh-compatible scripts. Drop, Indexes, and Data options are configured per collection in the collection list.")
                .font(.system(size: DesignConstants.FontSize.small))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, DesignConstants.Spacing.xxs)

            HStack {
                Text("Rows per insertMany")
                    .font(.system(size: DesignConstants.FontSize.body))

                Spacer()

                Picker("", selection: $options.batchSize) {
                    ForEach(Self.batchSizeOptions, id: \.self) { size in
                        Text("\(size)")
                            .tag(size)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
            }
            .help("Number of documents per insertMany statement. Higher values create fewer statements.")
        }
    }
}

// MARK: - Preview

#Preview {
    ExportMQLOptionsView(options: .constant(MQLExportOptions()))
        .padding()
        .frame(width: 300)
}
