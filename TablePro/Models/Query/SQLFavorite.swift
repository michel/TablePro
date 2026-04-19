//
//  SQLFavorite.swift
//  TablePro
//

import Foundation

/// A saved SQL query that can be quickly recalled and optionally expanded via keyword
internal struct SQLFavorite: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var query: String
    var keyword: String?
    var folderId: UUID?
    var connectionId: UUID?
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        query: String,
        keyword: String? = nil,
        folderId: UUID? = nil,
        connectionId: UUID? = nil,
        sortOrder: Int = 0,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        let now = Date()
        self.id = id
        self.name = name
        self.query = query
        self.keyword = keyword
        self.folderId = folderId
        self.connectionId = connectionId
        self.sortOrder = sortOrder
        self.createdAt = createdAt ?? now
        self.updatedAt = updatedAt ?? now
    }

    /// Generates a name from query text using the first comment or first non-empty line.
    /// Uses NSString operations for O(1) random access per CLAUDE.md performance rules.
    static func autoName(from query: String) -> String {
        let nsQuery = query as NSString
        let length = nsQuery.length
        var lineStart = 0
        while lineStart < length {
            var lineEnd = lineStart
            while lineEnd < length {
                let char = nsQuery.character(at: lineEnd)
                if char == 0x0A || char == 0x0D { break }
                lineEnd += 1
            }
            if lineEnd > lineStart {
                let line = nsQuery.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
                    .trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("--") {
                    let comment = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !comment.isEmpty {
                        let ns = comment as NSString
                        return ns.substring(to: min(50, ns.length))
                    }
                } else if !line.isEmpty {
                    let ns = line as NSString
                    return ns.substring(to: min(50, ns.length))
                }
            }
            lineStart = lineEnd + 1
        }
        return String(localized: "Untitled")
    }
}
