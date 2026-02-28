//
//  ConnectionURLParserTests.swift
//  TableProTests
//

import Foundation
import Testing
@testable import TablePro

@Suite("Connection URL Parser")
struct ConnectionURLParserTests {

    // MARK: - PostgreSQL

    @Test("Full PostgreSQL URL")
    func testFullPostgreSQLURL() {
        let result = ConnectionURLParser.parse("postgresql://admin:secret@db.example.com:5432/mydb")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .postgresql)
        #expect(parsed.host == "db.example.com")
        #expect(parsed.port == 5432)
        #expect(parsed.database == "mydb")
        #expect(parsed.username == "admin")
        #expect(parsed.password == "secret")
    }

    @Test("Postgres scheme alias")
    func testPostgresSchemeAlias() {
        let result = ConnectionURLParser.parse("postgres://user:pass@host:5432/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .postgresql)
        #expect(parsed.host == "host")
    }

    @Test("PostgreSQL without port")
    func testPostgreSQLWithoutPort() {
        let result = ConnectionURLParser.parse("postgresql://user:pass@host/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.port == nil)
        #expect(parsed.host == "host")
        #expect(parsed.database == "db")
    }

    @Test("PostgreSQL without user")
    func testPostgreSQLWithoutUser() {
        let result = ConnectionURLParser.parse("postgresql://host:5432/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.username == "")
        #expect(parsed.password == "")
        #expect(parsed.host == "host")
    }

    // MARK: - MySQL

    @Test("Full MySQL URL")
    func testFullMySQLURL() {
        let result = ConnectionURLParser.parse("mysql://root:password@localhost:3306/testdb")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mysql)
        #expect(parsed.host == "localhost")
        #expect(parsed.port == 3306)
        #expect(parsed.database == "testdb")
        #expect(parsed.username == "root")
        #expect(parsed.password == "password")
    }

    @Test("MySQL without database")
    func testMySQLWithoutDatabase() {
        let result = ConnectionURLParser.parse("mysql://root:pass@localhost:3306")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.database == "")
    }

    // MARK: - MariaDB

    @Test("MariaDB URL")
    func testMariaDBURL() {
        let result = ConnectionURLParser.parse("mariadb://user:pass@host:3306/mydb")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mariadb)
        #expect(parsed.host == "host")
    }

    // MARK: - MongoDB

    @Test("MongoDB URL")
    func testMongoDBURL() {
        let result = ConnectionURLParser.parse("mongodb://admin:pass@mongo.example.com:27017/admin")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mongodb)
        #expect(parsed.host == "mongo.example.com")
        #expect(parsed.port == 27017)
        #expect(parsed.database == "admin")
    }

    @Test("MongoDB+SRV URL")
    func testMongoDBSrvURL() {
        let result = ConnectionURLParser.parse("mongodb+srv://user:pass@cluster.mongodb.net/mydb")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mongodb)
        #expect(parsed.host == "cluster.mongodb.net")
    }

    // MARK: - SQLite

    @Test("SQLite absolute path")
    func testSQLiteAbsolutePath() {
        let result = ConnectionURLParser.parse("sqlite:///Users/me/data.db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .sqlite)
        #expect(parsed.database == "/Users/me/data.db")
        #expect(parsed.host == "")
    }

    @Test("SQLite relative path")
    func testSQLiteRelativePath() {
        let result = ConnectionURLParser.parse("sqlite://data.db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .sqlite)
        #expect(parsed.database == "data.db")
    }

    // MARK: - SSL Mode

    @Test("SSL mode query parameter")
    func testSSLModeQueryParam() {
        let result = ConnectionURLParser.parse("postgresql://user:pass@host/db?sslmode=require")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.sslMode == .required)
    }

    @Test("SSL mode verify-ca")
    func testSSLModeVerifyCa() {
        let result = ConnectionURLParser.parse("postgresql://user:pass@host/db?sslmode=verify-ca")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.sslMode == .verifyCa)
    }

    @Test("SSL mode verify-full")
    func testSSLModeVerifyFull() {
        let result = ConnectionURLParser.parse("postgresql://user:pass@host/db?sslmode=verify-full")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.sslMode == .verifyIdentity)
    }

    @Test("No SSL mode returns nil")
    func testNoSSLModeReturnsNil() {
        let result = ConnectionURLParser.parse("postgresql://user:pass@host/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.sslMode == nil)
    }

    // MARK: - Percent Encoding

    @Test("Percent-encoded password")
    func testPercentEncodedPassword() {
        let result = ConnectionURLParser.parse("postgresql://user:p%40ss%23word@host/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.password == "p@ss#word")
    }

    @Test("Percent-encoded username")
    func testPercentEncodedUsername() {
        let result = ConnectionURLParser.parse("postgresql://user%40domain:pass@host/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.username == "user@domain")
    }

    // MARK: - Suggested Name

    @Test("Suggested name with host and database")
    func testSuggestedNameWithHostAndDatabase() {
        let result = ConnectionURLParser.parse("postgresql://user:pass@db.example.com/mydb")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.suggestedName == "PostgreSQL db.example.com/mydb")
    }

    @Test("Suggested name without database")
    func testSuggestedNameWithoutDatabase() {
        let result = ConnectionURLParser.parse("mysql://user:pass@localhost")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.suggestedName == "MySQL localhost")
    }

    // MARK: - Error Cases

    @Test("Empty string returns error")
    func testEmptyStringReturnsError() {
        let result = ConnectionURLParser.parse("")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure"); return
        }
        #expect(error == .emptyString)
    }

    @Test("Whitespace-only string returns error")
    func testWhitespaceOnlyReturnsError() {
        let result = ConnectionURLParser.parse("   ")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure"); return
        }
        #expect(error == .emptyString)
    }

    @Test("Invalid URL returns error")
    func testInvalidURLReturnsError() {
        let result = ConnectionURLParser.parse("not-a-url")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure"); return
        }
        #expect(error == .invalidURL)
    }

    @Test("Unsupported scheme returns error")
    func testUnsupportedSchemeReturnsError() {
        let result = ConnectionURLParser.parse("redis://host:6379")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure"); return
        }
        if case .unsupportedScheme(let scheme) = error {
            #expect(scheme == "redis")
        } else {
            Issue.record("Expected unsupportedScheme error")
        }
    }

    @Test("Missing host returns error")
    func testMissingHostReturnsError() {
        let result = ConnectionURLParser.parse("postgresql:///db")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure"); return
        }
        #expect(error == .missingHost)
    }

    // MARK: - Case Insensitivity

    @Test("Case-insensitive scheme")
    func testCaseInsensitiveScheme() {
        let result = ConnectionURLParser.parse("POSTGRESQL://user:pass@host/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .postgresql)
    }

    @Test("Mixed case scheme")
    func testMixedCaseScheme() {
        let result = ConnectionURLParser.parse("MySQL://user:pass@host/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mysql)
    }
}
