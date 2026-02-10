//
//  ExportXLSXOptionsView.swift
//  TablePro
//
//  Options panel for Excel (.xlsx) export format.
//

import SwiftUI

/// Options panel for XLSX export
struct ExportXLSXOptionsView: View {
    @Binding var options: XLSXExportOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Include column headers", isOn: $options.includeHeaderRow)
                .toggleStyle(.checkbox)

            Toggle("Convert NULL to empty", isOn: $options.convertNullToEmpty)
                .toggleStyle(.checkbox)
        }
        .font(.system(size: 13))
    }
}

#Preview {
    ExportXLSXOptionsView(options: .constant(XLSXExportOptions()))
        .padding()
        .frame(width: 280)
}
