//
//  ColumnType.swift
//  TablePro
//
//  Column type metadata for type-aware formatting and display.
//  Extracted from database drivers and used throughout the app.
//

import Foundation

/// Represents the semantic type of a database column
enum ColumnType: Equatable {
    case text(rawType: String?)
    case integer(rawType: String?)
    case decimal(rawType: String?)
    case date(rawType: String?)
    case timestamp(rawType: String?)
    case datetime(rawType: String?)
    case boolean(rawType: String?)
    case blob(rawType: String?)
    case json(rawType: String?)
    case enumType(rawType: String?, values: [String]?)
    case set(rawType: String?, values: [String]?)
    case spatial(rawType: String?)

    /// Raw database type name (e.g., "LONGTEXT", "VARCHAR(255)", "CLOB")
    var rawType: String? {
        switch self {
        case .text(let raw), .integer(let raw), .decimal(let raw),
             .date(let raw), .timestamp(let raw), .datetime(let raw),
             .boolean(let raw), .blob(let raw), .json(let raw),
             .spatial(let raw):
            return raw
        case .enumType(let raw, _), .set(let raw, _):
            return raw
        }
    }

    // MARK: - MySQL Type Mapping

    /// Initialize from MySQL MYSQL_TYPE_* enum value
    /// Reference: https://dev.mysql.com/doc/c-api/8.0/en/c-api-data-structures.html
    init(fromMySQLType type: UInt32, rawType: String? = nil) {
        switch type {
        // Integer types
        case 1, 2, 3, 8, 9:  // TINY, SHORT, LONG, LONGLONG, INT24
            self = .integer(rawType: rawType)

        // Decimal types
        case 4, 5, 246:  // FLOAT, DOUBLE, NEWDECIMAL
            self = .decimal(rawType: rawType)

        // Date/time types
        case 10:  // DATE
            self = .date(rawType: rawType)
        case 7:   // TIMESTAMP
            self = .timestamp(rawType: rawType)
        case 12:  // DATETIME
            self = .datetime(rawType: rawType)
        case 11:  // TIME
            self = .timestamp(rawType: rawType)  // Treat TIME as timestamp for formatting

        // Boolean (TINYINT(1))
        // Note: MySQL doesn't have a dedicated boolean type
        // We detect TINYINT(1) in the driver itself

        // JSON type
        case 245:  // JSON
            self = .json(rawType: rawType)

        // Binary/blob types
        case 249, 250, 251, 252:  // TINY_BLOB, MEDIUM_BLOB, LONG_BLOB, BLOB
            self = .blob(rawType: rawType)

        // Enum/Set types
        case 247:  // ENUM
            self = .enumType(rawType: rawType, values: nil)
        case 248:  // SET
            self = .set(rawType: rawType, values: nil)

        // Geometry type
        case 255:  // GEOMETRY
            self = .spatial(rawType: rawType)

        // Text types (default)
        default:
            self = .text(rawType: rawType)
        }
    }

    /// Initialize from MySQL field metadata with size hint for boolean detection
    init(fromMySQLType type: UInt32, length: UInt64, rawType: String? = nil) {
        // Special case: TINYINT(1) is often used for boolean
        if type == 1 && length == 1 {
            self = .boolean(rawType: rawType)
        } else {
            self.init(fromMySQLType: type, rawType: rawType)
        }
    }

    // MARK: - PostgreSQL Type Mapping

