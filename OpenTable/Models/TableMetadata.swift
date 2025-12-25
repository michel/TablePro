//
//  TableMetadata.swift
//  OpenTable
//
//  Model for table-level metadata
//

import Foundation

/// Represents table-level metadata fetched from database
struct TableMetadata {
    let tableName: String
    let dataSize: Int64?
    let indexSize: Int64?
    let totalSize: Int64?
    let avgRowLength: Int64?
    let rowCount: Int64?
    let comment: String?
    let engine: String?          // MySQL/MariaDB only
    let collation: String?       // MySQL/MariaDB only
    let createTime: Date?
    let updateTime: Date?
    
    /// Format a size in bytes to human readable format
    static func formatSize(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "—" }
        if bytes == 0 { return "0 B" }
        
        let units = ["B", "KB", "MB", "GB", "TB"]
        let exponent = min(Int(log(Double(bytes)) / log(1024)), units.count - 1)
        let size = Double(bytes) / pow(1024, Double(exponent))
        
        if exponent == 0 {
            return "\(bytes) B"
        } else {
            return String(format: "%.1f %@", size, units[exponent])
        }
    }
    
    /// Returns metadata as an array of key-value pairs for display
    var displayProperties: [(key: String, value: String, type: String)] {
        var properties: [(key: String, value: String, type: String)] = []
        
        properties.append(("data_size", Self.formatSize(dataSize), "size"))
        properties.append(("index_size", Self.formatSize(indexSize), "size"))
        properties.append(("total_size", Self.formatSize(totalSize), "size"))
        
        if let avgRowLength = avgRowLength {
            properties.append(("avg_row_length", "\(avgRowLength)", "number"))
        }
        
        if let rowCount = rowCount {
            properties.append(("row_count", "\(rowCount)", "number"))
        }
        
        if let engine = engine {
            properties.append(("engine", engine, "string"))
        }
        
        if let collation = collation {
            properties.append(("collation", collation, "string"))
        }
        
        properties.append(("comment", comment ?? "EMPTY", "string"))
        
        if let createTime = createTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            properties.append(("create_time", formatter.string(from: createTime), "date"))
        }
        
        if let updateTime = updateTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            properties.append(("update_time", formatter.string(from: updateTime), "date"))
        }
        
        return properties
    }
}
