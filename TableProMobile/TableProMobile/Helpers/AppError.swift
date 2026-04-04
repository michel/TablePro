//
//  AppError.swift
//  TableProMobile
//

import Foundation
import os
import TableProModels

// MARK: - Error Category

enum AppErrorCategory: Sendable {
    case network
    case auth
    case config
    case query
    case ssh
    case system
}

// MARK: - App Error

struct AppError: LocalizedError, Sendable {
    let category: AppErrorCategory
    let title: String
    let message: String
    let recovery: String?
    let underlying: Error?

    var errorDescription: String? { message }
}

// MARK: - Error Context

struct ErrorContext: Sendable {
    let operation: String
    let databaseType: DatabaseType?
    let host: String?
    let sshEnabled: Bool

    init(operation: String, databaseType: DatabaseType? = nil, host: String? = nil, sshEnabled: Bool = false) {
        self.operation = operation
        self.databaseType = databaseType
        self.host = host
        self.sshEnabled = sshEnabled
    }
}

// MARK: - Error Classifier

enum ErrorClassifier {
    private static let logger = Logger(subsystem: "com.TablePro", category: "Error")

    static func classify(_ error: Error, context: ErrorContext) -> AppError {
        let message = error.localizedDescription.lowercased()

        // Log the error
        logger.error("[\(context.operation)] \(error.localizedDescription, privacy: .public)")

        // SSH errors
        if message.contains("ssh") || message.contains("tunnel") || message.contains("handshake") {
            return ssh(error, context: context)
        }

        // Auth errors
        if message.contains("authentication") || message.contains("password") ||
            message.contains("denied") || message.contains("credential") ||
            message.contains("permission") || message.contains("access denied") ||
            message.contains("fe_sendauth")
        {
            return auth(error, context: context)
        }

        // Network errors
        if message.contains("timeout") || message.contains("timed out") ||
            message.contains("connection refused") || message.contains("unreachable") ||
            message.contains("network") || message.contains("could not connect") ||
            message.contains("no route") || message.contains("connection reset")
        {
            return network(error, context: context)
        }

        // Query errors
        if message.contains("syntax") || message.contains("no such table") ||
            message.contains("does not exist") || message.contains("constraint") ||
            message.contains("duplicate") || message.contains("violation") ||
            message.contains("unknown column")
        {
            return query(error, context: context)
        }

        // Config errors
        if message.contains("not found") || message.contains("unsupported") ||
            message.contains("invalid") || message.contains("no driver")
        {
            return config(error, context: context)
        }

        // Default
        return AppError(
            category: .system,
            title: "Error",
            message: error.localizedDescription,
            recovery: nil,
            underlying: error
        )
    }

    private static func ssh(_ error: Error, context: ErrorContext) -> AppError {
        let msg = error.localizedDescription
        let recovery: String

        if msg.lowercased().contains("authentication") || msg.lowercased().contains("key") {
            recovery = "Check your SSH username, password, or private key."
        } else if msg.lowercased().contains("handshake") {
            recovery = "The SSH server may be unreachable or running a different protocol."
        } else if msg.lowercased().contains("channel") {
            recovery = "The SSH tunnel connected but could not forward to the database port."
        } else {
            recovery = "Check your SSH host, port, and credentials."
        }

        return AppError(
            category: .ssh,
            title: "SSH Tunnel Failed",
            message: msg,
            recovery: recovery,
            underlying: error
        )
    }

    private static func auth(_ error: Error, context: ErrorContext) -> AppError {
        let dbName = context.databaseType?.rawValue ?? "Database"
        return AppError(
            category: .auth,
            title: "Authentication Failed",
            message: error.localizedDescription,
            recovery: "Check your \(dbName) username and password.",
            underlying: error
        )
    }

    private static func network(_ error: Error, context: ErrorContext) -> AppError {
        let msg = error.localizedDescription
        let recovery: String

        if msg.lowercased().contains("timeout") || msg.lowercased().contains("timed out") {
            recovery = "The server is not responding. Check your network connection and that the server is running."
        } else if msg.lowercased().contains("refused") {
            recovery = "Connection refused. Verify the host address and port number."
        } else {
            recovery = "Check your network connection and server availability."
        }

        return AppError(
            category: .network,
            title: "Connection Failed",
            message: msg,
            recovery: recovery,
            underlying: error
        )
    }

    private static func query(_ error: Error, context: ErrorContext) -> AppError {
        let msg = error.localizedDescription
        let recovery: String

        if msg.lowercased().contains("syntax") {
            recovery = "Check your SQL syntax."
        } else if msg.lowercased().contains("constraint") || msg.lowercased().contains("duplicate") {
            recovery = "The operation violates a database constraint. Check for duplicate or missing required values."
        } else if msg.lowercased().contains("no such table") || msg.lowercased().contains("does not exist") {
            recovery = "The table or column does not exist. It may have been renamed or deleted."
        } else {
            recovery = "Check your query and try again."
        }

        return AppError(
            category: .query,
            title: "Query Error",
            message: msg,
            recovery: recovery,
            underlying: error
        )
    }

    private static func config(_ error: Error, context: ErrorContext) -> AppError {
        return AppError(
            category: .config,
            title: "Configuration Error",
            message: error.localizedDescription,
            recovery: "Check your connection settings.",
            underlying: error
        )
    }
}
