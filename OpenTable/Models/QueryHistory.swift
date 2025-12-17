//
//  QueryHistory.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation

/// Represents a single query history entry
struct QueryHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let query: String
    let executedAt: Date
    let connectionName: String
    let rowCount: Int?
    let executionTime: TimeInterval?
    let wasSuccessful: Bool
    
    init(
        id: UUID = UUID(),
        query: String,
        executedAt: Date = Date(),
        connectionName: String,
        rowCount: Int? = nil,
        executionTime: TimeInterval? = nil,
        wasSuccessful: Bool = true
    ) {
        self.id = id
        self.query = query
        self.executedAt = executedAt
        self.connectionName = connectionName
        self.rowCount = rowCount
        self.executionTime = executionTime
        self.wasSuccessful = wasSuccessful
    }
}

/// Manages query history storage
final class QueryHistoryManager {
    static let shared = QueryHistoryManager()
    
    private let historyKey = "com.opentable.queryhistory"
    private let maxEntries = 100
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    /// Load all history entries
    func loadHistory() -> [QueryHistoryEntry] {
        guard let data = defaults.data(forKey: historyKey) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([QueryHistoryEntry].self, from: data)
        } catch {
            print("Failed to load query history: \(error)")
            return []
        }
    }
    
    /// Add a new entry to history
    func addEntry(_ entry: QueryHistoryEntry) {
        var history = loadHistory()
        
        // Remove duplicates of the same query
        history.removeAll { $0.query == entry.query }
        
        // Add new entry at the beginning
        history.insert(entry, at: 0)
        
        // Limit to max entries
        if history.count > maxEntries {
            history = Array(history.prefix(maxEntries))
        }
        
        saveHistory(history)
    }
    
    /// Clear all history
    func clearHistory() {
        defaults.removeObject(forKey: historyKey)
    }
    
    private func saveHistory(_ history: [QueryHistoryEntry]) {
        do {
            let data = try JSONEncoder().encode(history)
            defaults.set(data, forKey: historyKey)
        } catch {
            print("Failed to save query history: \(error)")
        }
    }
}
