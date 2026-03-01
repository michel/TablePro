//
//  CreateTableServiceTests.swift
//  TableProTests
//
//  Tests for CreateTableService.swift
//

import Foundation
import Testing
@testable import TablePro

private func makeOptions(
    tableName: String = "users",
    databaseName: String = "testdb",
    columns: [ColumnDefinition] = [ColumnDefinition(name: "id", dataType: "INT")],
    primaryKeyColumns: [String] = []
) -> TableCreationOptions {
    var opts = TableCreationOptions()
    opts.tableName = tableName
    opts.databaseName = databaseName
    opts.columns = columns
    opts.primaryKeyColumns = primaryKeyColumns
    return opts
}

// MARK: - Validation

@Suite("CreateTableService - Validation")
struct CreateTableServiceValidationTests {

    @Test("Empty table name throws for all database types")
    func emptyTableName() {
        for dbType in [DatabaseType.mysql, .mariadb, .postgresql, .sqlite, .mongodb] {
            let service = CreateTableService(databaseType: dbType)
            let options = makeOptions(tableName: "")
            #expect {
                try service.validate(options)
            } throws: { error in
                (error as? CreateTableError).flatMap {
                    if case .emptyTableName = $0 { return true } else { return nil }
                } ?? false
            }
        }
    }

    @Test("Empty database name throws for MySQL but not SQLite or MongoDB")
    func emptyDatabaseName() {
        let mysqlService = CreateTableService(databaseType: .mysql)
        let mysqlOptions = makeOptions(databaseName: "")
        #expect {
            try mysqlService.validate(mysqlOptions)
        } throws: { error in
            (error as? CreateTableError).flatMap {
                if case .emptyDatabaseName = $0 { return true } else { return nil }
            } ?? false
        }

        let sqliteService = CreateTableService(databaseType: .sqlite)
        let sqliteOptions = makeOptions(databaseName: "")
        #expect(throws: Never.self) {
            try sqliteService.validate(sqliteOptions)
        }

        let mongoService = CreateTableService(databaseType: .mongodb)
        let mongoOptions = makeOptions(tableName: "users", databaseName: "", columns: [])
        #expect(throws: Never.self) {
            try mongoService.validate(mongoOptions)
        }
    }

    @Test("No columns throws for MySQL")
    func noColumns() {
        let service = CreateTableService(databaseType: .mysql)
        let options = makeOptions(columns: [])
        #expect {
            try service.validate(options)
        } throws: { error in
            (error as? CreateTableError).flatMap {
                if case .noColumns = $0 { return true } else { return nil }
            } ?? false
        }
    }

    @Test("Duplicate column names detected case-insensitively")
    func duplicateColumnName() {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [
            ColumnDefinition(name: "id", dataType: "INT"),
            ColumnDefinition(name: "ID", dataType: "INT"),
        ]
        let options = makeOptions(columns: columns)
        #expect {
            try service.validate(options)
        } throws: { error in
            guard let createError = error as? CreateTableError,
                  case .duplicateColumnName(let name) = createError else {
                return false
            }
            return name == "ID"
        }
    }

    @Test("Empty column name throws with column index")
    func emptyColumnName() {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [ColumnDefinition(name: "", dataType: "INT")]
        let options = makeOptions(columns: columns)
        #expect {
            try service.validate(options)
        } throws: { error in
            guard let createError = error as? CreateTableError,
                  case .emptyColumnName(let index) = createError else {
                return false
            }
            return index == 0
        }
    }

    @Test("VARCHAR without length throws missingLength")
    func missingVarcharLength() {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [ColumnDefinition(name: "name", dataType: "VARCHAR")]
        let options = makeOptions(columns: columns)
        #expect {
            try service.validate(options)
        } throws: { error in
            guard let createError = error as? CreateTableError,
                  case .missingLength(let col, let dt) = createError else {
                return false
            }
            return col == "name" && dt == "VARCHAR"
        }
    }

    @Test("Negative length throws invalidLength")
    func invalidLength() {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [ColumnDefinition(name: "name", dataType: "INT", length: -1)]
        let options = makeOptions(columns: columns)
        #expect {
            try service.validate(options)
        } throws: { error in
            guard let createError = error as? CreateTableError,
                  case .invalidLength(let col, _) = createError else {
                return false
            }
            return col == "name"
        }
    }

    @Test("Multiple auto-increment columns throws for MySQL")
    func multipleAutoIncrement() {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [
            ColumnDefinition(name: "id", dataType: "INT", autoIncrement: true),
            ColumnDefinition(name: "seq", dataType: "INT", autoIncrement: true),
        ]
        let options = makeOptions(columns: columns)
        #expect {
            try service.validate(options)
        } throws: { error in
            (error as? CreateTableError).flatMap {
                if case .multipleAutoIncrement = $0 { return true } else { return nil }
            } ?? false
        }
    }

    @Test("Auto-increment on non-integer type throws")
    func autoIncrementNotInteger() {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [ColumnDefinition(name: "name", dataType: "VARCHAR", length: 255, autoIncrement: true)]
        let options = makeOptions(columns: columns)
        #expect {
            try service.validate(options)
        } throws: { error in
            guard let createError = error as? CreateTableError,
                  case .autoIncrementNotInteger(let name) = createError else {
                return false
            }
            return name == "name"
        }
    }

    @Test("MongoDB skips column and database name validation")
    func mongodbSkipsColumnValidation() {
        let service = CreateTableService(databaseType: .mongodb)
        let options = makeOptions(tableName: "users", databaseName: "", columns: [])
        #expect(throws: Never.self) {
            try service.validate(options)
        }
    }

    @Test("SQLite skips database name validation")
    func sqliteSkipsDatabaseNameValidation() {
        let service = CreateTableService(databaseType: .sqlite)
        let options = makeOptions(databaseName: "")
        #expect(throws: Never.self) {
            try service.validate(options)
        }
    }
}

