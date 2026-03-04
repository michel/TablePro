//
//  AIPromptTemplates.swift
//  TablePro
//
//  Centralized prompt formatting for AI editor integration features.
//

import Foundation

/// Centralized prompt templates for AI-powered editor features
enum AIPromptTemplates {
    /// Build a prompt asking AI to explain a query
    static func explainQuery(_ query: String, databaseType: DatabaseType = .mysql) -> String {
        let (typeName, lang) = queryInfo(for: databaseType)
        return "Explain this \(typeName):\n\n```\(lang)\n\(query)\n```"
    }

    /// Build a prompt asking AI to optimize a query
    static func optimizeQuery(_ query: String, databaseType: DatabaseType = .mysql) -> String {
        let (typeName, lang) = queryInfo(for: databaseType)
        return "Optimize this \(typeName) for better performance:\n\n```\(lang)\n\(query)\n```"
    }

    /// Build a prompt asking AI to fix a query that produced an error
    static func fixError(query: String, error: String, databaseType: DatabaseType = .mysql) -> String {
        let (typeName, lang) = queryInfo(for: databaseType)
        return "This \(typeName) failed with an error. Please fix it.\n\nQuery:\n```\(lang)\n\(query)\n```\n\nError: \(error)"
    }

    private static func queryInfo(for databaseType: DatabaseType) -> (typeName: String, language: String) {
        switch databaseType {
        case .mongodb:
            return ("MongoDB query", "javascript")
        case .redis:
            return ("Redis command", "bash")
        default:
            return ("SQL query", "sql")
        }
    }
}
