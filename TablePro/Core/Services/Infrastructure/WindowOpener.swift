//
//  WindowOpener.swift
//  TablePro
//
//  Bridges SwiftUI's openWindow environment action to imperative code.
//  Stored by ContentView on appear so MainContentCommandActions can open native tabs.
//

import os
import SwiftUI

@MainActor
internal final class WindowOpener {
    private static let logger = Logger(subsystem: "com.TablePro", category: "WindowOpener")

    internal static let shared = WindowOpener()

    /// Set by ContentView when it appears. Safe to store — OpenWindowAction is app-scoped, not view-scoped.
    internal var openWindow: OpenWindowAction?

    /// Payloads for windows that have been requested but not yet acknowledged
    /// by MainContentView.configureWindow. Keyed by payload.id.
    /// Stores connectionId so windowDidBecomeKey can compute tabbingIdentifier
    /// synchronously (before SwiftUI renders) to avoid flicker.
    internal private(set) var pendingPayloads: [UUID: UUID] = [:]  // [payloadId: connectionId]

    /// Whether any payloads are pending — used for orphan detection in windowDidBecomeKey.
    internal var hasPendingPayloads: Bool { !pendingPayloads.isEmpty }

    /// Opens a new native window tab with the given payload.
    internal func openNativeTab(_ payload: EditorTabPayload) {
        pendingPayloads[payload.id] = payload.connectionId
        guard let openWindow else {
            Self.logger.warning("openNativeTab called before openWindow was set — payload dropped")
            pendingPayloads.removeValue(forKey: payload.id)
            return
        }
        openWindow(id: "main", value: payload)
    }

    /// Called by MainContentView.configureWindow after the window is fully set up.
    internal func acknowledgePayload(_ id: UUID) {
        pendingPayloads.removeValue(forKey: id)
    }

    /// Consumes and returns the connectionId for the oldest pending payload.
    /// Removes the entry so subsequent calls don't return stale data.
    internal func consumeAnyPendingConnectionId() -> UUID? {
        guard let first = pendingPayloads.first else { return nil }
        pendingPayloads.removeValue(forKey: first.key)
        return first.value
    }

    /// Returns the tabbingIdentifier for a connection.
    internal static func tabbingIdentifier(for connectionId: UUID) -> String {
        if AppSettingsManager.shared.tabs.groupAllConnectionTabs {
            return "com.TablePro.main"
        }
        return "com.TablePro.main.\(connectionId.uuidString)"
    }
}
