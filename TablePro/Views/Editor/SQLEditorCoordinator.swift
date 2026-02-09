//
//  SQLEditorCoordinator.swift
//  TablePro
//
//  TextViewCoordinator for the CodeEditSourceEditor-based SQL editor.
//  Handles find panel workarounds only — key bindings are handled by
//  SwiftUI .keyboardShortcut modifiers on QueryEditorView toolbar buttons.
//

import AppKit
import CodeEditSourceEditor

/// Coordinator for the SQL editor — manages find panel workarounds
@MainActor
final class SQLEditorCoordinator: TextViewCoordinator {
    // MARK: - Properties

    weak var controller: TextViewController?

    /// Whether the editor text view is currently the first responder.
    /// Used to guard cursor propagation — when the find panel highlights
    /// a match it changes the selection programmatically, and propagating
    /// that to SwiftUI triggers a re-render that disrupts the find panel's
    /// @FocusState.
    var isEditorFirstResponder: Bool {
        guard let textView = controller?.textView else { return false }
        return textView.window?.firstResponder === textView
    }

    // MARK: - TextViewCoordinator

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller

        // Deferred to next run loop because prepareCoordinator runs during
        // TextViewController.init, before the view hierarchy is fully loaded.
        DispatchQueue.main.async { [weak self] in
            guard self != nil else { return }
            self?.fixFindPanelHitTesting(controller: controller)
        }
    }

    func destroy() {}

    // MARK: - CodeEditSourceEditor Workarounds

    /// Reorder FindViewController's subviews so the find panel is on top for hit testing.
    ///
    /// **Why this is needed:**
    /// CodeEditSourceEditor's FindViewController adds its find panel (an NSHostingView)
    /// before the child scroll view. AppKit hit-tests subviews in reverse order (last
    /// subview first), so the scroll view intercepts clicks meant for the find panel's
    /// buttons. The `zPosition` property only affects rendering order, not hit testing.
    ///
    /// **Why it's deferred:**
    /// `prepareCoordinator` runs during `TextViewController.init`, before the view
    /// hierarchy is fully assembled. We dispatch to the next run loop so the find
    /// panel subviews exist when we reorder them.
    ///
    /// Uses `sortSubviews` to reorder without destroying Auto Layout constraints.
    ///
    /// TODO: Remove when CodeEditSourceEditor fixes subview ordering upstream.
    private func fixFindPanelHitTesting(controller: TextViewController) {
        // controller.view → findViewController.view → [findPanel, scrollView]
        guard let findVCView = controller.view.subviews.first else { return }
        findVCView.sortSubviews({ first, _, _ in
            let firstName = String(describing: type(of: first))
            let isFirstHosting = firstName.contains("HostingView")
            // Place HostingView (find panel) last so it's on top for hit testing
            return isFirstHosting ? .orderedDescending : .orderedAscending
        }, context: nil)
    }
}
