//
//  ColumnTypeSpatialTests.swift
//  TableProTests
//
//  Tests for ColumnType spatial type mapping and properties.
//

import Foundation
@testable import TablePro
import Testing

@Suite("Column Type Spatial")
struct ColumnTypeSpatialTests {
    // MARK: - MySQL Type Mapping

    @Test("MySQL type 255 creates spatial")
    func mysqlType255IsSpatial() {
        let type = ColumnType(fromMySQLType: 255, rawType: "GEOMETRY")
        if case .spatial = type {
            // pass
        } else {
            Issue.record("Expected .spatial, got \(type)")
        }
    }

    @Test("MySQL type 255 preserves rawType")
    func mysqlType255PreservesRawType() {
        let type = ColumnType(fromMySQLType: 255, rawType: "GEOMETRY")
        #expect(type.rawType == "GEOMETRY")
    }

    // MARK: - PostgreSQL Type Mapping

    @Test("PostgreSQL OID 600 creates spatial (point)")
    func postgresqlOid600IsSpatial() {
        let type = ColumnType(fromPostgreSQLOid: 600, rawType: "point")
        if case .spatial = type {
            // pass
        } else {
            Issue.record("Expected .spatial, got \(type)")
        }
    }

    @Test("PostgreSQL OID 601 creates spatial (lseg)")
    func postgresqlOid601IsSpatial() {
        let type = ColumnType(fromPostgreSQLOid: 601, rawType: "lseg")
        if case .spatial = type {
            // pass
        } else {
            Issue.record("Expected .spatial, got \(type)")
        }
    }

    @Test("PostgreSQL OID 602 creates spatial (path)")
    func postgresqlOid602IsSpatial() {
        let type = ColumnType(fromPostgreSQLOid: 602, rawType: "path")
        if case .spatial = type {
            // pass
        } else {
            Issue.record("Expected .spatial, got \(type)")
        }
    }

    @Test("PostgreSQL OID 603 creates spatial (box)")
    func postgresqlOid603IsSpatial() {
        let type = ColumnType(fromPostgreSQLOid: 603, rawType: "box")
        if case .spatial = type {
            // pass
        } else {
            Issue.record("Expected .spatial, got \(type)")
        }
    }

    @Test("PostgreSQL OID 604 creates spatial (polygon)")
    func postgresqlOid604IsSpatial() {
        let type = ColumnType(fromPostgreSQLOid: 604, rawType: "polygon")
        if case .spatial = type {
            // pass
        } else {
            Issue.record("Expected .spatial, got \(type)")
        }
    }

    @Test("PostgreSQL OID 628 creates spatial (line)")
    func postgresqlOid628IsSpatial() {
        let type = ColumnType(fromPostgreSQLOid: 628, rawType: "line")
        if case .spatial = type {
            // pass
        } else {
            Issue.record("Expected .spatial, got \(type)")
        }
    }

    @Test("PostgreSQL OID 718 creates spatial (circle)")
    func postgresqlOid718IsSpatial() {
        let type = ColumnType(fromPostgreSQLOid: 718, rawType: "circle")
        if case .spatial = type {
            // pass
        } else {
            Issue.record("Expected .spatial, got \(type)")
        }
    }

    @Test("SQLite POINT type does not create spatial")
    func sqlitePointIsNotSpatial() {
        let type = ColumnType(fromSQLiteType: "POINT")
        if case .spatial = type {
            Issue.record("Expected .text, got .spatial")
        }
    }

    // MARK: - Display Properties

    @Test("spatial displayName is Spatial")
    func spatialDisplayName() {
        let type = ColumnType.spatial(rawType: "GEOMETRY")
        #expect(type.displayName == "Spatial")
    }

    @Test("spatial badgeLabel is spatial")
    func spatialBadgeLabel() {
        let type = ColumnType.spatial(rawType: "GEOMETRY")
        #expect(type.badgeLabel == "spatial")
    }

    @Test("spatial with nil rawType returns spatial badge")
    func spatialNilRawTypeBadge() {
        let type = ColumnType.spatial(rawType: nil)
        #expect(type.badgeLabel == "spatial")
    }

    @Test("spatial rawType preserves value")
    func spatialRawTypePreserved() {
        let type = ColumnType.spatial(rawType: "point")
        #expect(type.rawType == "point")
    }

    // MARK: - Boolean Properties (all false)

    @Test("spatial is not JSON type")
    func spatialIsNotJsonType() {
        let type = ColumnType.spatial(rawType: nil)
        #expect(!type.isJsonType)
    }

    @Test("spatial is not date type")
    func spatialIsNotDateType() {
        let type = ColumnType.spatial(rawType: nil)
        #expect(!type.isDateType)
    }

    @Test("spatial is not long text")
    func spatialIsNotLongText() {
        let type = ColumnType.spatial(rawType: nil)
        #expect(!type.isLongText)
    }

    @Test("spatial is not enum type")
    func spatialIsNotEnumType() {
        let type = ColumnType.spatial(rawType: nil)
        #expect(!type.isEnumType)
    }

    @Test("spatial is not set type")
    func spatialIsNotSetType() {
        let type = ColumnType.spatial(rawType: nil)
        #expect(!type.isSetType)
    }

    @Test("spatial is not boolean type")
    func spatialIsNotBooleanType() {
        let type = ColumnType.spatial(rawType: nil)
        #expect(!type.isBooleanType)
    }

    @Test("spatial enumValues returns nil")
    func spatialEnumValuesNil() {
        let type = ColumnType.spatial(rawType: nil)
        #expect(type.enumValues == nil)
    }
}
