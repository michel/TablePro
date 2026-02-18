//
//  ToolbarItemIdentifier.swift
//  TablePro
//
//  Type-safe toolbar item identifiers for NSToolbar customization.
//  Provides compile-time safety and centralized toolbar item metadata.
//

import AppKit

/// Type-safe toolbar item identifiers
enum ToolbarItemIdentifier: String, CaseIterable {
    // MARK: - Left Section (Navigation)

    /// Connection switcher (dropdown to switch between saved connections)
    case connectionSwitcher = "com.TablePro.toolbar.connectionSwitcher"

    /// Database switcher (switch to different database within current connection)
    case databaseSwitcher = "com.TablePro.toolbar.databaseSwitcher"

    /// New query tab
    case newQueryTab = "com.TablePro.toolbar.newQueryTab"

    /// Refresh current view/query
    case refresh = "com.TablePro.toolbar.refresh"

    /// Reconnect to database when connection is lost
    case reconnect = "com.TablePro.toolbar.reconnect"

    // MARK: - Center Section (Principal)

    /// Connection status display (tag + connection info + execution indicator)
    case connectionStatus = "com.TablePro.toolbar.connectionStatus"

    // MARK: - Right Section (Actions)

    /// Toggle filter panel
    case filterToggle = "com.TablePro.toolbar.filterToggle"

    /// Toggle query history panel
    case historyToggle = "com.TablePro.toolbar.historyToggle"

    /// Export data
    case export = "com.TablePro.toolbar.export"

    /// Import data
    case `import` = "com.TablePro.toolbar.import"

    /// Toggle right sidebar (inspector)
    case inspector = "com.TablePro.toolbar.inspector"

    /// Toggle AI chat panel
    case aiChat = "com.TablePro.toolbar.aiChat"

    // MARK: - Conversion

    /// Convert to NSToolbarItem.Identifier
    var nsIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }

    // MARK: - Metadata

    /// Human-readable label for toolbar item
    /// Note: connectionStatus label is set dynamically based on connection name
    var label: String {
        switch self {
        case .connectionSwitcher: return String(localized: "Connection")
        case .databaseSwitcher: return String(localized: "Database")
        case .newQueryTab: return String(localized: "SQL")
        case .refresh: return String(localized: "Refresh")
        case .reconnect: return String(localized: "Reconnect")
        case .connectionStatus: return "" // Set dynamically in ToolbarItemFactory
        case .filterToggle: return String(localized: "Filters")
        case .historyToggle: return String(localized: "History")
        case .export: return String(localized: "Export")
        case .import: return String(localized: "Import")
        case .inspector: return String(localized: "Inspector")
        case .aiChat: return "AI"
        }
    }

    /// Label shown in customization palette
    var paletteLabel: String {
        switch self {
        case .connectionSwitcher: return String(localized: "Connection Switcher")
        case .databaseSwitcher: return String(localized: "Database Switcher")
        case .newQueryTab: return String(localized: "New Query Tab")
        case .refresh: return String(localized: "Refresh")
        case .reconnect: return String(localized: "Reconnect to Database")
        case .connectionStatus: return String(localized: "Connection Status")
        case .filterToggle: return String(localized: "Toggle Filters")
        case .historyToggle: return String(localized: "Toggle History")
        case .export: return String(localized: "Export Data")
        case .import: return String(localized: "Import Data")
        case .inspector: return String(localized: "Toggle Inspector")
        case .aiChat: return String(localized: "Toggle AI Chat")
        }
    }

    /// Tooltip text with keyboard shortcut (if applicable)
    var toolTip: String {
        switch self {
        case .connectionSwitcher:
            return String(localized: "Switch Connection")
        case .databaseSwitcher:
            return String(localized: "Switch Database (⌘K)")
        case .newQueryTab:
            return String(localized: "New Query Tab (⌘T)")
        case .refresh:
            return String(localized: "Refresh (⌘R)")
        case .reconnect:
            return String(localized: "Reconnect to Database")
        case .connectionStatus:
            return String(localized: "Connection Status")
        case .filterToggle:
            return String(localized: "Toggle Filters (⌘F)")
        case .historyToggle:
            return String(localized: "Toggle Query History (⌘⇧H)")
        case .export:
            return String(localized: "Export Data (⌘⇧E)")
        case .import:
            return String(localized: "Import Data (⌘⇧I)")
        case .inspector:
            return String(localized: "Toggle Inspector (⌘⌥B)")
        case .aiChat:
            return String(localized: "Toggle AI Chat (⌘⇧L)")
        }
    }

    /// SF Symbol name for the toolbar item icon
    var iconName: String {
        switch self {
        case .connectionSwitcher:
            return "network"
        case .databaseSwitcher:
            return "cylinder"
        case .newQueryTab:
            return "doc.text"
        case .refresh:
            return "arrow.clockwise"
        case .reconnect:
            return "arrow.triangle.2.circlepath"
        case .connectionStatus:
            return "info.circle"  // Not used (custom view)
        case .filterToggle:
            return "line.3.horizontal.decrease.circle"
        case .historyToggle:
            return "clock"
        case .export:
            return "square.and.arrow.up"
        case .import:
            return "square.and.arrow.down"
        case .inspector:
            return "sidebar.trailing"
        case .aiChat:
            return "sparkles"
        }
    }
}
