//
//  SSHTunnelFactory.swift
//  TableProMobile
//
//  Stateless factory that creates fully-connected, authenticated SSH tunnels.
//

import Foundation
import CLibSSH2
import TableProModels

enum SSHTunnelFactory {
    private static let initialized: Bool = {
        libssh2_init(0)
        return true
    }()

    static func create(
        config: SSHConfiguration,
        remoteHost: String,
        remotePort: Int,
        sshPassword: String?,
        keyPassphrase: String?
    ) async throws -> SSHTunnel {
        _ = initialized

        let tunnel = SSHTunnel()

        try await tunnel.connect(host: config.host, port: config.port)
        try await tunnel.handshake()

        switch config.authMethod {
        case .password:
            guard let password = sshPassword else {
                throw SSHTunnelError.authenticationFailed("No SSH password provided")
            }
            try await tunnel.authenticatePassword(username: config.username, password: password)

        case .privateKey:
            guard let keyPath = config.privateKeyPath else {
                throw SSHTunnelError.authenticationFailed("No private key path provided")
            }
            try await tunnel.authenticatePublicKey(
                username: config.username,
                keyPath: keyPath,
                passphrase: keyPassphrase
            )

        default:
            throw SSHTunnelError.authenticationFailed(
                "Auth method \(config.authMethod.rawValue) not supported on iOS"
            )
        }

        try await tunnel.startForwarding(remoteHost: remoteHost, remotePort: remotePort)
        await tunnel.startKeepAlive()

        return tunnel
    }
}
