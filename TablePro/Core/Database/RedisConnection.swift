//
//  RedisConnection.swift
//  TablePro
//
//  Swift wrapper around hiredis (Redis C client library)
//  Provides thread-safe, async-friendly Redis connections
//

#if canImport(CRedis)
import CRedis
#endif
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.TablePro", category: "RedisConnection")

// MARK: - Reply Type

enum RedisReply {
    case string(String)
    case integer(Int64)
    case array([RedisReply])
    case data(Data)
    case status(String)
    case error(String)
    case null

    /// Extract a String value from .string, .status, or .data replies
    var stringValue: String? {
        switch self {
        case .string(let s), .status(let s): return s
        case .data(let d): return String(data: d, encoding: .utf8)
        default: return nil
        }
    }

    /// Extract an Int value from .integer replies, or parse from .string
    var intValue: Int? {
        switch self {
        case .integer(let i): return Int(i)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    /// Extract a String array from .array replies
    var stringArrayValue: [String]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap(\.stringValue)
    }

    /// Extract the inner array from .array replies
    var arrayValue: [RedisReply]? {
        guard case .array(let items) = self else { return nil }
        return items
    }
}

// MARK: - Error Type

struct RedisError: Error, LocalizedError {
    let code: Int
    let message: String

    var errorDescription: String? { "Redis Error \(code): \(message)" }

    static let notConnected = RedisError(code: 0, message: "Not connected to Redis")
    static let connectionFailed = RedisError(code: 0, message: "Failed to establish connection")
    static let hiredisUnavailable = RedisError(
        code: 0,
        message: "Redis support requires hiredis. Run scripts/build-hiredis.sh first."
    )
}

// MARK: - Connection Class

/// Thread-safe Redis connection using hiredis.
/// All blocking C calls are dispatched to a dedicated serial queue.
/// Uses `queue.async` + continuations (never `queue.sync`) to prevent deadlocks.
final class RedisConnection: @unchecked Sendable {
    // MARK: - Properties

    #if canImport(CRedis)
    private static let initOnce: Void = {
        redisInitOpenSSL()
    }()

    private var context: UnsafeMutablePointer<redisContext>?
    private var sslContext: OpaquePointer? // redisSSLContext*
    #endif

    private let queue = DispatchQueue(label: "com.TablePro.redis", qos: .userInitiated)
    private let host: String
    private let port: Int
    private let password: String?
    private let database: Int
    private let sslConfig: SSLConfiguration

    private let stateLock = NSLock()
    private var _isConnected: Bool = false
    private var _isShuttingDown: Bool = false
    private var _cachedServerVersion: String?
    private var _isCancelled: Bool = false
    private var _currentDatabase: Int

    var isConnected: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isConnected
    }

