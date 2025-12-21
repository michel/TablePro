//
//  FilterPanelView.swift
//  OpenTable
//
//  Filter panel UI for table data filtering
//

import SwiftUI

/// Bottom filter panel for table data filtering
struct FilterPanelView: View {
    @ObservedObject var filterState: FilterStateManager
    let columns: [String]
    let primaryKeyColumn: String?
    let databaseType: DatabaseType
    let onApply: ([TableFilter]) -> Void
    let onUnset: () -> Void
    let onQuickSearch: ((String) -> Void)?  // New callback for Quick Search

    @State private var showSQLSheet = false
    @State private var showSettingsPopover = false
    @State private var generatedSQL = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and action buttons
            filterHeader

            Divider()
                .foregroundStyle(Color(nsColor: .separatorColor))
            
            // Quick Search field (when no filters or alongside filters)
            if filterState.hasActiveQuickSearch || filterState.filters.isEmpty {
                quickSearchField
                Divider()
                    .foregroundStyle(Color(nsColor: .separatorColor))
            }

            // Filter rows
            if filterState.filters.isEmpty {
                if !filterState.hasActiveQuickSearch {
                    emptyState
                }
            } else {
                filterList
            }

            Divider()
                .foregroundStyle(Color(nsColor: .separatorColor))

