import Testing
@testable import TablePro

@Suite("DatabaseType Cassandra Properties")
struct DatabaseTypeCassandraTests {
    @Test("Cassandra raw value is Cassandra")
    func cassandraRawValue() {
        #expect(DatabaseType(rawValue: "Cassandra").rawValue == "Cassandra")
    }

    @Test("ScyllaDB raw value is ScyllaDB")
    func scylladbRawValue() {
        #expect(DatabaseType(rawValue: "ScyllaDB").rawValue == "ScyllaDB")
    }

    @Test("Cassandra pluginTypeId is Cassandra")
    func cassandraPluginTypeId() {
        #expect(DatabaseType(rawValue: "Cassandra").pluginTypeId == "Cassandra")
    }

    @Test("ScyllaDB pluginTypeId is Cassandra")
    func scylladbPluginTypeId() {
        #expect(DatabaseType(rawValue: "ScyllaDB").pluginTypeId == "Cassandra")
    }

    @Test("Cassandra default port is 9042")
    func cassandraDefaultPort() {
        #expect(DatabaseType(rawValue: "Cassandra").defaultPort == 9_042)
    }

    @Test("ScyllaDB default port is 9042")
    func scylladbDefaultPort() {
        #expect(DatabaseType(rawValue: "ScyllaDB").defaultPort == 9_042)
    }

    @Test("Cassandra does not require authentication")
    func cassandraRequiresAuthentication() {
        #expect(DatabaseType(rawValue: "Cassandra").requiresAuthentication == false)
    }

    @Test("ScyllaDB does not require authentication")
    func scylladbRequiresAuthentication() {
        #expect(DatabaseType(rawValue: "ScyllaDB").requiresAuthentication == false)
    }

    @Test("Cassandra does not support foreign keys")
    func cassandraSupportsForeignKeys() {
        #expect(DatabaseType(rawValue: "Cassandra").supportsForeignKeys == false)
    }

    @Test("ScyllaDB does not support foreign keys")
    func scylladbSupportsForeignKeys() {
        #expect(DatabaseType(rawValue: "ScyllaDB").supportsForeignKeys == false)
    }

    @Test("Cassandra supports schema editing")
    func cassandraSupportsSchemaEditing() {
        #expect(DatabaseType(rawValue: "Cassandra").supportsSchemaEditing == true)
    }

    @Test("ScyllaDB supports schema editing")
    func scylladbSupportsSchemaEditing() {
        #expect(DatabaseType(rawValue: "ScyllaDB").supportsSchemaEditing == true)
    }

    @Test("Cassandra icon name is cassandra-icon")
    func cassandraIconName() {
        #expect(DatabaseType(rawValue: "Cassandra").iconName == "cassandra-icon")
    }

    @Test("ScyllaDB icon name is scylladb-icon")
    func scylladbIconName() {
        #expect(DatabaseType(rawValue: "ScyllaDB").iconName == "scylladb-icon")
    }

    @Test("Cassandra is a downloadable plugin")
    func cassandraIsDownloadablePlugin() {
        #expect(DatabaseType(rawValue: "Cassandra").isDownloadablePlugin == true)
    }

    @Test("ScyllaDB is a downloadable plugin")
    func scylladbIsDownloadablePlugin() {
        #expect(DatabaseType(rawValue: "ScyllaDB").isDownloadablePlugin == true)
    }

    @Test("Cassandra included in allCases")
    func cassandraIncludedInAllCases() {
        #expect(DatabaseType.allCases.contains(DatabaseType(rawValue: "Cassandra")))
    }

    @Test("ScyllaDB included in allCases")
    func scylladbIncludedInAllCases() {
        #expect(DatabaseType.allCases.contains(DatabaseType(rawValue: "ScyllaDB")))
    }
}
