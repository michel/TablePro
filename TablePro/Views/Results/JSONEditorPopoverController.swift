//
//  JSONEditorPopoverController.swift
//  TablePro
//
//  Popover editor for JSON/JSONB column values with formatting and validation.
//

import AppKit
import os

/// Manages showing a JSON editor popover for editing JSON/JSONB cells
@MainActor
final class JSONEditorPopoverController: NSObject, NSPopoverDelegate {
    static let shared = JSONEditorPopoverController()
    private static let logger = Logger(subsystem: "com.TablePro", category: "JSONEditor")

    private var popover: NSPopover?
    private var textView: NSTextView?
    private var onCommit: ((String) -> Void)?
    private var originalValue: String?
    private var validationLabel: NSTextField?

    private static let popoverWidth: CGFloat = 420
    private static let popoverHeight: CGFloat = 340

    func show(
        relativeTo bounds: NSRect,
        of view: NSView,
        value: String?,
        onCommit: @escaping (String) -> Void
    ) {
        popover?.close()

        self.onCommit = onCommit
        self.originalValue = value

        let contentView = buildContentView(value: value)

        let viewController = NSViewController()
        viewController.view = contentView

        let pop = NSPopover()
        pop.contentViewController = viewController
        pop.contentSize = NSSize(width: Self.popoverWidth, height: Self.popoverHeight)
        pop.behavior = .semitransient
        pop.delegate = self
        pop.show(relativeTo: bounds, of: view, preferredEdge: .maxY)

        popover = pop

        // Focus the text view
        DispatchQueue.main.async { [weak self] in
            self?.textView?.window?.makeFirstResponder(self?.textView)
        }
    }

    // MARK: - UI Building

