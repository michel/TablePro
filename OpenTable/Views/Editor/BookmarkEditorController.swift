//
//  BookmarkEditorController.swift
//  OpenTable
//
//  Native AppKit modal sheet for creating/editing bookmarks
//

import AppKit

/// Native AppKit controller for bookmark editor using standard macOS form patterns
final class BookmarkEditorController: NSViewController {

    // MARK: - Properties

    private var bookmark: QueryBookmark?
    private let query: String
    private let connectionId: UUID?
    private let isEditing: Bool

    var onSave: ((QueryBookmark) -> Void)?

    // MARK: - UI Components

    private var nameField: NSTextField!
    private var queryTextView: NSTextView!
    private var tagsField: NSTextField!
    private var notesTextView: NSTextView!

    // MARK: - Initialization

    init(bookmark: QueryBookmark? = nil, query: String, connectionId: UUID?) {
        self.bookmark = bookmark
        self.query = query
        self.connectionId = connectionId
        self.isEditing = bookmark != nil
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func loadView() {
        // Create main container
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 380))
        contentView.translatesAutoresizingMaskIntoConstraints = false

        // Build form using NSGridView (native macOS form layout)
        let gridView = buildFormGrid()

        // Buttons
        let buttonStack = buildButtonStack()

        contentView.addSubview(gridView)
        contentView.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            gridView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            gridView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            buttonStack.topAnchor.constraint(equalTo: gridView.bottomAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        self.view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isEditing ? "Edit Bookmark" : "New Bookmark"
        populateFields()
        preferredContentSize = NSSize(width: 450, height: 400)
        
        // Add accessibility identifiers
        nameField.setAccessibilityIdentifier("bookmarkNameField")
        tagsField.setAccessibilityIdentifier("bookmarkTagsField")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nameField)
    }

    // MARK: - Build UI

    private func buildFormGrid() -> NSGridView {
        // Name row
        let nameLabel = NSTextField(labelWithString: "Name:")
        nameLabel.alignment = .right
        nameField = NSTextField()
        nameField.placeholderString = "Bookmark name"

        // Query row
        let queryLabel = NSTextField(labelWithString: "Query:")
        queryLabel.alignment = .right
        let queryScrollView = buildQueryScrollView()

        // Tags row
        let tagsLabel = NSTextField(labelWithString: "Tags:")
        tagsLabel.alignment = .right
        tagsField = NSTextField()
        tagsField.placeholderString = "Optional, comma-separated"

        // Notes row
        let notesLabel = NSTextField(labelWithString: "Notes:")
        notesLabel.alignment = .right
        let notesScrollView = buildNotesScrollView()

        // Create grid
        let gridView = NSGridView(views: [
            [nameLabel, nameField],
            [queryLabel, queryScrollView],
            [tagsLabel, tagsField],
            [notesLabel, notesScrollView]
        ])

        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.columnSpacing = 10
        gridView.rowSpacing = 14

        // Configure column widths (slightly wider for label column)
        gridView.column(at: 0).width = 65
        gridView.column(at: 0).xPlacement = .trailing

        // Configure row alignments
        gridView.row(at: 0).topPadding = 0
        gridView.row(at: 1).topPadding = 6
        gridView.row(at: 2).topPadding = 6
        gridView.row(at: 3).topPadding = 6

        // Align labels to top for multi-line fields
        gridView.cell(atColumnIndex: 0, rowIndex: 1).yPlacement = .top
        gridView.cell(atColumnIndex: 0, rowIndex: 3).yPlacement = .top

        // Set heights for scroll views with better proportions
        queryScrollView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        notesScrollView.heightAnchor.constraint(equalToConstant: 70).isActive = true

        return gridView
    }

    private func buildQueryScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        queryTextView = NSTextView()
        queryTextView.isEditable = false
        queryTextView.isSelectable = true
        queryTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        queryTextView.string = query
        queryTextView.textContainerInset = NSSize(width: 6, height: 6)
        queryTextView.isVerticallyResizable = true
        queryTextView.isHorizontallyResizable = false
        queryTextView.autoresizingMask = [.width]
        queryTextView.textContainer?.widthTracksTextView = true
        queryTextView.backgroundColor = NSColor.controlBackgroundColor
        queryTextView.textColor = .secondaryLabelColor

        scrollView.documentView = queryTextView

        return scrollView
    }

    private func buildNotesScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        notesTextView = NSTextView()
        notesTextView.isRichText = false
        notesTextView.font = .systemFont(ofSize: 13)
        notesTextView.textContainerInset = NSSize(width: 6, height: 6)
        notesTextView.isVerticallyResizable = true
        notesTextView.isHorizontallyResizable = false
        notesTextView.autoresizingMask = [.width]
        notesTextView.textContainer?.widthTracksTextView = true

        scrollView.documentView = notesTextView

        return scrollView
    }

    private func buildButtonStack() -> NSStackView {
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let saveButton = NSButton(title: isEditing ? "Save" : "Save Bookmark", target: self, action: #selector(saveAction))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let stackView = NSStackView(views: [cancelButton, saveButton])
        stackView.orientation = .horizontal
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        return stackView
    }

    // MARK: - Data

    private func populateFields() {
        if let bookmark = bookmark {
            nameField.stringValue = bookmark.name
            tagsField.stringValue = bookmark.formattedTags
            notesTextView.string = bookmark.notes ?? ""
        }
    }

    // MARK: - Actions

    @objc private func saveAction() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Name Required"
            alert.informativeText = "Please enter a name for this bookmark."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: view.window!)
            return
        }

        let tags = QueryBookmark.parseTags(tagsField.stringValue)
        let notes = notesTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        let savedBookmark: QueryBookmark
        if let existing = bookmark {
            savedBookmark = QueryBookmark(
                id: existing.id,
                name: name,
                query: query,
                connectionId: connectionId,
                tags: tags,
                createdAt: existing.createdAt,
                lastUsedAt: existing.lastUsedAt,
                notes: notes.isEmpty ? nil : notes
            )
        } else {
            savedBookmark = QueryBookmark(
                name: name,
                query: query,
                connectionId: connectionId,
                tags: tags,
                notes: notes.isEmpty ? nil : notes
            )
        }

        onSave?(savedBookmark)
        dismiss(nil)
    }

    @objc private func cancelAction() {
        dismiss(nil)
    }
}
