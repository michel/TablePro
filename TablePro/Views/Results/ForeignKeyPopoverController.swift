//
//  ForeignKeyPopoverController.swift
//  TablePro
//
//  Searchable dropdown popover for foreign key column editing.
//

import AppKit
import os

/// Manages showing a searchable FK value popover for editing foreign key cells
@MainActor
final class ForeignKeyPopoverController: NSObject, NSPopoverDelegate {
    static let shared = ForeignKeyPopoverController()
    private static let logger = Logger(subsystem: "com.TablePro", category: "FKPopover")

    private var popover: NSPopover?
    private var tableView: NSTableView?
    private var searchField: NSSearchField?
    private var onCommit: ((String) -> Void)?
    private var allValues: [(id: String, display: String)] = []
    private var filteredValues: [(id: String, display: String)] = []
    private var currentValue: String?

    private static let maxFetchRows = 1_000
    private static let popoverWidth: CGFloat = 300
    private static let popoverHeight: CGFloat = 280

    func show(
        relativeTo bounds: NSRect,
        of view: NSView,
        currentValue: String?,
        fkInfo: ForeignKeyInfo,
        databaseType: DatabaseType,
        onCommit: @escaping (String) -> Void
    ) {
        popover?.close()

        self.onCommit = onCommit
        self.currentValue = currentValue
        self.allValues = []
        self.filteredValues = []

        // Build the content view
        let contentView = buildContentView()

        let viewController = NSViewController()
        viewController.view = contentView

        let pop = NSPopover()
        pop.contentViewController = viewController
        pop.contentSize = NSSize(width: Self.popoverWidth, height: Self.popoverHeight)
        pop.behavior = .transient
        pop.delegate = self
        pop.show(relativeTo: bounds, of: view, preferredEdge: .maxY)

        popover = pop

        // Fetch FK values asynchronously
        Task {
            await fetchForeignKeyValues(fkInfo: fkInfo, databaseType: databaseType)
        }
    }

    // MARK: - UI Building

    private func buildContentView() -> NSView {
        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth,
            height: Self.popoverHeight
        ))

        // Search field
        let search = NSSearchField(frame: NSRect(
            x: 8, y: Self.popoverHeight - 36,
            width: Self.popoverWidth - 16, height: 28
        ))
        search.placeholderString = "Search..."
        search.font = .systemFont(ofSize: 13)
        search.target = self
        search.action = #selector(searchChanged)
        search.sendsSearchStringImmediately = true
        search.autoresizingMask = [.width]
        container.addSubview(search)
        self.searchField = search

        // Table view in scroll view
        let scrollView = NSScrollView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth,
            height: Self.popoverHeight - 44
        ))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        let table = NSTableView()
        table.style = .plain
        table.headerView = nil
        table.rowHeight = 24
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.usesAlternatingRowBackgroundColors = true
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        scrollView.documentView = table
        container.addSubview(scrollView)
        self.tableView = table

        // Show loading state
        self.filteredValues = []
        table.reloadData()

        return container
    }

    // MARK: - Data Fetching

    private func fetchForeignKeyValues(fkInfo: ForeignKeyInfo, databaseType: DatabaseType) async {
        guard let driver = DatabaseManager.shared.activeDriver else {
            Self.logger.error("No active driver for FK lookup")
            return
        }

        let quotedTable = databaseType.quoteIdentifier(fkInfo.referencedTable)
        let quotedColumn = databaseType.quoteIdentifier(fkInfo.referencedColumn)

        // Try to find a display column (first text-like column that isn't the FK column)
        var displayColumn: String?
        do {
            let columnInfos = try await driver.fetchColumns(table: fkInfo.referencedTable)
            displayColumn = columnInfos.first(where: { col in
                col.name != fkInfo.referencedColumn &&
                !col.isPrimaryKey &&
                isTextLikeType(col.dataType)
            })?.name
        } catch {
            Self.logger.debug("Could not fetch columns for display: \(error.localizedDescription)")
        }

        let query: String
        if let displayCol = displayColumn {
            let quotedDisplay = databaseType.quoteIdentifier(displayCol)
            query = "SELECT \(quotedColumn), \(quotedDisplay) FROM \(quotedTable) ORDER BY \(quotedColumn) LIMIT \(Self.maxFetchRows)"
        } else {
            query = "SELECT DISTINCT \(quotedColumn) FROM \(quotedTable) ORDER BY \(quotedColumn) LIMIT \(Self.maxFetchRows)"
        }

        do {
            let result = try await DatabaseManager.shared.execute(query: query)
            var values: [(id: String, display: String)] = []
            for row in result.rows {
                guard let idVal = row.first ?? nil else { continue }
                let displayVal: String
                if displayColumn != nil, row.count > 1, let second = row[1] {
                    displayVal = "\(idVal) — \(second)"
                } else {
                    displayVal = idVal
                }
                values.append((id: idVal, display: displayVal))
            }
            self.allValues = values
            self.filteredValues = values
            self.tableView?.reloadData()

            // Select current value if it exists
            if let current = currentValue,
               let index = values.firstIndex(where: { $0.id == current }) {
                tableView?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                tableView?.scrollRowToVisible(index)
            }
        } catch {
            Self.logger.error("FK value fetch failed: \(error.localizedDescription)")
        }
    }

    private func isTextLikeType(_ typeString: String) -> Bool {
        let upper = typeString.uppercased()
        return upper.contains("CHAR") || upper.contains("TEXT") || upper.contains("NAME")
    }

    // MARK: - Actions

    @objc private func searchChanged() {
        let query = searchField?.stringValue.lowercased() ?? ""
        if query.isEmpty {
            filteredValues = allValues
        } else {
            filteredValues = allValues.filter { $0.display.lowercased().contains(query) }
        }
        tableView?.reloadData()
    }

    @objc private func rowDoubleClicked() {
        guard let table = tableView else { return }
        let row = table.clickedRow
        guard row >= 0, row < filteredValues.count else { return }

        let selected = filteredValues[row].id
        onCommit?(selected)
        popover?.close()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        cleanup()
    }

    private func cleanup() {
        tableView = nil
        searchField = nil
        onCommit = nil
        allValues = []
        filteredValues = []
        currentValue = nil
        popover = nil
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension ForeignKeyPopoverController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredValues.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredValues.count else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("FKCell")
        let cellView: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cellView = reused
        } else {
            cellView = NSTableCellView()
            cellView.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(textField)
            cellView.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        let value = filteredValues[row]
        cellView.textField?.stringValue = value.display

        // Highlight current value
        if let current = currentValue, value.id == current {
            cellView.textField?.textColor = .controlAccentColor
        } else {
            cellView.textField?.textColor = .labelColor
        }

        return cellView
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Single-click selection commits the value
        guard let table = tableView else { return }
        let row = table.selectedRow
        guard row >= 0, row < filteredValues.count else { return }

        let selected = filteredValues[row].id
        onCommit?(selected)
        popover?.close()
    }
}
