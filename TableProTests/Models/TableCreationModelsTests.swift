//
//  TableCreationModelsTests.swift
//  TablePro
//
//  Tests for table creation models
//

import Foundation
@testable import TablePro
import Testing

@Suite("Table Creation Models")
struct TableCreationModelsTests {
    // MARK: - ColumnDefinition.isValid Tests

    @Test("ColumnDefinition.isValid returns true for valid definition")
    func columnDefinitionValidIsTrue() {
        let column = ColumnDefinition(name: "id", dataType: "INT")
        #expect(column.isValid == true)
    }

    @Test("ColumnDefinition.isValid returns false when name is empty")
    func columnDefinitionInvalidEmptyName() {
        let column = ColumnDefinition(name: "", dataType: "INT")
        #expect(column.isValid == false)
    }

    @Test("ColumnDefinition.isValid returns false when dataType is empty")
    func columnDefinitionInvalidEmptyDataType() {
        let column = ColumnDefinition(name: "id", dataType: "")
        #expect(column.isValid == false)
    }

    // MARK: - ColumnDefinition.fullDataType Tests

    @Test("fullDataType returns type without length when length is nil")
    func fullDataTypeNoLength() {
        let column = ColumnDefinition(name: "id", dataType: "int", length: nil)
        #expect(column.fullDataType == "INT")
    }

    @Test("fullDataType returns type with length when length is specified")
    func fullDataTypeWithLength() {
        let column = ColumnDefinition(name: "name", dataType: "varchar", length: 255)
        #expect(column.fullDataType == "VARCHAR(255)")
    }

    @Test("fullDataType returns type with length and precision when both specified")
    func fullDataTypeWithLengthAndPrecision() {
        let column = ColumnDefinition(name: "price", dataType: "decimal", length: 10, precision: 2)
        #expect(column.fullDataType == "DECIMAL(10,2)")
    }

    // MARK: - ColumnDefinition.needsLength Tests

    @Test("needsLength returns true for VARCHAR")
    func needsLengthVarchar() {
        let column = ColumnDefinition(name: "name", dataType: "VARCHAR")
        #expect(column.needsLength(for: .mysql) == true)
    }

    @Test("needsLength returns false for INT")
    func needsLengthInt() {
        let column = ColumnDefinition(name: "id", dataType: "INT")
        #expect(column.needsLength(for: .mysql) == false)
    }

    @Test("needsLength returns true for CHAR")
    func needsLengthChar() {
        let column = ColumnDefinition(name: "code", dataType: "CHAR")
        #expect(column.needsLength(for: .mysql) == true)
    }

    @Test("needsLength returns true for VARBINARY")
    func needsLengthVarbinary() {
        let column = ColumnDefinition(name: "data", dataType: "VARBINARY")
        #expect(column.needsLength(for: .mysql) == true)
    }

    @Test("needsLength returns true for BINARY")
    func needsLengthBinary() {
        let column = ColumnDefinition(name: "data", dataType: "BINARY")
        #expect(column.needsLength(for: .mysql) == true)
    }

    // MARK: - ColumnDefinition.supportsAutoIncrement Tests

    @Test("supportsAutoIncrement returns true for INT")
    func supportsAutoIncrementInt() {
        let column = ColumnDefinition(name: "id", dataType: "INT")
        #expect(column.supportsAutoIncrement(for: .mysql) == true)
    }

    @Test("supportsAutoIncrement returns false for VARCHAR")
    func supportsAutoIncrementVarchar() {
        let column = ColumnDefinition(name: "name", dataType: "VARCHAR")
        #expect(column.supportsAutoIncrement(for: .mysql) == false)
    }

    @Test("supportsAutoIncrement returns true for BIGINT")
    func supportsAutoIncrementBigint() {
        let column = ColumnDefinition(name: "id", dataType: "BIGINT")
        #expect(column.supportsAutoIncrement(for: .mysql) == true)
    }

    @Test("supportsAutoIncrement returns true for SMALLINT")
    func supportsAutoIncrementSmallint() {
        let column = ColumnDefinition(name: "id", dataType: "SMALLINT")
        #expect(column.supportsAutoIncrement(for: .mysql) == true)
    }

    // MARK: - TableCreationOptions.isValid Tests

    @Test("TableCreationOptions.isValid returns true for valid options")
    func tableCreationOptionsValid() {
        let options = TableCreationOptions(
            tableName: "users",
            columns: [
                ColumnDefinition(name: "id", dataType: "INT"),
                ColumnDefinition(name: "name", dataType: "VARCHAR")
            ]
        )
        #expect(options.isValid == true)
    }

    @Test("TableCreationOptions.isValid returns false when tableName is empty")
    func tableCreationOptionsInvalidEmptyTableName() {
        let options = TableCreationOptions(
            tableName: "",
            columns: [ColumnDefinition(name: "id", dataType: "INT")]
        )
        #expect(options.isValid == false)
    }

