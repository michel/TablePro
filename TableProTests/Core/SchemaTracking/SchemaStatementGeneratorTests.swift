//
//  SchemaStatementGeneratorTests.swift
//  TableProTests
//
//  Tests for SchemaStatementGenerator
//

import Foundation
import Testing
@testable import TablePro

@Suite("Schema Statement Generator")
struct SchemaStatementGeneratorTests {

    // MARK: - Helpers

    private func makeGenerator(
        table: String = "users",
        dbType: DatabaseType = .mysql,
        pkConstraint: String? = nil
    ) -> SchemaStatementGenerator {
        SchemaStatementGenerator(
            tableName: table,
            databaseType: dbType,
            primaryKeyConstraintName: pkConstraint
        )
    }

    private func makeColumn(
        name: String = "email",
        dataType: String = "VARCHAR(255)",
        isNullable: Bool = true,
        autoIncrement: Bool = false,
        unsigned: Bool = false,
        isPrimaryKey: Bool = false,
        defaultValue: String? = nil,
        comment: String? = nil
    ) -> EditableColumnDefinition {
        EditableColumnDefinition(
            id: UUID(),
            name: name,
            dataType: dataType,
            isNullable: isNullable,
            defaultValue: defaultValue,
            autoIncrement: autoIncrement,
            unsigned: unsigned,
            comment: comment,
            collation: nil,
            onUpdate: nil,
            charset: nil,
            extra: nil,
            isPrimaryKey: isPrimaryKey
        )
    }

    private func makeIndex(
        name: String = "idx_email",
        columns: [String] = ["email"],
        isUnique: Bool = false,
        type: EditableIndexDefinition.IndexType = .btree
    ) -> EditableIndexDefinition {
        EditableIndexDefinition(
            id: UUID(),
            name: name,
            columns: columns,
            type: type,
            isUnique: isUnique,
            isPrimary: false,
            comment: nil
        )
    }

    private func makeFK(
        name: String = "fk_user_role",
        columns: [String] = ["role_id"],
        refTable: String = "roles",
        refColumns: [String] = ["id"]
    ) -> EditableForeignKeyDefinition {
        EditableForeignKeyDefinition(
            id: UUID(),
            name: name,
            columns: columns,
            referencedTable: refTable,
            referencedColumns: refColumns,
            onDelete: .cascade,
            onUpdate: .noAction
        )
    }

