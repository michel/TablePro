//
//  DatabaseTypeStyle.swift
//  TableProWidget
//

import SwiftUI

enum DatabaseTypeStyle {
    static func iconName(for type: String) -> String {
        switch type.lowercased() {
        case "mysql", "mariadb": return "cylinder"
        case "postgresql", "redshift": return "cylinder.split.1x2"
        case "sqlite": return "doc"
        case "redis": return "key"
        case "mongodb": return "leaf"
        case "clickhouse": return "bolt"
        case "mssql": return "server.rack"
        default: return "externaldrive"
        }
    }

    static func iconColor(for type: String) -> Color {
        switch type.lowercased() {
        case "mysql", "mariadb": return .orange
        case "postgresql", "redshift": return .blue
        case "sqlite": return .green
        case "redis": return .red
        case "mongodb": return .green
        case "clickhouse": return .yellow
        case "mssql": return .indigo
        default: return .gray
        }
    }
}
