//
//  MainContentCoordinator+Redis.swift
//  TablePro
//
//  Redis-specific query helpers for MainContentCoordinator.
//

import Foundation

extension MainContentCoordinator {
    /// Builds a Redis INFO command variant for explaining/profiling a command.
    /// Redis has no EXPLAIN equivalent, so we return a DEBUG OBJECT or INFO
    /// variant depending on whether the command targets a specific key.
    static func buildRedisDebugCommand(for command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // If the command references a key (second token), use DEBUG OBJECT
        if parts.count >= 2 {
            let key = parts[1]
            return "DEBUG OBJECT \(key)"
        }

        // Generic fallback: return server command stats
        return "INFO commandstats"
    }
}
