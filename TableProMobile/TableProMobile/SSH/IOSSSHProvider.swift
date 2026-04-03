//
//  IOSSSHProvider.swift
//  TableProMobile
//

import Foundation
import TableProDatabase
import TableProModels

final class IOSSSHProvider: SSHProvider, @unchecked Sendable {
    private let tunnelStore = TunnelStore()
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
        let keyPassphrase: String? = if config.privateKeyPath != nil || config.privateKeyData != nil {
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
        await tunnelStore.add(tunnel, port: port)

        return TableProDatabase.SSHTunnel(localHost: "127.0.0.1", localPort: port)
    }

    func closeTunnel(for connectionId: UUID) async throws {
        guard let tunnel = await tunnelStore.removeFirst() else { return }
        await tunnel.close()
    }
}

private actor TunnelStore {
    var tunnels: [Int: SSHTunnel] = [:]

    func add(_ tunnel: SSHTunnel, port: Int) {
        tunnels[port] = tunnel
    }

    func removeFirst() -> SSHTunnel? {
        guard let (port, tunnel) = tunnels.first else { return nil }
        tunnels.removeValue(forKey: port)
        return tunnel
    }
}
