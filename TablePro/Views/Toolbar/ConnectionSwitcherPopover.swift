//
//  ConnectionSwitcherPopover.swift
//  TablePro
//
//  Quick-switch popover for active and saved connections.
//  Shown from the toolbar connection button.
//

import SwiftUI

/// Popover content for quick connection switching
struct ConnectionSwitcherPopover: View {
    @State private var savedConnections: [DatabaseConnection] = []
    @State private var isConnecting: UUID?

    /// Callback when the popover should dismiss
    var onDismiss: (() -> Void)?

    private var activeSessions: [UUID: ConnectionSession] {
        DatabaseManager.shared.activeSessions
    }

    private var currentSessionId: UUID? {
        DatabaseManager.shared.currentSessionId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active connections section
            if !activeSessions.isEmpty {
                sectionHeader("Active Connections")

                ForEach(Array(activeSessions.values).sorted(by: { $0.lastActiveAt > $1.lastActiveAt })) { session in
                    connectionRow(
                        connection: session.connection,
                        isActive: session.id == currentSessionId,
                        isConnected: session.status.isConnected
                    )
                    .onTapGesture {
                        switchToSession(session.id)
                    }
                }

                Divider()
                    .padding(.vertical, 4)
            }

            // Saved connections (not currently active)
            let inactiveSaved = savedConnections.filter { activeSessions[$0.id] == nil }
            if !inactiveSaved.isEmpty {
                sectionHeader("Saved Connections")

                ForEach(inactiveSaved) { connection in
                    connectionRow(
                        connection: connection,
                        isActive: false,
                        isConnected: false,
                        isConnecting: isConnecting == connection.id
                    )
                    .onTapGesture {
                        connectToSaved(connection)
                    }
                }

                Divider()
                    .padding(.vertical, 4)
            }

            // Manage connections button
            Button {
                onDismiss?()
                NotificationCenter.default.post(name: .openWelcomeWindow, object: nil)
            } label: {
                HStack {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                    Text("Manage Connections...")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .padding(.vertical, 8)
        .frame(width: 280)
        .onAppear {
            savedConnections = ConnectionStorage.shared.loadConnections()
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private func connectionRow(
        connection: DatabaseConnection,
        isActive: Bool,
        isConnected: Bool,
        isConnecting: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            // Color indicator
            Circle()
                .fill(connection.displayColor)
                .frame(width: 8, height: 8)

            // Connection info
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)

                Text(connectionSubtitle(connection))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            if isConnecting {
                ProgressView()
                    .controlSize(.small)
            } else if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            } else if isConnected {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }

            // Database type badge
            Text(connection.type.rawValue.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            isActive
                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.1))
                : nil
        )
    }

    // MARK: - Helpers

    private func connectionSubtitle(_ connection: DatabaseConnection) -> String {
        if connection.type == .sqlite {
            return connection.database
        }
        let port = connection.port != connection.type.defaultPort ? ":\(connection.port)" : ""
        return "\(connection.host)\(port)/\(connection.database)"
    }

    private func switchToSession(_ sessionId: UUID) {
        onDismiss?()
        DatabaseManager.shared.switchToSession(sessionId)
    }

    private func connectToSaved(_ connection: DatabaseConnection) {
        isConnecting = connection.id
        onDismiss?()
        Task {
            try? await DatabaseManager.shared.connectToSession(connection)
            await MainActor.run {
                isConnecting = nil
            }
        }
    }
}
