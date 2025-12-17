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
    @State private var connectionState: String = "Connecting..."
    @State private var showTableBrowser: Bool = true
    @State private var showHistory: Bool = false
    @State private var queryHistory: [QueryHistoryEntry] = []
    
    private var currentTab: QueryTab? {
        tabManager.selectedTab
    }
    
    var body: some View {
        HSplitView {
            // Table Browser (left)
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
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
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
                        .fill(connectionState == "Connected" ? Color.green : Color.orange)
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
                    onExecute: runQuery
                )
                
                // History panel
                if showHistory {
                    historyPanel
                }
            }
            .frame(minHeight: 100, idealHeight: 200)
            
            // Results Table (bottom)
            resultsSection(tab: tab)
        }
    }
    
    // MARK: - Table Tab Content
    
    private func tableTabContent(tab: QueryTab) -> some View {
        VStack(spacing: 0) {
            // Toolbar with refresh button
            HStack {
                Image(systemName: "tablecells")
                    .foregroundStyle(.blue)
                Text(tab.tableName ?? tab.title)
                    .font(.headline)
                
                Spacer()
                
                Button(action: { runQuery() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Data")
                
                if !tab.resultColumns.isEmpty {
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
            
            // Results
            if let error = tab.errorMessage {
                errorBanner(error)
            }
            
            EditableResultsTableView(
                columns: tab.resultColumns,
                rows: Binding(
                    get: { tab.resultRows },
                    set: { newRows in
                        if let index = tabManager.selectedTabIndex {
                            tabManager.tabs[index].resultRows = newRows
                        }
                    }
                ),
                changeManager: changeManager,
                isEditable: tab.isEditable,
                onCommit: { sql in
                    executeCommitSQL(sql)
                }
            )
            .frame(maxHeight: .infinity, alignment: .top)
            
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
            
            EditableResultsTableView(
                columns: tab.resultColumns,
                rows: Binding(
                    get: { tab.resultRows },
                    set: { newRows in
                        if let index = tabManager.selectedTabIndex {
                            tabManager.tabs[index].resultRows = newRows
                        }
                    }
                ),
                changeManager: changeManager,
                isEditable: tab.isEditable,
                onCommit: { sql in
                    executeCommitSQL(sql)
                }
            )
            .frame(maxHeight: .infinity, alignment: .top)
            
            statusBar
        }
        .frame(minHeight: 150)
    }    
    // MARK: - Results Toolbar
    
    private var resultsToolbar: some View {
        HStack {
            Text("Results")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if let tab = currentTab, !tab.resultColumns.isEmpty {
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
            
            Text(connectionState)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            connectionState = "Connected"
            driver.disconnect()
        } catch {
            connectionState = "Failed"
            if let index = tabManager.selectedTabIndex {
                tabManager.tabs[index].errorMessage = error.localizedDescription
            }
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
        
        let sql = tabManager.tabs[index].query
        let conn = connection
        let tabId = tabManager.tabs[index].id
        
        // Detect table name from simple SELECT queries
        let tableName = extractTableName(from: sql)
        let isEditable = tableName != nil
        
        Task {
            do {
                let result = try await executeQueryAsync(sql: sql, connection: conn)
                
                // Find tab by ID (index may have changed)
                if let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) {
                    tabManager.tabs[idx].resultColumns = result.columns
                    tabManager.tabs[idx].resultRows = result.toQueryResultRows()
                    tabManager.tabs[idx].executionTime = result.executionTime
                    tabManager.tabs[idx].isExecuting = false
                    tabManager.tabs[idx].lastExecutedAt = Date()
                    tabManager.tabs[idx].tableName = tableName
                    tabManager.tabs[idx].isEditable = isEditable
                    
                    // Configure change manager for this table
                    changeManager.tableName = tableName ?? ""
                    changeManager.columns = result.columns
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
                }
                
                driver.disconnect()
                
                // Refresh the current query to show updated data
                runQuery()
                
            } catch {
                if let index = tabManager.selectedTabIndex {
                    tabManager.tabs[index].errorMessage = "Commit failed: \(error.localizedDescription)"
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
