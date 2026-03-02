//
//  ConnectionGroup.swift
//  TablePro
//

import Foundation

/// A named group (folder) for organizing database connections
struct ConnectionGroup: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var color: ConnectionColor

    init(id: UUID = UUID(), name: String, color: ConnectionColor = .none) {
        self.id = id
        self.name = name
        self.color = color
    }
}
