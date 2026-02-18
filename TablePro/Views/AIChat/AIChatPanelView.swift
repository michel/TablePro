//
//  AIChatPanelView.swift
//  TablePro
//
//  AI chat panel view - right-side panel for conversing with AI about database queries.
//

import OSLog
import SwiftUI

/// AI chat panel displayed alongside the main editor content
struct AIChatPanelView: View {
    let connection: DatabaseConnection
    let tables: [TableInfo]
    var coordinator: MainContentCoordinator?

    @StateObject private var viewModel = AIChatViewModel()
    @State private var isNearBottom: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if viewModel.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            Divider()

            inputArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.connection = connection
            viewModel.tables = tables
        }
        .onChange(of: tables) { newTables in
            viewModel.tables = newTables
        }
        .task(id: tables) {
            await fetchSchemaContext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sendAIPrompt)) { notification in
            guard let userInfo = notification.userInfo,
                  let prompt = userInfo["prompt"] as? String,
                  let featureRaw = userInfo["feature"] as? String,
                  let feature = AIFeature(rawValue: featureRaw) else { return }
            updateContext()
            viewModel.sendWithContext(prompt: prompt, feature: feature)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label(String(localized: "AI Chat"), systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // History menu
            Menu {
                Button {
                    viewModel.startNewConversation()
                } label: {
                    Label(String(localized: "New Conversation"), systemImage: "plus")
                }

                if !viewModel.conversations.isEmpty {
                    Divider()

                    ForEach(viewModel.conversations) { conversation in
                        Button {
                            viewModel.switchConversation(to: conversation.id)
                        } label: {
                            HStack {
                                Text(conversation.title.isEmpty
                                    ? String(localized: "Untitled")
                                    : conversation.title)
                                if conversation.id == viewModel.activeConversationID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Conversation History"))

            // New chat button
            Button {
                viewModel.startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "New Conversation"))

            // Clear/trash button
            if !viewModel.messages.isEmpty {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Clear Conversation"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Ask AI about your database")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Get help writing queries, explaining schemas, or fixing errors.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        if message.role != .system {
                            AIChatMessageView(
                                message: message,
                                onRetry: shouldShowRetry(for: message) ? { viewModel.retry() } : nil,
                                onRegenerate: shouldShowRegenerate(for: message) ? { viewModel.regenerate() } : nil
                            )
                            .id(message.id)
                        }
                    }

                    // Invisible bottom anchor to track scroll position
                    Color.clear
                        .frame(height: 1)
                        .id("bottomAnchor")
                        .onAppear { isNearBottom = true }
                        .onDisappear { isNearBottom = false }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.last?.content) { _ in
                if isNearBottom {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottomAnchor", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.messages.count) { _ in
                // Always scroll on new message (user just sent a message)
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.1))
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                String(localized: "Ask about your database..."),
                text: $viewModel.inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .onSubmit {
                if !NSEvent.modifierFlags.contains(.shift) {
                    updateContext()
                    viewModel.sendMessage()
                }
            }

            if viewModel.isStreaming {
                Button {
                    viewModel.cancelStream()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Stop Generating"))
            } else {
                Button {
                    updateContext()
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .secondary : .accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(String(localized: "Send Message"))
            }
        }
        .padding(12)
    }

    // MARK: - Schema Context

    private static let logger = Logger(subsystem: "com.TablePro", category: "AIChatPanelView")

    /// Fetch column and foreign key info for tables and populate the view model.
    /// Respects AI settings (`includeSchema`, `maxSchemaTables`).
    private func fetchSchemaContext() async {
        let settings = AppSettingsManager.shared.ai
        guard settings.includeSchema,
              let driver = DatabaseManager.shared.activeDriver
        else { return }

        let tablesToFetch = Array(tables.prefix(settings.maxSchemaTables))
        var columns: [String: [ColumnInfo]] = [:]
        var foreignKeys: [String: [ForeignKeyInfo]] = [:]

        for table in tablesToFetch {
            do {
                let cols = try await driver.fetchColumns(table: table.name)
                columns[table.name] = cols

                let fks = try await driver.fetchForeignKeys(table: table.name)
                foreignKeys[table.name] = fks
            } catch {
                // Schema fetch failure is non-critical — skip this table
                Self.logger.warning(
                    "Failed to fetch schema for table '\(table.name)': \(error.localizedDescription)"
                )
                continue
            }
        }

        viewModel.columnsByTable = columns
        viewModel.foreignKeysByTable = foreignKeys
    }

    // MARK: - Helpers

    private func updateContext() {
        viewModel.currentQuery = coordinator?.tabManager.selectedTab?.query
    }

    private func shouldShowRetry(for message: AIChatMessage) -> Bool {
        message.role == .user
            && message.id == viewModel.messages.last?.id
            && viewModel.lastMessageFailed
    }

    private func shouldShowRegenerate(for message: AIChatMessage) -> Bool {
        message.role == .assistant
            && message.id == viewModel.messages.last?.id
            && !viewModel.isStreaming
            && !message.content.isEmpty
    }
}
