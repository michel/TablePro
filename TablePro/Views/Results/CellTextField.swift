//
//  CellTextField.swift
//  TablePro
//
//  Custom text field that delegates context menu to row view.
//  Extracted from DataGridView for better maintainability.
//

import AppKit

/// NSTextField subclass that shows row context menu instead of text editing menu
final class CellTextField: NSTextField {

    override class var cellClass: AnyClass? {
        get { CellTextFieldCell.self }
        set { }
    }

    /// Override right mouse down to end editing and show row context menu
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)

        var view: NSView? = self
        while let parent = view?.superview {
            if let rowView = parent as? TableRowViewWithMenu {
                if let menu = rowView.menu(for: event) {
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                }
                return
            }
            view = parent
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(nil)

        var view: NSView? = self
        while let parent = view?.superview {
            if let rowView = parent as? TableRowViewWithMenu {
                return rowView.menu(for: event)
            }
            view = parent
        }

        return nil
    }
}

/// Custom text field cell that provides a field editor with custom context menu behavior
final class CellTextFieldCell: NSTextFieldCell {

    private class CellFieldEditor: NSTextView {

        override func rightMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(nil)

            var view: NSView? = self
            while let parent = view?.superview {
                if let cellTextField = parent as? CellTextField {
                    cellTextField.rightMouseDown(with: event)
                    return
                }
                view = parent
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            return nil
        }
    }

    private var customFieldEditor: CellFieldEditor?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if customFieldEditor == nil {
            customFieldEditor = CellFieldEditor()
            customFieldEditor?.isFieldEditor = true
        }
        return customFieldEditor
    }
}
