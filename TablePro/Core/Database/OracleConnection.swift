//
//  OracleConnection.swift
//  TablePro
//
//  Swift wrapper around Oracle OCI C API.
//  Provides thread-safe, async-friendly Oracle Database connections.
//

import COracle
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.TablePro", category: "OracleConnection")

// MARK: - Error Types

struct OracleError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { "Oracle Error: \(message)" }

    static let notConnected = OracleError(message: "Not connected to database")
    static let connectionFailed = OracleError(message: "Failed to establish connection")
    static let queryFailed = OracleError(message: "Query execution failed")
}

// MARK: - Query Result

struct OracleQueryResult {
    let columns: [String]
    let columnTypeNames: [String]
    let rows: [[String?]]
    let affectedRows: Int
}

// MARK: - Connection Class

final class OracleConnection: @unchecked Sendable {
    // MARK: - Properties

    private var envHandle: UnsafeMutablePointer<OCIEnv>?
    private var errHandle: UnsafeMutablePointer<OCIError>?
    private var svcHandle: UnsafeMutablePointer<OCISvcCtx>?
    private var srvHandle: UnsafeMutablePointer<OCIServer>?
    private var sesHandle: UnsafeMutablePointer<OCISession>?

    private let queue: DispatchQueue

    private let host: String
    private let port: Int
    private let user: String
    private let password: String
    private let database: String

    private let lock = NSLock()
    private var _isConnected = false

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    // MARK: - Initialization

    init(host: String, port: Int, user: String, password: String, database: String) {
        self.queue = DispatchQueue(label: "com.TablePro.oracle.\(host).\(port)", qos: .userInitiated)
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
    }

