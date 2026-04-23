//
//  DataGridSkeletonView.swift
//  TablePro
//
//  Skeleton loading placeholder that mimics a data grid layout.
//

import AppKit
import SwiftUI

struct DataGridSkeletonView: View {
    private let columnWidths: [CGFloat] = [80, 140, 180, 120, 90]
    private let rowNumberWidth: CGFloat = 40
    private let rowCount = 15

    private let placeholderTexts: [[String]] = [
        ["12345", "John Doe", "email@example.com", "2024-01-15", "active"],
        ["67890", "Jane Smith", "jane.smith@mail.co", "2024-02-20", "pending"],
        ["11223", "Bob Wilson", "bob@company.org", "2024-03-10", "active"],
        ["44556", "Alice Chen", "alice.chen@dev.io", "2024-04-05", "inactive"],
        ["78901", "Tom Brown", "t.brown@example.com", "2024-05-12", "active"],
        ["23456", "Eva Green", "eva.g@sample.net", "2024-06-18", "pending"],
        ["34567", "Sam Lee", "samlee@work.com", "2024-07-22", "active"],
        ["89012", "Mia Davis", "mia.d@test.org", "2024-08-30", "inactive"],
        ["45678", "Dan Park", "dan.park@mail.com", "2024-09-14", "active"],
        ["56789", "Lily Wang", "lily.w@corp.io", "2024-10-01", "pending"],
        ["90123", "Max Hall", "max.hall@dev.co", "2024-11-07", "active"],
        ["12340", "Zoe Kim", "zoe.k@example.com", "2024-12-25", "inactive"],
        ["67801", "Raj Patel", "raj.p@sample.org", "2025-01-03", "active"],
        ["23450", "Amy Fox", "amy.fox@work.net", "2025-02-14", "pending"],
        ["78900", "Ian Cole", "ian.c@test.io", "2025-03-19", "active"]
    ]

    private var showAlternateRows: Bool {
        AppSettingsManager.shared.dataGrid.showAlternateRows
    }

    private var rowHeight: CGFloat {
        CGFloat(AppSettingsManager.shared.dataGrid.rowHeight.rawValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            bodyRows
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel(String(localized: "Loading data"))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: .placeholderTextColor))
                .frame(width: rowNumberWidth, alignment: .center)

            Color(nsColor: .separatorColor)
                .frame(width: 1)

            ForEach(Array(columnWidths.enumerated()), id: \.offset) { index, width in
                Text(headerPlaceholder(for: index))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
                    .frame(width: width, alignment: .leading)
                    .padding(.horizontal, 6)

                if index < columnWidths.count - 1 {
                    Color(nsColor: .separatorColor)
                        .frame(width: 1)
                }
            }

            Spacer()
        }
        .frame(height: rowHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var bodyRows: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { rowIndex in
                    bodyRow(at: rowIndex)
                    if rowIndex < rowCount - 1 {
                        Color(nsColor: .separatorColor)
                            .frame(height: 1)
                    }
                }
            }
        }
        .phaseAnimator([false, true]) { content, phase in
            content.opacity(phase ? 1.0 : 0.6)
        } animation: { _ in
            .easeInOut(duration: 1.2)
        }
    }

    private func bodyRow(at index: Int) -> some View {
        let texts = placeholderTexts[index % placeholderTexts.count]
        let isOddRow = index % 2 == 1

        return HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: rowNumberWidth, alignment: .center)

            Color(nsColor: .separatorColor)
                .frame(width: 1)

            ForEach(Array(texts.enumerated()), id: \.offset) { colIndex, text in
                Text(text)
                    .font(.system(size: 13))
                    .frame(width: columnWidths[colIndex], alignment: .leading)
                    .padding(.horizontal, 6)

                if colIndex < texts.count - 1 {
                    Color(nsColor: .separatorColor)
                        .frame(width: 1)
                }
            }

            Spacer()
        }
        .frame(height: rowHeight)
        .background(
            showAlternateRows && isOddRow
                ? Color(nsColor: .alternatingContentBackgroundColors[1])
                : Color.clear
        )
        .redacted(reason: .placeholder)
    }

    private func headerPlaceholder(for index: Int) -> String {
        switch index {
        case 0: return "column_1"
        case 1: return "column_2"
        case 2: return "column_3"
        case 3: return "column_4"
        case 4: return "column_5"
        default: return "column"
        }
    }
}

#Preview {
    DataGridSkeletonView()
        .frame(width: 800, height: 400)
}