    /// Initialize from PostgreSQL Oid
    /// Reference: https://www.postgresql.org/docs/current/datatype-oid.html
    init(fromPostgreSQLOid oid: UInt32, rawType: String? = nil) {
        switch oid {
        // Boolean
        case 16:  // BOOLOID
            self = .boolean(rawType: rawType)

        // Integer types
        case 20, 21, 23, 26:  // INT8, INT2, INT4, OID
            self = .integer(rawType: rawType)

        // Decimal types
        case 700, 701, 1_700:  // FLOAT4, FLOAT8, NUMERIC
            self = .decimal(rawType: rawType)

        // Date/time types
        case 1_082:  // DATE
            self = .date(rawType: rawType)
        case 1_083, 1_266:  // TIME, TIMETZ
            self = .timestamp(rawType: rawType)
        case 1_114, 1_184:  // TIMESTAMP, TIMESTAMPTZ
            self = .timestamp(rawType: rawType)

        // JSON types
        case 114, 3_802:  // JSON, JSONB
            self = .json(rawType: rawType)

        // Binary types
        case 17:  // BYTEA
            self = .blob(rawType: rawType)

        // Native geometry types
        case 600, 601, 602, 603, 604, 628, 718:  // point, lseg, path, box, polygon, line, circle
            self = .spatial(rawType: rawType)

        // Text types (default)
        default:
            // Check for user-defined enum types (rawType formatted as "ENUM(typename)")
            if let raw = rawType?.uppercased(), raw.hasPrefix("ENUM(") {
                self = .enumType(rawType: rawType, values: nil)
            } else {
                self = .text(rawType: rawType)
            }
        }
    }

    // MARK: - SQLite Type Mapping

    /// Initialize from SQLite declared type string
    /// SQLite uses type affinity rules: https://www.sqlite.org/datatype3.html
    init(fromSQLiteType declaredType: String?) {
        guard let type = declaredType?.uppercased() else {
            self = .text(rawType: declaredType)
            return
        }

        // SQLite type affinity rules
        if type.hasPrefix("ENUM(") {
            self = .enumType(rawType: declaredType, values: nil)
        } else if type.contains("INT") {
            self = .integer(rawType: declaredType)
        } else if type.contains("CHAR") || type.contains("CLOB") || type.contains("TEXT") {
            self = .text(rawType: declaredType)
        } else if type.contains("BLOB") || type.isEmpty {
            self = .blob(rawType: declaredType)
        } else if type.contains("REAL") || type.contains("FLOA") || type.contains("DOUB") {
            self = .decimal(rawType: declaredType)
        } else if type.contains("DATE") && !type.contains("TIME") {
            self = .date(rawType: declaredType)
        } else if type.contains("TIME") || type.contains("TIMESTAMP") {
            self = .timestamp(rawType: declaredType)
        } else if type.contains("BOOL") {
            self = .boolean(rawType: declaredType)
        } else if type.contains("JSON") {
            self = .json(rawType: declaredType)
        } else {
            // Numeric affinity (catch-all for numeric types)
            self = .text(rawType: declaredType)
        }
    }

    // MARK: - Oracle Type Mapping

    init(fromOracleType typeName: String?) {
        guard let type = typeName?.lowercased() else {
            self = .text(rawType: typeName)
            return
        }

        switch type {
        case "integer", "smallint":
            self = .integer(rawType: typeName)
        case "number":
            self = .decimal(rawType: typeName)
        case "float", "binary_float", "binary_double":
            self = .decimal(rawType: typeName)
        case "date":
            self = .date(rawType: typeName)
        case "timestamp", "timestamp with time zone", "timestamp with local time zone":
            self = .timestamp(rawType: typeName)
        case "interval year to month", "interval day to second":
            self = .text(rawType: typeName)
        case "blob", "raw", "long raw", "bfile":
            self = .blob(rawType: typeName)
        case "clob", "nclob", "long":
            self = .text(rawType: typeName)
        case "rowid":
            self = .text(rawType: typeName)
        default:
            self = .text(rawType: typeName)
        }
    }

    // MARK: - MongoDB BSON Type Mapping

