import Testing
@testable import TablePro

@Suite("DatabaseType Redis Properties")
struct DatabaseTypeRedisTests {
    @Test("Default port is 6379")
    func defaultPort() {
        #expect(DatabaseType(rawValue: "Redis").defaultPort == 6_379)
    }

    @Test("Icon name is redis-icon")
    func iconName() {
        #expect(DatabaseType(rawValue: "Redis").iconName == "redis-icon")
    }

    @Test("Does not require authentication")
    func requiresAuthentication() {
        #expect(DatabaseType(rawValue: "Redis").requiresAuthentication == false)
    }

    @Test("Does not support foreign keys")
    func supportsForeignKeys() {
        #expect(DatabaseType(rawValue: "Redis").supportsForeignKeys == false)
    }

    @Test("Does not support schema editing")
    func supportsSchemaEditing() {
        #expect(DatabaseType(rawValue: "Redis").supportsSchemaEditing == false)
    }

    @Test("Raw value is Redis")
    func rawValue() {
        #expect(DatabaseType(rawValue: "Redis").rawValue == "Redis")
    }

    @Test("Theme color is derived from plugin brand color")
    @MainActor func themeColor() {
        #expect(DatabaseType(rawValue: "Redis").themeColor == PluginManager.shared.brandColor(for: DatabaseType(rawValue: "Redis")))
    }

    @Test("Included in allKnownTypes")
    func includedInAllKnownTypes() {
        #expect(DatabaseType.allKnownTypes.contains(DatabaseType(rawValue: "Redis")))
    }

    @Test("Included in allCases shim")
    func includedInAllCases() {
        #expect(DatabaseType.allCases.contains(DatabaseType(rawValue: "Redis")))
    }
}
