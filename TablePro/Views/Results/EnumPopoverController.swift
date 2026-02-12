//
//  EnumPopoverController.swift
//  TablePro
//
//  Searchable dropdown popover for ENUM column editing.
//

import AppKit
import Combine
import SwiftUI

private let enumNullMarker = "\u{2300} NULL"

// MARK: - SwiftUI State

private class EnumPopoverState: ObservableObject {
    @Published var searchText: String = ""

    let allValues: [String]
    let currentValue: String?
    let isNullable: Bool
    var onCommit: ((String?) -> Void)?
    var dismiss: (() -> Void)?

    init(
        allValues: [String],
        currentValue: String?,
        isNullable: Bool,
        onCommit: ((String?) -> Void)?
    ) {
        self.allValues = allValues
        self.currentValue = currentValue
        self.isNullable = isNullable
        self.onCommit = onCommit
    }
}

// MARK: - SwiftUI Content View

private struct EnumPopoverContentView: View {
    @ObservedObject var state: EnumPopoverState

    private static let rowHeight: CGFloat = 24
    private static let searchAreaHeight: CGFloat = 44
    private static let maxHeight: CGFloat = 320

    private var filteredValues: [String] {
        let query = state.searchText.lowercased()
        if query.isEmpty {
            return state.allValues
        }
        return state.allValues.filter { $0.lowercased().contains(query) }
    }

    private var listHeight: CGFloat {
        let contentHeight = CGFloat(filteredValues.count) * Self.rowHeight
        return min(contentHeight, Self.maxHeight - Self.searchAreaHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search...", text: $state.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            Divider()

            List {
                ForEach(filteredValues, id: \.self) { value in
                    rowLabel(for: value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            commitValue(value)
                        }
                        .listRowInsets(EdgeInsets(
                            top: 2, leading: 6, bottom: 2, trailing: 6
                        ))
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .frame(height: listHeight)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private func rowLabel(for value: String) -> some View {
        if value == enumNullMarker {
            Text(value)
                .font(.system(size: 12, design: .monospaced).italic())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if value == state.currentValue {
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.accentColor)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func commitValue(_ value: String) {
        if value == enumNullMarker {
            state.onCommit?(nil)
        } else {
            state.onCommit?(value)
        }
        state.dismiss?()
    }
}

// MARK: - Controller

/// Manages showing a searchable enum value popover for editing ENUM cells
@MainActor
final class EnumPopoverController: NSObject, NSPopoverDelegate {
    static let shared = EnumPopoverController()

    private var popover: NSPopover?
    private var state: EnumPopoverState?
    private var keyMonitor: Any?

    func show(
        relativeTo bounds: NSRect,
        of view: NSView,
        currentValue: String?,
        allowedValues: [String],
        isNullable: Bool,
        onCommit: @escaping (String?) -> Void
    ) {
        popover?.close()

        // Build value list (NULL first if nullable)
        var values: [String] = []
        if isNullable {
            values.append(enumNullMarker)
        }
        values.append(contentsOf: allowedValues)

        // Create state and SwiftUI content
        let popoverState = EnumPopoverState(
            allValues: values,
            currentValue: currentValue,
            isNullable: isNullable,
            onCommit: onCommit
        )
        self.state = popoverState

        let contentView = EnumPopoverContentView(state: popoverState)
        let hostingController = NSHostingController(rootView: contentView)

        // Calculate height to fit content
        let rowHeight: CGFloat = 24
        let searchAreaHeight: CGFloat = 44
        let maxHeight: CGFloat = 320
        let listHeight = min(CGFloat(values.count) * rowHeight, maxHeight - searchAreaHeight)
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