// MARK: - MongoDB

@Suite("CreateTableService - MongoDB")
struct CreateTableServiceMongoDBTests {

    @Test("MongoDB generates db.createCollection command")
    func mongodbGenerateSQL() throws {
        let service = CreateTableService(databaseType: .mongodb)
        let options = makeOptions(tableName: "users", columns: [])
        let sql = try service.generateSQL(options)
        #expect(sql == "db.createCollection(\"users\")")
    }

    @Test("MongoDB preview SQL returns same as generateSQL")
    func mongodbPreviewSQL() {
        let service = CreateTableService(databaseType: .mongodb)
        let options = makeOptions(tableName: "users", columns: [])
        let sql = service.generatePreviewSQL(options)
        #expect(sql == "db.createCollection(\"users\")")
    }

    @Test("MongoDB validate succeeds with only table name")
    func mongodbValidateAcceptsNameOnly() {
        let service = CreateTableService(databaseType: .mongodb)
        var options = TableCreationOptions()
        options.tableName = "logs"
        #expect(throws: Never.self) {
            try service.validate(options)
        }
    }
}

// MARK: - MySQL SQL Generation

@Suite("CreateTableService - MySQL SQL Generation")
struct CreateTableServiceMySQLTests {

    @Test("Basic CREATE TABLE with columns and primary key")
    func basicCreateTable() throws {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [
            ColumnDefinition(name: "id", dataType: "INT", notNull: true),
            ColumnDefinition(name: "name", dataType: "VARCHAR", length: 255, notNull: true),
        ]
        let options = makeOptions(columns: columns, primaryKeyColumns: ["id"])
        let sql = try service.generateSQL(options)

        #expect(sql.contains("CREATE TABLE"))
        #expect(sql.contains("`id`"))
        #expect(sql.contains("`name`"))
        #expect(sql.contains("INT"))
        #expect(sql.contains("VARCHAR(255)"))
        #expect(sql.contains("NOT NULL"))
        #expect(sql.contains("PRIMARY KEY"))
        #expect(sql.contains("ENGINE=InnoDB"))
        #expect(sql.contains("CHARSET=utf8mb4"))
    }

    @Test("Auto-increment column produces AUTO_INCREMENT keyword")
    func autoIncrementColumn() throws {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [
            ColumnDefinition(name: "id", dataType: "INT", notNull: true, autoIncrement: true),
        ]
        let options = makeOptions(columns: columns)
        let sql = try service.generateSQL(options)
        #expect(sql.contains("AUTO_INCREMENT"))
    }

    @Test("Default values rendered correctly for different types")
    func defaultValues() throws {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [
            ColumnDefinition(name: "count", dataType: "INT", defaultValue: "0"),
            ColumnDefinition(name: "label", dataType: "VARCHAR", length: 100, defaultValue: "hello"),
            ColumnDefinition(name: "deleted_at", dataType: "TIMESTAMP", defaultValue: "NULL"),
            ColumnDefinition(name: "created_at", dataType: "TIMESTAMP", defaultValue: "NOW()"),
        ]
        let options = makeOptions(columns: columns)
        let sql = try service.generateSQL(options)

        #expect(sql.contains("DEFAULT 0"))
        #expect(sql.contains("DEFAULT 'hello'"))
        #expect(sql.contains("DEFAULT NULL"))
        #expect(sql.contains("DEFAULT NOW()"))
    }

    @Test("Unsigned column produces UNSIGNED keyword")
    func unsignedColumn() throws {
        let service = CreateTableService(databaseType: .mysql)
        let columns = [
            ColumnDefinition(name: "age", dataType: "INT", unsigned: true),
        ]
        let options = makeOptions(columns: columns)
        let sql = try service.generateSQL(options)
        #expect(sql.contains("UNSIGNED"))
    }
}

// MARK: - PostgreSQL SQL Generation

@Suite("CreateTableService - PostgreSQL SQL Generation")
struct CreateTableServicePostgreSQLTests {

    @Test("Basic CREATE TABLE with double-quote quoting and schema.table format")
    func basicCreateTable() throws {
        let service = CreateTableService(databaseType: .postgresql)
        let columns = [
            ColumnDefinition(name: "id", dataType: "INT", notNull: true),
            ColumnDefinition(name: "name", dataType: "VARCHAR", length: 255),
        ]
        let options = makeOptions(columns: columns, primaryKeyColumns: ["id"])
        let sql = try service.generateSQL(options)

        #expect(sql.contains("CREATE TABLE"))
        #expect(sql.contains("\"testdb\".\"users\""))
        #expect(sql.contains("\"id\""))
        #expect(sql.contains("\"name\""))
        #expect(sql.contains("PRIMARY KEY"))
    }

