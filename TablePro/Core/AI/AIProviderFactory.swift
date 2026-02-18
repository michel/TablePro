//
//  AIProviderFactory.swift
//  TablePro
//
//  Factory for creating AI provider instances based on configuration.
//

import Foundation

/// Factory for creating AI provider instances
enum AIProviderFactory {
    /// Create an AI provider for the given configuration
    static func createProvider(
        for config: AIProviderConfig,
        apiKey: String?
    ) -> AIProvider {
        switch config.type {
        case .claude:
            return AnthropicProvider(
                endpoint: config.endpoint,
                apiKey: apiKey ?? ""
            )
        case .openAI, .openRouter, .ollama, .custom:
            return OpenAICompatibleProvider(
                endpoint: config.endpoint,
                apiKey: apiKey,
                providerType: config.type
            )
        }
    }
}