    /// Initialize from BSON type integer code
    /// Reference: https://www.mongodb.com/docs/manual/reference/bson-types/
    init(fromBsonType type: Int32) {
        switch type {
        case 1:   // Double
            self = .decimal(rawType: "Double")
        case 2:   // String
            self = .text(rawType: "String")
        case 3:   // Document (embedded)
            self = .json(rawType: "Object")
        case 4:   // Array
            self = .json(rawType: "Array")
        case 5:   // Binary
            self = .blob(rawType: "Binary")
        case 7:   // ObjectId
            self = .text(rawType: "ObjectId")
        case 8:   // Boolean
            self = .boolean(rawType: "Boolean")
        case 9:   // Date
            self = .datetime(rawType: "Date")
        case 10:  // Null
            self = .text(rawType: "Null")
        case 16:  // Int32
            self = .integer(rawType: "Int32")
        case 17:  // Timestamp
            self = .timestamp(rawType: "Timestamp")
        case 18:  // Int64
            self = .integer(rawType: "Int64")
        case 19:  // Decimal128
            self = .decimal(rawType: "Decimal128")
        default:
            self = .text(rawType: nil)
        }
    }

    // MARK: - Redis Type Mapping

    /// Initialize from Redis TYPE command result string
    init(fromRedisType type: String) {
        switch type.lowercased() {
        case "string":
            self = .text(rawType: "String")
        case "list":
            self = .json(rawType: "List")
        case "set":
            self = .json(rawType: "Set")
        case "zset":
            self = .json(rawType: "Sorted Set")
        case "hash":
            self = .json(rawType: "Hash")
        case "stream":
            self = .json(rawType: "Stream")
        case "none":
            self = .text(rawType: "None")
        default:
            self = .text(rawType: type)
        }
    }

    // MARK: - ClickHouse Type Mapping

    /// Initialize from ClickHouse type string
    /// Unwraps Nullable(...) and LowCardinality(...) wrappers before matching the inner type.
    init(fromClickHouseType type: String?) {
        guard let originalType = type else {
            self = .text(rawType: type)
            return
        }

        // Unwrap Nullable(...) and LowCardinality(...) wrappers recursively
        var inner = originalType
        while true {
            let trimmed = inner.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Nullable(") && trimmed.hasSuffix(")") {
                inner = String(trimmed.dropFirst(9).dropLast(1))
            } else if trimmed.hasPrefix("LowCardinality(") && trimmed.hasSuffix(")") {
                inner = String(trimmed.dropFirst(15).dropLast(1))
            } else {
                break
            }
        }

        let upperInner = inner.trimmingCharacters(in: .whitespaces)

        // Integer types
        if upperInner.hasPrefix("UInt") || upperInner.hasPrefix("Int") {
            // Match Int8, Int16, Int32, Int64, Int128, Int256, UInt8, UInt16, UInt32, UInt64, UInt128, UInt256
            let suffix = upperInner.hasPrefix("UInt") ? String(upperInner.dropFirst(4)) : String(upperInner.dropFirst(3))
            if ["8", "16", "32", "64", "128", "256"].contains(suffix) {
                self = .integer(rawType: originalType)
                return
            }
        }

        // Float/Decimal types
        if upperInner == "Float32" || upperInner == "Float64" || upperInner.hasPrefix("Decimal") {
            self = .decimal(rawType: originalType)
            return
        }

        // Date types
        if upperInner == "Date" || upperInner == "Date32" {
            self = .date(rawType: originalType)
            return
        }

        // DateTime types
        if upperInner.hasPrefix("DateTime") {
            self = .datetime(rawType: originalType)
            return
        }

        // Boolean
        if upperInner == "Bool" {
            self = .boolean(rawType: originalType)
            return
        }

        // Text-like types
        if upperInner == "String" || upperInner.hasPrefix("FixedString") ||
            upperInner == "UUID" || upperInner == "IPv4" || upperInner == "IPv6" ||
            upperInner.hasPrefix("Enum8") || upperInner.hasPrefix("Enum16") {
            self = .text(rawType: originalType)
            return
        }

        // Structured/JSON types
        if upperInner.hasPrefix("Array") || upperInner.hasPrefix("Tuple") ||
            upperInner.hasPrefix("Map") || upperInner == "JSON" {
            self = .json(rawType: originalType)
            return
        }

