//
//  SQLCompletionWindowController.swift
//  OpenTable
//
//  Popup window for SQL autocomplete suggestions
//

import AppKit
import SwiftUI

// MARK: - Completion Window Controller

/// Controller for the autocomplete popup window
final class SQLCompletionWindowController: NSObject {
    
    // MARK: - Properties
    
    private var window: NSPanel?
    private var tableView: NSTableView?
    private var scrollView: NSScrollView?
    
    private var items: [SQLCompletionItem] = []
    private var selectedIndex: Int = 0
    
    /// Callback when an item is selected
    var onSelect: ((SQLCompletionItem) -> Void)?
    
    /// Callback when completion is dismissed
    var onDismiss: (() -> Void)?
    
    /// Whether the window is currently visible
    var isVisible: Bool {
        window?.isVisible ?? false
    }
    
    // MARK: - Window Configuration
    
    private let windowWidth: CGFloat = 350
    private let rowHeight: CGFloat = 24
    private let maxVisibleRows: Int = 10
    
    // MARK: - Public API
    
    /// Show completions at the specified screen position
    func showCompletions(
        _ items: [SQLCompletionItem],
        at position: NSPoint,
        relativeTo parentWindow: NSWindow?
    ) {
        guard !items.isEmpty else {
            dismiss()
            return
        }
        
        self.items = items
        self.selectedIndex = 0
        
        // Create or update window
        if window == nil {
            createWindow()
        }
        
        // Update table data
        tableView?.reloadData()
        tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        
        // Calculate window height
        let visibleRows = min(items.count, maxVisibleRows)
        let height = CGFloat(visibleRows) * rowHeight + 4
        
        // Position window
        var windowOrigin = position
        windowOrigin.y -= height  // Position below cursor
        
        // Ensure window stays on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            
            if windowOrigin.x + windowWidth > screenFrame.maxX {
                windowOrigin.x = screenFrame.maxX - windowWidth - 10
            }
            if windowOrigin.y < screenFrame.minY {
                windowOrigin.y = position.y + 20  // Position above cursor instead
            }
        }
        
        window?.setFrame(NSRect(x: windowOrigin.x, y: windowOrigin.y, width: windowWidth, height: height), display: true)
        
        // Show window
        if let parent = parentWindow {
            parent.addChildWindow(window!, ordered: .above)
        }
        window?.orderFront(nil)
    }
    
    /// Update completions without repositioning
    func updateCompletions(_ items: [SQLCompletionItem]) {
        guard !items.isEmpty else {
            dismiss()
            return
        }
        
        self.items = items
        self.selectedIndex = min(selectedIndex, items.count - 1)
        
        tableView?.reloadData()
        tableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        
        // Update height
        let visibleRows = min(items.count, maxVisibleRows)
        let height = CGFloat(visibleRows) * rowHeight + 4
        
        if var frame = window?.frame {
            let oldY = frame.origin.y + frame.height
            frame.size.height = height
            frame.origin.y = oldY - height
            window?.setFrame(frame, display: true)
        }
    }
    
    /// Dismiss the completion window
    func dismiss() {
        window?.parent?.removeChildWindow(window!)
        window?.orderOut(nil)
        onDismiss?()
    }
    
    // MARK: - Keyboard Navigation
    
    /// Handle key event, returns true if handled
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        
        switch event.keyCode {
        case 125: // Down arrow
            selectNext()
            return true
            
        case 126: // Up arrow
            selectPrevious()
            return true
            
        case 36: // Return
            confirmSelection()
            return true
            
        case 53: // Escape
            dismiss()
            return true
            
        case 48: // Tab
            confirmSelection()
            return true
            
        default:
            return false
        }
    }
    
    /// Move selection down
    func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
        tableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView?.scrollRowToVisible(selectedIndex)
    }
    
    /// Move selection up
    func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
        tableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView?.scrollRowToVisible(selectedIndex)
    }
    
    /// Confirm current selection
    func confirmSelection() {
        guard selectedIndex < items.count else { return }
        let item = items[selectedIndex]
        dismiss()
        onSelect?(item)
    }
    
    // MARK: - Window Creation
    
    private func createWindow() {
        // Create panel (non-activating)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = NSColor.controlBackgroundColor
        panel.isOpaque = false
        
        // Create scroll view
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.controlBackgroundColor
        
        // Create table view
        let table = NSTableView()
        table.style = .plain
        table.headerView = nil
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.backgroundColor = NSColor.controlBackgroundColor
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.delegate = self
        table.dataSource = self
        table.doubleAction = #selector(tableDoubleClicked)
        table.target = self
        
        // Add single column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion"))
        column.width = windowWidth - 20
        table.addTableColumn(column)
        
        scroll.documentView = table
        panel.contentView = scroll
        
        // Add visual polish: rounded corners, border, shadow
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 8
        panel.contentView?.layer?.masksToBounds = true
        panel.contentView?.layer?.borderWidth = 1
        panel.contentView?.layer?.borderColor = NSColor.separatorColor.cgColor
        
        // Enhanced shadow
        panel.hasShadow = true
        if let shadowLayer = panel.contentView?.superview?.layer {
            shadowLayer.shadowColor = NSColor.black.cgColor
            shadowLayer.shadowOpacity = 0.15
            shadowLayer.shadowOffset = CGSize(width: 0, height: -2)
            shadowLayer.shadowRadius = 8
        }
        
        self.window = panel
        self.tableView = table
        self.scrollView = scroll
    }
    
    @objc private func tableDoubleClicked() {
        confirmSelection()
    }
}

// MARK: - NSTableViewDelegate & DataSource

extension SQLCompletionWindowController: NSTableViewDelegate, NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]
        
        // Reuse or create cell view
        let cellId = NSUserInterfaceItemIdentifier("CompletionCell")
        var cellView = tableView.makeView(withIdentifier: cellId, owner: nil) as? CompletionCellView
        
        if cellView == nil {
            cellView = CompletionCellView()
            cellView?.identifier = cellId
        }
        
        cellView?.configure(with: item)
        return cellView
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if let table = notification.object as? NSTableView {
            selectedIndex = table.selectedRow >= 0 ? table.selectedRow : 0
        }
    }
}

// MARK: - Completion Cell View

private final class CompletionCellView: NSTableCellView {
    
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        
        // Label
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        labelField.lineBreakMode = .byTruncatingTail
        labelField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(labelField)
        
        // Detail (type info)
        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        detailField.alignment = .right
        detailField.lineBreakMode = .byTruncatingTail
        detailField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        addSubview(detailField)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            labelField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            detailField.leadingAnchor.constraint(greaterThanOrEqualTo: labelField.trailingAnchor, constant: 8),
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detailField.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailField.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
        ])
    }
    
    func configure(with item: SQLCompletionItem) {
        // Icon
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        if let image = NSImage(systemSymbolName: item.kind.iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            iconView.image = image
            iconView.contentTintColor = item.kind.iconColor
        }
        
        // Label
        labelField.stringValue = item.label
        
        // Detail
        detailField.stringValue = item.detail ?? ""
    }
}
