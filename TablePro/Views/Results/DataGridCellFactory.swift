//
//  DataGridCellFactory.swift
//  TablePro
//
//  Factory for creating and configuring data grid cells.
//  Extracted from DataGridView coordinator for better maintainability.
//

import AppKit

/// Factory for creating data grid cell views
final class DataGridCellFactory {
    private let cellIdentifier = NSUserInterfaceItemIdentifier("DataCell")
    private let rowNumberCellIdentifier = NSUserInterfaceItemIdentifier("RowNumberCell")

    /// Large dataset threshold - above this, disable expensive visual features
    private let largeDatasetThreshold = 5000

    // MARK: - Row Number Cell

    func makeRowNumberCell(
        tableView: NSTableView,
        row: Int,
        cachedRowCount: Int,
        visualState: RowVisualState
    ) -> NSView {
        let cellViewId = NSUserInterfaceItemIdentifier("RowNumberCellView")
        let cellView: NSTableCellView
        let cell: NSTextField

        if let reused = tableView.makeView(withIdentifier: cellViewId, owner: nil) as? NSTableCellView,
           let textField = reused.textField {
            cellView = reused
            cell = textField
        } else {
            cellView = NSTableCellView()
            cellView.identifier = cellViewId

            cell = NSTextField(labelWithString: "")
            cell.alignment = .right
            cell.font = .monospacedDigitSystemFont(ofSize: DesignConstants.FontSize.medium, weight: .regular)
            cell.textColor = .secondaryLabelColor
            cell.translatesAutoresizingMaskIntoConstraints = false

            cellView.textField = cell
            cellView.addSubview(cell)

            NSLayoutConstraint.activate([
                cell.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                cell.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                cell.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        guard row >= 0 && row < cachedRowCount else {
            cell.stringValue = ""
            return cellView
        }

        cell.stringValue = "\(row + 1)"
        cell.textColor = visualState.isDeleted ? .systemRed.withAlphaComponent(0.5) : .secondaryLabelColor

        return cellView
    }

    // MARK: - Data Cell

    func makeDataCell(
        tableView: NSTableView,
        row: Int,
        columnIndex: Int,
        value: String?,
        visualState: RowVisualState,
        isEditable: Bool,
        isLargeDataset: Bool,
        isFocused: Bool,
        delegate: NSTextFieldDelegate
    ) -> NSView {
        let cellViewId = NSUserInterfaceItemIdentifier("DataCellView")
        let cellView: NSTableCellView
        let cell: NSTextField
        let isNewCell: Bool

        if let reused = tableView.makeView(withIdentifier: cellViewId, owner: nil) as? NSTableCellView,
           let textField = reused.textField {
            cellView = reused
            cell = textField
            isNewCell = false
        } else {
            cellView = NSTableCellView()
            cellView.identifier = cellViewId
            cellView.wantsLayer = true

            cell = CellTextField()
            cell.font = .monospacedSystemFont(ofSize: DesignConstants.FontSize.body, weight: .regular)
            cell.drawsBackground = false
            cell.isBordered = false
            cell.focusRingType = .none
            cell.lineBreakMode = .byTruncatingTail
            cell.maximumNumberOfLines = 1
            cell.cell?.truncatesLastVisibleLine = true
            cell.translatesAutoresizingMaskIntoConstraints = false

            cellView.textField = cell
            cellView.addSubview(cell)

            NSLayoutConstraint.activate([
                cell.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                cell.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                cell.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
            isNewCell = true
        }

        cell.isEditable = isEditable
        cell.delegate = delegate
        cell.identifier = cellIdentifier

        let isDeleted = visualState.isDeleted
        let isInserted = visualState.isInserted
        let isModified = visualState.modifiedColumns.contains(columnIndex)

        // Update text content
        cell.placeholderString = nil

        if value == nil {
            cell.stringValue = ""
            if !isLargeDataset {
                cell.placeholderString = "NULL"
                cell.textColor = .secondaryLabelColor
                if isNewCell || cell.font?.fontDescriptor.symbolicTraits.contains(.italic) != true {
                    cell.font = .monospacedSystemFont(ofSize: DesignConstants.FontSize.body, weight: .regular).withTraits(.italic)
                }
            } else {
                cell.textColor = .secondaryLabelColor
            }
        } else if value == "__DEFAULT__" {
            cell.stringValue = ""
            if !isLargeDataset {
                cell.placeholderString = "DEFAULT"
                cell.textColor = .systemBlue
                cell.font = .monospacedSystemFont(ofSize: DesignConstants.FontSize.body, weight: .medium)
            } else {
                cell.textColor = .systemBlue
            }
        } else if value == "" {
            cell.stringValue = ""
            if !isLargeDataset {
                cell.placeholderString = "Empty"
                cell.textColor = .secondaryLabelColor
                if isNewCell || cell.font?.fontDescriptor.symbolicTraits.contains(.italic) != true {
                    cell.font = .monospacedSystemFont(ofSize: DesignConstants.FontSize.body, weight: .regular).withTraits(.italic)
                }
            } else {
                cell.textColor = .secondaryLabelColor
            }
        } else {
            // Sanitize value: replace newlines with spaces for single-line display
            let sanitizedValue = value?
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            cell.stringValue = sanitizedValue ?? ""
            cell.textColor = .labelColor
            if cell.font?.fontDescriptor.symbolicTraits.contains(.italic) == true ||
               cell.font?.fontDescriptor.symbolicTraits.contains(.bold) == true {
                cell.font = .monospacedSystemFont(ofSize: DesignConstants.FontSize.body, weight: .regular)
            }
        }

        // Update background color
        if isDeleted {
            cellView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
        } else if isInserted {
            cellView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        } else if isModified && !isLargeDataset {
            cellView.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.3).cgColor
        } else {
            cellView.layer?.backgroundColor = nil
        }

        // Focus ring
        if isLargeDataset {
            cellView.layer?.borderWidth = 0
        } else if isFocused {
            cellView.layer?.borderWidth = 2
            cellView.layer?.borderColor = NSColor.selectedControlColor.cgColor
        } else {
            cellView.layer?.borderWidth = 0
        }

        return cellView
    }

    // MARK: - Column Width Calculation

    func calculateColumnWidth(for columnName: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: DesignConstants.FontSize.body, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (columnName as NSString).size(withAttributes: attributes)
        let width = size.width + 48
        return max(width, 30)
    }
}

// MARK: - NSFont Extension

extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
