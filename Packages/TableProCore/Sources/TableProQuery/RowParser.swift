import Foundation

public protocol RowDataParser: Sendable {
    func parse(text: String, columns: [String]) throws -> [[String?]]
}

public enum RowParserError: Error, LocalizedError {
    case invalidFormat(String)
    case columnCountMismatch(expected: Int, got: Int, row: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid format: \(message)"
        case .columnCountMismatch(let expected, let got, let row):
            return "Row \(row): expected \(expected) columns but got \(got)"
        }
    }
}

public struct TSVRowParser: RowDataParser, Sendable {
    public init() {}

    public func parse(text: String, columns: [String]) throws -> [[String?]] {
        let lines = text.components(separatedBy: .newlines)
        var result: [[String?]] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let values = line.components(separatedBy: "\t")
            let row: [String?] = values.map { value in
                let trimmedValue = value.trimmingCharacters(in: .whitespaces)
                if trimmedValue == "NULL" || trimmedValue == "\\N" {
                    return nil
                }
                return trimmedValue
            }

            if !columns.isEmpty && row.count != columns.count {
                throw RowParserError.columnCountMismatch(
                    expected: columns.count,
                    got: row.count,
                    row: index + 1
                )
            }

            result.append(row)
        }

        return result
    }
}

public struct CSVRowParser: RowDataParser, Sendable {
    public init() {}

    public func parse(text: String, columns: [String]) throws -> [[String?]] {
        let lines = text.components(separatedBy: .newlines)
        var result: [[String?]] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let values = parseCSVLine(line)
            let row: [String?] = values.map { value in
                let trimmedValue = value.trimmingCharacters(in: .whitespaces)
                if trimmedValue == "NULL" {
                    return nil
                }
                return trimmedValue
            }

            if !columns.isEmpty && row.count != columns.count {
                throw RowParserError.columnCountMismatch(
                    expected: columns.count,
                    got: row.count,
                    row: index + 1
                )
            }

            result.append(row)
        }

        return result
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let char = line[i]

            if inQuotes {
                if char == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        i = line.index(after: next)
                    } else {
                        inQuotes = false
                        i = line.index(after: i)
                    }
                } else {
                    current.append(char)
                    i = line.index(after: i)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                    i = line.index(after: i)
                } else if char == "," {
                    fields.append(current)
                    current = ""
                    i = line.index(after: i)
                } else {
                    current.append(char)
                    i = line.index(after: i)
                }
            }
        }

        fields.append(current)
        return fields
    }
}
