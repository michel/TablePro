import Testing
import Foundation
@testable import TableProModels

@Suite("DatabaseType Tests")
struct DatabaseTypeTests {
    @Test("Static constants have correct raw values")
    func staticConstants() {
        #expect(DatabaseType.mysql.rawValue == "mysql")
        #expect(DatabaseType.postgresql.rawValue == "postgresql")
        #expect(DatabaseType.sqlite.rawValue == "sqlite")
        #expect(DatabaseType.redis.rawValue == "redis")
        #expect(DatabaseType.mongodb.rawValue == "mongodb")
        #expect(DatabaseType.cloudflareD1.rawValue == "cloudflared1")
    }

    @Test("pluginTypeId maps multi-type databases")
    func pluginTypeIdMapping() {
        #expect(DatabaseType.mysql.pluginTypeId == "mysql")
        #expect(DatabaseType.mariadb.pluginTypeId == "mysql")
        #expect(DatabaseType.postgresql.pluginTypeId == "postgresql")
        #expect(DatabaseType.redshift.pluginTypeId == "postgresql")
        #expect(DatabaseType.sqlite.pluginTypeId == "sqlite")
    }

    @Test("Unknown types pass through pluginTypeId")
    func unknownTypePassthrough() {
        let custom = DatabaseType(rawValue: "custom_db")
        #expect(custom.pluginTypeId == "custom_db")
    }

    @Test("Codable round-trip preserves value")
    func codableRoundTrip() throws {
        let original = DatabaseType.postgresql
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DatabaseType.self, from: data)
        #expect(decoded == original)
    }

    @Test("Unknown type Codable round-trip")
    func unknownCodableRoundTrip() throws {
        let original = DatabaseType(rawValue: "future_db")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DatabaseType.self, from: data)
        #expect(decoded == original)
        #expect(decoded.rawValue == "future_db")
    }

    @Test("allKnownTypes contains all expected types")
    func allKnownTypesComplete() {
        #expect(DatabaseType.allKnownTypes.count == 16)
        #expect(DatabaseType.allKnownTypes.contains(.mysql))
        #expect(DatabaseType.allKnownTypes.contains(.bigquery))
    }

    @Test("Hashable conformance")
    func hashableConformance() {
        var set: Set<DatabaseType> = [.mysql, .postgresql, .mysql]
        #expect(set.count == 2)
        set.insert(DatabaseType(rawValue: "mysql"))
        #expect(set.count == 2)
    }
}
