//
//  ClickHouseConnection.swift
//  TablePro
//
//  Swift wrapper around the ClickHouse HTTP API (port 8123).
//  Uses URLSession for HTTP requests — no C bridge needed.
//

import Foundation
import os

// MARK: - Error Types

struct ClickHouseError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { "ClickHouse Error: \(message)" }

    static let notConnected = ClickHouseError(message: "Not connected to database")
    static let connectionFailed = ClickHouseError(message: "Failed to establish connection")
}

// MARK: - Query Result

struct ClickHouseQueryResult {
    let columns: [String]
    let columnTypeNames: [String]
    let rows: [[String?]]
    let affectedRows: Int
}

// MARK: - Connection Class

/// Thread-safe ClickHouse connection over the HTTP API.
/// Uses a dedicated URLSession instance for request lifecycle control.
final class ClickHouseConnection: @unchecked Sendable {
    // MARK: - Properties

    private static let logger = Logger(subsystem: "com.TablePro", category: "ClickHouseConnection")

    private let host: String
    private let port: Int
    private let user: String
    private let password: String

    private let lock = NSLock()
    private var _isConnected = false
    private var _currentDatabase: String
    private var currentTask: URLSessionDataTask?
    private var session: URLSession?

    /// Query prefixes that return tabular results and need FORMAT suffix
    private static let selectPrefixes: Set<String> = [
        "SELECT", "SHOW", "DESCRIBE", "EXISTS", "EXPLAIN", "WITH"
    ]

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    // MARK: - Initialization

    init(host: String, port: Int, user: String, password: String, database: String) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self._currentDatabase = database
    }

    // MARK: - Connection

    func connect() async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300

        lock.lock()
        session = URLSession(configuration: config)
        lock.unlock()

        // Test connectivity with a simple query
        do {
            _ = try await executeQuery("SELECT 1")
        } catch {
            lock.lock()
            session?.invalidateAndCancel()
            session = nil
            lock.unlock()
            Self.logger.error("Connection test failed: \(error.localizedDescription)")
            throw ClickHouseError.connectionFailed
        }

        lock.lock()
        _isConnected = true
        lock.unlock()

        Self.logger.debug("Connected to ClickHouse at \(self.host):\(self.port)")
    }

    func switchDatabase(_ database: String) async throws {
        lock.lock()
        _currentDatabase = database
        lock.unlock()
    }

    func disconnect() {
        lock.lock()
        currentTask?.cancel()
        currentTask = nil
        session?.invalidateAndCancel()
        session = nil
        _isConnected = false
        lock.unlock()

        Self.logger.debug("Disconnected from ClickHouse")
    }

    // MARK: - Query Execution

    func executeQuery(_ query: String) async throws -> ClickHouseQueryResult {
        lock.lock()
        guard let session = self.session else {
            lock.unlock()
            throw ClickHouseError.notConnected
        }
        let database = _currentDatabase
        lock.unlock()

        let request = try buildRequest(query: query, database: database)
        let isSelect = Self.isSelectLikeQuery(query)

        let (data, response) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data = data, let response = response else {
                        continuation.resume(throwing: ClickHouseError(message: "Empty response from server"))
                        return
                    }
                    continuation.resume(returning: (data, response))
                }

                self.lock.lock()
                self.currentTask = task
                self.lock.unlock()

                task.resume()
            }
        } onCancel: {
            self.cancel()
        }

        lock.lock()
        currentTask = nil
        lock.unlock()

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            Self.logger.error("ClickHouse HTTP \(httpResponse.statusCode): \(body)")
            throw ClickHouseError(message: body.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if isSelect {
            return parseTabSeparatedResponse(data)
        }

        return ClickHouseQueryResult(columns: [], columnTypeNames: [], rows: [], affectedRows: 0)
    }

    func cancel() {
        lock.lock()
        currentTask?.cancel()
        currentTask = nil
        lock.unlock()
    }

    // MARK: - Private Helpers

    private func buildRequest(query: String, database: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/"

        if !database.isEmpty {
            components.queryItems = [URLQueryItem(name: "database", value: database)]
        }

        guard let url = components.url else {
            throw ClickHouseError(message: "Failed to construct request URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Basic auth
        let credentials = "\(user):\(password)"
        if let credData = credentials.data(using: .utf8) {
            request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        if Self.isSelectLikeQuery(query) {
            request.httpBody = (query + " FORMAT TabSeparatedWithNamesAndTypes").data(using: .utf8)
        } else {
            request.httpBody = query.data(using: .utf8)
        }

        return request
    }

    private static func isSelectLikeQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstWord = trimmed.split(separator: " ", maxSplits: 1).first else {
            return false
        }
        return selectPrefixes.contains(firstWord.uppercased())
    }

    private func parseTabSeparatedResponse(_ data: Data) -> ClickHouseQueryResult {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return ClickHouseQueryResult(columns: [], columnTypeNames: [], rows: [], affectedRows: 0)
        }

        let lines = text.components(separatedBy: "\n")

        guard lines.count >= 2 else {
            return ClickHouseQueryResult(columns: [], columnTypeNames: [], rows: [], affectedRows: 0)
        }

        let columns = lines[0].components(separatedBy: "\t")
        let columnTypes = lines[1].components(separatedBy: "\t")

        var rows: [[String?]] = []
        for i in 2..<lines.count {
            let line = lines[i]
            if line.isEmpty { continue }

            let fields = line.components(separatedBy: "\t")
            let row = fields.map { field -> String? in
                if field == "\\N" {
                    return nil
                }
                return unescapeTsvField(field)
            }
            rows.append(row)
        }

        return ClickHouseQueryResult(
            columns: columns,
            columnTypeNames: columnTypes,
            rows: rows,
            affectedRows: rows.count
        )
    }

    /// Unescape TSV escape sequences: `\\` -> `\`, `\t` -> tab, `\n` -> newline
    private func unescapeTsvField(_ field: String) -> String {
        var result = ""
        result.reserveCapacity(field.count)
        var iterator = field.makeIterator()

        while let char = iterator.next() {
            if char == "\\" {
                if let next = iterator.next() {
                    switch next {
                    case "\\": result.append("\\")
                    case "t": result.append("\t")
                    case "n": result.append("\n")
                    default:
                        result.append("\\")
                        result.append(next)
                    }
                } else {
                    result.append("\\")
                }
            } else {
                result.append(char)
            }
        }

        return result
    }
}
