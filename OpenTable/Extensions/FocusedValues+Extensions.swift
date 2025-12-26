//
//  FocusedValues+Extensions.swift
//  OpenTable
//

import SwiftUI

// MARK: - Database Switcher Focus

/// Key for tracking whether DatabaseSwitcher sheet is currently open
struct IsDatabaseSwitcherOpenKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    /// Whether the DatabaseSwitcher sheet is currently presented
    /// Used by commands to disable conflicting keyboard shortcuts
    var isDatabaseSwitcherOpen: Bool? {
        get { self[IsDatabaseSwitcherOpenKey.self] }
        set { self[IsDatabaseSwitcherOpenKey.self] = newValue }
    }
}
