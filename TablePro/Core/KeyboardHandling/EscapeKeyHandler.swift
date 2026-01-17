//
//  EscapeKeyHandler.swift
//  TablePro
//
//  Declarative ESC key handling system using SwiftUI environment.
//  Views declare their ESC behavior, system automatically coordinates priority.
//

import Foundation

// MARK: - Priority

/// Priority levels for ESC key handlers (higher = handled first)
public enum EscapeKeyPriority: Int, Comparable {
    /// Popup windows like autocomplete (highest priority)
    case popup = 100
    
    /// Nested modal sheets (e.g., Create Database inside Database Switcher)
    case nestedSheet = 80
    
    /// Top-level modal sheets and dialogs
    case sheet = 60
    
    /// View-specific behavior (e.g., collapse panel, clear search)
    case view = 40
    
    /// Global actions (e.g., clear selection, hide sidebar)
    case global = 20
    
    public static func < (lhs: EscapeKeyPriority, rhs: EscapeKeyPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Result

/// Result of an ESC key handler
public enum EscapeKeyResult {
    /// Handler processed the ESC key (stop propagation)
    case handled
    
    /// Handler didn't process the ESC key (continue to next handler)
    case ignored
}

// MARK: - Handler

/// A single ESC key handler with priority and action
public struct EscapeKeyHandler: Identifiable {
    public let id: UUID
    public let priority: EscapeKeyPriority
    public let handle: () -> EscapeKeyResult
    
    public init(
        id: UUID = UUID(),
        priority: EscapeKeyPriority,
        handle: @escaping () -> EscapeKeyResult
    ) {
        self.id = id
        self.priority = priority
        self.handle = handle
    }
}
