import Foundation
import TableProModels
import TableProPluginKit

public final class ConnectionManager: @unchecked Sendable {
    private let pluginLoader: PluginLoader
    private let secureStore: SecureStore
    private let sshProvider: SSHProvider?

    private let lock = NSLock()
    private var sessions: [UUID: ConnectionSession] = [:]

    public init(
        pluginLoader: PluginLoader,
        secureStore: SecureStore,
        sshProvider: SSHProvider? = nil
    ) {
        self.pluginLoader = pluginLoader
        self.secureStore = secureStore
        self.sshProvider = sshProvider
    }

    public func connect(_ connection: DatabaseConnection) async throws -> ConnectionSession {
        let password = try secureStore.retrieve(forKey: connection.id.uuidString)

        var effectiveHost = connection.host
        var effectivePort = connection.port
        if connection.sshEnabled, let ssh = connection.sshConfiguration {
            guard let provider = sshProvider else {
                throw ConnectionError.sshNotSupported
            }
            let tunnel = try await provider.createTunnel(
                config: ssh,
                remoteHost: connection.host,
                remotePort: connection.port
            )
            effectiveHost = tunnel.localHost
            effectivePort = tunnel.localPort
        }

        do {
            guard let plugin = pluginLoader.driverPlugin(for: connection.type.pluginTypeId) else {
                throw ConnectionError.pluginNotFound(connection.type.rawValue)
            }

            let config = DriverConnectionConfig(
                host: effectiveHost,
                port: effectivePort,
                username: connection.username,
                password: password ?? "",
                database: connection.database,
                additionalFields: connection.additionalFields
            )
            let pluginDriver = plugin.createDriver(config: config)

            let driver = PluginDriverAdapter(pluginDriver: pluginDriver)
            try await driver.connect()

            let session = ConnectionSession(
                connectionId: connection.id,
                driver: driver,
                activeDatabase: connection.database,
                status: .connected
            )
            storeSession(session, for: connection.id)
            return session
        } catch {
            if connection.sshEnabled, let provider = sshProvider {
                try? await provider.closeTunnel(for: connection.id)
            }
            throw error
        }
    }

    public func disconnect(_ connectionId: UUID) async {
        let session = removeSession(for: connectionId)

        guard let session else { return }
        try? await session.driver.disconnect()

        if let sshProvider {
            try? await sshProvider.closeTunnel(for: connectionId)
        }
    }

    public func updateSession(_ connectionId: UUID, _ mutation: (inout ConnectionSession) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard var session = sessions[connectionId] else { return }
        mutation(&session)
        sessions[connectionId] = session
    }

    public func switchDatabase(_ connectionId: UUID, to database: String) async throws {
        guard let session = session(for: connectionId) else {
            throw ConnectionError.notConnected
        }
        try await session.driver.switchDatabase(to: database)
        updateSession(connectionId) { $0.activeDatabase = database }
    }

    private func storeSession(_ session: ConnectionSession, for id: UUID) {
        lock.lock()
        sessions[id] = session
        lock.unlock()
    }

    private func removeSession(for id: UUID) -> ConnectionSession? {
        lock.lock()
        let session = sessions.removeValue(forKey: id)
        lock.unlock()
        return session
    }

    public func session(for connectionId: UUID) -> ConnectionSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[connectionId]
    }
}
