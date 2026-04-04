import Foundation

public protocol SecureStore: Sendable {
    func store(_ value: String, forKey key: String) throws
    func retrieve(forKey key: String) throws -> String?
    func delete(forKey key: String) throws
}
