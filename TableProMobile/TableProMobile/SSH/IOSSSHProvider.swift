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

    /// Set by caller before createTunnel to enable connectionId-based Keychain lookup
    var pendingConnectionId: UUID?

    init(secureStore: SecureStore) {
        self.secureStore = secureStore
    }

    func createTunnel(
        config: SSHConfiguration,
        remoteHost: String,
        remotePort: Int
    ) async throws -> TableProDatabase.SSHTunnel {
        // Resolve SSH credentials using macOS-compatible Keychain keys
        let sshPassword: String?
        let keyPassphrase: String?

        if let connId = pendingConnectionId {
            sshPassword = try? secureStore.retrieve(
                forKey: "com.TablePro.sshpassword.\(connId.uuidString)")
            keyPassphrase = try? secureStore.retrieve(
                forKey: "com.TablePro.keypassphrase.\(connId.uuidString)")
        } else {
            sshPassword = nil
            keyPassphrase = nil
        }

        pendingConnectionId = nil

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
