//
//  AnthropicProvider.swift
//  TablePro
//
//  Anthropic Claude API provider using the Messages API with SSE streaming.
//

import Foundation
import os

/// AI provider for Anthropic's Claude models
final class AnthropicProvider: AIProvider {
    private static let logger = Logger(subsystem: "com.TablePro", category: "AnthropicProvider")

    private let endpoint: String
    private let apiKey: String
    private let session: URLSession

    init(endpoint: String, apiKey: String) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = URLSession.shared
    }

    // MARK: - AIProvider

    func streamChat(
        messages: [AIChatMessage],
        model: String,
        systemPrompt: String?
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildMessagesRequest(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt
                    )

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIProviderError.networkError("Invalid response")
                    }

                    guard httpResponse.statusCode == 200 else {
                        let errorBody = try await collectErrorBody(from: bytes)
                        throw mapHTTPError(
                            statusCode: httpResponse.statusCode,
                            body: errorBody
                        )
                    }

                    var inputTokens = 0
                    var outputTokens = 0

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }

                        if let text = parseContentBlockDelta(jsonString) {
                            continuation.yield(.text(text))
                        }
                        if let tokens = parseInputTokens(jsonString) {
                            inputTokens = tokens
                        }
                        if let tokens = parseOutputTokens(jsonString) {
                            outputTokens = tokens
                        }
                    }

                    // Yield usage if we got any token data
                    if inputTokens > 0 || outputTokens > 0 {
                        continuation.yield(.usage(AITokenUsage(
                            inputTokens: inputTokens,
                            outputTokens: outputTokens
                        )))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func fetchAvailableModels() async throws -> [String] {
        // Anthropic doesn't have a models endpoint; return known models
        [
            "claude-sonnet-4-5-20250514",
            "claude-haiku-4-5-20251001",
            "claude-opus-4-20250514"
        ]
    }

    func testConnection() async throws -> Bool {
        let testMessage = AIChatMessage(role: .user, content: "Hi")
        let request = try buildMessagesRequest(
            messages: [testMessage],
            model: "claude-sonnet-4-5-20250514",
            systemPrompt: nil,
            maxTokens: 1
        )

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        // 200 = success, 401 = bad key
        return httpResponse.statusCode == 200
    }

    // MARK: - Private

    private func buildMessagesRequest(
        messages: [AIChatMessage],
        model: String,
        systemPrompt: String?,
        maxTokens: Int = 4096
    ) throws -> URLRequest {
        guard let url = URL(string: "\(endpoint)/v1/messages") else {
            throw AIProviderError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true
        ]

        if let systemPrompt {
            body["system"] = systemPrompt
        }

        // Convert messages (skip system role — handled via system parameter)
        let apiMessages = messages
            .filter { $0.role != .system }
            .map { message -> [String: String] in
                ["role": message.role.rawValue, "content": message.content]
            }
        body["messages"] = apiMessages

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseContentBlockDelta(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "content_block_delta",
              let delta = json["delta"] as? [String: Any],
              let text = delta["text"] as? String
        else {
            return nil
        }
        return text
    }

    private func parseInputTokens(_ jsonString: String) -> Int? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "message_start",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let inputTokens = usage["input_tokens"] as? Int
        else {
            return nil
        }
        return inputTokens
    }

    private func parseOutputTokens(_ jsonString: String) -> Int? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "message_delta",
              let usage = json["usage"] as? [String: Any],
              let outputTokens = usage["output_tokens"] as? Int
        else {
            return nil
        }
        return outputTokens
    }

    private func collectErrorBody(
        from bytes: URLSession.AsyncBytes
    ) async throws -> String {
        var body = ""
        for try await line in bytes.lines {
            body += line
            if body.count > 2000 { break }
        }
        return body
    }

    private func mapHTTPError(statusCode: Int, body: String) -> AIProviderError {
        switch statusCode {
        case 401:
            return .authenticationFailed(body)
        case 429:
            return .rateLimited
        case 404:
            return .modelNotFound(body)
        default:
            return .serverError(statusCode, body)
        }
    }
}
