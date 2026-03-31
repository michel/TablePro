import Foundation

public struct PluginImportResult: Sendable {
    public let executedStatements: Int
    public let executionTime: TimeInterval
    public let failedStatement: String?
    public let failedLine: Int?

    public init(
        executedStatements: Int,
        executionTime: TimeInterval,
        failedStatement: String? = nil,
        failedLine: Int? = nil
    ) {
        self.executedStatements = executedStatements
        self.executionTime = executionTime
        self.failedStatement = failedStatement
        self.failedLine = failedLine
    }
}

public enum PluginImportError: LocalizedError {
    case statementFailed(statement: String, line: Int, underlyingError: any Error)
    case rollbackFailed(underlyingError: any Error)
    case cancelled
    case importFailed(String)

    public var errorDescription: String? {
        switch self {
        case .statementFailed(_, let line, let error):
            return "Import failed at line \(line): \(error.localizedDescription)"
        case .rollbackFailed(let error):
            return "Transaction rollback failed: \(error.localizedDescription)"
        case .cancelled:
            return "Import cancelled"
        case .importFailed(let message):
            return "Import failed: \(message)"
        }
    }
}

public struct PluginImportCancellationError: Error, LocalizedError {
    public init() {}
    public var errorDescription: String? { "Import cancelled" }
}

public protocol PluginImportSource: AnyObject, Sendable {
    func statements() async throws -> AsyncThrowingStream<(statement: String, lineNumber: Int), Error>
    func fileURL() -> URL
    func fileSizeBytes() -> Int64
}

public protocol PluginImportDataSink: AnyObject, Sendable {
    var databaseTypeId: String { get }
    func execute(statement: String) async throws
    func beginTransaction() async throws
    func commitTransaction() async throws
    func rollbackTransaction() async throws
    func disableForeignKeyChecks() async throws
    func enableForeignKeyChecks() async throws
}

public extension PluginImportDataSink {
    func disableForeignKeyChecks() async throws {}
    func enableForeignKeyChecks() async throws {}
}

public final class PluginImportProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _processedStatements: Int = 0
    private var _estimatedTotalStatements: Int = 0
    private var _statusMessage: String = ""
    private var _isCancelled: Bool = false

    private let updateInterval: Int = 500
    private var internalCount: Int = 0

    public var onUpdate: (@Sendable (Int, Int, String) -> Void)?

    public init() {}

    public func setEstimatedTotal(_ count: Int) {
        lock.lock()
        _estimatedTotalStatements = count
        lock.unlock()
    }

    public func incrementStatement() {
        lock.lock()
        internalCount += 1
        _processedStatements = internalCount
        let shouldNotify = internalCount % updateInterval == 0
        lock.unlock()
        if shouldNotify {
            notifyUpdate()
        }
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
            throw PluginImportCancellationError()
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

    public var processedStatements: Int {
        lock.lock()
        defer { lock.unlock() }
        return _processedStatements
    }

    public var estimatedTotalStatements: Int {
        lock.lock()
        defer { lock.unlock() }
        return _estimatedTotalStatements
    }

    public func finalize() {
        notifyUpdate()
    }

    private func notifyUpdate() {
        lock.lock()
        let processed = _processedStatements
        let total = _estimatedTotalStatements
        let status = _statusMessage
        lock.unlock()
        onUpdate?(processed, total, status)
    }
}

public protocol ImportFormatPlugin: TableProPlugin {
    static var formatId: String { get }
    static var formatDisplayName: String { get }
    static var acceptedFileExtensions: [String] { get }
    static var iconName: String { get }
    static var supportedDatabaseTypeIds: [String] { get }
    static var excludedDatabaseTypeIds: [String] { get }

    func performImport(
        source: any PluginImportSource,
        sink: any PluginImportDataSink,
        progress: PluginImportProgress
    ) async throws -> PluginImportResult
}

public extension ImportFormatPlugin {
    static var capabilities: [PluginCapability] { [.importFormat] }
    static var supportedDatabaseTypeIds: [String] { [] }
    static var excludedDatabaseTypeIds: [String] { [] }
}
