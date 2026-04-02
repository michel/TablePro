//
//  IOSSSHProvider.swift
//  TableProMobile
//
//  SSHProvider implementation for iOS using libssh2.
//

import Foundation
import TableProDatabase
import TableProModels

final class IOSSSHProvider: SSHProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var activeTunnels: [Int: SSHTunnel] = [:]
    private let secureStore: SecureStore

    init(secureStore: SecureStore) {
        self.secureStore = secureStore
    }

    func createTunnel(
        config: SSHConfiguration,
        remoteHost: String,
        remotePort: Int
    ) async throws -> TableProDatabase.SSHTunnel {
        let sshPassword = try? secureStore.retrieve(forKey: "ssh-\(config.host)-\(config.username)")
        let keyPassphrase: String? = if config.privateKeyPath != nil {
            try? secureStore.retrieve(forKey: "ssh-key-\(config.host)-\(config.username)")
        } else {
            nil
        }

        let tunnel = try await SSHTunnelFactory.create(
            config: config,
            remoteHost: remoteHost,
            remotePort: remotePort,
            sshPassword: sshPassword,
            keyPassphrase: keyPassphrase
        )

        let port = await tunnel.port

        lock.lock()
        activeTunnels[port] = tunnel
        lock.unlock()

        return TableProDatabase.SSHTunnel(localHost: "127.0.0.1", localPort: port)
    }

    func closeTunnel(for connectionId: UUID) async throws {
        lock.lock()
        let allTunnels = activeTunnels
        activeTunnels.removeAll()
        lock.unlock()

        for (_, tunnel) in allTunnels {
            await tunnel.close()
        }
    }
}