    // MARK: - Connection

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try self.connectSync()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func connectSync() throws {
        // Create OCI environment
        var env: UnsafeMutableRawPointer?
        var status = OCIEnvCreate(
            &envHandle, UInt32(OCI_THREADED),
            nil, nil, nil, nil, 0, nil
        )
        guard status == Int32(OCI_SUCCESS), envHandle != nil else {
            throw OracleError(message: "Failed to create OCI environment")
        }

        // Allocate error handle
        status = OCIHandleAlloc(
            envHandle, &env, UInt32(OCI_HTYPE_ERROR), 0, nil
        )
        guard status == Int32(OCI_SUCCESS) else {
            throw OracleError(message: "Failed to allocate error handle")
        }
        errHandle = env?.assumingMemoryBound(to: OCIError.self)

        // Allocate server handle
        env = nil
        status = OCIHandleAlloc(
            envHandle, &env, UInt32(OCI_HTYPE_SERVER), 0, nil
        )
        guard status == Int32(OCI_SUCCESS) else {
            throw OracleError(message: "Failed to allocate server handle")
        }
        srvHandle = env?.assumingMemoryBound(to: OCIServer.self)

        // Build connect string: //host:port/service_name
        let connectString = "//\(host):\(port)/\(database)"

        // Attach to server
        status = connectString.withCString { cStr in
            OCIServerAttach(
                srvHandle, errHandle,
                cStr, Int32(connectString.utf8.count),
                UInt32(OCI_DEFAULT)
            )
        }
        guard status == Int32(OCI_SUCCESS) || status == Int32(OCI_SUCCESS_WITH_INFO) else {
            let detail = getErrorMessage()
            throw OracleError(message: "Failed to connect to \(host):\(port) \u{2014} \(detail)")
        }

        // Allocate service context
        env = nil
        status = OCIHandleAlloc(
            envHandle, &env, UInt32(OCI_HTYPE_SVCCTX), 0, nil
        )
        guard status == Int32(OCI_SUCCESS) else {
            throw OracleError(message: "Failed to allocate service context")
        }
        svcHandle = env?.assumingMemoryBound(to: OCISvcCtx.self)

        // Set server on service context
        status = OCIAttrSet(
            svcHandle, UInt32(OCI_HTYPE_SVCCTX),
            srvHandle, 0, UInt32(OCI_ATTR_SERVER),
            errHandle
        )
        guard status == Int32(OCI_SUCCESS) else {
            throw OracleError(message: "Failed to set server attribute")
        }

        // Allocate session handle
        env = nil
        status = OCIHandleAlloc(
            envHandle, &env, UInt32(OCI_HTYPE_SESSION), 0, nil
        )
        guard status == Int32(OCI_SUCCESS) else {
            throw OracleError(message: "Failed to allocate session handle")
        }
        sesHandle = env?.assumingMemoryBound(to: OCISession.self)

        // Set username
        status = user.withCString { cStr in
            OCIAttrSet(
                sesHandle, UInt32(OCI_HTYPE_SESSION),
                UnsafeMutableRawPointer(mutating: cStr), UInt32(user.utf8.count),
                UInt32(OCI_ATTR_USERNAME), errHandle
            )
        }
        guard status == Int32(OCI_SUCCESS) else {
            throw OracleError(message: "Failed to set username")
        }

        // Set password
        status = password.withCString { cStr in
            OCIAttrSet(
                sesHandle, UInt32(OCI_HTYPE_SESSION),
                UnsafeMutableRawPointer(mutating: cStr), UInt32(password.utf8.count),
                UInt32(OCI_ATTR_PASSWORD), errHandle
            )
        }
        guard status == Int32(OCI_SUCCESS) else {
            throw OracleError(message: "Failed to set password")
        }

        // Begin session
        status = OCISessionBegin(
            svcHandle, errHandle, sesHandle,
            UInt32(OCI_CRED_RDBMS), UInt32(OCI_DEFAULT)
        )
        guard status == Int32(OCI_SUCCESS) || status == Int32(OCI_SUCCESS_WITH_INFO) else {
            let detail = getErrorMessage()
            throw OracleError(message: "Authentication failed \u{2014} \(detail)")
        }

        // Set session on service context
        status = OCIAttrSet(
            svcHandle, UInt32(OCI_HTYPE_SVCCTX),
            sesHandle, 0, UInt32(OCI_ATTR_SESSION),
            errHandle
        )
        guard status == Int32(OCI_SUCCESS) else {
            throw OracleError(message: "Failed to set session attribute")
        }

        lock.lock()
        _isConnected = true
        lock.unlock()

        logger.debug("Connected to Oracle \(self.host):\(self.port)/\(self.database)")
    }

    func disconnect() {
        lock.lock()
        let wasConnected = _isConnected
        _isConnected = false
        lock.unlock()

        guard wasConnected else { return }

        queue.async { [self] in
            if let ses = sesHandle, let svc = svcHandle, let err = errHandle {
                _ = OCISessionEnd(svc, err, ses, UInt32(OCI_DEFAULT))
            }
            if let srv = srvHandle, let err = errHandle {
                _ = OCIServerDetach(srv, err, UInt32(OCI_DEFAULT))
            }
            if let ses = sesHandle { _ = OCIHandleFree(ses, UInt32(OCI_HTYPE_SESSION)) }
            if let svc = svcHandle { _ = OCIHandleFree(svc, UInt32(OCI_HTYPE_SVCCTX)) }
            if let srv = srvHandle { _ = OCIHandleFree(srv, UInt32(OCI_HTYPE_SERVER)) }
            if let err = errHandle { _ = OCIHandleFree(err, UInt32(OCI_HTYPE_ERROR)) }
            if let env = envHandle { _ = OCIHandleFree(env, UInt32(OCI_HTYPE_ENV)) }

            self.sesHandle = nil
            self.svcHandle = nil
            self.srvHandle = nil
            self.errHandle = nil
            self.envHandle = nil
        }
    }

    // MARK: - Query Execution

