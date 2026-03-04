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
        let result = ConnectionURLParser.parse("ftp://host:21")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure"); return
        }
        if case .unsupportedScheme(let scheme) = error {
            #expect(scheme == "ftp")
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

    // MARK: - MongoDB

    @Test("Full MongoDB URL")
    func testFullMongoDBURL() {
        let result = ConnectionURLParser.parse("mongodb://admin:secret@mongo.example.com:27017/mydb")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mongodb)
        #expect(parsed.host == "mongo.example.com")
        #expect(parsed.port == 27017)
        #expect(parsed.database == "mydb")
        #expect(parsed.username == "admin")
        #expect(parsed.password == "secret")
    }

    @Test("MongoDB+SRV scheme")
    func testMongoDBSrvScheme() {
        let result = ConnectionURLParser.parse("mongodb+srv://user:pass@cluster.mongodb.net/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mongodb)
        #expect(parsed.port == nil)
    }

    @Test("MongoDB with authSource")
    func testMongoDBWithAuthSource() {
        let result = ConnectionURLParser.parse("mongodb://user:pass@host/db?authSource=admin")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.authSource == "admin")
    }

    // MARK: - Multiple Query Parameters

    @Test("Multiple query parameters")
    func testMultipleQueryParameters() {
        let result = ConnectionURLParser.parse("postgresql://user:pass@host/db?sslmode=require&connect_timeout=10")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.sslMode == .required)
    }

    // MARK: - SSH Tunnel URLs

    @Test("Full mysql+ssh URL")
    func testFullMySQLSSHURL() {
        let result = ConnectionURLParser.parse("mysql+ssh://root@123.123.123.123:1234/database_user:database_password@127.0.0.1/database_name?name=FlashPanel&usePrivateKey=true&env=production")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mysql)
        #expect(parsed.host == "127.0.0.1")
        #expect(parsed.port == nil)
        #expect(parsed.database == "database_name")
        #expect(parsed.username == "database_user")
        #expect(parsed.password == "database_password")
        #expect(parsed.sshHost == "123.123.123.123")
        #expect(parsed.sshPort == 1234)
        #expect(parsed.sshUsername == "root")
        #expect(parsed.usePrivateKey == true)
        #expect(parsed.connectionName == "FlashPanel")
    }

    @Test("PostgreSQL SSH URL")
    func testPostgreSQLSSHURL() {
        let result = ConnectionURLParser.parse("postgresql+ssh://deploy@db.example.com:22/admin:secret@10.0.0.5/mydb")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .postgresql)
        #expect(parsed.host == "10.0.0.5")
        #expect(parsed.database == "mydb")
        #expect(parsed.username == "admin")
        #expect(parsed.password == "secret")
        #expect(parsed.sshHost == "db.example.com")
        #expect(parsed.sshPort == 22)
        #expect(parsed.sshUsername == "deploy")
    }

    @Test("Postgres SSH scheme alias")
    func testPostgresSSHAlias() {
        let result = ConnectionURLParser.parse("postgres+ssh://user@host:22/dbuser:pass@localhost/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .postgresql)
        #expect(parsed.sshHost == "host")
    }

    @Test("MariaDB SSH URL")
    func testMariaDBSSHURL() {
        let result = ConnectionURLParser.parse("mariadb+ssh://admin@192.168.1.1:2222/root:pass@127.0.0.1/production")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mariadb)
        #expect(parsed.sshHost == "192.168.1.1")
        #expect(parsed.sshPort == 2222)
        #expect(parsed.sshUsername == "admin")
        #expect(parsed.host == "127.0.0.1")
        #expect(parsed.database == "production")
    }

    @Test("SSH URL without SSH port")
    func testSSHURLWithoutSSHPort() {
        let result = ConnectionURLParser.parse("mysql+ssh://root@myserver/dbuser:pass@localhost/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.sshHost == "myserver")
        #expect(parsed.sshPort == nil)
        #expect(parsed.sshUsername == "root")
    }

    @Test("SSH URL with connection name")
    func testSSHURLWithConnectionName() {
        let result = ConnectionURLParser.parse("mysql+ssh://root@host:22/user:pass@localhost/db?name=My+Server")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.connectionName == "My Server")
        #expect(parsed.suggestedName == "My Server")
    }

    @Test("SSH URL with usePrivateKey")
    func testSSHURLWithUsePrivateKey() {
        let result = ConnectionURLParser.parse("mysql+ssh://root@host:22/user:pass@localhost/db?usePrivateKey=true")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.usePrivateKey == true)
    }

    @Test("Non-SSH URL has nil SSH fields")
    func testNonSSHURLHasNilSSHFields() {
        let result = ConnectionURLParser.parse("mysql://root:pass@localhost:3306/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.sshHost == nil)
        #expect(parsed.sshPort == nil)
        #expect(parsed.sshUsername == nil)
        #expect(parsed.usePrivateKey == nil)
        #expect(parsed.connectionName == nil)
    }

    @Test("Case-insensitive SSH scheme")
    func testCaseInsensitiveSSHScheme() {
        let result = ConnectionURLParser.parse("MYSQL+SSH://root@host:22/user:pass@localhost/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .mysql)
        #expect(parsed.sshHost == "host")
    }

    @Test("SSH URL with percent-encoded password")
    func testSSHURLPercentEncodedPassword() {
        let result = ConnectionURLParser.parse("mysql+ssh://root@host:22/dbuser:p%40ss%23word@localhost/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.username == "dbuser")
        #expect(parsed.password == "p@ss#word")
        #expect(parsed.sshUsername == "root")
    }

    @Test("SSH URL with percent-encoded SSH username")
    func testSSHURLPercentEncodedSSHUsername() {
        let result = ConnectionURLParser.parse("mysql+ssh://user%40domain@host:22/dbuser:pass@localhost/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.sshUsername == "user@domain")
    }

    @Test("SSH URL with IPv6 host in brackets")
    func testSSHURLIPv6Host() {
        let result = ConnectionURLParser.parse("mysql+ssh://root@[::1]:22/dbuser:pass@[fe80::1]:3306/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.sshHost == "::1")
        #expect(parsed.sshPort == 22)
        #expect(parsed.host == "fe80::1")
        #expect(parsed.port == 3306)
    }

    // MARK: - Redshift

    @Test("Full Redshift URL")
    func testFullRedshiftURL() {
        let result = ConnectionURLParser.parse("redshift://admin:secret@cluster.us-east-1.redshift.amazonaws.com:5439/mydb")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redshift)
        #expect(parsed.host == "cluster.us-east-1.redshift.amazonaws.com")
        #expect(parsed.port == 5439)
        #expect(parsed.database == "mydb")
        #expect(parsed.username == "admin")
        #expect(parsed.password == "secret")
    }

    @Test("Redshift without port")
    func testRedshiftWithoutPort() {
        let result = ConnectionURLParser.parse("redshift://user:pass@host/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redshift)
        #expect(parsed.port == nil)
        #expect(parsed.host == "host")
        #expect(parsed.database == "db")
    }

    @Test("Redshift with SSL mode")
    func testRedshiftWithSSL() {
        let result = ConnectionURLParser.parse("redshift://user:pass@host:5439/db?sslmode=require")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redshift)
        #expect(parsed.sslMode == .required)
        #expect(parsed.port == 5439)
    }

    @Test("Redshift suggested name includes host and database")
    func testRedshiftSuggestedName() {
        let result = ConnectionURLParser.parse("redshift://user:pass@cluster.example.com/analytics")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.suggestedName == "Redshift cluster.example.com/analytics")
    }

    @Test("Redshift without user")
    func testRedshiftWithoutUser() {
        let result = ConnectionURLParser.parse("redshift://host:5439/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.username == "")
        #expect(parsed.password == "")
        #expect(parsed.host == "host")
    }

    @Test("Case-insensitive Redshift scheme")
    func testCaseInsensitiveRedshiftScheme() {
        let result = ConnectionURLParser.parse("REDSHIFT://user:pass@host/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redshift)
    }

    // MARK: - Redis

    @Test("Redis URL parses host and port")
    func testRedisBasicURL() {
        let result = ConnectionURLParser.parse("redis://localhost:6379")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redis)
        #expect(parsed.host == "localhost")
        #expect(parsed.port == 6379)
        #expect(parsed.redisDatabase == nil)
    }

    @Test("Redis URL with database index")
    func testRedisURLWithDatabaseIndex() {
        let result = ConnectionURLParser.parse("redis://localhost:6379/3")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redis)
        #expect(parsed.redisDatabase == 3)
        #expect(parsed.database == "")
    }

    @Test("Redis URL without port")
    func testRedisURLWithoutPort() {
        let result = ConnectionURLParser.parse("redis://localhost")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redis)
        #expect(parsed.host == "localhost")
        #expect(parsed.port == nil)
    }

    @Test("Rediss scheme enables SSL")
    func testRedissSchemeEnablesSSL() {
        let result = ConnectionURLParser.parse("rediss://host:6379")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redis)
        #expect(parsed.sslMode == .required)
    }

    @Test("Redis URL with password only")
    func testRedisURLWithPasswordOnly() {
        let result = ConnectionURLParser.parse("redis://:password@localhost:6379")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redis)
        #expect(parsed.password == "password")
        #expect(parsed.host == "localhost")
    }

    @Test("Redis URL with user, password, and database index")
    func testRedisURLWithUserPasswordAndDatabase() {
        let result = ConnectionURLParser.parse("redis://user:pass@localhost:6379/2")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redis)
        #expect(parsed.username == "user")
        #expect(parsed.password == "pass")
        #expect(parsed.host == "localhost")
        #expect(parsed.port == 6379)
        #expect(parsed.redisDatabase == 2)
        #expect(parsed.database == "")
    }

    @Test("Redis URL with database index zero")
    func testRedisURLWithDatabaseIndexZero() {
        let result = ConnectionURLParser.parse("redis://localhost:6379/0")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .redis)
        #expect(parsed.redisDatabase == 0)
        #expect(parsed.database == "")
    }
}