    @Test("TableCreationOptions.isValid returns false when columns is empty")
    func tableCreationOptionsInvalidEmptyColumns() {
        let options = TableCreationOptions(tableName: "users", columns: [])
        #expect(options.isValid == false)
    }

    @Test("TableCreationOptions.isValid returns false when column names are duplicated")
    func tableCreationOptionsInvalidDuplicateColumns() {
        let options = TableCreationOptions(
            tableName: "users",
            columns: [
                ColumnDefinition(name: "id", dataType: "INT"),
                ColumnDefinition(name: "ID", dataType: "VARCHAR")
            ]
        )
        #expect(options.isValid == false)
    }

    @Test("TableCreationOptions.isValid returns false when any column is invalid")
    func tableCreationOptionsInvalidColumn() {
        let options = TableCreationOptions(
            tableName: "users",
            columns: [
                ColumnDefinition(name: "id", dataType: "INT"),
                ColumnDefinition(name: "", dataType: "VARCHAR")
            ]
        )
        #expect(options.isValid == false)
    }

    // MARK: - TableCreationOptions.hasPrimaryKey Tests

    @Test("hasPrimaryKey returns true when primaryKeyColumns is not empty")
    func hasPrimaryKeyTrue() {
        let options = TableCreationOptions(
            tableName: "users",
            columns: [ColumnDefinition(name: "id", dataType: "INT")],
            primaryKeyColumns: ["id"]
        )
        #expect(options.hasPrimaryKey == true)
    }

    @Test("hasPrimaryKey returns false when primaryKeyColumns is empty")
    func hasPrimaryKeyFalse() {
        let options = TableCreationOptions(
            tableName: "users",
            columns: [ColumnDefinition(name: "id", dataType: "INT")],
            primaryKeyColumns: []
        )
        #expect(options.hasPrimaryKey == false)
    }

    // MARK: - ColumnTemplate.createColumn Tests

    @Test("ColumnTemplate.id creates INT column with autoIncrement for MySQL")
    func columnTemplateIdMySQL() {
        let column = ColumnTemplate.id.createColumn(for: .mysql)
        #expect(column.name == "id")
        #expect(column.dataType == "INT")
        #expect(column.autoIncrement == true)
        #expect(column.notNull == true)
    }

    @Test("ColumnTemplate.uuid creates UUID column for PostgreSQL")
    func columnTemplateUuidPostgreSQL() {
        let column = ColumnTemplate.uuid.createColumn(for: .postgresql)
        #expect(column.name == "id")
        #expect(column.dataType == "UUID")
        #expect(column.length == nil)
        #expect(column.notNull == true)
    }

    @Test("ColumnTemplate.uuid creates VARCHAR(36) column for MySQL")
    func columnTemplateUuidMySQL() {
        let column = ColumnTemplate.uuid.createColumn(for: .mysql)
        #expect(column.name == "id")
        #expect(column.dataType == "VARCHAR")
        #expect(column.length == 36)
        #expect(column.notNull == true)
    }

    @Test("ColumnTemplate.name creates VARCHAR(255) column")
    func columnTemplateName() {
        let column = ColumnTemplate.name.createColumn(for: .mysql)
        #expect(column.name == "name")
        #expect(column.dataType == "VARCHAR")
        #expect(column.length == 255)
        #expect(column.notNull == true)
        #expect(column.defaultValue == "''")
    }

    @Test("ColumnTemplate.createdAt has CURRENT_TIMESTAMP default for PostgreSQL")
    func columnTemplateCreatedAtPostgreSQL() {
        let column = ColumnTemplate.createdAt.createColumn(for: .postgresql)
        #expect(column.name == "created_at")
        #expect(column.dataType == "TIMESTAMP")
        #expect(column.notNull == true)
        #expect(column.defaultValue == "CURRENT_TIMESTAMP")
    }

    @Test("ColumnTemplate.createdAt has NOW() default for MySQL")
    func columnTemplateCreatedAtMySQL() {
        let column = ColumnTemplate.createdAt.createColumn(for: .mysql)
        #expect(column.name == "created_at")
        #expect(column.dataType == "TIMESTAMP")
        #expect(column.notNull == true)
        #expect(column.defaultValue == "NOW()")
    }

    @Test("ColumnTemplate.isActive creates BOOLEAN column for PostgreSQL")
    func columnTemplateIsActivePostgreSQL() {
        let column = ColumnTemplate.isActive.createColumn(for: .postgresql)
        #expect(column.name == "is_active")
        #expect(column.dataType == "BOOLEAN")
        #expect(column.length == nil)
        #expect(column.notNull == true)
        #expect(column.defaultValue == "TRUE")
    }

    @Test("ColumnTemplate.isActive creates TINYINT(1) column for MySQL")
    func columnTemplateIsActiveMySQL() {
        let column = ColumnTemplate.isActive.createColumn(for: .mysql)
        #expect(column.name == "is_active")
        #expect(column.dataType == "TINYINT")
        #expect(column.length == 1)
        #expect(column.notNull == true)
        #expect(column.defaultValue == "1")
    }
}