    private func buildContentView(value: String?) -> NSView {
        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth,
            height: Self.popoverHeight
        ))

        // Toolbar: Format + Validate buttons
        let toolbarHeight: CGFloat = 32
        let toolbar = NSView(frame: NSRect(
            x: 0, y: Self.popoverHeight - toolbarHeight,
            width: Self.popoverWidth, height: toolbarHeight
        ))
        toolbar.autoresizingMask = [.width]

        let formatButton = NSButton(title: "Format", target: self, action: #selector(formatJSON))
        formatButton.bezelStyle = .accessoryBarAction
        formatButton.font = .systemFont(ofSize: 12)
        formatButton.frame = NSRect(x: 8, y: 4, width: 70, height: 24)
        toolbar.addSubview(formatButton)

        let compactButton = NSButton(title: "Compact", target: self, action: #selector(compactJSON))
        compactButton.bezelStyle = .accessoryBarAction
        compactButton.font = .systemFont(ofSize: 12)
        compactButton.frame = NSRect(x: 82, y: 4, width: 70, height: 24)
        toolbar.addSubview(compactButton)

        let validation = NSTextField(labelWithString: "")
        validation.font = .systemFont(ofSize: 11)
        validation.textColor = .secondaryLabelColor
        validation.alignment = .right
        validation.frame = NSRect(x: 160, y: 6, width: Self.popoverWidth - 168, height: 20)
        validation.autoresizingMask = [.width]
        toolbar.addSubview(validation)
        self.validationLabel = validation

        container.addSubview(toolbar)

        // Bottom bar: Cancel + Save buttons
        let bottomHeight: CGFloat = 36
        let bottomBar = NSView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth, height: bottomHeight
        ))
        bottomBar.autoresizingMask = [.width]

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelEditing))
        cancelButton.bezelStyle = .rounded
        cancelButton.font = .systemFont(ofSize: 13)
        cancelButton.frame = NSRect(x: Self.popoverWidth - 164, y: 6, width: 72, height: 24)
        cancelButton.autoresizingMask = [.minXMargin]
        bottomBar.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveJSON))
        saveButton.bezelStyle = .rounded
        saveButton.font = .systemFont(ofSize: 13)
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: Self.popoverWidth - 84, y: 6, width: 72, height: 24)
        saveButton.autoresizingMask = [.minXMargin]
        bottomBar.addSubview(saveButton)

        container.addSubview(bottomBar)

        // Text view in scroll view
        let textAreaY = bottomHeight
        let textAreaHeight = Self.popoverHeight - toolbarHeight - bottomHeight

        let scrollView = NSScrollView(frame: NSRect(
            x: 0, y: textAreaY,
            width: Self.popoverWidth, height: textAreaHeight
        ))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: NSRect(
            x: 0, y: 0,
            width: Self.popoverWidth, height: textAreaHeight
        ))
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isRichText = false
        textView.usesFindPanel = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self

        // Set initial value (try to pretty-print)
        let displayValue = prettyPrint(value) ?? value ?? ""
        textView.string = displayValue

        scrollView.documentView = textView
        container.addSubview(scrollView)
        self.textView = textView

        // Initial validation
        validateJSON(displayValue)

        return container
    }

    // MARK: - JSON Operations

    private func prettyPrint(_ jsonString: String?) -> String? {
        guard let data = jsonString?.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: jsonObject,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }

    private func compact(_ jsonString: String?) -> String? {
        guard let data = jsonString?.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let compactData = try? JSONSerialization.data(
                  withJSONObject: jsonObject,
                  options: [.withoutEscapingSlashes]
              ),
              let compactString = String(data: compactData, encoding: .utf8) else {
            return nil
        }
        return compactString
    }

    private func validateJSON(_ text: String) {
        if text.isEmpty {
            validationLabel?.stringValue = ""
            validationLabel?.textColor = .secondaryLabelColor
            return
        }

        guard let data = text.data(using: .utf8) else {
            validationLabel?.stringValue = "Invalid encoding"
            validationLabel?.textColor = .systemRed
            return
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data)
            validationLabel?.stringValue = "Valid JSON"
            validationLabel?.textColor = .systemGreen
        } catch {
            let nsError = error as NSError
            let description = nsError.localizedDescription
            // Truncate long error messages
            let shortDesc = description.count > 40
                ? String(description.prefix(40)) + "..."
                : description
            validationLabel?.stringValue = shortDesc
            validationLabel?.textColor = .systemRed
        }
    }

    // MARK: - Actions

    @objc private func formatJSON() {
        guard let tv = textView else { return }
        if let formatted = prettyPrint(tv.string) {
            tv.string = formatted
            validateJSON(formatted)
        }
    }

    @objc private func compactJSON() {
        guard let tv = textView else { return }
        if let compacted = compact(tv.string) {
            tv.string = compacted
            validateJSON(compacted)
        }
    }

    @objc private func saveJSON() {
        guard let tv = textView else { return }
        let newValue = tv.string

        // Validate before saving
        if !newValue.isEmpty {
            guard let data = newValue.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                // Show validation error but don't prevent save
                let alert = NSAlert()
                alert.messageText = "Invalid JSON"
                alert.informativeText = "The text is not valid JSON. Save anyway?"
                alert.addButton(withTitle: "Save Anyway")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning

                guard let window = tv.window else { return }
                alert.beginSheetModal(for: window) { [weak self] response in
                    if response == .alertFirstButtonReturn {
                        self?.commitAndClose(newValue)
                    }
                }
                return
            }
        }

        commitAndClose(newValue)
    }

    @objc private func cancelEditing() {
        popover?.close()
    }

    private func commitAndClose(_ value: String) {
        // Compact the JSON before saving (send minified to database)
        let saveValue = compact(value) ?? value
        if saveValue != originalValue {
            onCommit?(saveValue)
        }
        popover?.close()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        cleanup()
    }

    private func cleanup() {
        textView = nil
        validationLabel = nil
        onCommit = nil
        originalValue = nil
        popover = nil
    }
}

// MARK: - NSTextViewDelegate

extension JSONEditorPopoverController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = textView else { return }
        validateJSON(tv.string)
    }
}
