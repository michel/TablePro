//
//  AIPromptTemplates.swift
//  TablePro
//
//  Centralized prompt formatting for AI editor integration features.
//

import Foundation

/// Centralized prompt templates for AI-powered editor features
enum AIPromptTemplates {
    /// Build a prompt asking AI to explain a SQL query
    static func explainQuery(_ query: String) -> String {
        String(localized: "Explain this SQL query:\n\n```sql\n\(query)\n```")
    }

    /// Build a prompt asking AI to optimize a SQL query
    static func optimizeQuery(_ query: String) -> String {
        String(localized: "Optimize this SQL query for better performance:\n\n```sql\n\(query)\n```")
    }

    /// Build a prompt asking AI to fix a query that produced an error
    static func fixError(query: String, error: String) -> String {
        String(localized: "This SQL query failed with an error. Please fix it.\n\nQuery:\n```sql\n\(query)\n```\n\nError: \(error)")
    }
}
