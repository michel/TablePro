//
//  RegistryModels.swift
//  TablePro
//

import Foundation

struct RegistryManifest: Codable, Sendable {
    let schemaVersion: Int
    let plugins: [RegistryPlugin]
}

struct RegistryPlugin: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let version: String
    let summary: String
    let author: RegistryAuthor
    let homepage: String?
    let category: RegistryCategory
    let databaseTypeIds: [String]?
    let downloadURL: String
    let sha256: String
    let minAppVersion: String?
    let minPluginKitVersion: Int?
    let iconName: String?
    let isVerified: Bool
}

struct RegistryAuthor: Codable, Sendable {
    let name: String
    let url: String?
}

enum RegistryCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case databaseDriver = "database-driver"
    case exportFormat = "export-format"
    case importFormat = "import-format"
    case theme = "theme"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .databaseDriver: String(localized: "Database Drivers")
        case .exportFormat: String(localized: "Export Formats")
        case .importFormat: String(localized: "Import Formats")
        case .theme: String(localized: "Themes")
        case .other: String(localized: "Other")
        }
    }
}
