//
//  ConnectionURLParser.swift
//  TablePro
//

import Foundation

struct ParsedConnectionURL {
    let type: DatabaseType
    let host: String
    let port: Int?
    let database: String
    let username: String
    let password: String
    let sslMode: SSLMode?

    var suggestedName: String {
        let typeName = type.rawValue
        if !database.isEmpty {
            return "\(typeName) \(host)/\(database)"
        }
        if !host.isEmpty {
            return "\(typeName) \(host)"
        }
        return typeName
    }
}

enum ConnectionURLParseError: Error, LocalizedError, Equatable {
    case emptyString
    case invalidURL
    case unsupportedScheme(String)
    case missingHost

    var errorDescription: String? {
        switch self {
        case .emptyString:
            return String(localized: "Connection URL cannot be empty")
        case .invalidURL:
            return String(localized: "Invalid connection URL format")
        case .unsupportedScheme(let scheme):
            return String(localized: "Unsupported database scheme: \(scheme)")
        case .missingHost:
            return String(localized: "Connection URL must include a host")
        }
    }
}

struct ConnectionURLParser {
    static func parse(_ urlString: String) -> Result<ParsedConnectionURL, ConnectionURLParseError> {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptyString)
        }

        guard let schemeEnd = trimmed.range(of: "://") else {
            return .failure(.invalidURL)
        }

        let scheme = trimmed[trimmed.startIndex..<schemeEnd.lowerBound].lowercased()

        let dbType: DatabaseType
        switch scheme {
        case "postgresql", "postgres":
            dbType = .postgresql
        case "mysql":
            dbType = .mysql
        case "mariadb":
            dbType = .mariadb
        case "mongodb", "mongodb+srv":
            dbType = .mongodb
        case "sqlite":
            dbType = .sqlite
        default:
            return .failure(.unsupportedScheme(scheme))
        }

        if dbType == .sqlite {
            let path = String(trimmed[schemeEnd.upperBound...])
            return .success(ParsedConnectionURL(
                type: .sqlite,
                host: "",
                port: nil,
                database: path,
                username: "",
                password: "",
                sslMode: nil
            ))
        }

        let httpURL = "http://" + String(trimmed[schemeEnd.upperBound...])
        guard let components = URLComponents(string: httpURL) else {
            return .failure(.invalidURL)
        }

        guard let host = components.host, !host.isEmpty else {
            return .failure(.missingHost)
        }

        let port = components.port
        let username = components.percentEncodedUser.flatMap {
            $0.removingPercentEncoding
        } ?? ""
        let password = components.percentEncodedPassword.flatMap {
            $0.removingPercentEncoding
        } ?? ""

        var database = components.path
        if database.hasPrefix("/") {
            database = String(database.dropFirst())
        }

        var sslMode: SSLMode?
        if let queryItems = components.queryItems {
            for item in queryItems where item.name == "sslmode" {
                if let value = item.value {
                    sslMode = parseSSLMode(value)
                }
            }
        }

        return .success(ParsedConnectionURL(
            type: dbType,
            host: host,
            port: port,
            database: database,
            username: username,
            password: password,
            sslMode: sslMode
        ))
    }

    private static func parseSSLMode(_ value: String) -> SSLMode? {
        switch value.lowercased() {
        case "disable", "disabled":
            return .disabled
        case "prefer", "preferred":
            return .preferred
        case "require", "required":
            return .required
        case "verify-ca":
            return .verifyCa
        case "verify-full", "verify-identity":
            return .verifyIdentity
        default:
            return nil
        }
    }
}