    func executeQuery(_ query: String) async throws -> OracleQueryResult {
        let queryToRun = String(query)
        return try await withCheckedThrowingContinuation { [self] (cont: CheckedContinuation<OracleQueryResult, Error>) in
            queue.async { [self] in
                do {
                    let result = try self.executeQuerySync(queryToRun)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func executeQuerySync(_ query: String) throws -> OracleQueryResult {
        guard let svc = svcHandle, let err = errHandle, let env = envHandle else {
            throw OracleError.notConnected
        }

        // Allocate statement handle
        var stmtRaw: UnsafeMutableRawPointer?
        var status = OCIHandleAlloc(env, &stmtRaw, UInt32(OCI_HTYPE_STMT), 0, nil)
        guard status == Int32(OCI_SUCCESS), let stmtPtr = stmtRaw else {
            throw OracleError(message: "Failed to allocate statement handle")
        }
        let stmt = stmtPtr.assumingMemoryBound(to: OCIStmt.self)
        defer { _ = OCIHandleFree(stmt, UInt32(OCI_HTYPE_STMT)) }

        // Prepare statement
        status = query.withCString { cStr in
            OCIStmtPrepare(
                stmt, err, cStr, UInt32(query.utf8.count),
                UInt32(OCI_DEFAULT), UInt32(OCI_DEFAULT)
            )
        }
        guard status == Int32(OCI_SUCCESS) else {
            let detail = getErrorMessage()
            throw OracleError(message: "Failed to prepare query: \(detail)")
        }

        // Determine if this is a SELECT (iters=0) or DML (iters=1)
        let isSelect = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased().hasPrefix("SELECT")
            || query.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased().hasPrefix("WITH")
        let iters: UInt32 = isSelect ? 0 : 1

        // Execute
        status = OCIStmtExecute(
            svc, stmt, err, iters, 0, nil, nil,
            UInt32(OCI_DEFAULT)
        )
        guard status == Int32(OCI_SUCCESS) || status == Int32(OCI_SUCCESS_WITH_INFO)
            || status == Int32(OCI_NO_DATA) else {
            let detail = getErrorMessage()
            throw OracleError(message: detail)
        }

        // For non-SELECT, get affected row count
        if !isSelect {
            var rowCount: UInt32 = 0
            _ = OCIAttrGet(
                stmt, UInt32(OCI_HTYPE_STMT),
                &rowCount, nil, UInt32(OCI_ATTR_ROW_COUNT), err
            )
            return OracleQueryResult(columns: [], columnTypeNames: [], rows: [], affectedRows: Int(rowCount))
        }

        // Get column count
        var paramCount: UInt32 = 0
        _ = OCIAttrGet(
            stmt, UInt32(OCI_HTYPE_STMT),
            &paramCount, nil, UInt32(OCI_ATTR_PARAM_COUNT), err
        )

        let numCols = Int(paramCount)
        guard numCols > 0 else {
            return OracleQueryResult(columns: [], columnTypeNames: [], rows: [], affectedRows: 0)
        }

        // Describe columns and set up define buffers
        var columns: [String] = []
        var typeNames: [String] = []
        let bufSize = 4_096
        var buffers: [[CChar]] = []
        var indicators: [Int16] = Array(repeating: 0, count: numCols)
        var returnLengths: [UInt16] = Array(repeating: 0, count: numCols)
        var defines: [UnsafeMutablePointer<OCIDefine>?] = Array(repeating: nil, count: numCols)

        for i in 1...numCols {
            // Get parameter descriptor
            var paramRaw: UnsafeMutableRawPointer?
            _ = OCIParamGet(stmt, UInt32(OCI_HTYPE_STMT), err, &paramRaw, UInt32(i))

            // Get column name
            var namePtr: UnsafeMutablePointer<CChar>?
            var nameLen: UInt32 = 0
            _ = OCIAttrGet(
                paramRaw, UInt32(OCI_DTYPE_PARAM),
                &namePtr, &nameLen, UInt32(OCI_ATTR_NAME), err
            )
            let colName: String
            if let namePtr, nameLen > 0 {
                colName = String(cString: namePtr)
            } else {
                colName = "col\(i)"
            }
            columns.append(colName)

            // Get data type
            var dataType: UInt16 = 0
            _ = OCIAttrGet(
                paramRaw, UInt32(OCI_DTYPE_PARAM),
                &dataType, nil, UInt32(OCI_ATTR_DATA_TYPE), err
            )
            typeNames.append(oracleTypeName(Int32(dataType)))

            // Define output buffer — convert everything to string
            var buf = [CChar](repeating: 0, count: bufSize)
            buffers.append(buf)
        }

        // Set up define by position for each column
        for i in 0..<numCols {
            buffers[i].withUnsafeMutableBufferPointer { bufPtr in
                _ = OCIDefineByPos(
                    stmt, &defines[i], err,
                    UInt32(i + 1),
                    bufPtr.baseAddress, Int32(bufSize),
                    UInt16(SQLT_STR),
                    &indicators[i], &returnLengths[i], nil,
                    UInt32(OCI_DEFAULT)
                )
            }
        }

        // Fetch rows
        var allRows: [[String?]] = []
        while true {
            status = OCIStmtFetch2(
                stmt, err, 1, UInt16(OCI_FETCH_NEXT), 0, UInt32(OCI_DEFAULT)
            )
            if status == Int32(OCI_NO_DATA) { break }
            if status != Int32(OCI_SUCCESS) && status != Int32(OCI_SUCCESS_WITH_INFO) { break }

            var row: [String?] = []
            for i in 0..<numCols {
                if indicators[i] == -1 {
                    row.append(nil)
                } else {
                    let str = buffers[i].withUnsafeBufferPointer { bufPtr -> String? in
                        guard let base = bufPtr.baseAddress else { return nil }
                        return String(cString: base)
                    }
                    row.append(str)
                }
            }
            allRows.append(row)
        }

        return OracleQueryResult(
            columns: columns,
            columnTypeNames: typeNames,
            rows: allRows,
            affectedRows: allRows.count
        )
    }

    // MARK: - Private Helpers

    private func getErrorMessage() -> String {
        guard let err = errHandle else { return "Unknown error" }
        var errCode: Int32 = 0
        var buf = [CChar](repeating: 0, count: 512)
        _ = OCIErrorGet(
            err, 1, nil, &errCode, &buf, UInt32(buf.count), UInt32(OCI_HTYPE_ERROR)
        )
        return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func oracleTypeName(_ type: Int32) -> String {
        switch type {
        case Int32(SQLT_CHR), Int32(SQLT_AFC), Int32(SQLT_AVC): return "varchar2"
        case Int32(SQLT_NUM): return "number"
        case Int32(SQLT_INT): return "integer"
        case Int32(SQLT_FLT): return "float"
        case Int32(SQLT_STR): return "string"
        case Int32(SQLT_LNG): return "long"
        case Int32(SQLT_RID), Int32(SQLT_RDD): return "rowid"
        case Int32(SQLT_DAT): return "date"
        case Int32(SQLT_BIN): return "raw"
        case Int32(SQLT_LBI): return "long raw"
        case Int32(SQLT_IBFLOAT): return "binary_float"
        case Int32(SQLT_IBDOUBLE): return "binary_double"
        case Int32(SQLT_CLOB): return "clob"
        case Int32(SQLT_BLOB): return "blob"
        case Int32(SQLT_BFILEE): return "bfile"
        case Int32(SQLT_TIMESTAMP): return "timestamp"
        case Int32(SQLT_TIMESTAMP_TZ): return "timestamp with time zone"
        case Int32(SQLT_TIMESTAMP_LTZ): return "timestamp with local time zone"
        case Int32(SQLT_INTERVAL_YM): return "interval year to month"
        case Int32(SQLT_INTERVAL_DS): return "interval day to second"
        default: return "unknown"
        }
    }
}