    private var isShuttingDown: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isShuttingDown
        }
        set {
            stateLock.lock()
            _isShuttingDown = newValue
            stateLock.unlock()
        }
    }

    // MARK: - Initialization

    init(
        host: String,
        port: Int,
        password: String?,
        database: Int = 0,
        sslConfig: SSLConfiguration = SSLConfiguration()
    ) {
        self.host = host
        self.port = port
        self.password = password
        self.database = database
        self.sslConfig = sslConfig
        self._currentDatabase = database
    }

    deinit {
        #if canImport(CRedis)
        stateLock.lock()
        let handle = context
        let ssl = sslContext
        context = nil
        sslContext = nil
        stateLock.unlock()

        let cleanupQueue = queue
        if handle != nil || ssl != nil {
            cleanupQueue.async {
                if let handle = handle {
                    redisFree(handle)
                }
                if let ssl = ssl {
                    redisFreeSSLContext(ssl)
                }
            }
        }
        #endif
    }

    // MARK: - Connection Management

    func connect() async throws {
        #if canImport(CRedis)
        _ = Self.initOnce
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                logger.debug("Connecting to Redis at \(host):\(port)")

                guard let ctx = redisConnect(host, Int32(port)) else {
                    logger.error("Failed to create Redis context")
                    continuation.resume(throwing: RedisError.connectionFailed)
                    return
                }

                if ctx.pointee.err != 0 {
                    let errMsg = withUnsafePointer(to: &ctx.pointee.errstr) { ptr in
                        ptr.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
                    }
                    logger.error("Redis connection error: \(errMsg)")
                    redisFree(ctx)
                    continuation.resume(throwing: RedisError(code: Int(ctx.pointee.err), message: errMsg))
                    return
                }

                self.context = ctx

                // SSL setup
                if sslConfig.isEnabled {
                    do {
                        try connectSSL(ctx)
                    } catch {
                        redisFree(ctx)
                        self.context = nil
                        continuation.resume(throwing: error)
                        return
                    }
                }

                // AUTH
                if let password = password, !password.isEmpty {
                    do {
                        let reply = try executeCommandSync(["AUTH", password])
                        if case .error(let msg) = reply {
                            redisFree(ctx)
                            self.context = nil
                            continuation.resume(throwing: RedisError(code: 1, message: "AUTH failed: \(msg)"))
                            return
                        }
                    } catch {
                        redisFree(ctx)
                        self.context = nil
                        continuation.resume(throwing: error)
                        return
                    }
                }

                // SELECT database
                if database != 0 {
                    do {
                        let reply = try executeCommandSync(["SELECT", String(database)])
                        if case .error(let msg) = reply {
                            redisFree(ctx)
                            self.context = nil
                            continuation.resume(
                                throwing: RedisError(code: 2, message: "SELECT \(database) failed: \(msg)")
                            )
                            return
                        }
                    } catch {
                        redisFree(ctx)
                        self.context = nil
                        continuation.resume(throwing: error)
                        return
                    }
                }

                // PING
                do {
                    let reply = try executeCommandSync(["PING"])
                    if case .error(let msg) = reply {
                        redisFree(ctx)
                        self.context = nil
                        continuation.resume(throwing: RedisError(code: 3, message: "PING failed: \(msg)"))
                        return
                    }
                } catch {
                    redisFree(ctx)
                    self.context = nil
                    continuation.resume(throwing: error)
                    return
                }

                // Fetch server version
                let versionString = fetchServerVersionSync()

                stateLock.lock()
                _cachedServerVersion = versionString
                _isConnected = true
                _currentDatabase = database
                stateLock.unlock()

                logger.info("Connected to Redis \(versionString ?? "unknown")")
                continuation.resume()
            }
        }
        #else
        throw RedisError.hiredisUnavailable
        #endif
    }

    func disconnect() {
        isShuttingDown = true

        stateLock.lock()
        #if canImport(CRedis)
        let handle = context
        let ssl = sslContext
        context = nil
        sslContext = nil
        #endif
        _isConnected = false
        _cachedServerVersion = nil
        _isCancelled = false
        _currentDatabase = database
        stateLock.unlock()

        #if canImport(CRedis)
        if handle != nil || ssl != nil {
            queue.async {
                if let handle = handle {
                    redisFree(handle)
                }
                if let ssl = ssl {
                    redisFreeSSLContext(ssl)
                }
            }
        }
        #endif
    }

    // MARK: - Cancellation

    func cancelCurrentQuery() {
        stateLock.lock()
        _isCancelled = true
        stateLock.unlock()
    }

    private func checkCancelled() throws {
        stateLock.lock()
        let cancelled = _isCancelled
        if cancelled { _isCancelled = false }
        stateLock.unlock()
        if cancelled {
            throw RedisError(code: 0, message: String(localized: "Query cancelled"))
        }
    }

    private func resetCancellation() {
        stateLock.lock()
        _isCancelled = false
        stateLock.unlock()
    }

    // MARK: - Ping

    func ping() async throws -> Bool {
        #if canImport(CRedis)
        return try await withCheckedThrowingContinuation { [self] (cont: CheckedContinuation<Bool, Error>) in
            queue.async { [self] in
                guard !isShuttingDown, context != nil else {
                    cont.resume(throwing: RedisError.notConnected)
                    return
                }
                do {
                    let reply = try executeCommandSync(["PING"])
                    if case .status(let s) = reply {
                        cont.resume(returning: s == "PONG")
                    } else {
                        cont.resume(returning: false)
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        #else
        throw RedisError.hiredisUnavailable
        #endif
    }

    // MARK: - Server Information

    func serverVersion() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _cachedServerVersion
    }

    func serverInfo() async throws -> String {
        #if canImport(CRedis)
        resetCancellation()
        return try await withCheckedThrowingContinuation { [self] (cont: CheckedContinuation<String, Error>) in
            queue.async { [self] in
                guard !isShuttingDown, context != nil else {
                    cont.resume(throwing: RedisError.notConnected)
                    return
                }
                do {
                    try checkCancelled()
                    let reply = try executeCommandSync(["INFO"])
                    if case .string(let info) = reply {
                        cont.resume(returning: info)
                    } else {
                        cont.resume(returning: "")
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        #else
        throw RedisError.hiredisUnavailable
        #endif
    }

    func currentDatabase() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _currentDatabase
    }

    // MARK: - Command Execution

    func executeCommand(_ args: [String]) async throws -> RedisReply {
        #if canImport(CRedis)
        resetCancellation()
        return try await withCheckedThrowingContinuation { [self] (cont: CheckedContinuation<RedisReply, Error>) in
            queue.async { [self] in
                guard !isShuttingDown, context != nil else {
                    cont.resume(throwing: RedisError.notConnected)
                    return
                }
                do {
                    try checkCancelled()
                    let result = try executeCommandSync(args)
                    try checkCancelled()
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        #else
        throw RedisError.hiredisUnavailable
        #endif
    }

    // MARK: - Key Operations

    func selectDatabase(_ index: Int) async throws {
        #if canImport(CRedis)
        resetCancellation()
        try await withCheckedThrowingContinuation { [self] (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard !isShuttingDown, context != nil else {
                    continuation.resume(throwing: RedisError.notConnected)
                    return
                }
                do {
                    try checkCancelled()
                    let reply = try executeCommandSync(["SELECT", String(index)])
                    if case .error(let msg) = reply {
                        continuation.resume(
                            throwing: RedisError(code: 2, message: "SELECT \(index) failed: \(msg)")
                        )
                        return
                    }
                    stateLock.lock()
                    _currentDatabase = index
                    stateLock.unlock()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #else
        throw RedisError.hiredisUnavailable
        #endif
    }

    func scanKeys(
        pattern: String, cursor: Int, count: Int
    ) async throws -> (cursor: Int, keys: [String]) {
        #if canImport(CRedis)
        resetCancellation()
        return try await withCheckedThrowingContinuation {
            [self] (cont: CheckedContinuation<(cursor: Int, keys: [String]), Error>) in
            queue.async { [self] in
                guard !isShuttingDown, context != nil else {
                    cont.resume(throwing: RedisError.notConnected)
                    return
                }
                do {
                    try checkCancelled()
                    let reply = try executeCommandSync([
                        "SCAN", String(cursor), "MATCH", pattern, "COUNT", String(count)
                    ])
                    guard case .array(let parts) = reply, parts.count == 2 else {
                        cont.resume(returning: (cursor: 0, keys: []))
                        return
                    }
                    let newCursor: Int
                    if case .string(let cursorStr) = parts[0], let c = Int(cursorStr) {
                        newCursor = c
                    } else {
                        newCursor = 0
                    }
                    var keys: [String] = []
                    if case .array(let keyReplies) = parts[1] {
                        for keyReply in keyReplies {
                            if case .string(let k) = keyReply {
                                keys.append(k)
                            }
                        }
                    }
                    cont.resume(returning: (cursor: newCursor, keys: keys))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        #else
        throw RedisError.hiredisUnavailable
        #endif
    }

    func typeOf(key: String) async throws -> String {
        let reply = try await executeCommand(["TYPE", key])
        if case .status(let t) = reply { return t }
        return "none"
    }

    func ttl(key: String) async throws -> Int64 {
        let reply = try await executeCommand(["TTL", key])
        if case .integer(let t) = reply { return t }
        return -2
    }

    func get(key: String) async throws -> String? {
        let reply = try await executeCommand(["GET", key])
        switch reply {
        case .string(let s): return s
        case .data(let d): return String(data: d, encoding: .utf8)
        case .null: return nil
        default: return nil
        }
    }

    func set(key: String, value: String, ex: Int? = nil) async throws {
        var args = ["SET", key, value]
        if let ex = ex {
            args.append("EX")
            args.append(String(ex))
        }
        let reply = try await executeCommand(args)
        if case .error(let msg) = reply {
            throw RedisError(code: 4, message: "SET failed: \(msg)")
        }
    }

    func del(keys: [String]) async throws -> Int64 {
        guard !keys.isEmpty else { return 0 }
        let reply = try await executeCommand(["DEL"] + keys)
        if case .integer(let n) = reply { return n }
        if case .error(let msg) = reply {
            throw RedisError(code: 5, message: "DEL failed: \(msg)")
        }
        return 0
    }

    func expire(key: String, seconds: Int) async throws -> Bool {
        let reply = try await executeCommand(["EXPIRE", key, String(seconds)])
        if case .integer(let n) = reply { return n == 1 }
        if case .error(let msg) = reply {
            throw RedisError(code: 6, message: "EXPIRE failed: \(msg)")
        }
        return false
    }

    func persist(key: String) async throws -> Bool {
        let reply = try await executeCommand(["PERSIST", key])
        if case .integer(let n) = reply { return n == 1 }
        if case .error(let msg) = reply {
            throw RedisError(code: 7, message: "PERSIST failed: \(msg)")
        }
        return false
    }

    func rename(key: String, newKey: String) async throws {
        let reply = try await executeCommand(["RENAME", key, newKey])
        if case .error(let msg) = reply {
            throw RedisError(code: 8, message: "RENAME failed: \(msg)")
        }
    }

    // MARK: - Hash Operations

    func hgetall(key: String) async throws -> [(field: String, value: String)] {
        let reply = try await executeCommand(["HGETALL", key])
        guard case .array(let items) = reply else { return [] }

        var pairs: [(field: String, value: String)] = []
        // HGETALL returns alternating field, value
        var i = 0
        while i + 1 < items.count {
            let field: String
            let value: String
            if case .string(let f) = items[i] { field = f } else { i += 2; continue }
            if case .string(let v) = items[i + 1] { value = v } else { i += 2; continue }
            pairs.append((field: field, value: value))
            i += 2
        }
        return pairs
    }

    func hset(key: String, field: String, value: String) async throws {
        let reply = try await executeCommand(["HSET", key, field, value])
        if case .error(let msg) = reply {
            throw RedisError(code: 9, message: "HSET failed: \(msg)")
        }
    }

    // MARK: - List Operations

    func lrange(key: String, start: Int, stop: Int) async throws -> [String] {
        let reply = try await executeCommand(["LRANGE", key, String(start), String(stop)])
        guard case .array(let items) = reply else { return [] }
        return items.compactMap { item in
            if case .string(let s) = item { return s }
            return nil
        }
    }

    // MARK: - Set Operations

    func smembers(key: String) async throws -> [String] {
        let reply = try await executeCommand(["SMEMBERS", key])
        guard case .array(let items) = reply else { return [] }
        return items.compactMap { item in
            if case .string(let s) = item { return s }
            return nil
        }
    }

    func sadd(key: String, members: [String]) async throws -> Int64 {
        guard !members.isEmpty else { return 0 }
        let reply = try await executeCommand(["SADD", key] + members)
        if case .integer(let n) = reply { return n }
        if case .error(let msg) = reply {
            throw RedisError(code: 10, message: "SADD failed: \(msg)")
        }
        return 0
    }

    // MARK: - Sorted Set Operations

    func zrangeWithScores(
        key: String, start: Int, stop: Int
    ) async throws -> [(member: String, score: Double)] {
        let reply = try await executeCommand([
            "ZRANGE", key, String(start), String(stop), "WITHSCORES"
        ])
        guard case .array(let items) = reply else { return [] }

        var pairs: [(member: String, score: Double)] = []
        // ZRANGE ... WITHSCORES returns alternating member, score
        var i = 0
        while i + 1 < items.count {
            let member: String
            let score: Double
            if case .string(let m) = items[i] { member = m } else { i += 2; continue }
            if case .string(let s) = items[i + 1], let d = Double(s) {
                score = d
            } else {
                i += 2; continue
            }
            pairs.append((member: member, score: score))
            i += 2
        }
        return pairs
    }

    // MARK: - Stream Operations

    func xrange(key: String, start: String, end: String, count: Int? = nil) async throws -> [RedisReply] {
        var args = ["XRANGE", key, start, end]
        if let count = count {
            args.append("COUNT")
            args.append(String(count))
        }
        let reply = try await executeCommand(args)
        guard case .array(let entries) = reply else { return [] }
        return entries
    }

    // MARK: - Database Operations

    func dbsize() async throws -> Int64 {
        let reply = try await executeCommand(["DBSIZE"])
        if case .integer(let n) = reply { return n }
        if case .error(let msg) = reply {
            throw RedisError(code: 11, message: "DBSIZE failed: \(msg)")
        }
        return 0
    }

    func flushdb() async throws {
        let reply = try await executeCommand(["FLUSHDB"])
        if case .error(let msg) = reply {
            throw RedisError(code: 12, message: "FLUSHDB failed: \(msg)")
        }
    }

    func configGet(_ parameter: String) async throws -> [String] {
        let reply = try await executeCommand(["CONFIG", "GET", parameter])
        guard case .array(let items) = reply else { return [] }
        return items.compactMap { item in
            if case .string(let s) = item { return s }
            return nil
        }
    }
}

// MARK: - Synchronous Helpers (must be called on the serial queue)

#if canImport(CRedis)
private extension RedisConnection {

    func connectSSL(_ ctx: UnsafeMutablePointer<redisContext>) throws {
        var sslError = redisSSLContextError(0)

        let caCert: UnsafePointer<CChar>? = sslConfig.caCertificatePath.isEmpty
            ? nil
            : (sslConfig.caCertificatePath as NSString).utf8String
        let clientCert: UnsafePointer<CChar>? = sslConfig.clientCertificatePath.isEmpty
            ? nil
            : (sslConfig.clientCertificatePath as NSString).utf8String
        let clientKey: UnsafePointer<CChar>? = sslConfig.clientKeyPath.isEmpty
            ? nil
            : (sslConfig.clientKeyPath as NSString).utf8String

        guard let ssl = redisCreateSSLContext(caCert, nil, clientCert, clientKey, nil, &sslError) else {
            let errCode = Int(sslError.rawValue)
            throw RedisError(code: errCode, message: "Failed to create SSL context (error \(errCode))")
        }

        self.sslContext = ssl

        let result = redisInitiateSSLWithContext(ctx, ssl)
        if result != REDIS_OK {
            let errMsg = withUnsafePointer(to: &ctx.pointee.errstr) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
            }
            throw RedisError(code: Int(result), message: "SSL handshake failed: \(errMsg)")
        }

        logger.debug("SSL connection established")
    }

    func executeCommandSync(_ args: [String]) throws -> RedisReply {
        guard let ctx = context else { throw RedisError.notConnected }

        let argc = Int32(args.count)
        let lengths = args.map { $0.utf8.count }

        return try withArgvPointers(args: args, lengths: lengths) { argv, argvlen in
            guard let rawReply = redisCommandArgv(ctx, argc, argv, argvlen) else {
                if ctx.pointee.err != 0 {
                    let errMsg = withUnsafePointer(to: &ctx.pointee.errstr) { ptr in
                        ptr.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
                    }
                    throw RedisError(code: Int(ctx.pointee.err), message: errMsg)
                }
                throw RedisError(code: -1, message: "No reply from Redis")
            }

            let replyPtr = rawReply.assumingMemoryBound(to: redisReply.self)
            let parsed = parseReply(replyPtr)
            freeReplyObject(rawReply)
            return parsed
        }
    }

    /// Execute redisCommandArgv with properly managed C string pointers.
    /// The closure receives the argv array and length array suitable for hiredis.
    func withArgvPointers<T>(
        args: [String],
        lengths: [Int],
        body: (UnsafeMutablePointer<UnsafePointer<CChar>?>, UnsafeMutablePointer<Int>) throws -> T
    ) rethrows -> T {
        let count = args.count

        // Allocate arrays for argv and argvlen
        let argv = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: count)
        let argvlen = UnsafeMutablePointer<Int>.allocate(capacity: count)
        defer {
            argv.deallocate()
            argvlen.deallocate()
        }

        // Build each C string using withCString nested calls.
        // We use a recursive helper to keep all withCString scopes alive.
        func buildArgv(index: Int) throws -> T {
            if index == count {
                return try body(argv, argvlen)
            }
            return try args[index].withCString { cStr in
                argv[index] = cStr
                argvlen[index] = lengths[index]
                return try buildArgv(index: index + 1)
            }
        }

        return try buildArgv(index: 0)
    }

    func parseReply(_ reply: UnsafeMutablePointer<redisReply>) -> RedisReply {
        let type = reply.pointee.type

        switch type {
        case REDIS_REPLY_STRING:
            if let str = reply.pointee.str {
                let len = reply.pointee.len
                // Use len for binary safety
                let data = Data(bytes: str, count: len)
                if let string = String(data: data, encoding: .utf8) {
                    return .string(string)
                }
                return .data(data)
            }
            return .null

        case REDIS_REPLY_INTEGER:
            return .integer(reply.pointee.integer)

        case REDIS_REPLY_ARRAY:
            let count = reply.pointee.elements
            guard count > 0, let elements = reply.pointee.element else {
                return .array([])
            }
            var items: [RedisReply] = []
            items.reserveCapacity(count)
            for i in 0 ..< count {
                if let element = elements[i] {
                    items.append(parseReply(element))
                } else {
                    items.append(.null)
                }
            }
            return .array(items)

        case REDIS_REPLY_NIL:
            return .null

        case REDIS_REPLY_STATUS:
            if let str = reply.pointee.str {
                let len = reply.pointee.len
                let data = Data(bytes: str, count: len)
                return .status(String(data: data, encoding: .utf8) ?? "")
            }
            return .status("")

        case REDIS_REPLY_ERROR:
            if let str = reply.pointee.str {
                let len = reply.pointee.len
                let data = Data(bytes: str, count: len)
                return .error(String(data: data, encoding: .utf8) ?? "Unknown error")
            }
            return .error("Unknown error")

        default:
            logger.warning("Unknown Redis reply type: \(type)")
            return .null
        }
    }

    /// Parse the redis_version line from INFO server output.
    func fetchServerVersionSync() -> String? {
        guard context != nil else { return nil }
        do {
            let reply = try executeCommandSync(["INFO", "server"])
            if case .string(let info) = reply {
                return parseVersionFromInfo(info)
            }
        } catch {
            logger.debug("Failed to fetch server version: \(error.localizedDescription)")
        }
        return nil
    }

    func parseVersionFromInfo(_ info: String) -> String? {
        // INFO returns key:value pairs separated by \r\n
        for line in info.components(separatedBy: "\r\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("redis_version:") {
                let value = trimmed.dropFirst("redis_version:".count)
                return String(value).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
#endif
