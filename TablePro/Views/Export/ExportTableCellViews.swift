//
//  ExportTableCellViews.swift
//  TablePro
//
//  Custom NSTableCellView implementations for export table outline view.
//  Provides high-performance cell reuse for database and table rows.
//

import AppKit
import SwiftUI

// MARK: - Database Row Cell

/// Cell view for database rows with tristate checkbox and name
final class DatabaseRowCellView: NSTableCellView {

    private let checkbox: NSButton
    private let iconView: NSImageView
    private let nameLabel: NSTextField
    private let spacerView: NSView
    private var spacerWidthConstraint: NSLayoutConstraint!

    var checkboxAction: ((NSButton) -> Void)?

    override init(frame frameRect: NSRect) {
        // Create checkbox
        checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.allowsMixedState = true
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        // Create icon
        iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "cylinder", accessibilityDescription: "Database")
        iconView.contentTintColor = .systemBlue
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Create name label
        nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // Create spacer for SQL format alignment
        spacerView = NSView()
        spacerView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: frameRect)

        addSubview(checkbox)
        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(spacerView)

        // Create spacer width constraint (will be updated based on format)
        spacerWidthConstraint = spacerView.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            // Checkbox
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 16),

            // Icon
            iconView.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 3),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            // Name
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 3),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: spacerView.leadingAnchor, constant: -2),

            // Spacer (for SQL format alignment)
            spacerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            spacerWidthConstraint,
            spacerView.heightAnchor.constraint(equalToConstant: 1)
        ])

        checkbox.target = self
        checkbox.action = #selector(checkboxToggled(_:))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        checkboxAction?(sender)
    }

    func configure(database: ExportDatabaseItem, action: @escaping (NSButton) -> Void) {
        nameLabel.stringValue = database.name
        checkboxAction = action

        // Calculate tristate based on table selection
        let selectedCount = database.tables.filter(\.isSelected).count
        if selectedCount == 0 {
            checkbox.state = .off
        } else if selectedCount == database.tables.count {
            checkbox.state = .on
        } else {
            checkbox.state = .mixed
        }

        // No spacer needed - SQL checkboxes are in separate columns now
        spacerWidthConstraint.constant = 0

        checkbox.setAccessibilityLabel("Select database \(database.name)")
    }
}

// MARK: - Table Row Cell

/// Cell view for table rows with selection checkbox, name, and optional SQL options
final class TableRowCellView: NSTableCellView {

    private let selectionCheckbox: NSButton
    private let iconView: NSImageView
    private let nameLabel: NSTextField

    var selectionAction: ((NSButton) -> Void)?

    override init(frame frameRect: NSRect) {
        // Create selection checkbox
        selectionCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        selectionCheckbox.translatesAutoresizingMaskIntoConstraints = false

        // Create icon
        iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: "Table")
        iconView.contentTintColor = .systemGray
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Create name label
        nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: frameRect)

        addSubview(selectionCheckbox)
        addSubview(iconView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            // Selection checkbox (NSOutlineView handles indentation)
            selectionCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            selectionCheckbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionCheckbox.widthAnchor.constraint(equalToConstant: 16),

            // Icon
            iconView.leadingAnchor.constraint(equalTo: selectionCheckbox.trailingAnchor, constant: 3),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            // Name
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 3),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
        ])

        selectionCheckbox.target = self
        selectionCheckbox.action = #selector(selectionToggled(_:))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func selectionToggled(_ sender: NSButton) {
        selectionAction?(sender)
    }

    func configure(table: ExportTableItem, selectionAction: @escaping (NSButton) -> Void) {
        nameLabel.stringValue = table.name
        selectionCheckbox.state = table.isSelected ? .on : .off
        self.selectionAction = selectionAction
        selectionCheckbox.setAccessibilityLabel("Select table \(table.name)")
    }
}

// MARK: - SQL Option Cell

/// Cell view for SQL option columns (Structure, Drop, Data)
final class SQLOptionCellView: NSTableCellView {
    private let checkbox: NSButton

    var checkboxAction: ((NSButton) -> Void)?

    override init(frame frameRect: NSRect) {
        checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: frameRect)

        addSubview(checkbox)

        NSLayoutConstraint.activate([
            checkbox.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 16),
        ])

        checkbox.target = self
        checkbox.action = #selector(checkboxToggled(_:))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        checkboxAction?(sender)
    }

    func configure(isChecked: Bool, isEnabled: Bool, action: @escaping (NSButton) -> Void) {
        checkbox.state = isChecked ? .on : .off
        checkbox.isEnabled = isEnabled
        checkbox.alphaValue = isEnabled ? 1.0 : 0.4
        checkboxAction = action
    }
}
