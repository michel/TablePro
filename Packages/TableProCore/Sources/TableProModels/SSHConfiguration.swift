import Foundation

public struct SSHConfiguration: Codable, Hashable, Sendable {
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: SSHAuthMethod
    public var privateKeyPath: String?
    public var jumpHosts: [SSHJumpHost]

    public enum SSHAuthMethod: String, Codable, Sendable {
        case password
        case privateKey
        case sshAgent
        case keyboardInteractive

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "password": self = .password
            case "privateKey", "publicKey": self = .privateKey
            case "sshAgent", "agent": self = .sshAgent
            case "keyboardInteractive": self = .keyboardInteractive
            default: self = .password
            }
        }
    }

    public init(
        host: String = "",
        port: Int = 22,
        username: String = "",
        authMethod: SSHAuthMethod = .password,
        privateKeyPath: String? = nil,
        jumpHosts: [SSHJumpHost] = []
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.jumpHosts = jumpHosts
    }

    // Custom Codable to handle macOS extra fields gracefully
    private enum CodingKeys: String, CodingKey {
        case host, port, username, authMethod, privateKeyPath, jumpHosts
        // macOS-only fields we read but ignore
        case enabled, useSSHConfig, agentSocketPath
        case totpMode, totpAlgorithm, totpDigits, totpPeriod
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = (try? container.decode(String.self, forKey: .host)) ?? ""
        port = (try? container.decode(Int.self, forKey: .port)) ?? 22
        username = (try? container.decode(String.self, forKey: .username)) ?? ""
        authMethod = (try? container.decode(SSHAuthMethod.self, forKey: .authMethod)) ?? .password
        privateKeyPath = try? container.decode(String.self, forKey: .privateKeyPath)
        jumpHosts = (try? container.decode([SSHJumpHost].self, forKey: .jumpHosts)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(authMethod, forKey: .authMethod)
        try container.encodeIfPresent(privateKeyPath, forKey: .privateKeyPath)
        try container.encode(jumpHosts, forKey: .jumpHosts)
    }
}

public struct SSHJumpHost: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var host: String
    public var port: Int
    public var username: String

    public init(
        id: UUID = UUID(),
        host: String = "",
        port: Int = 22,
        username: String = ""
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.username = username
    }
}
