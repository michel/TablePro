//
//  EscapeKeyEnvironment.swift
//  TablePro
//
//  SwiftUI Environment for declarative ESC key handling.
//

import SwiftUI

// MARK: - Environment Context

/// Container for ESC key handlers in the current view hierarchy
public struct EscapeKeyContext {
    /// All registered handlers (automatically maintained by SwiftUI environment)
    var handlers: [EscapeKeyHandler] = []
    
    /// Add a handler to the context
    mutating func addHandler(_ handler: EscapeKeyHandler) {
        handlers.append(handler)
    }
    
    /// Get sorted handlers (highest priority first)
    func sortedHandlers() -> [EscapeKeyHandler] {
        handlers.sorted { $0.priority > $1.priority }
    }
}

// MARK: - Environment Key

private struct EscapeKeyContextKey: EnvironmentKey {
    static let defaultValue = EscapeKeyContext()
}

extension EnvironmentValues {
    /// Access the ESC key handler context
    public var escapeKeyContext: EscapeKeyContext {
        get { self[EscapeKeyContextKey.self] }
        set { self[EscapeKeyContextKey.self] = newValue }
    }
}