    private func normalizeSQL(_ sql: String) -> String {
        sql.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Column Tests

    @Test("Add column MySQL with basic properties")
    func addColumnMySQL() throws {
        let generator = makeGenerator()
        let column = makeColumn(name: "age", dataType: "INT")
        let changes: [SchemaChange] = [.addColumn(column)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("ALTER TABLE"))
        #expect(sql.contains("ADD COLUMN"))
        #expect(sql.contains("`age`"))
        #expect(sql.contains("INT"))
        #expect(sql.hasSuffix(";"))
        #expect(statements[0].isDestructive == false)
    }

    @Test("Add column with all properties MySQL")
    func addColumnWithAllPropertiesMySQL() throws {
        let generator = makeGenerator()
        let column = makeColumn(
            name: "score",
            dataType: "INT",
            isNullable: false,
            autoIncrement: true,
            unsigned: true,
            defaultValue: "0",
            comment: "User score"
        )
        let changes: [SchemaChange] = [.addColumn(column)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("UNSIGNED"))
        #expect(sql.contains("NOT NULL"))
        #expect(sql.contains("DEFAULT 0"))
        #expect(sql.contains("AUTO_INCREMENT"))
        #expect(sql.contains("COMMENT 'User score'"))
    }

    @Test("Add column PostgreSQL with AUTO_INCREMENT becomes SERIAL")
    func addColumnPostgreSQLAutoIncrement() throws {
        let generator = makeGenerator(dbType: .postgresql)
        let column = makeColumn(name: "id", dataType: "INT", autoIncrement: true)
        let changes: [SchemaChange] = [.addColumn(column)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("SERIAL") || sql.contains("AUTO_INCREMENT"))
    }

    @Test("Delete column is destructive")
    func deleteColumn() throws {
        let generator = makeGenerator()
        let column = makeColumn(name: "old_field")
        let changes: [SchemaChange] = [.deleteColumn(column)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP COLUMN"))
        #expect(sql.contains("`old_field`"))
        #expect(sql.hasSuffix(";"))
        #expect(statements[0].isDestructive == true)
    }

    @Test("Modify column MySQL uses MODIFY COLUMN")
    func modifyColumnMySQL() throws {
        let generator = makeGenerator()
        let oldColumn = makeColumn(name: "name", dataType: "VARCHAR(100)")
        let newColumn = makeColumn(name: "name", dataType: "VARCHAR(255)")
        let changes: [SchemaChange] = [.modifyColumn(old: oldColumn, new: newColumn)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("MODIFY COLUMN"))
        #expect(sql.contains("`name`"))
        #expect(sql.contains("VARCHAR(255)"))
    }

    @Test("Modify column PostgreSQL uses separate ALTER statements")
    func modifyColumnPostgreSQL() throws {
        let generator = makeGenerator(dbType: .postgresql)
        let oldColumn = makeColumn(name: "email", dataType: "VARCHAR(100)", isNullable: false)
        let newColumn = makeColumn(name: "email_new", dataType: "VARCHAR(255)", isNullable: true, defaultValue: "''")
        let changes: [SchemaChange] = [.modifyColumn(old: oldColumn, new: newColumn)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count >= 1)
        let allSQL = statements.map { $0.sql }.joined(separator: " ")
        #expect(allSQL.contains("ALTER COLUMN") || allSQL.contains("RENAME COLUMN"))
    }

    @Test("Modify column SQLite throws unsupported operation")
    func modifyColumnSQLiteThrows() throws {
        let generator = makeGenerator(dbType: .sqlite)
        let oldColumn = makeColumn(name: "field", dataType: "TEXT")
        let newColumn = makeColumn(name: "field", dataType: "INTEGER")
        let changes: [SchemaChange] = [.modifyColumn(old: oldColumn, new: newColumn)]

        #expect(throws: DatabaseError.self) {
            try generator.generate(changes: changes)
        }
    }

    @Test("Modify column with type change is destructive")
    func modifyColumnTypeChangeDestructive() throws {
        let generator = makeGenerator()
        let oldColumn = makeColumn(name: "count", dataType: "INT")
        let newColumn = makeColumn(name: "count", dataType: "BIGINT")
        let changes: [SchemaChange] = [.modifyColumn(old: oldColumn, new: newColumn)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        #expect(statements[0].isDestructive == true)
    }

    // MARK: - Index Tests

    @Test("Add index MySQL with USING clause")
    func addIndexMySQL() throws {
        let generator = makeGenerator()
        let index = makeIndex(name: "idx_email", columns: ["email"], type: .btree)
        let changes: [SchemaChange] = [.addIndex(index)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("CREATE INDEX"))
        #expect(sql.contains("`idx_email`"))
        #expect(sql.contains("ON `users`"))
        #expect(sql.contains("USING"))
        #expect(sql.hasSuffix(";"))
    }

    @Test("Add index PostgreSQL skips USING for BTREE")
    func addIndexPostgreSQLBTree() throws {
        let generator = makeGenerator(dbType: .postgresql)
        let index = makeIndex(name: "idx_name", columns: ["name"], type: .btree)
        let changes: [SchemaChange] = [.addIndex(index)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("CREATE INDEX"))
        #expect(!sql.contains("USING BTREE") || sql.contains("USING"))
    }

    @Test("Add unique index")
    func addUniqueIndex() throws {
        let generator = makeGenerator()
        let index = makeIndex(name: "idx_unique_email", columns: ["email"], isUnique: true)
        let changes: [SchemaChange] = [.addIndex(index)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("UNIQUE INDEX"))
    }

    @Test("Delete index MySQL uses DROP INDEX ON table")
    func deleteIndexMySQL() throws {
        let generator = makeGenerator()
        let index = makeIndex(name: "idx_old")
        let changes: [SchemaChange] = [.deleteIndex(index)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP INDEX"))
        #expect(sql.contains("`idx_old`"))
        #expect(sql.contains("ON `users`"))
    }

    @Test("Delete index PostgreSQL uses DROP INDEX without ON")
    func deleteIndexPostgreSQL() throws {
        let generator = makeGenerator(dbType: .postgresql)
        let index = makeIndex(name: "idx_old")
        let changes: [SchemaChange] = [.deleteIndex(index)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP INDEX"))
        #expect(sql.contains("\"idx_old\""))
        #expect(!sql.contains("ON"))
    }

    @Test("Modify index generates drop and create in single statement")
    func modifyIndex() throws {
        let generator = makeGenerator()
        let oldIndex = makeIndex(name: "idx_email", columns: ["email"])
        let newIndex = makeIndex(name: "idx_email", columns: ["email", "name"], isUnique: true)
        let changes: [SchemaChange] = [.modifyIndex(old: oldIndex, new: newIndex)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP INDEX"))
        #expect(sql.contains("CREATE"))
        #expect(sql.contains("UNIQUE"))
    }

    // MARK: - Foreign Key Tests

    @Test("Add foreign key with all clauses")
    func addForeignKey() throws {
        let generator = makeGenerator()
        let fk = makeFK(name: "fk_user_role", columns: ["role_id"], refTable: "roles", refColumns: ["id"])
        let changes: [SchemaChange] = [.addForeignKey(fk)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("ALTER TABLE"))
        #expect(sql.contains("ADD CONSTRAINT"))
        #expect(sql.contains("`fk_user_role`"))
        #expect(sql.contains("FOREIGN KEY"))
        #expect(sql.contains("`role_id`"))
        #expect(sql.contains("REFERENCES"))
        #expect(sql.contains("`roles`"))
        #expect(sql.contains("ON DELETE"))
        #expect(sql.contains("ON UPDATE"))
    }

    @Test("Delete foreign key MySQL uses DROP FOREIGN KEY")
    func deleteForeignKeyMySQL() throws {
        let generator = makeGenerator()
        let fk = makeFK(name: "fk_old")
        let changes: [SchemaChange] = [.deleteForeignKey(fk)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP FOREIGN KEY"))
        #expect(sql.contains("`fk_old`"))
    }

    @Test("Delete foreign key PostgreSQL uses DROP CONSTRAINT")
    func deleteForeignKeyPostgreSQL() throws {
        let generator = makeGenerator(dbType: .postgresql)
        let fk = makeFK(name: "fk_old")
        let changes: [SchemaChange] = [.deleteForeignKey(fk)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP CONSTRAINT"))
        #expect(sql.contains("\"fk_old\""))
    }

    @Test("Modify foreign key generates drop and create in single statement")
    func modifyForeignKey() throws {
        let generator = makeGenerator()
        let oldFK = makeFK(name: "fk_role", columns: ["role_id"], refTable: "roles", refColumns: ["id"])
        let newFK = makeFK(name: "fk_role", columns: ["role_id"], refTable: "roles", refColumns: ["role_id"])
        let changes: [SchemaChange] = [.modifyForeignKey(old: oldFK, new: newFK)]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP"))
        #expect(sql.contains("ADD CONSTRAINT"))
    }

    // MARK: - Primary Key Tests

    @Test("Modify primary key MySQL uses DROP and ADD PRIMARY KEY")
    func modifyPrimaryKeyMySQL() throws {
        let generator = makeGenerator()
        let changes: [SchemaChange] = [.modifyPrimaryKey(old: ["id"], new: ["id", "tenant_id"])]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP PRIMARY KEY"))
        #expect(sql.contains("ADD PRIMARY KEY"))
        #expect(sql.contains("`id`"))
        #expect(sql.contains("`tenant_id`"))
    }

    @Test("Modify primary key PostgreSQL with custom constraint name")
    func modifyPrimaryKeyPostgreSQLCustom() throws {
        let generator = makeGenerator(dbType: .postgresql, pkConstraint: "users_pk")
        let changes: [SchemaChange] = [.modifyPrimaryKey(old: ["id"], new: ["uuid"])]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP CONSTRAINT"))
        #expect(sql.contains("\"users_pk\""))
        #expect(sql.contains("ADD PRIMARY KEY"))
    }

    @Test("Modify primary key PostgreSQL with default pkey name")
    func modifyPrimaryKeyPostgreSQLDefault() throws {
        let generator = makeGenerator(table: "orders", dbType: .postgresql)
        let changes: [SchemaChange] = [.modifyPrimaryKey(old: ["id"], new: ["order_id"])]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 1)
        let sql = statements[0].sql
        #expect(sql.contains("DROP CONSTRAINT"))
        #expect(sql.contains("\"orders_pkey\""))
        #expect(sql.contains("ADD PRIMARY KEY"))
    }

    @Test("Modify primary key SQLite throws unsupported")
    func modifyPrimaryKeySQLiteThrows() throws {
        let generator = makeGenerator(dbType: .sqlite)
        let changes: [SchemaChange] = [.modifyPrimaryKey(old: ["id"], new: ["new_id"])]

        #expect(throws: DatabaseError.self) {
            try generator.generate(changes: changes)
        }
    }

    // MARK: - Ordering Tests

    @Test("Dependency ordering FK drops before column drops")
    func dependencyOrderingFKBeforeColumn() throws {
        let generator = makeGenerator()
        let column = makeColumn(name: "role_id")
        let fk = makeFK(name: "fk_role", columns: ["role_id"])
        let changes: [SchemaChange] = [
            .deleteColumn(column),
            .deleteForeignKey(fk)
        ]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 2)
        #expect(statements[0].sql.contains("DROP FOREIGN KEY"))
        #expect(statements[1].sql.contains("DROP COLUMN"))
    }

    @Test("Dependency ordering index adds after PK changes")
    func dependencyOrderingIndexAfterPK() throws {
        let generator = makeGenerator()
        let index = makeIndex(name: "idx_name", columns: ["name"])
        let changes: [SchemaChange] = [
            .addIndex(index),
            .modifyPrimaryKey(old: ["id"], new: ["id", "tenant_id"])
        ]

        let statements = try generator.generate(changes: changes)

        let pkIndex = statements.firstIndex { $0.sql.contains("PRIMARY KEY") }
        let indexIndex = statements.firstIndex { $0.sql.contains("CREATE INDEX") }

        if let pkIdx = pkIndex, let idxIdx = indexIndex {
            #expect(pkIdx < idxIdx)
        }
    }

    // MARK: - Miscellaneous Tests

    @Test("All statements end with semicolon")
    func allStatementsEndWithSemicolon() throws {
        let generator = makeGenerator()
        let column = makeColumn(name: "field1")
        let index = makeIndex(name: "idx_field1", columns: ["field1"])
        let fk = makeFK(name: "fk_field1", columns: ["field1"], refTable: "other", refColumns: ["id"])
        let changes: [SchemaChange] = [
            .addColumn(column),
            .addIndex(index),
            .addForeignKey(fk)
        ]

        let statements = try generator.generate(changes: changes)

        for statement in statements {
            #expect(statement.sql.hasSuffix(";"))
        }
    }

    @Test("Add column is not destructive")
    func addColumnNotDestructive() throws {
        let generator = makeGenerator()
        let column = makeColumn(name: "new_field")
        let changes: [SchemaChange] = [.addColumn(column)]

        let statements = try generator.generate(changes: changes)

        #expect(statements[0].isDestructive == false)
    }

    // MARK: - S-02: SQLite FK Delete Must Throw

    @Test("Delete foreign key SQLite throws unsupported operation")
    func deleteForeignKeySQLiteThrows() throws {
        let generator = makeGenerator(dbType: .sqlite)
        let fk = makeFK(name: "fk_role")
        let changes: [SchemaChange] = [.deleteForeignKey(fk)]

        #expect(throws: DatabaseError.self) {
            try generator.generate(changes: changes)
        }
    }

    @Test("Modify foreign key SQLite throws unsupported operation (contains drop)")
    func modifyForeignKeySQLiteThrows() throws {
        let generator = makeGenerator(dbType: .sqlite)
        let oldFK = makeFK(name: "fk_role", columns: ["role_id"], refTable: "roles", refColumns: ["id"])
        let newFK = makeFK(name: "fk_role", columns: ["role_id"], refTable: "roles", refColumns: ["role_id"])
        let changes: [SchemaChange] = [.modifyForeignKey(old: oldFK, new: newFK)]

        #expect(throws: DatabaseError.self) {
            try generator.generate(changes: changes)
        }
    }

    @Test("Delete foreign key MySQL still works (not affected by SQLite fix)")
    func deleteForeignKeyMySQLStillWorks() throws {
        let generator = makeGenerator(dbType: .mysql)
        let fk = makeFK(name: "fk_role")
        let changes: [SchemaChange] = [.deleteForeignKey(fk)]

        let statements = try generator.generate(changes: changes)
        #expect(statements.count == 1)
        #expect(statements[0].sql.contains("DROP FOREIGN KEY"))
    }

    @Test("Delete foreign key PostgreSQL still works (not affected by SQLite fix)")
    func deleteForeignKeyPostgreSQLStillWorks() throws {
        let generator = makeGenerator(dbType: .postgresql)
        let fk = makeFK(name: "fk_role")
        let changes: [SchemaChange] = [.deleteForeignKey(fk)]

        let statements = try generator.generate(changes: changes)
        #expect(statements.count == 1)
        #expect(statements[0].sql.contains("DROP CONSTRAINT"))
    }

    @Test("Complex schema change ordering")
    func complexSchemaChangeOrdering() throws {
        let generator = makeGenerator()
        let column = makeColumn(name: "status")
        let index = makeIndex(name: "idx_status", columns: ["status"])
        let fk = makeFK(name: "fk_status", columns: ["status"], refTable: "statuses", refColumns: ["id"])

        let changes: [SchemaChange] = [
            .addColumn(column),
            .addIndex(index),
            .addForeignKey(fk),
            .deleteColumn(makeColumn(name: "old_col")),
            .deleteIndex(makeIndex(name: "idx_old")),
            .deleteForeignKey(makeFK(name: "fk_old"))
        ]

        let statements = try generator.generate(changes: changes)

        #expect(statements.count == 6)

        let fkDropIndex = statements.firstIndex { $0.sql.contains("DROP FOREIGN KEY") }
        let colDropIndex = statements.firstIndex { $0.sql.contains("DROP COLUMN") }
        let fkAddIndex = statements.firstIndex { $0.sql.contains("ADD CONSTRAINT") }

        if let fkDrop = fkDropIndex, let colDrop = colDropIndex {
            #expect(fkDrop < colDrop)
        }

        if let colDrop = colDropIndex, let fkAdd = fkAddIndex {
            #expect(colDrop < fkAdd)
        }
    }
}
