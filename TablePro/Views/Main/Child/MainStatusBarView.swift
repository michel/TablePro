//
//  MainStatusBarView.swift
//  TablePro
//
//  Created by Ngo Quoc Dat on 24/12/25.
//

import SwiftUI

/// Status bar at the bottom of the results section
struct MainStatusBarView: View {
    let tab: QueryTab?
    let filterStateManager: FilterStateManager
    let selectedRowIndices: Set<Int>
    @Binding var showStructure: Bool

    var body: some View {
        HStack {
            // Left: Data/Structure toggle for table tabs
            if let tab = tab, tab.tabType == .table, tab.tableName != nil {
                Picker("", selection: $showStructure) {
                    Label("Data", systemImage: "tablecells").tag(false)
                    Label("Structure", systemImage: "list.bullet.rectangle").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .controlSize(.small)
                .offset(x: -26)
            }

            Spacer()

            // Center: Row info (pagination/selection)
            if let tab = tab, !tab.resultRows.isEmpty {
                Text(rowInfoText(for: tab))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right: Filters toggle button
            if let tab = tab, tab.tabType == .table, tab.tableName != nil {
                Toggle(isOn: Binding(
                    get: { filterStateManager.isVisible },
                    set: { _ in filterStateManager.toggle() }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: filterStateManager.hasAppliedFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                        Text("Filters")
                        if filterStateManager.hasAppliedFilters {
                            Text("(\(filterStateManager.appliedFilters.count))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Toggle Filters (Cmd+F)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Generate row info text based on selection and pagination state
    private func rowInfoText(for tab: QueryTab) -> String {
        let loadedCount = tab.resultRows.count
        // Use selectedRowIndices parameter instead of tab.selectedRowIndices
        let selectedCount = selectedRowIndices.count
        let total = tab.pagination.totalRowCount

        if selectedCount > 0 {
            // Selection mode
            if selectedCount == loadedCount {
                return "All \(loadedCount) rows selected"
            } else {
                return "\(selectedCount) of \(loadedCount) rows selected"
            }
        } else if let total = total, total > loadedCount {
            // Pagination mode: "1-100 of 5000 rows"
            return "1-\(loadedCount) of \(total) rows"
        } else {
            // Simple mode: "100 rows"
            return "\(loadedCount) rows"
        }
    }
}
