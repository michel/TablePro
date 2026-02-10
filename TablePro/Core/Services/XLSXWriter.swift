//
//  XLSXWriter.swift
//  TablePro
//
//  Lightweight XLSX writer that creates Excel files without external dependencies.
//  XLSX format = ZIP archive containing XML files (Office Open XML).
//

import Foundation
import os

/// Writes data to XLSX format using raw ZIP file construction
final class XLSXWriter {
    private static let logger = Logger(subsystem: "com.TablePro", category: "XLSXWriter")

    /// Shared strings table for deduplication
    private var sharedStrings: [String] = []
    private var sharedStringIndex: [String: Int] = [:]

    /// Worksheet data (one per table)
    private var sheets: [(name: String, rows: [[CellValue]])] = []

    enum CellValue {
        case string(String)
        case number(String)
        case empty
    }

    /// Add a worksheet with the given name, columns, and rows
    func addSheet(name: String, columns: [String], rows: [[String?]], includeHeader: Bool, convertNullToEmpty: Bool) {
        var sheetRows: [[CellValue]] = []

        if includeHeader {
            sheetRows.append(columns.map { .string($0) })
        }

        for row in rows {
            let cellRow: [CellValue] = row.map { value in
                guard let val = value else {
                    return convertNullToEmpty ? .empty : .string("NULL")
                }
                if val.isEmpty {
                    return .empty
                }
                // Try to detect numeric values
                if let _ = Double(val), !val.hasPrefix("0") || val == "0" || val.contains(".") {
                    return .number(val)
                }
                return .string(val)
            }
            sheetRows.append(cellRow)
        }

        // Sanitize sheet name for Excel (max 31 chars, no special chars)
        let sanitized = sanitizeSheetName(name)
        sheets.append((name: sanitized, rows: sheetRows))
    }

    /// Write the XLSX file to the given URL
    func write(to url: URL) throws {
        // Build shared strings from all sheets
        buildSharedStrings()

        // Create ZIP entries
        var entries: [ZipFileEntry] = []

        entries.append(ZipFileEntry(path: "[Content_Types].xml", data: contentTypesXML()))
        entries.append(ZipFileEntry(path: "_rels/.rels", data: relsXML()))
        entries.append(ZipFileEntry(path: "xl/workbook.xml", data: workbookXML()))
        entries.append(ZipFileEntry(path: "xl/_rels/workbook.xml.rels", data: workbookRelsXML()))
        entries.append(ZipFileEntry(path: "xl/styles.xml", data: stylesXML()))

        if !sharedStrings.isEmpty {
            entries.append(ZipFileEntry(path: "xl/sharedStrings.xml", data: sharedStringsXML()))
        }

        for (index, sheet) in sheets.enumerated() {
            entries.append(ZipFileEntry(
                path: "xl/worksheets/sheet\(index + 1).xml",
                data: worksheetXML(for: sheet.rows)
            ))
        }

        let zipData = ZipBuilder.build(entries: entries)
        try zipData.write(to: url)
    }

    // MARK: - Shared Strings

    private func buildSharedStrings() {
        sharedStrings = []
        sharedStringIndex = [:]

        for sheet in sheets {
            for row in sheet.rows {
                for cell in row {
                    if case .string(let value) = cell {
                        if sharedStringIndex[value] == nil {
                            sharedStringIndex[value] = sharedStrings.count
                            sharedStrings.append(value)
                        }
                    }
                }
            }
        }
    }

    // MARK: - XML Generation

    private func contentTypesXML() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        xml += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        xml += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        xml += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        xml += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        if !sharedStrings.isEmpty {
            xml += "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>"
        }
        for (index, _) in sheets.enumerated() {
            xml += "<Override PartName=\"/xl/worksheets/sheet\(index + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        xml += "</Types>"
        return Data(xml.utf8)
    }

