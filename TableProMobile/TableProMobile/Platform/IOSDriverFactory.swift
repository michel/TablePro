//
//  IOSDriverFactory.swift
//  TableProMobile
//

import Foundation
import TableProDatabase
import TableProModels

final class IOSDriverFactory: DriverFactory {
    func createDriver(for connection: DatabaseConnection, password: String?) throws -> any DatabaseDriver {
        // Normalize type for case-insensitive matching
        // macOS uses "MySQL"/"PostgreSQL", iOS uses "mysql"/"postgresql"
        let typeKey = connection.type.rawValue.lowercased()

        switch typeKey {
        case "sqlite":
            return SQLiteDriver(path: connection.database)
        case "mysql", "mariadb":
            return MySQLDriver(
                host: connection.host,
                port: connection.port,
                user: connection.username,
                password: password ?? "",
                database: connection.database
            )
        case "postgresql", "redshift":
            return PostgreSQLDriver(
                host: connection.host,
                port: connection.port,
                user: connection.username,
                password: password ?? "",
                database: connection.database
            )
        case "redis":
            let dbIndex = Int(connection.database) ?? 0
            return RedisDriver(
                host: connection.host,
                port: connection.port,
                password: password,
                database: dbIndex
            )
        default:
            throw ConnectionError.driverNotFound(connection.type.rawValue)
        }
    }

    func supportedTypes() -> [DatabaseType] {
        [.sqlite, .mysql, .mariadb, .postgresql, .redshift, .redis]
    }
}