        // Default fallback
        self = .text(rawType: originalType)
    }

    // MARK: - Display Properties

    /// Human-readable name for this column type
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .integer: return "Integer"
        case .decimal: return "Decimal"
        case .date: return "Date"
        case .timestamp: return "Timestamp"
        case .datetime: return "DateTime"
        case .boolean: return "Boolean"
        case .blob: return "Binary"
        case .json: return "JSON"
        case .enumType: return "Enum"
        case .set: return "Set"
        case .spatial: return "Spatial"
        }
    }

    /// Whether this type represents a JSON value that should use JSON editor
    var isJsonType: Bool {
        switch self {
        case .json:
            return true
        default:
            return false
        }
    }

    /// Whether this type represents a date/time value that should be formatted
    var isDateType: Bool {
        switch self {
        case .date, .timestamp, .datetime:
            return true
        default:
            return false
        }
    }

    /// Whether this type represents long text that should use multi-line editor
    /// Checks for TEXT, LONGTEXT, MEDIUMTEXT, TINYTEXT, CLOB types
    var isLongText: Bool {
        guard let raw = rawType?.uppercased() else {
            return false
        }

        // MySQL long text types (exact match to avoid matching VARCHAR, etc.)
        if raw == "TEXT" || raw == "TINYTEXT" || raw == "MEDIUMTEXT" || raw == "LONGTEXT" {
            return true
        }

        // PostgreSQL/SQLite CLOB type
        if raw == "CLOB" {
            return true
        }

        return false
    }

    /// Whether this type is an enum column
    var isEnumType: Bool {
        switch self {
        case .enumType:
            return true
        default:
            return false
        }
    }

    /// Whether this type is a SET column
    var isSetType: Bool {
        switch self {
        case .set:
            return true
        default:
            return false
        }
    }

    var isBooleanType: Bool {
        switch self {
        case .boolean: return true
        default: return false
        }
    }

    /// Compact lowercase badge label for sidebar
    var badgeLabel: String {
        switch self {
        case .boolean: return "bool"
        case .json: return "json"
        case .date, .timestamp, .datetime: return "date"
        case .enumType(let rawType, _):
            return rawType == "RedisType" ? "option" : "enum"
        case .set: return "set"
        case .integer(let rawType):
            return rawType == "RedisInt" ? "second" : "number"
        case .decimal: return "number"
        case .blob: return "binary"
        case .text(let rawType):
            return rawType == "RedisRaw" ? "raw" : "string"
        case .spatial: return "spatial"
        }
    }

    /// The allowed enum/set values, if known
    var enumValues: [String]? {
        switch self {
        case .enumType(_, let values), .set(_, let values):
            return values
        default:
            return nil
        }
    }

    // MARK: - Enum Value Parsing

    /// Parse enum/set values from a type string like "ENUM('a','b','c')" or "SET('x','y')"
    static func parseEnumValues(from typeString: String) -> [String]? {
        let upper = typeString.uppercased()
        guard upper.hasPrefix("ENUM(") || upper.hasPrefix("SET(") else {
            return nil
        }

        // Find the opening paren and closing paren
        guard let openParen = typeString.firstIndex(of: "("),
              let closeParen = typeString.lastIndex(of: ")") else {
            return nil
        }

        let inner = typeString[typeString.index(after: openParen)..<closeParen]

        // Parse comma-separated quoted values: 'val1','val2','val3'
        var values: [String] = []
        var current = ""
        var inQuote = false
        var escaped = false

        for char in inner {
            if escaped {
                current.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "'" {
                inQuote.toggle()
            } else if char == "," && !inQuote {
                values.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            values.append(current)
        }

        // Trim whitespace from values
        values = values.map { $0.trimmingCharacters(in: .whitespaces) }

        return values.isEmpty ? nil : values
    }
}
