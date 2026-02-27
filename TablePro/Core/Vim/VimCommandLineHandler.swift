//
//  VimCommandLineHandler.swift
//  TablePro
//
//  Handles Vim command-line commands (:w, :q, etc.)
//

import Foundation

/// Handles Vim command-line commands
struct VimCommandLineHandler {
    /// Callback to execute the current query (:w)
    var onExecuteQuery: (() -> Void)?

    /// Process a command string (without the leading : or /)
    func handle(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)

        switch trimmed {
        case "w":
            onExecuteQuery?()
        case "q":
            // Close tab — optional, no-op for now
            break
        case "wq":
            onExecuteQuery?()
        default:
            break // Unknown commands are silently ignored
        }
    }
}
