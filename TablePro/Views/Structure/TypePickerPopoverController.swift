//
//  TypePickerPopoverController.swift
//  TablePro
//
//  Searchable type picker popover for structure view column type editing.
//

import AppKit
import Combine
import SwiftUI

// MARK: - SwiftUI State

private final class TypePickerState: ObservableObject {
    @Published var searchText: String = ""

    let databaseType: DatabaseType
    let currentValue: String
    var onCommit: ((String) -> Void)?
    var dismiss: (() -> Void)?

    init(
        databaseType: DatabaseType,
        currentValue: String,
        onCommit: ((String) -> Void)?
    ) {
        self.databaseType = databaseType
        self.currentValue = currentValue
        self.onCommit = onCommit
    }
}

// MARK: - SwiftUI Content View

private struct TypePickerContentView: View {
    @ObservedObject var state: TypePickerState

    private static let rowHeight: CGFloat = 22
    private static let sectionHeaderHeight: CGFloat = 28
    private static let searchAreaHeight: CGFloat = 44
    private static let maxTotalHeight: CGFloat = 360

    private var visibleCategories: [DataTypeCategory] {
        DataTypeCategory.allCases.filter { !filteredTypes(for: $0).isEmpty }
    }

    private func filteredTypes(for category: DataTypeCategory) -> [String] {
        let types = category.types(for: state.databaseType)
        if state.searchText.isEmpty {
            return types
        }
        let query = state.searchText.lowercased()
        return types.filter { $0.lowercased().contains(query) }
    }

    private var totalFilteredCount: Int {
        visibleCategories.reduce(0) { $0 + filteredTypes(for: $1).count }
    }

    private var listHeight: CGFloat {
        let contentHeight = CGFloat(totalFilteredCount) * Self.rowHeight
            + CGFloat(visibleCategories.count) * Self.sectionHeaderHeight
            + 8
        return min(contentHeight, Self.maxTotalHeight - Self.searchAreaHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search or type...", text: $state.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .onSubmit { commitFreeform() }

            Divider()

            List {
                ForEach(visibleCategories, id: \.self) { category in
                    Section(header: Text(category.rawValue)) {
                        ForEach(filteredTypes(for: category), id: \.self) { type in
                            typeRow(type)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { commitType(type) }
                                .listRowInsets(EdgeInsets(
                                    top: 2, leading: 6, bottom: 2, trailing: 6
                                ))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .frame(height: listHeight)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private func typeRow(_ type: String) -> some View {
        if type.caseInsensitiveCompare(state.currentValue) == .orderedSame {
            Text(type)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.accentColor)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(type)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func commitFreeform() {
        let text = state.searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        state.onCommit?(text)
        state.dismiss?()
    }

    private func commitType(_ type: String) {
        state.onCommit?(type)
        state.dismiss?()
    }
}

// MARK: - Controller

/// Manages showing a searchable type picker popover for structure view column type editing
@MainActor
final class TypePickerPopoverController: NSObject, NSPopoverDelegate {
    static let shared = TypePickerPopoverController()

    private var popover: NSPopover?
    private var state: TypePickerState?
    private var keyMonitor: Any?

    func show(
        relativeTo bounds: NSRect,
        of view: NSView,
        databaseType: DatabaseType,
        currentValue: String,
        onCommit: @escaping (String) -> Void
    ) {
        popover?.close()

        // Create state and SwiftUI content
        let popoverState = TypePickerState(
            databaseType: databaseType,
            currentValue: currentValue,
            onCommit: onCommit
        )
        self.state = popoverState

        let contentView = TypePickerContentView(state: popoverState)
        let hostingController = NSHostingController(rootView: contentView)

        // Calculate height to fit content
        let searchAreaHeight: CGFloat = 44
        let maxTotalHeight: CGFloat = 360
        let rowHeight: CGFloat = 22
        let sectionHeaderHeight: CGFloat = 28

        var totalRows = 0
        var sectionCount = 0
        for category in DataTypeCategory.allCases {
            let types = category.types(for: databaseType)
            if !types.isEmpty {
                totalRows += types.count
                sectionCount += 1
            }
        }
        let listHeight = min(
            CGFloat(totalRows) * rowHeight + CGFloat(sectionCount) * sectionHeaderHeight + 8,
            maxTotalHeight - searchAreaHeight
        )
        let totalHeight = searchAreaHeight + listHeight

        let pop = NSPopover()
        pop.contentViewController = hostingController
        pop.contentSize = NSSize(width: 280, height: totalHeight)
        pop.behavior = .semitransient
        pop.delegate = self
        pop.show(relativeTo: bounds, of: view, preferredEdge: .maxY)

        popover = pop

        popoverState.dismiss = { [weak self] in
            self?.popover?.close()
        }

        // Handle Escape to cancel
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover != nil else { return event }
            if event.keyCode == 53 { // Escape
                self.popover?.close()
                return nil
            }
            return event
        }
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
        state = nil
        popover = nil
    }
}
