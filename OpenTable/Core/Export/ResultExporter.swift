//
//  ResultExporter.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Service for exporting query results to various formats
enum ResultExporter {
    
    // MARK: - CSV Export
    
    /// Convert query result to CSV format
    static func toCSV(columns: [String], rows: [QueryResultRow]) -> String {
        var csv = ""
        
        // Header row
        csv += columns.map { escapeCSV($0) }.joined(separator: ",")
        csv += "\n"
        
        // Data rows
        for row in rows {
            let values = columns.enumerated().map { index, _ in
                escapeCSV(row.values[safe: index].flatMap { $0 } ?? "")
            }
            csv += values.joined(separator: ",")
            csv += "\n"
        }
        
        return csv
    }
    
    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
    
    // MARK: - JSON Export
    
    /// Convert query result to JSON format
    static func toJSON(columns: [String], rows: [QueryResultRow]) -> String {
        var jsonArray: [[String: Any]] = []
        
        for row in rows {
            var jsonRow: [String: Any] = [:]
            for (index, column) in columns.enumerated() {
                jsonRow[column] = row.values[safe: index] ?? NSNull()
            }
            jsonArray.append(jsonRow)
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }
    
    // MARK: - File Export
    
    /// Show save dialog and export to CSV
    static func exportToCSVFile(columns: [String], rows: [QueryResultRow]) {
        let csv = toCSV(columns: columns, rows: rows)
        saveToFile(content: csv, defaultName: "export.csv", fileType: "csv")
    }
    
    /// Show save dialog and export to JSON
    static func exportToJSONFile(columns: [String], rows: [QueryResultRow]) {
        let json = toJSON(columns: columns, rows: rows)
        saveToFile(content: json, defaultName: "export.json", fileType: "json")
    }
    
    private static func saveToFile(content: String, defaultName: String, fileType: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.init(filenameExtension: fileType)!]
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to save file: \(error)")
            }
        }
    }
    
    // MARK: - Clipboard
    
    /// Copy results to clipboard as tab-separated values
    static func copyToClipboard(columns: [String], rows: [QueryResultRow]) {
        var tsv = columns.joined(separator: "\t") + "\n"
        
        for row in rows {
            let values = columns.enumerated().map { index, _ in
                row.values[safe: index].flatMap { $0 } ?? ""
            }
            tsv += values.joined(separator: "\t") + "\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tsv, forType: .string)
    }
}
