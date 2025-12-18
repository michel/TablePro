//
//  MainContentView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Combine
import SwiftUI

/// Main content view combining query editor and results table
struct MainContentView: View {
    let connection: DatabaseConnection

    @StateObject private var tabManager = QueryTabManager()
    @StateObject private var changeManager = DataChangeManager()

    @State private var showTableBrowser: Bool = true
    @State private var selectedRowIndices: Set<Int> = []
    @State private var showDiscardAlert: Bool = false
    @State private var showCloseTabAlert: Bool = false
    @State private var schemaProvider: SQLSchemaProvider = SQLSchemaProvider()
    @State private var cursorPosition: Int = 0  // For query-at-cursor execution
    @State private var currentQueryTask: Task<Void, Never>?  // Track running query to cancel on new query
    @State private var queryGeneration: Int = 0  // Incremented on each new query, used to ignore stale results
    @State private var changeManagerUpdateTask: Task<Void, Never>?  // Debounce changeManager updates

    private var currentTab: QueryTab? {
        tabManager.selectedTab
    }

    var body: some View {
        Group {
            bodyContent
        }
    }
    
    @ViewBuilder
    private var bodyContent: some View {
        HSplitView {
            // Table Browser (left) - toggle with Cmd+1
            if showTableBrowser {
                TableBrowserView(
                    connection: connection,
                    onSelectQuery: { query in
                        if let index = tabManager.selectedTabIndex {
                            tabManager.tabs[index].query = query
                        }
                    },
                    onOpenTable: { tableName in
                        openTableData(tableName)
                    },
                    activeTableName: currentTab?.tableName
                )
                .frame(minWidth: 150, idealWidth: 220, maxWidth: 400)
            }

            // Main content (right)
            VStack(spacing: 0) {
                // Tab bar
                QueryTabBar(tabManager: tabManager)

                Divider()

                // Content for selected tab
                if let tab = currentTab {
                    if tab.tabType == .query {
                        // Query Tab: Editor + Results
                        queryTabContent(tab: tab)
                    } else {
                        // Table Tab: Results only
                        tableTabContent(tab: tab)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { showTableBrowser.toggle() }) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Table Browser")

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)

                    Image(systemName: connection.type.iconName)
                        .foregroundStyle(connection.type.themeColor)

                    Text(connection.name)
                        .fontWeight(.medium)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if currentTab?.isExecuting == true {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task {
            await establishConnection()
            await loadSchema()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTableBrowser)) { _ in
            showTableBrowser.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportCSV)) { _ in
            if let tab = currentTab, !tab.resultColumns.isEmpty {
                ResultExporter.exportToCSVFile(columns: tab.resultColumns, rows: tab.resultRows)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportJSON)) { _ in
            if let tab = currentTab, !tab.resultColumns.isEmpty {
                ResultExporter.exportToJSONFile(columns: tab.resultColumns, rows: tab.resultRows)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyResults)) { _ in
            if let tab = currentTab, !tab.resultColumns.isEmpty {
                ResultExporter.copyToClipboard(columns: tab.resultColumns, rows: tab.resultRows)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeCurrentTab)) { _ in
            if currentTab != nil {
                // Check for unsaved changes before closing
                if changeManager.hasChanges {
                    showCloseTabAlert = true
                } else {
                    closeCurrentTab()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveChanges)) { _ in
            // Cmd+S to save changes
            saveChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshData)) { _ in
            // Cmd+R to refresh data - warn if pending changes
            if changeManager.hasChanges {
                showDiscardAlert = true
            } else {
                runQuery()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedRows)) { _ in
            // Delete key to mark selected rows for deletion
            deleteSelectedRows()
        }
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                // Clear both changeManager and tab's stored pending changes
                changeManager.clearChanges()
                if let index = tabManager.selectedTabIndex {
                    tabManager.tabs[index].pendingChanges = TabPendingChanges()
                }
                runQuery()
            }
        } message: {
            Text("You have unsaved changes. Do you want to discard them and refresh?")
        }
        .alert("Close Tab?", isPresented: $showCloseTabAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Discard & Close", role: .destructive) {
                // Clear both changeManager and tab's stored pending changes
                changeManager.clearChanges()
                if let index = tabManager.selectedTabIndex {
                    tabManager.tabs[index].pendingChanges = TabPendingChanges()
                }
                closeCurrentTab()
            }
        } message: {
            Text("You have unsaved changes. Close this tab and discard changes?")
        }
        .onChange(of: tabManager.selectedTabId) { oldTabId, newTabId in
            // Save state to the old tab before switching
            if let oldId = oldTabId,
                let oldIndex = tabManager.tabs.firstIndex(where: { $0.id == oldId })
            {
                // Save pending changes
                tabManager.tabs[oldIndex].pendingChanges = changeManager.saveState()
                // Save row selection
                tabManager.tabs[oldIndex].selectedRowIndices = selectedRowIndices
                // sortState is already in tab, no need to save from local state
            }

            // Restore state from the new tab
            if let newId = newTabId,
                let newIndex = tabManager.tabs.firstIndex(where: { $0.id == newId })
            {
                let newTab = tabManager.tabs[newIndex]

                // Restore pending changes
                if newTab.pendingChanges.hasChanges {
                    changeManager.restoreState(
                        from: newTab.pendingChanges, tableName: newTab.tableName ?? "")
                } else {
                    // Clear changeManager for tabs without pending changes (atomically)
                    changeManager.configureForTable(
                        tableName: newTab.tableName ?? "",
                        columns: newTab.resultColumns,
                        primaryKeyColumn: newTab.resultColumns.first
                    )
                }

                // Restore row selection
                selectedRowIndices = newTab.selectedRowIndices
                // sortState is accessed via binding, no need to restore to local state
            }
        }
        .onChange(of: currentTab?.resultColumns) { _, newColumns in
            // Sync changeManager when data loads on the current tab
            guard let newColumns = newColumns, !newColumns.isEmpty else { return }
            guard let tab = tabManager.selectedTab else { return }
            guard !tab.pendingChanges.hasChanges else { return }
            
            // Only update if columns have actually changed
            guard changeManager.columns != newColumns else { return }
            
            changeManager.configureForTable(
                tableName: tab.tableName ?? "",
                columns: newColumns,
                primaryKeyColumn: newColumns.first
            )
        }
    }

    // MARK: - Query Tab Content

    private func queryTabContent(tab: QueryTab) -> some View {
        VSplitView {
            // Query Editor (top)
            VStack(spacing: 0) {
                QueryEditorView(
                    queryText: Binding(
                        get: { tab.query },
                        set: { newValue in
                            if let index = tabManager.selectedTabIndex {
                                tabManager.tabs[index].query = newValue
                            }
                        }
                    ),
                    cursorPosition: $cursorPosition,
                    onExecute: runQuery,
                    schemaProvider: schemaProvider
                )
            }
            .frame(minHeight: 100, idealHeight: 200)

            // Results Table (bottom)
            resultsSection(tab: tab)
        }
    }

    // MARK: - Table Tab Content

    private func tableTabContent(tab: QueryTab) -> some View {
        VStack(spacing: 0) {
            // Toolbar with Data/Structure toggle
            HStack {
                Image(systemName: "tablecells")
                    .foregroundStyle(.blue)
                Text(tab.tableName ?? tab.title)
                    .font(.headline)

                Spacer()

                // Data/Structure toggle
                Picker(
                    "",
                    selection: Binding(
                        get: { tab.showStructure ? "structure" : "data" },
                        set: { newValue in
                            DispatchQueue.main.async {
                                if let index = tabManager.selectedTabIndex {
                                    tabManager.tabs[index].showStructure = (newValue == "structure")
                                }
                            }
                        }
                    )
                ) {
                    Label("Data", systemImage: "tablecells").tag("data")
                    Label("Structure", systemImage: "list.bullet.rectangle").tag("structure")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Show structure view or data view based on toggle
            if tab.showStructure, let tableName = tab.tableName {
                TableStructureView(tableName: tableName, connection: connection)
                    .frame(maxHeight: .infinity)
            } else {
                // Data view
                if let error = tab.errorMessage {
                    errorBanner(error)
                }

                DataGridView(
                    rowProvider: InMemoryRowProvider(
                        rows: sortedRows(for: tab),
                        columns: tab.resultColumns,
                        columnDefaults: tab.columnDefaults
                    ),
                    changeManager: changeManager,
                    isEditable: tab.isEditable,
                    onCommit: { sql in
                        executeCommitSQL(sql)
                    },
                    onRefresh: { runQuery() },
                    onCellEdit: { rowIndex, colIndex, newValue in
                        updateCellInTab(rowIndex: rowIndex, columnIndex: colIndex, value: newValue)
                    },
                    onSort: { columnIndex in
                        handleSort(columnIndex: columnIndex)
                    },
                    selectedRowIndices: $selectedRowIndices,
                    sortState: sortStateBinding
                )
                .frame(maxHeight: .infinity, alignment: .top)
            }

            statusBar
        }
    }

    // MARK: - Results Section (shared)

    private func resultsSection(tab: QueryTab) -> some View {
        VStack(spacing: 0) {
            resultsToolbar

            if let error = tab.errorMessage {
                errorBanner(error)
            }

            // Show structure view or data view based on toggle
            if tab.showStructure, let tableName = tab.tableName {
                TableStructureView(tableName: tableName, connection: connection)
                    .frame(maxHeight: .infinity)
            } else {
                DataGridView(
                    rowProvider: InMemoryRowProvider(
                        rows: sortedRows(for: tab),
                        columns: tab.resultColumns,
                        columnDefaults: tab.columnDefaults
                    ),
                    changeManager: changeManager,
                    isEditable: tab.isEditable,
                    onCommit: { sql in
                        executeCommitSQL(sql)
                    },
                    onRefresh: { runQuery() },
                    onCellEdit: { rowIndex, colIndex, newValue in
                        updateCellInTab(rowIndex: rowIndex, columnIndex: colIndex, value: newValue)
                    },
                    onSort: { columnIndex in
                        handleSort(columnIndex: columnIndex)
                    },
                    selectedRowIndices: $selectedRowIndices,
                    sortState: sortStateBinding
                )
                .frame(maxHeight: .infinity, alignment: .top)
            }

            statusBar
        }
        .frame(minHeight: 150)
    }
    // MARK: - Results Toolbar

    private var resultsToolbar: some View {
        HStack {
            // Data/Structure toggle for table tabs
            if let tab = currentTab, tab.tabType == .table, tab.tableName != nil {
                Picker(
                    "",
                    selection: Binding(
                        get: { tab.showStructure ? "structure" : "data" },
                        set: { newValue in
                            DispatchQueue.main.async {
                                if let index = tabManager.selectedTabIndex {
                                    tabManager.tabs[index].showStructure = (newValue == "structure")
                                }
                            }
                        }
                    )
                ) {
                    Label("Data", systemImage: "tablecells").tag("data")
                    Label("Structure", systemImage: "list.bullet.rectangle").tag("structure")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            } else {
                Text("Results")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let tab = currentTab, !tab.resultColumns.isEmpty, !tab.showStructure {
                Button(action: {
                    ResultExporter.copyToClipboard(columns: tab.resultColumns, rows: tab.resultRows)
                }) {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help("Copy to Clipboard")

                Menu {
                    Button("Export as CSV...") {
                        ResultExporter.exportToCSVFile(
                            columns: tab.resultColumns, rows: tab.resultRows)
                    }
                    Button("Export as JSON...") {
                        ResultExporter.exportToJSONFile(
                            columns: tab.resultColumns, rows: tab.resultRows)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .help("Export Results")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }



    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if let time = currentTab?.executionTime {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Query executed in \(String(format: "%.3f", time))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let tab = currentTab, !tab.resultRows.isEmpty {
                Text("\(tab.resultRows.count) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)

            Spacer()

            Button("Dismiss") {
                if let index = tabManager.selectedTabIndex {
                    tabManager.tabs[index].errorMessage = nil
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.15))
    }

    // MARK: - Actions

    /// Establish connection using DatabaseManager (with SSH tunnel support)
    private func establishConnection() async {
        do {
            try await DatabaseManager.shared.connect(to: connection)
        } catch {
            if let index = tabManager.selectedTabIndex {
                tabManager.tabs[index].errorMessage = error.localizedDescription
            }
        }
    }

    private func loadSchema() async {
        // Use activeDriver from DatabaseManager (already connected with SSH tunnel if enabled)
        guard let driver = DatabaseManager.shared.activeDriver else {
            print("[MainContentView] Failed to load schema: No active driver")
            return
        }
        await schemaProvider.loadSchema(using: driver, connection: connection)
    }

    private func runQuery() {
        guard let index = tabManager.selectedTabIndex else { return }

        // Cancel any previous running query to prevent race conditions
        // This is critical for SSH connections where rapid sorting can cause
        // multiple queries to return out of order, leading to EXC_BAD_ACCESS
        currentQueryTask?.cancel()
        
        // Increment generation - any query with a different generation will be ignored
        queryGeneration += 1
        let capturedGeneration = queryGeneration

        guard !tabManager.tabs[index].isExecuting else { return }

        tabManager.tabs[index].isExecuting = true
        tabManager.tabs[index].executionTime = nil
        tabManager.tabs[index].errorMessage = nil

        // Note: We don't discard changes here anymore - changes persist until:
        // 1. User saves (Cmd+S)
        // 2. User explicitly discards (via alert)
        // 3. Tab is closed

        let fullQuery = tabManager.tabs[index].query

        // Extract query at cursor position (like TablePlus)
        let sql = extractQueryAtCursor(from: fullQuery, at: cursorPosition)

        let conn = connection
        let tabId = tabManager.tabs[index].id

        // Detect table name from simple SELECT queries
        let tableName = extractTableName(from: sql)
        let isEditable = tableName != nil

        currentQueryTask = Task {
            do {
                let result = try await executeQueryAsync(sql: sql, connection: conn)

                // Fetch column defaults if editable table
                var columnDefaults: [String: String?] = [:]
                if isEditable, let tableName = tableName {
                    // Use activeDriver from DatabaseManager (already connected with SSH tunnel)
                    if let driver = DatabaseManager.shared.activeDriver {
                        let columnInfo = try await driver.fetchColumns(table: tableName)
                        for col in columnInfo {
                            columnDefaults[col.name] = col.defaultValue
                        }
                    }
                }

                // ===== CRITICAL: Deep copy ALL data BEFORE leaving this async context =====
                // Create NEW String objects to avoid any reference to underlying C buffers
                var safeColumns: [String] = []
                for col in result.columns {
                    safeColumns.append(String(col))
                }

                var safeRows: [QueryResultRow] = []
                for row in result.rows {
                    var safeValues: [String?] = []
                    for val in row {
                        if let v = val {
                            safeValues.append(String(v))
                        } else {
                            safeValues.append(nil)
                        }
                    }
                    safeRows.append(QueryResultRow(values: safeValues))
                }

                let safeExecutionTime = result.executionTime
                let safeRowCount = result.rowCount

                // Copy columnDefaults too
                var safeColumnDefaults: [String: String?] = [:]
                for (key, value) in columnDefaults {
                    safeColumnDefaults[String(key)] = value.map { String($0) }
                }

                let safeTableName = tableName.map { String($0) }

                // Check if task was cancelled (e.g., user triggered another sort)
                // This prevents race conditions where cancelled queries still try to update UI
                guard !Task.isCancelled else {
                    await MainActor.run {
                        if let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) {
                            tabManager.tabs[idx].isExecuting = false
                        }
                    }
                    return
                }

                // Find tab by ID (index may have changed) - must update on main thread
                await MainActor.run {
                    // Critical: Only update if this is still the most recent query
                    // This prevents race conditions when navigating quickly between tables
                    // where cancelled/stale queries could still update changeManager
                    guard capturedGeneration == queryGeneration else { return }
                    guard !Task.isCancelled else { return }
                    
                    if let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) {
                        // CRITICAL: Update tab atomically to prevent objc_retain crashes
                        // with large result sets (25+ columns). Working with a copy first
                        // prevents partial updates that can crash during deallocation.
                        var updatedTab = tabManager.tabs[idx]
                        updatedTab.resultColumns = safeColumns
                        updatedTab.columnDefaults = safeColumnDefaults
                        updatedTab.resultRows = safeRows
                        updatedTab.executionTime = safeExecutionTime
                        updatedTab.isExecuting = false
                        updatedTab.lastExecutedAt = Date()
                        updatedTab.tableName = safeTableName
                        updatedTab.isEditable = isEditable
                        
                        // Atomically replace the tab
                        tabManager.tabs[idx] = updatedTab
                        
                        // IMPORTANT: We do NOT update changeManager here.
                        // After extensive debugging, updating changeManager from async
                        // Task completion causes EXC_BAD_ACCESS crashes during rapid navigation.
                        // The onChange(selectedTabId) handler updates changeManager synchronously
                        // when this tab becomes selected, which is safe and reliable.
                    }
                }

            } catch {
                // Only update if this is still the current query
                guard capturedGeneration == queryGeneration else { return }
                
                if let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) {
                    tabManager.tabs[idx].errorMessage = error.localizedDescription
                    tabManager.tabs[idx].isExecuting = false
                }
            }
        }
    }

    private func executeQueryAsync(sql: String, connection: DatabaseConnection) async throws
        -> QueryResult
    {
        // Use DatabaseManager to execute query - this ensures proper thread safety
        return try await DatabaseManager.shared.execute(query: sql)
    }

    /// Extract table name from a simple SELECT query
    private func extractTableName(from sql: String) -> String? {
        let pattern =
            #"(?i)^\s*SELECT\s+.+?\s+FROM\s+[`"]?(\w+)[`"]?\s*(?:WHERE|ORDER|LIMIT|GROUP|HAVING|$|;)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let match = regex.firstMatch(
                in: sql, options: [], range: NSRange(sql.startIndex..., in: sql)),
            let range = Range(match.range(at: 1), in: sql)
        else {
            return nil
        }

        return String(sql[range])
    }

    /// Extract the SQL statement at the cursor position (semicolon-delimited)
    /// This enables TablePlus-like behavior: execute only the current query, not all queries
    private func extractQueryAtCursor(from fullQuery: String, at position: Int) -> String {
        let trimmed = fullQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // If no semicolons, return the entire query
        guard trimmed.contains(";") else { return trimmed }

        // Split by semicolon but keep track of positions
        var statements: [(text: String, range: Range<Int>)] = []
        var currentStart = 0
        var inString = false
        var stringChar: Character = "\""

        for (i, char) in fullQuery.enumerated() {
            // Track string literals to avoid splitting on semicolons inside strings
            if char == "'" || char == "\"" {
                if !inString {
                    inString = true
                    stringChar = char
                } else if char == stringChar {
                    inString = false
                }
            }

            // Found a statement delimiter
            if char == ";" && !inString {
                let statement = String(
                    fullQuery[
                        fullQuery.index(
                            fullQuery.startIndex, offsetBy: currentStart)..<fullQuery.index(
                                fullQuery.startIndex, offsetBy: i)]
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                if !statement.isEmpty {
                    statements.append((text: statement, range: currentStart..<(i + 1)))
                }
                currentStart = i + 1
            }
        }

        // Don't forget the last statement (may not end with ;)
        if currentStart < fullQuery.count {
            let remaining = String(
                fullQuery[fullQuery.index(fullQuery.startIndex, offsetBy: currentStart)...]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                statements.append((text: remaining, range: currentStart..<fullQuery.count))
            }
        }

        // Find the statement containing the cursor position
        let safePosition = min(max(0, position), fullQuery.count)
        for statement in statements {
            if statement.range.contains(safePosition) || statement.range.upperBound == safePosition
            {
                return statement.text
            }
        }

        // If cursor is at end or no match, return last statement
        return statements.last?.text ?? trimmed
    }

    /// Update cell value in the current tab's resultRows
    private func updateCellInTab(rowIndex: Int, columnIndex: Int, value: String?) {
        guard let index = tabManager.selectedTabIndex,
            rowIndex < tabManager.tabs[index].resultRows.count
        else { return }

        // Update the underlying data so it persists across UI refreshes
        tabManager.tabs[index].resultRows[rowIndex].values[columnIndex] = value
        
        // Mark tab as having user interaction (prevents auto-replacement)
        tabManager.tabs[index].hasUserInteraction = true
    }

    /// Delete selected rows (Delete key)
    private func deleteSelectedRows() {
        guard let index = tabManager.selectedTabIndex,
            !selectedRowIndices.isEmpty
        else { return }

        // Mark each selected row for deletion
        for rowIndex in selectedRowIndices.sorted(by: >) {
            if rowIndex < tabManager.tabs[index].resultRows.count {
                let originalRow = tabManager.tabs[index].resultRows[rowIndex].values
                changeManager.recordRowDeletion(rowIndex: rowIndex, originalRow: originalRow)
            }
        }

        // Clear selection after marking for deletion
        selectedRowIndices.removeAll()
        
        // Mark tab as having user interaction (prevents auto-replacement)
        tabManager.tabs[index].hasUserInteraction = true
    }

    // MARK: - Column Sorting

    /// Binding for the current tab's sort state
    private var sortStateBinding: Binding<SortState> {
        Binding(
            get: {
                guard let index = tabManager.selectedTabIndex else {
                    return SortState()
                }
                return tabManager.tabs[index].sortState
            },
            set: { newValue in
                if let index = tabManager.selectedTabIndex {
                    tabManager.tabs[index].sortState = newValue
                }
            }
        )
    }
    
    /// Binding for column widths - persists widths across tab switches


    /// Get rows for a tab (sorting is done via SQL ORDER BY, so just return as-is)
    private func sortedRows(for tab: QueryTab) -> [QueryResultRow] {
        return tab.resultRows
    }

    /// Handle column header click for sorting (uses SQL ORDER BY)
    private func handleSort(columnIndex: Int) {
        guard let tabIndex = tabManager.selectedTabIndex else { return }
        
        // Capture all values early to prevent deallocation issues
        guard tabIndex < tabManager.tabs.count else { return }
        let tab = tabManager.tabs[tabIndex]
        
        // CRITICAL: Validate column index for large tables
        guard columnIndex >= 0 && columnIndex < tab.resultColumns.count else {
            print("ERROR: Invalid column index \(columnIndex), table has \(tab.resultColumns.count) columns")
            return
        }

        // Capture column name to avoid string retention issues
        let columnName = String(tab.resultColumns[columnIndex])
        var currentSort = tab.sortState

        // Toggle direction if same column, otherwise start ascending
        if currentSort.columnIndex == columnIndex {
            currentSort.direction.toggle()
        } else {
            currentSort.columnIndex = columnIndex
            currentSort.direction = .ascending
        }

        // Verify tab still exists before updating
        guard tabIndex < tabManager.tabs.count else { return }
        
        // Update sort state
        tabManager.tabs[tabIndex].sortState = currentSort
        
        // Mark tab as having user interaction (prevents auto-replacement)
        tabManager.tabs[tabIndex].hasUserInteraction = true

        // Build ORDER BY clause with explicit string copies to avoid retention issues
        let orderDirection = currentSort.direction == .ascending ? "ASC" : "DESC"

        // Get base query (remove any existing ORDER BY) - work with copy
        var baseQuery = String(tab.query)
        if let orderByRange = baseQuery.range(
            of: "ORDER BY", options: [.caseInsensitive, .backwards])
        {
            // Find the end of ORDER BY clause (before LIMIT or end of query)
            let afterOrderBy = baseQuery[orderByRange.upperBound...]
            if let limitRange = afterOrderBy.range(of: "LIMIT", options: .caseInsensitive) {
                // Keep LIMIT, remove ORDER BY clause
                let beforeOrderBy = baseQuery[..<orderByRange.lowerBound]
                let limitClause = baseQuery[limitRange.lowerBound...]
                baseQuery = String(beforeOrderBy) + String(limitClause)
            } else if afterOrderBy.range(of: ";") != nil {
                // Remove ORDER BY until semicolon
                baseQuery = String(baseQuery[..<orderByRange.lowerBound]) + ";"
            } else {
                // Remove ORDER BY until end
                baseQuery = String(baseQuery[..<orderByRange.lowerBound])
            }
        }

        // Insert ORDER BY before LIMIT (if exists) or at end
        let orderByClause = "ORDER BY `\(columnName)` \(orderDirection)"
        
        let newQuery: String
        if let limitRange = baseQuery.range(of: "LIMIT", options: .caseInsensitive) {
            let beforeLimit = baseQuery[..<limitRange.lowerBound].trimmingCharacters(
                in: .whitespaces)
            let limitClause = baseQuery[limitRange.lowerBound...]
            newQuery = "\(beforeLimit) \(orderByClause) \(limitClause)"
        } else {
            // Remove trailing semicolon and add ORDER BY
            let trimmed = baseQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(";") {
                newQuery = String(trimmed.dropLast()) + " \(orderByClause);"
            } else {
                newQuery = "\(trimmed) \(orderByClause)"
            }
        }
        
        // Final validation before updating tab
        guard tabIndex < tabManager.tabs.count else { return }
        tabManager.tabs[tabIndex].query = newQuery

        // Re-execute query to fetch sorted data
        runQuery()
    }

    /// Close the current tab or go back to home if it's the last tab
    private func closeCurrentTab() {
        guard let tab = currentTab else { return }

        if tabManager.tabs.count > 1 {
            tabManager.closeTab(tab)
        } else {
            // Last tab - go back to home (deselect connection)
            NotificationCenter.default.post(name: .deselectConnection, object: nil)
        }
    }

    /// Save pending changes (Cmd+S)
    private func saveChanges() {
        guard changeManager.hasChanges else { return }

        let statements = changeManager.generateSQL()
        guard !statements.isEmpty else { return }

        let sql = statements.joined(separator: ";\n")
        executeCommitSQL(sql)
    }

    /// Execute commit SQL and refresh data
    private func executeCommitSQL(_ sql: String) {
        guard !sql.isEmpty else { return }

        Task {
            do {
                // Use activeDriver from DatabaseManager (already connected with SSH tunnel)
                guard let driver = DatabaseManager.shared.activeDriver else {
                    throw DatabaseError.notConnected
                }

                // Execute each statement
                let statements = sql.components(separatedBy: ";").filter {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

                for statement in statements {
                    _ = try await driver.execute(query: statement)
                }

                // Clear pending changes since they're now saved
                await MainActor.run {
                    changeManager.clearChanges()
                    // Also clear the tab's stored pending changes
                    if let index = tabManager.selectedTabIndex {
                        tabManager.tabs[index].pendingChanges = TabPendingChanges()
                    }
                }

                // Refresh the current query to show updated data
                runQuery()

            } catch {
                if let index = tabManager.selectedTabIndex {
                    tabManager.tabs[index].errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// Debounced update of changeManager to prevent crashes during rapid navigation
    /// Only updates if tab remains selected for 100ms
    private func debouncedUpdateChangeManager(for tabId: UUID) {
        // Cancel any pending update
        changeManagerUpdateTask?.cancel()
        
        // Schedule new update after delay
        changeManagerUpdateTask = Task { @MainActor in
            // Wait 100ms to allow rapid navigation to settle
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            guard !Task.isCancelled else { return }
            guard tabManager.selectedTabId == tabId else { return }
            guard let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) else { return }
            
            let tab = tabManager.tabs[idx]
            changeManager.configureForTable(
                tableName: tab.tableName ?? "",
                columns: tab.resultColumns,
                primaryKeyColumn: tab.resultColumns.first
            )
        }
    }

    /// Open table data (TablePlus-style smart tab behavior)
    /// - Reuses clean table tabs instead of creating new ones
    /// - Creates new tab if current tab has unsaved changes or is a query tab
    /// - Preserves pending changes per-tab when switching
    private func openTableData(_ tableName: String) {
        // Note: Save/restore of pending changes is handled by onChange(of: selectedTabId)
        // which fires whenever the selected tab changes

        // Use smart tab opening - reuse clean table tabs
        // Returns true if we need to run query (new/replaced tab), false if just switching to existing
        let needsQuery = tabManager.openTableTabSmart(
            tableName: tableName, hasUnsavedChanges: changeManager.hasChanges)

        // Clear selection for new/replaced tabs (prevents old selection from leaking)
        // For existing tabs, onChange will restore their saved selection
        if needsQuery {
            selectedRowIndices = []
            runQuery()
        }
    }
}

#Preview("With Connection") {
    MainContentView(connection: DatabaseConnection.sampleConnections[0])
        .frame(width: 1000, height: 600)
}
