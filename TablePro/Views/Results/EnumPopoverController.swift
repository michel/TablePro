//
//  EnumPopoverController.swift
//  TablePro
//
//  Searchable dropdown popover for ENUM column editing.
//

import AppKit

/// Manages showing a searchable enum value popover for editing ENUM cells
@MainActor
final class EnumPopoverController: NSObject, NSPopoverDelegate {
    static let shared = EnumPopoverController()

    private var popover: NSPopover?
    private var tableView: NSTableView?
    private var searchField: NSSearchField?
    private var onCommit: ((String?) -> Void)?
    private var allValues: [String] = []
    private var filteredValues: [String] = []
    private var currentValue: String?
    private var isNullable: Bool = false
    private var keyMonitor: Any?

    private static let nullMarker = "\u{2300} NULL"
    private static let popoverWidth: CGFloat = 280
    private static let popoverMaxHeight: CGFloat = 320
    private static let searchAreaHeight: CGFloat = 44
    private static let rowHeight: CGFloat = 24

    func show(
        relativeTo bounds: NSRect,
        of view: NSView,
        currentValue: String?,
        allowedValues: [String],
        isNullable: Bool,
        onCommit: @escaping (String?) -> Void
    ) {
        popover?.close()

        self.onCommit = onCommit
        self.currentValue = currentValue
        self.isNullable = isNullable

        // Build value list (NULL first if nullable)
        var values: [String] = []
        if isNullable {
            values.append(Self.nullMarker)
        }
        values.append(contentsOf: allowedValues)
        self.allValues = values
        self.filteredValues = values

        // Build the content view
        let contentView = buildContentView()

        let viewController = NSViewController()
        viewController.view = contentView

        let pop = NSPopover()
        pop.contentViewController = viewController
        pop.contentSize = NSSize(width: Self.popoverWidth, height: Self.popoverMaxHeight)
        pop.behavior = .semitransient
        pop.delegate = self
        pop.show(relativeTo: bounds, of: view, preferredEdge: .maxY)

        popover = pop

        // Handle Enter key to commit selected row, Escape to cancel
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover != nil else { return event }
            if event.keyCode == 36 { // Return/Enter
                self.commitSelectedRow()
                return nil
            }
            if event.keyCode == 53 { // Escape
                self.popover?.close()
                return nil
            }
            return event
        }

        // Resize to fit content and select current value
        resizeToFit(rowCount: values.count)
        selectCurrentValue()
    }

    // MARK: - UI Building

    private func buildContentView() -> NSView {
        let height = Self.popoverMaxHeight
        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth,
            height: height
        ))

        // Search field
        let search = NSSearchField(frame: NSRect(
            x: 8, y: height - 36,
            width: Self.popoverWidth - 16, height: 28
        ))
        search.placeholderString = "Search..."
        search.font = .systemFont(ofSize: 13)
        search.target = self
        search.action = #selector(searchChanged)
        search.sendsSearchStringImmediately = true
        search.autoresizingMask = [.width, .minYMargin]
        container.addSubview(search)
        self.searchField = search

        // Table view in scroll view
        let scrollView = NSScrollView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth,
            height: height - Self.searchAreaHeight
        ))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        let table = NSTableView()
        table.style = .plain
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.usesAlternatingRowBackgroundColors = true
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        column.title = ""
        column.width = Self.popoverWidth
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.sizeLastColumnToFit()

        scrollView.documentView = table
        container.addSubview(scrollView)
        self.tableView = table

        return container
    }

    // MARK: - Helpers

    private func resizeToFit(rowCount: Int) {
        let contentHeight = CGFloat(rowCount) * Self.rowHeight
        let totalHeight = min(Self.searchAreaHeight + contentHeight, Self.popoverMaxHeight)
        popover?.contentSize = NSSize(width: Self.popoverWidth, height: totalHeight)
    }

    private func selectCurrentValue() {
        guard let current = currentValue else {
            // If current value is nil and nullable, select NULL row
            if isNullable, let index = filteredValues.firstIndex(of: Self.nullMarker) {
                tableView?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                tableView?.scrollRowToVisible(index)
            }
            return
        }
        if let index = filteredValues.firstIndex(of: current) {
            tableView?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView?.scrollRowToVisible(index)
        }
    }

    // MARK: - Actions

    @objc private func searchChanged() {
        let query = searchField?.stringValue.lowercased() ?? ""
        if query.isEmpty {
            filteredValues = allValues
        } else {
            filteredValues = allValues.filter { $0.lowercased().contains(query) }
        }
        tableView?.reloadData()
    }

    @objc private func rowDoubleClicked() {
        commitSelectedRow()
    }

    private func commitSelectedRow() {
        guard let table = tableView else { return }
        let row = table.selectedRow
        guard row >= 0, row < filteredValues.count else { return }

        let selected = filteredValues[row]
        if selected == Self.nullMarker {
            onCommit?(nil)
        } else {
            onCommit?(selected)
        }
        popover?.close()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        cleanup()
    }

    private func cleanup() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        tableView = nil
        searchField = nil
        onCommit = nil
        allValues = []
        filteredValues = []
        currentValue = nil
        isNullable = false
        popover = nil
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension EnumPopoverController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredValues.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredValues.count else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("EnumCell")
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
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])
        }

        let value = filteredValues[row]
        cellView.textField?.stringValue = value

        if value == Self.nullMarker {
            // NULL option: italic, secondary color
            cellView.textField?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).withTraits(.italicFontMask)
            cellView.textField?.textColor = .secondaryLabelColor
        } else if value == currentValue {
            // Current value: accent color
            cellView.textField?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            cellView.textField?.textColor = .controlAccentColor
        } else {
            cellView.textField?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            cellView.textField?.textColor = .labelColor
        }

        return cellView
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Single-click only highlights; double-click or Enter commits
    }
}

// MARK: - NSFont Italic Helper

private extension NSFont {
    func withTraits(_ traits: NSFontTraitMask) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits(rawValue: UInt32(traits.rawValue)))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
