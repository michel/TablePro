//
//  MainContentView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

/// Main content view combining query editor and results table
struct MainContentView: View {
    let connection: DatabaseConnection
    
    @StateObject private var tabManager = QueryTabManager()
    @StateObject private var changeManager = DataChangeManager()

    @State private var showTableBrowser: Bool = true
    @State private var showHistory: Bool = false
    @State private var queryHistory: [QueryHistoryEntry] = []
    @State private var selectedRowIndices: Set<Int> = []
    @State private var showDiscardAlert: Bool = false
    @State private var schemaProvider: SQLSchemaProvider = SQLSchemaProvider()
    @State private var cursorPosition: Int = 0  // For query-at-cursor execution
    
    private var currentTab: QueryTab? {
        tabManager.selectedTab
    }
    
    var body: some View {
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
                Button(action: { showHistory.toggle() }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("Query History")
                
                if currentTab?.isExecuting == true {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task {
            await testConnection()
            await loadSchema()
            queryHistory = QueryHistoryManager.shared.loadHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTableBrowser)) { _ in
            showTableBrowser.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleHistory)) { _ in
            showHistory.toggle()
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
            if let tab = currentTab {
                if tabManager.tabs.count > 1 {
                    tabManager.closeTab(tab)
                } else {
                    // Last tab - go back to home (deselect connection)
                    NotificationCenter.default.post(name: .deselectConnection, object: nil)
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
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                changeManager.clearChanges()
                runQuery()
            }
        } message: {
            Text("You have unsaved changes. Do you want to discard them and refresh?")
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
            
            // Results Table + History (bottom)
            VStack(spacing: 0) {
                resultsSection(tab: tab)
                
                // History panel at bottom
                if showHistory {
                    historyPanel
                }
            }
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
                Picker("", selection: Binding(
                    get: { tab.showStructure ? "structure" : "data" },
                    set: { newValue in
                        if let index = tabManager.selectedTabIndex {
                            tabManager.tabs[index].showStructure = (newValue == "structure")
                        }
                    }
                )) {
                    Label("Data", systemImage: "tablecells").tag("data")
                    Label("Structure", systemImage: "list.bullet.rectangle").tag("structure")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                
                Button(action: { runQuery() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Data")
                
                if !tab.resultColumns.isEmpty && !tab.showStructure {
                    Button(action: {
                        ResultExporter.copyToClipboard(columns: tab.resultColumns, rows: tab.resultRows)
                    }) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to Clipboard")
                    
                    Menu {
                        Button("Export as CSV...") {
                            ResultExporter.exportToCSVFile(columns: tab.resultColumns, rows: tab.resultRows)
                        }
                        Button("Export as JSON...") {
                            ResultExporter.exportToJSONFile(columns: tab.resultColumns, rows: tab.resultRows)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Export Results")
                }
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
                        rows: tab.resultRows,
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
                    selectedRowIndices: $selectedRowIndices
                )
                .frame(maxHeight: .infinity, alignment: .top)
            }
            
            // History panel at bottom
            if showHistory {
                historyPanel
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
                        rows: tab.resultRows,
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
                    selectedRowIndices: $selectedRowIndices
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
                Picker("", selection: Binding(
                    get: { tab.showStructure ? "structure" : "data" },
                    set: { newValue in
                        if let index = tabManager.selectedTabIndex {
                            tabManager.tabs[index].showStructure = (newValue == "structure")
                        }
                    }
                )) {
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
                        ResultExporter.exportToCSVFile(columns: tab.resultColumns, rows: tab.resultRows)
                    }
                    Button("Export as JSON...") {
                        ResultExporter.exportToJSONFile(columns: tab.resultColumns, rows: tab.resultRows)
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
    
    // MARK: - History Panel
    
    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            
            HStack {
                Text("History")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Clear") {
                    QueryHistoryManager.shared.clearHistory()
                    queryHistory = []
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(queryHistory.prefix(20)) { entry in
                        Button(action: {
                            if let index = tabManager.selectedTabIndex {
                                tabManager.tabs[index].query = entry.query
                            }
                            showHistory = false
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.query)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                
                                Text(entry.executedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
    
    private func testConnection() async {
        let driver = DatabaseDriverFactory.createDriver(for: connection)
        do {
            try await driver.connect()
            driver.disconnect()
        } catch {
            if let index = tabManager.selectedTabIndex {
                tabManager.tabs[index].errorMessage = error.localizedDescription
            }
        }
    }
    
    private func loadSchema() async {
        let driver = DatabaseDriverFactory.createDriver(for: connection)
        do {
            try await driver.connect()
            await schemaProvider.loadSchema(using: driver, connection: connection)
            driver.disconnect()
        } catch {
            print("[MainContentView] Failed to load schema: \(error)")
        }
    }
    
    private func runQuery() {
        guard let index = tabManager.selectedTabIndex else { return }
        guard !tabManager.tabs[index].isExecuting else { return }
        
        tabManager.tabs[index].isExecuting = true
        tabManager.tabs[index].executionTime = nil
        tabManager.tabs[index].errorMessage = nil
        
        // Clear pending changes when running new query
        changeManager.discardChanges()
        
        let fullQuery = tabManager.tabs[index].query
        
        // Extract query at cursor position (like TablePlus)
        let sql = extractQueryAtCursor(from: fullQuery, at: cursorPosition)
        
        let conn = connection
        let tabId = tabManager.tabs[index].id
        
        // Detect table name from simple SELECT queries
        let tableName = extractTableName(from: sql)
        let isEditable = tableName != nil
        
        Task {
            do {
                let result = try await executeQueryAsync(sql: sql, connection: conn)
                
                // Fetch column defaults if editable table
                var columnDefaults: [String: String?] = [:]
                if isEditable, let tableName = tableName {
                    let driver = DatabaseDriverFactory.createDriver(for: conn)
                    try await driver.connect()
                    let columnInfo = try await driver.fetchColumns(table: tableName)
                    driver.disconnect()
                    
                    for col in columnInfo {
                        columnDefaults[col.name] = col.defaultValue
                    }
                }
                
                // Find tab by ID (index may have changed) - must update on main thread
                await MainActor.run {
                    if let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) {
                        tabManager.tabs[idx].resultColumns = result.columns
                        tabManager.tabs[idx].columnDefaults = columnDefaults
                        tabManager.tabs[idx].resultRows = result.toQueryResultRows()
                        tabManager.tabs[idx].executionTime = result.executionTime
                        tabManager.tabs[idx].isExecuting = false
                        tabManager.tabs[idx].lastExecutedAt = Date()
                        tabManager.tabs[idx].tableName = tableName
                        tabManager.tabs[idx].isEditable = isEditable
                        
                        // Configure change manager for this table
                        changeManager.tableName = tableName ?? ""
                        changeManager.columns = result.columns
                        // Default to first column as primary key (usually 'id')
                        changeManager.primaryKeyColumn = result.columns.first
                        
                        // Force table reload with fresh data
                        changeManager.reloadVersion += 1
                    }
                    
                    // Save to history
                    let entry = QueryHistoryEntry(
                        query: sql,
                        connectionName: conn.name,
                        rowCount: result.rowCount,
                        executionTime: result.executionTime,
                        wasSuccessful: true
                    )
                    QueryHistoryManager.shared.addEntry(entry)
                    queryHistory = QueryHistoryManager.shared.loadHistory()
                }
                
            } catch {
                if let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) {
                    tabManager.tabs[idx].errorMessage = error.localizedDescription
                    tabManager.tabs[idx].isExecuting = false
                }
                
                // Save failed query to history
                let entry = QueryHistoryEntry(
                    query: sql,
                    connectionName: conn.name,
                    wasSuccessful: false
                )
                QueryHistoryManager.shared.addEntry(entry)
                queryHistory = QueryHistoryManager.shared.loadHistory()
            }
        }
    }
    
    private func executeQueryAsync(sql: String, connection: DatabaseConnection) async throws -> QueryResult {
        let driver = DatabaseDriverFactory.createDriver(for: connection)
        try await driver.connect()
        let result = try await driver.execute(query: sql)
        driver.disconnect()
        return result
    }
    
    /// Extract table name from a simple SELECT query
    private func extractTableName(from sql: String) -> String? {
        let pattern = #"(?i)^\s*SELECT\s+.+?\s+FROM\s+[`"]?(\w+)[`"]?\s*(?:WHERE|ORDER|LIMIT|GROUP|HAVING|$|;)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: sql, options: [], range: NSRange(sql.startIndex..., in: sql)),
              let range = Range(match.range(at: 1), in: sql) else {
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
                let statement = String(fullQuery[fullQuery.index(fullQuery.startIndex, offsetBy: currentStart)..<fullQuery.index(fullQuery.startIndex, offsetBy: i)])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !statement.isEmpty {
                    statements.append((text: statement, range: currentStart..<(i + 1)))
                }
                currentStart = i + 1
            }
        }
        
        // Don't forget the last statement (may not end with ;)
        if currentStart < fullQuery.count {
            let remaining = String(fullQuery[fullQuery.index(fullQuery.startIndex, offsetBy: currentStart)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                statements.append((text: remaining, range: currentStart..<fullQuery.count))
            }
        }
        
        // Find the statement containing the cursor position
        let safePosition = min(max(0, position), fullQuery.count)
        for statement in statements {
            if statement.range.contains(safePosition) || statement.range.upperBound == safePosition {
                return statement.text
            }
        }
        
        // If cursor is at end or no match, return last statement
        return statements.last?.text ?? trimmed
    }
    
    /// Update cell value in the current tab's resultRows
    private func updateCellInTab(rowIndex: Int, columnIndex: Int, value: String?) {
        guard let index = tabManager.selectedTabIndex,
              rowIndex < tabManager.tabs[index].resultRows.count else { return }
        
        // Update the underlying data so it persists across UI refreshes
        tabManager.tabs[index].resultRows[rowIndex].values[columnIndex] = value
    }
    
    /// Delete selected rows (Delete key)
    private func deleteSelectedRows() {
        guard let index = tabManager.selectedTabIndex,
              !selectedRowIndices.isEmpty else { return }
        
        // Mark each selected row for deletion
        for rowIndex in selectedRowIndices.sorted(by: >) {
            if rowIndex < tabManager.tabs[index].resultRows.count {
                let originalRow = tabManager.tabs[index].resultRows[rowIndex].values
                changeManager.recordRowDeletion(rowIndex: rowIndex, originalRow: originalRow)
            }
        }
        
        // Clear selection after marking for deletion
        selectedRowIndices.removeAll()
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
                let driver = DatabaseDriverFactory.createDriver(for: connection)
                try await driver.connect()
                
                // Execute each statement
                let statements = sql.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                
                for statement in statements {
                    _ = try await driver.execute(query: statement)
                    
                    // Add to history
                    await MainActor.run {
                        let entry = QueryHistoryEntry(
                            query: statement.trimmingCharacters(in: .whitespacesAndNewlines),
                            connectionName: connection.name,
                            rowCount: 1,
                            executionTime: 0,
                            wasSuccessful: true
                        )
                        QueryHistoryManager.shared.addEntry(entry)
                        queryHistory = QueryHistoryManager.shared.loadHistory()
                    }
                }
                
                driver.disconnect()
                
                // Clear pending changes since they're now saved
                await MainActor.run {
                    changeManager.clearChanges()
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
    
    /// Open table data on double-click (like TablePlus)
    private func openTableData(_ tableName: String) {
        // Create or switch to table tab
        tabManager.addTableTab(tableName: tableName)
        
        // Auto-execute query
        runQuery()
    }
}

#Preview("With Connection") {
    MainContentView(connection: DatabaseConnection.sampleConnections[0])
        .frame(width: 1000, height: 600)
}
