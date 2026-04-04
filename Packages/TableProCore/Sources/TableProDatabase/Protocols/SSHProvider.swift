import Foundation
import TableProModels

public protocol SSHProvider: Sendable {
    func createTunnel(
        config: SSHConfiguration,
        remoteHost: String,
        remotePort: Int
    ) async throws -> SSHTunnel

    func closeTunnel(for connectionId: UUID) async throws
}

public struct SSHTunnel: Sendable {
    public let localHost: String
    public let localPort: Int

    public init(localHost: String, localPort: Int) {
        self.localHost = localHost
        self.localPort = localPort
    }
}
