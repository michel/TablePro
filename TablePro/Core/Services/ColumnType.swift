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
    case text
    case integer
    case decimal
    case date
    case timestamp
    case datetime
    case boolean
    case blob
    
    // MARK: - MySQL Type Mapping
    
    /// Initialize from MySQL MYSQL_TYPE_* enum value
    /// Reference: https://dev.mysql.com/doc/c-api/8.0/en/c-api-data-structures.html
    init(fromMySQLType type: UInt32) {
        switch type {
        // Integer types
        case 1, 2, 3, 8, 9:  // TINY, SHORT, LONG, LONGLONG, INT24
            self = .integer
            
        // Decimal types
        case 4, 5, 246:  // FLOAT, DOUBLE, NEWDECIMAL
            self = .decimal
            
        // Date/time types
        case 10:  // DATE
            self = .date
        case 7:   // TIMESTAMP
            self = .timestamp
        case 12:  // DATETIME
            self = .datetime
        case 11:  // TIME
            self = .timestamp  // Treat TIME as timestamp for formatting
            
        // Boolean (TINYINT(1))
        // Note: MySQL doesn't have a dedicated boolean type
        // We detect TINYINT(1) in the driver itself
            
        // Binary/blob types
        case 249, 250, 251, 252:  // TINY_BLOB, MEDIUM_BLOB, LONG_BLOB, BLOB
            self = .blob
            
        // Text types (default)
        default:
            self = .text
        }
    }
    
    /// Initialize from MySQL field metadata with size hint for boolean detection
    init(fromMySQLType type: UInt32, length: UInt64) {
        // Special case: TINYINT(1) is often used for boolean
        if type == 1 && length == 1 {
            self = .boolean
        } else {
            self.init(fromMySQLType: type)
        }
    }
    
    // MARK: - PostgreSQL Type Mapping
    
    /// Initialize from PostgreSQL Oid
    /// Reference: https://www.postgresql.org/docs/current/datatype-oid.html
    init(fromPostgreSQLOid oid: UInt32) {
        switch oid {
        // Boolean
        case 16:  // BOOLOID
            self = .boolean
            
        // Integer types
        case 20, 21, 23, 26:  // INT8, INT2, INT4, OID
            self = .integer
            
        // Decimal types
        case 700, 701, 1700:  // FLOAT4, FLOAT8, NUMERIC
            self = .decimal
            
        // Date/time types
        case 1082:  // DATE
            self = .date
        case 1083, 1266:  // TIME, TIMETZ
            self = .timestamp
        case 1114, 1184:  // TIMESTAMP, TIMESTAMPTZ
            self = .timestamp
            
        // Binary types
        case 17:  // BYTEA
            self = .blob
            
        // Text types (default)
        default:
            self = .text
        }
    }
    
    // MARK: - SQLite Type Mapping
    
    /// Initialize from SQLite declared type string
    /// SQLite uses type affinity rules: https://www.sqlite.org/datatype3.html
    init(fromSQLiteType declaredType: String?) {
        guard let type = declaredType?.uppercased() else {
            self = .text
            return
        }
        
        // SQLite type affinity rules
        if type.contains("INT") {
            self = .integer
        } else if type.contains("CHAR") || type.contains("CLOB") || type.contains("TEXT") {
            self = .text
        } else if type.contains("BLOB") || type.isEmpty {
            self = .blob
        } else if type.contains("REAL") || type.contains("FLOA") || type.contains("DOUB") {
            self = .decimal
        } else if type.contains("DATE") && !type.contains("TIME") {
            self = .date
        } else if type.contains("TIME") || type.contains("TIMESTAMP") {
            self = .timestamp
        } else if type.contains("BOOL") {
            self = .boolean
        } else {
            // Numeric affinity (catch-all for numeric types)
            self = .text
        }
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
}
