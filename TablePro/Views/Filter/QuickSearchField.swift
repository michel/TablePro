//
//  QuickSearchField.swift
//  TablePro
//
//  Quick search field component for filtering across all columns.
//  Extracted from FilterPanelView for better maintainability.
//

import SwiftUI

/// Quick search field for filtering across all columns
struct QuickSearchField: View {
    @Binding var searchText: String
    let hasActiveSearch: Bool
    let onSubmit: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Quick search across all columns...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit {
                    if !searchText.isEmpty {
                        onSubmit()
                    }
                }

            if hasActiveSearch {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