            // Footer with Apply All, Unset, SQL buttons
            filterFooter
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSQLSheet) {
            SQLPreviewSheet(sql: generatedSQL, tableName: "", databaseType: databaseType)
        }
    }

    // MARK: - Header

    private var filterHeader: some View {
        HStack(spacing: 8) {
            Text("Filters")
                .font(.system(size: 12, weight: .medium))

            if filterState.hasAppliedFilters {
                Text("(\(filterState.appliedFilters.count) active)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Settings button (gear icon)
            Button(action: { showSettingsPopover.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Filter Settings")
            .popover(isPresented: $showSettingsPopover, arrowEdge: .bottom) {
                FilterSettingsPopover()
            }

            // Add filter button
            Button(action: {
                filterState.addFilter(columns: columns, primaryKeyColumn: primaryKeyColumn)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Add Filter")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { filterState.focusedFilterId = nil }
    }
    
    // MARK: - Quick Search
    
    private var quickSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            TextField("Quick search across all columns...", text: $filterState.quickSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit {
                    // Apply quick search on Enter
                    if !filterState.quickSearchText.isEmpty {
                        onQuickSearch?(filterState.quickSearchText)
                    }
                }
            
            if filterState.hasActiveQuickSearch {
                Button(action: { filterState.clearQuickSearch() }) {
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            
            Text("No filters active")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                Button("Add Filter") {
                    filterState.addFilter(columns: columns, primaryKeyColumn: primaryKeyColumn)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Text("or use Quick Search above")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Filter List

    private var filterList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filterState.filters) { filter in
                    FilterRowView(
                        filter: filterState.binding(for: filter),
                        columns: columns,
                        isFocused: filterState.focusedFilterId == filter.id,
                        onDuplicate: { filterState.duplicateFilter(filter) },
                        onRemove: { filterState.removeFilter(filter) },
                        onApply: { applySingleFilter(filter) },
                        onFocus: { filterState.focusedFilterId = filter.id }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        // Dynamic height: ~40pt per row, max 4 rows visible before scrolling
        .frame(maxHeight: min(CGFloat(filterState.filters.count) * 40 + 8, 160))
    }

    // MARK: - Footer

    private var filterFooter: some View {
        HStack(spacing: 8) {
            // Select all checkbox
            Toggle("Select All", isOn: selectAllBinding)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .disabled(filterState.filters.isEmpty)

            Spacer()

            // Unset button
            Button("Unset") {
                filterState.clearAppliedFilters()
                onUnset()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!filterState.hasAppliedFilters)

            // SQL button - now uses extracted method
            Button("SQL") {
                generatedSQL = filterState.generatePreviewSQL(databaseType: databaseType)
                showSQLSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(filterState.filters.isEmpty)

            // Apply All button (for selected filters)
            Button("Apply All") {
                applySelectedFilters()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!filterState.hasSelectedFilters)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { filterState.focusedFilterId = nil }
    }

    // MARK: - Helpers

    private var selectAllBinding: Binding<Bool> {
        Binding(
            get: { filterState.allFiltersSelected },
            set: { filterState.selectAll($0) }
        )
    }

    private func applySingleFilter(_ filter: TableFilter) {
        guard filter.isValid else { return }
        filterState.applySingleFilter(filter)
        onApply([filter])
    }

    private func applySelectedFilters() {
        filterState.applySelectedFilters()
        onApply(filterState.appliedFilters)
    }
}

// MARK: - Filter Row View

/// Single filter row view with native macOS styling
struct FilterRowView: View {
    @Binding var filter: TableFilter
    let columns: [String]
    let isFocused: Bool
    let onDuplicate: () -> Void
    let onRemove: () -> Void
    let onApply: () -> Void
    let onFocus: () -> Void

    /// Display name for the column (handles raw SQL and empty)
    private var displayColumnName: String {
        if filter.columnName == TableFilter.rawSQLColumn {
            return "Raw SQL"
        } else if filter.columnName.isEmpty {
            return "Column"
        } else {
            return filter.columnName
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox for multi-select
            Toggle("", isOn: $filter.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()

            // Column dropdown - native Menu style
            columnMenu
                .frame(width: 120)

            // Operator dropdown (hidden for raw SQL)
            if !filter.isRawSQL {
                operatorMenu
                    .frame(width: 110)
            }

            // Value field(s)
            valueFields

            Spacer(minLength: 0)

            // Action buttons
            actionButtons
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isFocused ? Color.accentColor.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
    }

    // MARK: - Column Menu

    private var columnMenu: some View {
        Menu {
            Button(action: { filter.columnName = TableFilter.rawSQLColumn }) {
                if filter.columnName == TableFilter.rawSQLColumn {
                    Label("Raw SQL", systemImage: "checkmark")
                } else {
                    Text("Raw SQL")
                }
            }

            if !columns.isEmpty {
                Divider()
                ForEach(columns, id: \.self) { column in
                    Button(action: { filter.columnName = column }) {
                        if filter.columnName == column {
                            Label(column, systemImage: "checkmark")
                        } else {
                            Text(column)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(displayColumnName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }

    // MARK: - Operator Menu

    private var operatorMenu: some View {
        Menu {
            ForEach(FilterOperator.allCases) { op in
                Button(action: { filter.filterOperator = op }) {
                    if filter.filterOperator == op {
                        Label(op.displayName, systemImage: "checkmark")
                    } else {
                        Text(op.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(filter.filterOperator.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }

    // MARK: - Value Fields

    @ViewBuilder
    private var valueFields: some View {
        if filter.isRawSQL {
            // Raw SQL input
            TextField("WHERE clause...", text: Binding(
                get: { filter.rawSQL ?? "" },
                set: { filter.rawSQL = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .onSubmit { onApply() }
            .simultaneousGesture(TapGesture().onEnded { onFocus() })
        } else if filter.filterOperator.requiresValue {
            // Standard value input
            TextField("Value", text: $filter.value)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .frame(minWidth: 80)
                .onSubmit { onApply() }
                .simultaneousGesture(TapGesture().onEnded { onFocus() })

            // Second value for BETWEEN
            if filter.filterOperator.requiresSecondValue {
                Text("and")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Value", text: Binding(
                    get: { filter.secondValue ?? "" },
                    set: { filter.secondValue = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .frame(minWidth: 80)
                .onSubmit { onApply() }
                .simultaneousGesture(TapGesture().onEnded { onFocus() })
            }
        } else {
            // No value needed (IS NULL, etc.) - show indicator
            Text("—")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 80, alignment: .leading)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Apply single filter
            Button(action: onApply) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(filter.isValid ? Color(nsColor: .systemGreen) : Color.secondary)
            .disabled(!filter.isValid)
            .help("Apply This Filter")

            // Duplicate
            Button(action: onDuplicate) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Duplicate Filter")

            // Remove
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove Filter")
        }
    }
}

// MARK: - SQL Preview Sheet

/// Modal sheet to display generated SQL
struct SQLPreviewSheet: View {
    let sql: String
    let tableName: String
    let databaseType: DatabaseType
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Generated WHERE Clause")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }

            ScrollView {
                Text(sql.isEmpty ? "(no conditions)" : sql)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            HStack {
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Copied!" : "Copy")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(sql.isEmpty)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.escape)
            }
        }
        .padding(16)
        .frame(width: 480, height: 300)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sql, forType: .string)
        copied = true

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Filter Settings Popover

/// Popover for filter default settings
struct FilterSettingsPopover: View {
    @State private var settings: FilterSettings

    init() {
        _settings = State(initialValue: FilterSettingsStorage.shared.loadSettings())
    }

    var body: some View {
        Form {
            Picker("Default Column", selection: $settings.defaultColumn) {
                ForEach(FilterDefaultColumn.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Picker("Default Operator", selection: $settings.defaultOperator) {
                ForEach(FilterDefaultOperator.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Picker("Panel State", selection: $settings.panelState) {
                ForEach(FilterPanelDefaultState.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 280)
        .onChange(of: settings) { _, newValue in
            FilterSettingsStorage.shared.saveSettings(newValue)
        }
    }
}

// MARK: - Preview

#Preview("Filter Panel") {
    FilterPanelView(
        filterState: {
            let state = FilterStateManager()
            Task { @MainActor in
                state.filters = [
                    TableFilter(columnName: "name", filterOperator: .contains, value: "John"),
                    TableFilter(columnName: "age", filterOperator: .greaterThan, value: "18")
                ]
            }
            return state
        }(),
        columns: ["id", "name", "age", "email"],
        primaryKeyColumn: "id",
        databaseType: .mysql,
        onApply: { _ in },
        onUnset: { },
        onQuickSearch: { _ in }
    )
    .frame(width: 600)
}
