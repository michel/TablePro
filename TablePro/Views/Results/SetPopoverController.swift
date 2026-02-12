//
//  SetPopoverController.swift
//  TablePro
//
//  Checkbox popover for SET column editing (multi-select).
//

import AppKit

/// Manages showing a checkbox popover for editing SET cells (multi-select)
@MainActor
final class SetPopoverController: NSObject, NSPopoverDelegate {
    static let shared = SetPopoverController()

    private var popover: NSPopover?
    private var checkboxes: [NSButton] = []
    private var onCommit: ((String?) -> Void)?
    private var keyMonitor: Any?

    private static let popoverWidth: CGFloat = 260
    private static let popoverMaxHeight: CGFloat = 360
    private static let checkboxHeight: CGFloat = 22
    private static let buttonAreaHeight: CGFloat = 44
    private static let padding: CGFloat = 12

    func show(
        relativeTo bounds: NSRect,
        of view: NSView,
        currentValue: String?,
        allowedValues: [String],
        onCommit: @escaping (String?) -> Void
    ) {
        popover?.close()

        self.onCommit = onCommit

        // Parse current value to determine checked state
        let currentSet: Set<String>
        if let value = currentValue {
            currentSet = Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        } else {
            currentSet = []
        }

        // Build UI
        let contentView = buildContentView(allowedValues: allowedValues, currentSet: currentSet)

        let viewController = NSViewController()
        viewController.view = contentView

        // Calculate height
        let checkboxesHeight = CGFloat(allowedValues.count) * Self.checkboxHeight
        let totalHeight = min(
            Self.padding + checkboxesHeight + Self.buttonAreaHeight,
            Self.popoverMaxHeight
        )

        let pop = NSPopover()
        pop.contentViewController = viewController
        pop.contentSize = NSSize(width: Self.popoverWidth, height: totalHeight)
        pop.behavior = .semitransient
        pop.delegate = self
        pop.show(relativeTo: bounds, of: view, preferredEdge: .maxY)
        popover = pop

        // Keyboard monitor
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover != nil else { return event }
            if event.keyCode == 36 { // Return/Enter
                self.commitSelection()
                return nil
            }
            if event.keyCode == 53 { // Escape
                self.popover?.close()
                return nil
            }
            return event
        }
    }

    // MARK: - UI Building

    private func buildContentView(allowedValues: [String], currentSet: Set<String>) -> NSView {
        let checkboxesHeight = CGFloat(allowedValues.count) * Self.checkboxHeight
        let totalHeight = min(
            Self.padding + checkboxesHeight + Self.buttonAreaHeight,
            Self.popoverMaxHeight
        )

        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth,
            height: totalHeight
        ))

        // Scroll view for checkboxes
        let scrollViewHeight = totalHeight - Self.buttonAreaHeight
        let scrollView = NSScrollView(frame: NSRect(
            x: 0, y: Self.buttonAreaHeight,
            width: Self.popoverWidth,
            height: scrollViewHeight
        ))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        // Document view for checkboxes
        let documentHeight = max(checkboxesHeight + Self.padding, scrollViewHeight)
        let documentView = NSView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth,
            height: documentHeight
        ))

        // Create checkboxes
        checkboxes = []
        for (index, value) in allowedValues.enumerated() {
            let yPosition = documentHeight - Self.padding - CGFloat(index + 1) * Self.checkboxHeight
            let checkbox = NSButton(checkboxWithTitle: value, target: nil, action: nil)
            checkbox.frame = NSRect(
                x: Self.padding,
                y: yPosition,
                width: Self.popoverWidth - Self.padding * 2,
                height: Self.checkboxHeight
            )
            checkbox.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            checkbox.state = currentSet.contains(value) ? .on : .off
            documentView.addSubview(checkbox)
            checkboxes.append(checkbox)
        }

        scrollView.documentView = documentView
        container.addSubview(scrollView)

        // Button area (OK / Cancel)
        let buttonAreaView = NSView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth,
            height: Self.buttonAreaHeight
        ))

        // Separator line
        let separator = NSBox(frame: NSRect(
            x: 0, y: Self.buttonAreaHeight - 1,
            width: Self.popoverWidth, height: 1
        ))
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .minYMargin]
        buttonAreaView.addSubview(separator)

        // OK button
        let okButton = NSButton(title: "OK", target: self, action: #selector(okClicked))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.frame = NSRect(
            x: Self.popoverWidth - 80 - Self.padding,
            y: 8,
            width: 80,
            height: 28
        )
        buttonAreaView.addSubview(okButton)

        // Cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        cancelButton.frame = NSRect(
            x: Self.popoverWidth - 80 - Self.padding - 84,
            y: 8,
            width: 80,
            height: 28
        )
        buttonAreaView.addSubview(cancelButton)

        container.addSubview(buttonAreaView)

        return container
    }

    // MARK: - Actions

    @objc private func okClicked() {
        commitSelection()
    }

    @objc private func cancelClicked() {
        popover?.close()
    }

    private func commitSelection() {
        let selectedValues = checkboxes
            .filter { $0.state == .on }
            .map { $0.title }

        let result = selectedValues.isEmpty ? nil : selectedValues.joined(separator: ",")
        onCommit?(result)
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
        checkboxes = []
        onCommit = nil
        popover = nil
    }
}