    private func relsXML() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        xml += "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
        xml += "</Relationships>"
        return Data(xml.utf8)
    }

    private func workbookXML() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        xml += "<sheets>"
        for (index, sheet) in sheets.enumerated() {
            xml += "<sheet name=\"\(escapeXML(sheet.name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }
        xml += "</sheets>"
        xml += "</workbook>"
        return Data(xml.utf8)
    }

    private func workbookRelsXML() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for (index, _) in sheets.enumerated() {
            xml += "<Relationship Id=\"rId\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index + 1).xml\"/>"
        }
        let nextId = sheets.count + 1
        xml += "<Relationship Id=\"rId\(nextId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        if !sharedStrings.isEmpty {
            xml += "<Relationship Id=\"rId\(nextId + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>"
        }
        xml += "</Relationships>"
        return Data(xml.utf8)
    }

    private func stylesXML() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        xml += "<fonts count=\"2\">"
        xml += "<font><sz val=\"11\"/><name val=\"Calibri\"/></font>"
        xml += "<font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font>"
        xml += "</fonts>"
        xml += "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
        xml += "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
        xml += "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        xml += "<cellXfs count=\"2\">"
        xml += "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
        xml += "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
        xml += "</cellXfs>"
        xml += "</styleSheet>"
        return Data(xml.utf8)
    }

    private func sharedStringsXML() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(sharedStrings.count)\" uniqueCount=\"\(sharedStrings.count)\">"
        for str in sharedStrings {
            xml += "<si><t>\(escapeXML(str))</t></si>"
        }
        xml += "</sst>"
        return Data(xml.utf8)
    }

    private func worksheetXML(for rows: [[CellValue]]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        xml += "<sheetData>"

        for (rowIndex, row) in rows.enumerated() {
            let rowNum = rowIndex + 1
            // First row gets bold style (s="1") if it's a header
            let isHeader = rowIndex == 0
            xml += "<row r=\"\(rowNum)\">"
            for (colIndex, cell) in row.enumerated() {
                let cellRef = columnLetter(colIndex) + "\(rowNum)"
                switch cell {
                case .string(let value):
                    if let ssIndex = sharedStringIndex[value] {
                        let style = isHeader ? " s=\"1\"" : ""
                        xml += "<c r=\"\(cellRef)\" t=\"s\"\(style)><v>\(ssIndex)</v></c>"
                    }
                case .number(let value):
                    xml += "<c r=\"\(cellRef)\"><v>\(escapeXML(value))</v></c>"
                case .empty:
                    break
                }
            }
            xml += "</row>"
        }

        xml += "</sheetData>"
        xml += "</worksheet>"
        return Data(xml.utf8)
    }

    // MARK: - Helpers

    private func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func columnLetter(_ index: Int) -> String {
        var result = ""
        var n = index
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    private func sanitizeSheetName(_ name: String) -> String {
        var sanitized = name
        // Remove characters invalid for sheet names
        let invalid: [Character] = ["\\", "/", "?", "*", "[", "]", ":"]
        sanitized = String(sanitized.filter { !invalid.contains($0) })
        // Truncate to 31 chars (Excel limit)
        if sanitized.count > 31 {
            sanitized = String(sanitized.prefix(31))
        }
        if sanitized.isEmpty {
            sanitized = "Sheet"
        }
        return sanitized
    }
}

// MARK: - ZIP File Builder

/// Minimal ZIP file builder (store-only, no compression)
private struct ZipFileEntry {
    let path: String
    let data: Data
}

private enum ZipBuilder {
    static func build(entries: [ZipFileEntry]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            offsets.append(UInt32(output.count))

            let pathData = Data(entry.path.utf8)
            let crc = crc32(entry.data)

            // Local file header
            output.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])  // Signature
            output.appendUInt16(20)                                 // Version needed
            output.appendUInt16(0)                                  // Flags
            output.appendUInt16(0)                                  // Compression: stored
            output.appendUInt16(0)                                  // Mod time
            output.appendUInt16(0)                                  // Mod date
            output.appendUInt32(crc)                                // CRC-32
            output.appendUInt32(UInt32(entry.data.count))           // Compressed size
            output.appendUInt32(UInt32(entry.data.count))           // Uncompressed size
            output.appendUInt16(UInt16(pathData.count))             // File name length
            output.appendUInt16(0)                                  // Extra field length
            output.append(pathData)
            output.append(entry.data)

            // Central directory entry
            centralDirectory.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])  // Signature
            centralDirectory.appendUInt16(20)                                // Version made by
            centralDirectory.appendUInt16(20)                                // Version needed
            centralDirectory.appendUInt16(0)                                 // Flags
            centralDirectory.appendUInt16(0)                                 // Compression
            centralDirectory.appendUInt16(0)                                 // Mod time
            centralDirectory.appendUInt16(0)                                 // Mod date
            centralDirectory.appendUInt32(crc)                               // CRC-32
            centralDirectory.appendUInt32(UInt32(entry.data.count))          // Compressed size
            centralDirectory.appendUInt32(UInt32(entry.data.count))          // Uncompressed size
            centralDirectory.appendUInt16(UInt16(pathData.count))            // File name length
            centralDirectory.appendUInt16(0)                                 // Extra field length
            centralDirectory.appendUInt16(0)                                 // Comment length
            centralDirectory.appendUInt16(0)                                 // Disk number start
            centralDirectory.appendUInt16(0)                                 // Internal attributes
            centralDirectory.appendUInt32(0)                                 // External attributes
            centralDirectory.appendUInt32(offsets.last!)                     // Local header offset
            centralDirectory.append(pathData)
        }

        let centralDirOffset = UInt32(output.count)
        output.append(centralDirectory)

        // End of central directory
        output.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])     // Signature
        output.appendUInt16(0)                                    // Disk number
        output.appendUInt16(0)                                    // Central dir disk
        output.appendUInt16(UInt16(entries.count))                // Entries on disk
        output.appendUInt16(UInt16(entries.count))                // Total entries
        output.appendUInt32(UInt32(centralDirectory.count))       // Central dir size
        output.appendUInt32(centralDirOffset)                     // Central dir offset
        output.appendUInt16(0)                                    // Comment length

        return output
    }

    /// CRC-32 calculation (IEEE 802.3 polynomial)
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Data Extensions for ZIP

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { append(contentsOf: $0) }
    }
}