    @Test("INT with auto-increment becomes SERIAL")
    func serialType() throws {
        let service = CreateTableService(databaseType: .postgresql)
        let columns = [
            ColumnDefinition(name: "id", dataType: "INT", autoIncrement: true),
        ]
        let options = makeOptions(columns: columns)
        let sql = try service.generateSQL(options)

        #expect(sql.contains("SERIAL"))
        #expect(!sql.contains("AUTO_INCREMENT"))
    }

    @Test("BIGINT with auto-increment becomes BIGSERIAL")
    func bigserialType() throws {
        let service = CreateTableService(databaseType: .postgresql)
        let columns = [
            ColumnDefinition(name: "id", dataType: "BIGINT", autoIncrement: true),
        ]
        let options = makeOptions(columns: columns)
        let sql = try service.generateSQL(options)
        #expect(sql.contains("BIGSERIAL"))
    }

    @Test("Non-NOT NULL column gets explicit NULL in PostgreSQL")
    func nullExplicit() throws {
        let service = CreateTableService(databaseType: .postgresql)
        let columns = [
            ColumnDefinition(name: "bio", dataType: "TEXT"),
        ]
        let options = makeOptions(columns: columns)
        let sql = try service.generateSQL(options)
        #expect(sql.contains("NULL"))
    }
}

// MARK: - SQLite SQL Generation

@Suite("CreateTableService - SQLite SQL Generation")
struct CreateTableServiceSQLiteTests {

    @Test("Basic CREATE TABLE without database qualifier")
    func basicCreateTable() throws {
        let service = CreateTableService(databaseType: .sqlite)
        let columns = [
            ColumnDefinition(name: "id", dataType: "INTEGER", notNull: true),
            ColumnDefinition(name: "name", dataType: "TEXT"),
        ]
        let options = makeOptions(columns: columns)
        let sql = try service.generateSQL(options)

        #expect(sql.contains("CREATE TABLE"))
        #expect(sql.contains("`users`"))
        #expect(!sql.contains("testdb"))
        #expect(sql.contains("INTEGER"))
        #expect(sql.contains("TEXT"))
    }

    @Test("Single primary key column gets PRIMARY KEY inline")
    func singlePrimaryKeyInline() throws {
        let service = CreateTableService(databaseType: .sqlite)
        let columns = [
            ColumnDefinition(name: "id", dataType: "INTEGER", notNull: true),
            ColumnDefinition(name: "name", dataType: "TEXT"),
        ]
        let options = makeOptions(columns: columns, primaryKeyColumns: ["id"])
        let sql = try service.generateSQL(options)

        #expect(sql.contains("PRIMARY KEY"))
        #expect(!sql.contains("PRIMARY KEY ("))
    }

    @Test("Multiple primary key columns produce separate PRIMARY KEY constraint")
    func compositePrimaryKey() throws {
        let service = CreateTableService(databaseType: .sqlite)
        let columns = [
            ColumnDefinition(name: "user_id", dataType: "INTEGER"),
            ColumnDefinition(name: "role_id", dataType: "INTEGER"),
        ]
        let options = makeOptions(columns: columns, primaryKeyColumns: ["user_id", "role_id"])
        let sql = try service.generateSQL(options)

        #expect(sql.contains("PRIMARY KEY ("))
        #expect(sql.contains("`user_id`"))
        #expect(sql.contains("`role_id`"))
    }

    @Test("INTEGER auto-increment with PK produces PRIMARY KEY AUTOINCREMENT")
    func autoIncrementSQLite() throws {
        let service = CreateTableService(databaseType: .sqlite)
        let columns = [
            ColumnDefinition(name: "id", dataType: "INTEGER", autoIncrement: true),
        ]
        let options = makeOptions(columns: columns, primaryKeyColumns: ["id"])
        let sql = try service.generateSQL(options)

        #expect(sql.contains("PRIMARY KEY"))
        #expect(sql.contains("AUTOINCREMENT"))
        #expect(!sql.contains("AUTO_INCREMENT"))
    }
}

// MARK: - Preview SQL

@Suite("CreateTableService - Preview SQL")
struct CreateTableServicePreviewSQLTests {

    @Test("Preview SQL returns SQL for valid options")
    func previewSQLReturnsSQL() {
        let service = CreateTableService(databaseType: .mysql)
        let options = makeOptions()
        let sql = service.generatePreviewSQL(options)
        #expect(sql.contains("CREATE TABLE"))
    }

    @Test("Preview SQL returns error comment for invalid options")
    func previewSQLReturnsError() {
        let service = CreateTableService(databaseType: .mysql)
        let options = makeOptions(tableName: "")
        let sql = service.generatePreviewSQL(options)
        #expect(sql.hasPrefix("-- Error:"))
    }
}
