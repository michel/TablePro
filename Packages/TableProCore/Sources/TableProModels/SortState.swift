import Foundation

public struct SortState: Codable, Sendable {
    public var columns: [SortColumn]

    public var isSorting: Bool { !columns.isEmpty }

    public init(columns: [SortColumn] = []) {
        self.columns = columns
    }

    public mutating func toggle(column: String) {
        if let index = columns.firstIndex(where: { $0.name == column }) {
            let existing = columns[index]
            if existing.ascending {
                columns[index] = SortColumn(name: column, ascending: false)
            } else {
                columns.remove(at: index)
            }
        } else {
            columns = [SortColumn(name: column, ascending: true)]
        }
    }

    public mutating func clear() {
        columns = []
    }
}

public struct SortColumn: Codable, Sendable {
    public let name: String
    public let ascending: Bool

    public init(name: String, ascending: Bool) {
        self.name = name
        self.ascending = ascending
    }
}

public struct PaginationState: Codable, Sendable {
    public var pageSize: Int
    public var currentPage: Int
    public var totalRows: Int?

    public var currentOffset: Int { currentPage * pageSize }

    public var hasNextPage: Bool {
        guard let total = totalRows else { return true }
        return currentOffset + pageSize < total
    }

    public init(pageSize: Int = 200, currentPage: Int = 0, totalRows: Int? = nil) {
        self.pageSize = pageSize
        self.currentPage = currentPage
        self.totalRows = totalRows
    }

    public mutating func reset() {
        currentPage = 0
        totalRows = nil
    }
}
