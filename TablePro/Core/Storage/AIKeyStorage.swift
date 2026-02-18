//
//  AIKeyStorage.swift
//  TablePro
//
//  Keychain storage for AI provider API keys.
//  Follows ConnectionStorage.swift Keychain pattern.
//

import Foundation
import os
import Security

/// Singleton Keychain storage for AI provider API keys
final class AIKeyStorage {
    static let shared = AIKeyStorage()
    private static let logger = Logger(subsystem: "com.TablePro", category: "AIKeyStorage")

    private init() {}

    // MARK: - API Key Operations

    /// Save an API key to Keychain for the given provider
    func saveAPIKey(_ apiKey: String, for providerID: UUID) {
        let key = "com.TablePro.aikey.\(providerID.uuidString)"

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        guard let data = apiKey.data(using: .utf8) else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            Self.logger.error("Failed to save API key for provider \(providerID.uuidString): \(status)")
        }
    }

    /// Load an API key from Keychain for the given provider
    func loadAPIKey(for providerID: UUID) -> String? {
        let key = "com.TablePro.aikey.\(providerID.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return apiKey
    }

    /// Delete an API key from Keychain for the given provider
    func deleteAPIKey(for providerID: UUID) {
        let key = "com.TablePro.aikey.\(providerID.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }
}
