import Foundation

public struct PluginExportTable: Sendable {
    public let name: String
    public let databaseName: String
    public let tableType: String
    public let optionValues: [Bool]

    public init(name: String, databaseName: String, tableType: String, optionValues: [Bool] = []) {
        self.name = name
        self.databaseName = databaseName
        self.tableType = tableType
        self.optionValues = optionValues
    }

    public var qualifiedName: String {
        databaseName.isEmpty ? name : "\(databaseName).\(name)"
    }
}

public struct PluginExportOptionColumn: Sendable, Identifiable {
    public let id: String
    public let label: String
    public let width: Double
    public let defaultValue: Bool

    public init(id: String, label: String, width: Double, defaultValue: Bool = true) {
        self.id = id
        self.label = label
        self.width = width
        self.defaultValue = defaultValue
    }
}

public enum PluginExportError: LocalizedError {
    case fileWriteFailed(String)
    case encodingFailed
    case compressionFailed
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileWriteFailed(let path):
            return "Failed to write file: \(path)"
        case .encodingFailed:
            return "Failed to encode content as UTF-8"
        case .compressionFailed:
            return "Failed to compress data"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        }
    }
}

public struct PluginExportCancellationError: Error, LocalizedError {
    public init() {}
    public var errorDescription: String? { "Export cancelled" }
}

public struct PluginSequenceInfo: Sendable {
    public let name: String
    public let ddl: String

    public init(name: String, ddl: String) {
        self.name = name
        self.ddl = ddl
    }
}

public struct PluginEnumTypeInfo: Sendable {
    public let name: String
    public let labels: [String]

    public init(name: String, labels: [String]) {
        self.name = name
        self.labels = labels
    }
}

public protocol PluginExportDataSource: AnyObject, Sendable {
    var databaseTypeId: String { get }
    func fetchRows(table: String, databaseName: String, offset: Int, limit: Int) async throws -> PluginQueryResult
    func fetchTableDDL(table: String, databaseName: String) async throws -> String
    func execute(query: String) async throws -> PluginQueryResult
    func quoteIdentifier(_ identifier: String) -> String
    func escapeStringLiteral(_ value: String) -> String
    func fetchApproximateRowCount(table: String, databaseName: String) async throws -> Int?
    func fetchDependentSequences(table: String, databaseName: String) async throws -> [PluginSequenceInfo]
    func fetchDependentTypes(table: String, databaseName: String) async throws -> [PluginEnumTypeInfo]
}

public extension PluginExportDataSource {
    func fetchDependentSequences(table: String, databaseName: String) async throws -> [PluginSequenceInfo] { [] }
    func fetchDependentTypes(table: String, databaseName: String) async throws -> [PluginEnumTypeInfo] { [] }
}

public final class PluginExportProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _currentTable: String = ""
    private var _currentTableIndex: Int = 0
    private var _processedRows: Int = 0
    private var _totalRows: Int = 0
    private var _statusMessage: String = ""
    private var _isCancelled: Bool = false

    private let updateInterval: Int = 1_000
    private var internalRowCount: Int = 0

    public var onUpdate: (@Sendable (String, Int, Int, Int, String) -> Void)?

    public init() {}

    public func setCurrentTable(_ name: String, index: Int) {
        lock.lock()
        _currentTable = name
        _currentTableIndex = index
        lock.unlock()
        notifyUpdate()
    }

    public func incrementRow() {
        lock.lock()
        internalRowCount += 1
        _processedRows = internalRowCount
        let shouldNotify = internalRowCount % updateInterval == 0
        lock.unlock()
        if shouldNotify {
            notifyUpdate()
        }
    }

    public func finalizeTable() {
        notifyUpdate()
    }

    public func setTotalRows(_ count: Int) {
        lock.lock()
        _totalRows = count
        lock.unlock()
    }

    public func setStatus(_ message: String) {
        lock.lock()
        _statusMessage = message
        lock.unlock()
        notifyUpdate()
    }

    public func checkCancellation() throws {
        lock.lock()
        let cancelled = _isCancelled
        lock.unlock()
        if cancelled || Task.isCancelled {
            throw PluginExportCancellationError()
        }
    }

    public func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    public var processedRows: Int {
        lock.lock()
        defer { lock.unlock() }
        return _processedRows
    }

    public var totalRows: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalRows
    }

    private func notifyUpdate() {
        lock.lock()
        let table = _currentTable
        let index = _currentTableIndex
        let rows = _processedRows
        let total = _totalRows
        let status = _statusMessage
        lock.unlock()
        onUpdate?(table, index, rows, total, status)
    }
}

public protocol ExportFormatPlugin: TableProPlugin {
    static var formatId: String { get }
    static var formatDisplayName: String { get }
    static var defaultFileExtension: String { get }
    static var iconName: String { get }
    static var supportedDatabaseTypeIds: [String] { get }
    static var excludedDatabaseTypeIds: [String] { get }

    static var perTableOptionColumns: [PluginExportOptionColumn] { get }
    func defaultTableOptionValues() -> [Bool]
    func isTableExportable(optionValues: [Bool]) -> Bool

    var currentFileExtension: String { get }
    var warnings: [String] { get }

    func export(
        tables: [PluginExportTable],
        dataSource: any PluginExportDataSource,
        destination: URL,
        progress: PluginExportProgress
    ) async throws
}

public extension ExportFormatPlugin {
    static var capabilities: [PluginCapability] { [.exportFormat] }
    static var supportedDatabaseTypeIds: [String] { [] }
    static var excludedDatabaseTypeIds: [String] { [] }
    static var perTableOptionColumns: [PluginExportOptionColumn] { [] }
    func defaultTableOptionValues() -> [Bool] { [] }
    func isTableExportable(optionValues: [Bool]) -> Bool { true }
    var currentFileExtension: String { Self.defaultFileExtension }
    var warnings: [String] { [] }
}
