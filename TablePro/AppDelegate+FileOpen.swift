//
//  AppDelegate+FileOpen.swift
//  TablePro
//
//  URL and file open handling dispatched from application(_:open:)
//

import AppKit
import os
import SwiftUI

private let fileOpenLogger = Logger(subsystem: "com.TablePro", category: "FileOpen")

extension AppDelegate {
    // MARK: - URL Classification

    private static let databaseURLSchemes: Set<String> = [
        "postgresql", "postgres", "mysql", "mariadb", "sqlite",
        "mongodb", "mongodb+srv", "redis", "rediss", "redshift",
        "mssql", "sqlserver", "oracle", "duckdb"
    ]

    static let sqliteFileExtensions: Set<String> = [
        "sqlite", "sqlite3", "db3", "s3db", "sl3", "sqlitedb"
    ]

    static let duckdbFileExtensions: Set<String> = ["duckdb", "ddb"]

    private func isDatabaseURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        let base = scheme
            .replacingOccurrences(of: "+ssh", with: "")
            .replacingOccurrences(of: "+srv", with: "")
        return Self.databaseURLSchemes.contains(base) || Self.databaseURLSchemes.contains(scheme)
    }

    private func isSQLiteFile(_ url: URL) -> Bool {
        Self.sqliteFileExtensions.contains(url.pathExtension.lowercased())
    }

    private func isDuckDBFile(_ url: URL) -> Bool {
        Self.duckdbFileExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Main Dispatch

    func handleOpenURLs(_ urls: [URL]) {
        let deeplinks = urls.filter { $0.scheme == "tablepro" }
        if !deeplinks.isEmpty {
            Task { @MainActor in
                for url in deeplinks { self.handleDeeplink(url) }
            }
        }

        let plugins = urls.filter { $0.pathExtension == "tableplugin" }
        if !plugins.isEmpty {
            Task { @MainActor in
                for url in plugins { await self.handlePluginInstall(url) }
            }
        }

        let databaseURLs = urls.filter { isDatabaseURL($0) }
        if !databaseURLs.isEmpty {
            suppressWelcomeWindow()
            Task { @MainActor in
                for url in databaseURLs { self.handleDatabaseURL(url) }
                self.scheduleWelcomeWindowSuppression()
            }
        }

        let sqliteFiles = urls.filter { isSQLiteFile($0) }
        if !sqliteFiles.isEmpty {
            suppressWelcomeWindow()
            Task { @MainActor in
                for url in sqliteFiles { self.handleSQLiteFile(url) }
                self.scheduleWelcomeWindowSuppression()
            }
        }

        let duckdbFiles = urls.filter { isDuckDBFile($0) }
        if !duckdbFiles.isEmpty {
            suppressWelcomeWindow()
            Task { @MainActor in
                for url in duckdbFiles { self.handleDuckDBFile(url) }
                self.scheduleWelcomeWindowSuppression()
            }
        }

        let sqlFiles = urls.filter { $0.pathExtension.lowercased() == "sql" }
        if !sqlFiles.isEmpty {
            if DatabaseManager.shared.currentSession != nil {
                suppressWelcomeWindow()
                for window in NSApp.windows where isMainWindow(window) {
                    window.makeKeyAndOrderFront(nil)
                }
                for window in NSApp.windows where isWelcomeWindow(window) {
                    window.close()
                }
                NotificationCenter.default.post(name: .openSQLFiles, object: sqlFiles)
                scheduleWelcomeWindowSuppression()
            } else {
                queuedFileURLs.append(contentsOf: sqlFiles)
                openWelcomeWindow()
            }
        }
    }

    // MARK: - Welcome Window Suppression

    func suppressWelcomeWindow() {
        isHandlingFileOpen = true
        fileOpenSuppressionCount += 1
        for window in NSApp.windows where isWelcomeWindow(window) {
            window.orderOut(nil)
        }
    }

    // MARK: - Deeplink Handling

    private func handleDeeplink(_ url: URL) {
        guard let action = DeeplinkHandler.parse(url) else { return }

        switch action {
        case .connect(let name):
            connectViaDeeplink(connectionName: name)

        case .openTable(let name, let table, let database):
            connectViaDeeplink(connectionName: name) { connectionId in
                EditorTabPayload(connectionId: connectionId, tabType: .table,
                                 tableName: table, databaseName: database)
            }

        case .openQuery(let name, let sql):
            connectViaDeeplink(connectionName: name) { connectionId in
                EditorTabPayload(connectionId: connectionId, tabType: .query,
                                 initialQuery: sql)
            }

        case .importConnection(let name, let host, let port, let type, let username, let database):
            handleImportDeeplink(name: name, host: host, port: port, type: type,
                                 username: username, database: database)
        }
    }

    private func connectViaDeeplink(
        connectionName: String,
        makePayload: (@Sendable (UUID) -> EditorTabPayload)? = nil
    ) {
        guard let connection = DeeplinkHandler.resolveConnection(named: connectionName) else {
            fileOpenLogger.error("Deep link: no connection named '\(connectionName, privacy: .public)'")
            AlertHelper.showErrorSheet(
                title: String(localized: "Connection Not Found"),
                message: String(localized: "No saved connection named \"\(connectionName)\"."),
                window: NSApp.keyWindow
            )
            return
        }

        if DatabaseManager.shared.activeSessions[connection.id]?.driver != nil {
            if let payload = makePayload?(connection.id) {
                WindowOpener.shared.openNativeTab(payload)
            } else {
                for window in NSApp.windows where isMainWindow(window) {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
            }
            return
        }

        let hadExistingMain = NSApp.windows.contains { isMainWindow($0) && $0.isVisible }
        if hadExistingMain {
            NSWindow.allowsAutomaticWindowTabbing = false
        }

        let deeplinkPayload = EditorTabPayload(connectionId: connection.id)
        WindowOpener.shared.openNativeTab(deeplinkPayload)

        Task { @MainActor in
            do {
                try await DatabaseManager.shared.connectToSession(connection)
                for window in NSApp.windows where self.isWelcomeWindow(window) {
                    window.close()
                }
                if let payload = makePayload?(connection.id) {
                    WindowOpener.shared.openNativeTab(payload)
                }
            } catch {
                fileOpenLogger.error("Deep link connect failed: \(error.localizedDescription)")
                await self.handleConnectionFailure(error)
            }
        }
    }

    private func handleImportDeeplink(
        name: String, host: String, port: Int,
        type: DatabaseType, username: String, database: String
    ) {
        let connection = DatabaseConnection(
            name: name, host: host, port: port,
            database: database, username: username, type: type
        )
        ConnectionStorage.shared.addConnection(connection)
        NotificationCenter.default.post(name: .connectionUpdated, object: nil)

        if let openWindow = WindowOpener.shared.openWindow {
            openWindow(id: "connection-form", value: connection.id)
        }
    }

    // MARK: - Plugin Install

    private func handlePluginInstall(_ url: URL) async {
        do {
            let entry = try await PluginManager.shared.installPlugin(from: url)
            fileOpenLogger.info("Installed plugin '\(entry.name)' from Finder")

            UserDefaults.standard.set(SettingsTab.plugins.rawValue, forKey: "selectedSettingsTab")
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } catch {
            fileOpenLogger.error("Plugin install failed: \(error.localizedDescription)")
            AlertHelper.showErrorSheet(
                title: String(localized: "Plugin Installation Failed"),
                message: error.localizedDescription,
                window: NSApp.keyWindow
            )
        }
    }
}
