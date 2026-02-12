//
//  SetPopoverController.swift
//  TablePro
//
//  Checkbox popover for SET column editing (multi-select).
//

import AppKit
import Combine
import SwiftUI

// MARK: - SwiftUI State

private final class SetPopoverState: ObservableObject {
    @Published var selections: [String: Bool]
    let allowedValues: [String]
    var onCommit: ((String?) -> Void)?
    var dismiss: (() -> Void)?

    init(allowedValues: [String], selections: [String: Bool]) {
        self.allowedValues = allowedValues
        self.selections = selections
    }
}

// MARK: - SwiftUI Content View

private struct SetPopoverContentView: View {
    @ObservedObject var state: SetPopoverState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.allowedValues, id: \.self) { value in
                        Toggle(
                            value,
                            isOn: Binding(
                                get: { state.selections[value] ?? false },
                                set: { state.selections[value] = $0 }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, design: .monospaced))
                    }
                }
                .padding(12)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    state.dismiss?()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    commitAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 260)
        .frame(maxHeight: 360)
    }

    private func commitAndDismiss() {
        let selected = state.allowedValues.filter { state.selections[$0] == true }
        let result = selected.isEmpty ? nil : selected.joined(separator: ",")
        state.onCommit?(result)
        state.dismiss?()
    }
}

// MARK: - Controller

/// Manages showing a checkbox popover for editing SET cells (multi-select)
@MainActor
final class SetPopoverController: NSObject, NSPopoverDelegate {
    static let shared = SetPopoverController()

    private var popover: NSPopover?
    private var state: SetPopoverState?
    private var keyMonitor: Any?

    func show(
        relativeTo bounds: NSRect,
        of view: NSView,
        currentValue: String?,
        allowedValues: [String],
        onCommit: @escaping (String?) -> Void
    ) {
        popover?.close()

        // Parse current value to determine checked state
        let currentSet: Set<String>
        if let value = currentValue {
            currentSet = Set(
                value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            )
        } else {
            currentSet = []
        }

        var selections: [String: Bool] = [:]
        for value in allowedValues {
            selections[value] = currentSet.contains(value)
        }

        // Create SwiftUI state and view
        let popoverState = SetPopoverState(
            allowedValues: allowedValues,
            selections: selections
        )
        popoverState.onCommit = onCommit
        self.state = popoverState

        let contentView = SetPopoverContentView(state: popoverState)
        let hostingController = NSHostingController(rootView: contentView)

        let pop = NSPopover()
        pop.contentViewController = hostingController
        pop.behavior = .semitransient
        pop.delegate = self
        pop.show(relativeTo: bounds, of: view, preferredEdge: .maxY)
        popover = pop

        popoverState.dismiss = { [weak self] in
            self?.popover?.close()
        }

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

    // MARK: - Actions

    private func commitSelection() {
        guard let state = state else {
            popover?.close()
            return
        }
        let selected = state.allowedValues.filter { state.selections[$0] == true }
        let result = selected.isEmpty ? nil : selected.joined(separator: ",")
        state.onCommit?(result)
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
        state = nil
        popover = nil
    }
}
