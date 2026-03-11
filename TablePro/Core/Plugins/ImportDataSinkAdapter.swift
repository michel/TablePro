//
//  ImportDataSinkAdapter.swift
//  TablePro
//

import Foundation
import os
import TableProPluginKit

final class ImportDataSinkAdapter: PluginImportDataSink, @unchecked Sendable {
    let databaseTypeId: String
    private let driver: DatabaseDriver
    private let dbType: DatabaseType

    private static let logger = Logger(subsystem: "com.TablePro", category: "ImportDataSinkAdapter")

    init(driver: DatabaseDriver, databaseType: DatabaseType) {
        self.driver = driver
        self.dbType = databaseType
        self.databaseTypeId = databaseType.rawValue
    }

    func execute(statement: String) async throws {
        _ = try await driver.execute(query: statement)
    }

    func beginTransaction() async throws {
        try await driver.beginTransaction()
    }

    func commitTransaction() async throws {
        try await driver.commitTransaction()
    }

    func rollbackTransaction() async throws {
        try await driver.rollbackTransaction()
    }

    func disableForeignKeyChecks() async throws {
        for stmt in fkDisableStatements() {
            _ = try await driver.execute(query: stmt)
        }
    }

    func enableForeignKeyChecks() async throws {
        for stmt in fkEnableStatements() {
            _ = try await driver.execute(query: stmt)
        }
    }

    // MARK: - FK Statements

    private func fkDisableStatements() -> [String] {
        switch dbType {
        case .mysql, .mariadb:
            return ["SET FOREIGN_KEY_CHECKS=0"]
        case .postgresql, .redshift, .mssql, .oracle:
            return []
        case .sqlite:
            return ["PRAGMA foreign_keys = OFF"]
        case .mongodb, .redis, .clickhouse, .duckdb:
            return []
        }
    }

    private func fkEnableStatements() -> [String] {
        switch dbType {
        case .mysql, .mariadb:
            return ["SET FOREIGN_KEY_CHECKS=1"]
        case .postgresql, .redshift, .mssql, .oracle:
            return []
        case .sqlite:
            return ["PRAGMA foreign_keys = ON"]
        case .mongodb, .redis, .clickhouse, .duckdb:
            return []
        }
    }
}
