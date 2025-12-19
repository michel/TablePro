//
//  WelcomeView.swift
//  OpenTable
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import SwiftUI

// MARK: - WelcomeView

/// Modern welcome page with unique centered layout and floating connection cards.
struct WelcomeView: View {
    let connections: [DatabaseConnection]
    var onSelectConnection: ((DatabaseConnection) -> Void)?
    var onEditConnection: ((DatabaseConnection) -> Void)?
    var onDeleteConnection: ((DatabaseConnection) -> Void)?
    var onAddConnection: () -> Void

    @State private var hoveredConnectionId: UUID?

    private var recentConnections: [DatabaseConnection] {
        Array(connections.prefix(6))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer()

                // App identity - centered, minimal
                appHeader

                Spacer()
                    .frame(height: 40)

                // Connections or empty state
                if recentConnections.isEmpty {
                    emptyState
                } else {
                    connectionsGrid
                }

                Spacer()
                    .frame(height: 32)

                // New connection button
                newConnectionButton

                Spacer()

                // Footer
                footer
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .closeCurrentTab)) { _ in
            // On welcome screen, Cmd+W closes the window (default macOS behavior)
            NSApplication.shared.keyWindow?.performClose(nil)
        }
    }

    // MARK: - App Header

    private var appHeader: some View {
        VStack(spacing: 12) {
            // Logo with subtle glow
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 88, height: 88)
                    .blur(radius: 20)

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
            }

            VStack(spacing: 4) {
                Text("OpenTable")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))

                Text("Connect to your databases")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Connections Grid

    private var connectionsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)],
                spacing: 12
            ) {
                ForEach(recentConnections) { connection in
                    ConnectionCard(
                        connection: connection,
                        onTap: { onSelectConnection?(connection) },
                        onEdit: { onEditConnection?(connection) },
                        onDelete: { onDeleteConnection?(connection) }
                    )
                }
            }
        }
        .frame(maxWidth: 520)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    .frame(width: 72, height: 72)

                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 4) {
                Text("No connections yet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Create your first connection to get started")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 160)
    }

    // MARK: - New Connection Button

    private var newConnectionButton: some View {
        Button(action: onAddConnection) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("New Connection")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.accentColor)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 24) {
            HStack(spacing: 16) {
                FooterHint(keys: "⌘N", label: "New")
                FooterHint(keys: "⌘,", label: "Settings")
            }

            Spacer()

            Text("v\(Bundle.main.appVersion)")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
}

// MARK: - ConnectionCard

/// Floating card for a connection with glassmorphism effect
private struct ConnectionCard: View {
    let connection: DatabaseConnection
    let onTap: () -> Void
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: connection.type.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(connection.type.themeColor)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(connection.type.themeColor.opacity(0.12))
                    )

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: { onTap() }) {
                Label("Connect", systemImage: "play.fill")
            }
            
            Divider()
            
            if let onEdit = onEdit {
                Button(action: onEdit) {
                    Label("Edit Connection", systemImage: "pencil")
                }
            }
            
            if let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Connection", systemImage: "trash")
                }
            }
        }
    }

    private var subtitle: String {
        if connection.host.isEmpty {
            return connection.database.isEmpty ? connection.type.rawValue : connection.database
        }
        return connection.host
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.ultraThinMaterial)
            .shadow(
                color: .black.opacity(0.06),
                radius: 6,
                y: 2
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
                Color.primary.opacity(0.06),
                lineWidth: 1
            )
    }
}

// MARK: - FooterHint

private struct FooterHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                )
            Text(label)
        }
    }
}

// MARK: - Bundle Extension

extension Bundle {
    fileprivate var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Preview

#Preview("With Connections") {
    WelcomeView(
        connections: DatabaseConnection.sampleConnections,
        onSelectConnection: { _ in },
        onAddConnection: {}
    )
    .frame(width: 700, height: 500)
}

#Preview("Empty") {
    WelcomeView(
        connections: [],
        onSelectConnection: { _ in },
        onAddConnection: {}
    )
    .frame(width: 700, height: 500)
}
