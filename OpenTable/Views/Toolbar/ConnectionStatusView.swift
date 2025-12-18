//
//  ConnectionStatusView.swift
//  OpenTable
//
//  Central toolbar component displaying database type, version,
//  connection name, and connection state indicator.
//

import SwiftUI

/// Main connection status display for the toolbar center
struct ConnectionStatusView: View {
    let databaseType: DatabaseType
    let databaseVersion: String?
    let connectionName: String
    let connectionState: ToolbarConnectionState

    var body: some View {
        HStack(spacing: 10) {
            // Database type icon + version
            databaseInfoSection

            // Vertical separator
            Divider()
                .frame(height: 16)

            // Connection name + status indicator
            connectionInfoSection
        }
    }

    // MARK: - Subviews

    /// Database type icon and version info
    private var databaseInfoSection: some View {
        HStack(spacing: 6) {
            // Database type icon
            Image(systemName: databaseType.iconName)
                .font(.system(size: 14))
                .foregroundStyle(databaseType.themeColor)

            // Database type + version
            Text(formattedDatabaseInfo)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .help("Database: \(formattedDatabaseInfo)")
    }

    /// Connection name and status dot
    private var connectionInfoSection: some View {
        HStack(spacing: 8) {
            // Connection name
            Text(connectionName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Status indicator
            statusIndicator
        }
        .help(connectionState.description)
    }

    /// Animated status indicator dot
    @ViewBuilder
    private var statusIndicator: some View {
        if connectionState.isAnimating {
            // Show pulsing dot for connecting/executing states
            Circle()
                .fill(connectionState.indicatorColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(connectionState.indicatorColor.opacity(0.5), lineWidth: 2)
                        .scaleEffect(1.5)
                )
                .modifier(PulseAnimation())
        } else {
            // Static status dot
            Circle()
                .fill(connectionState.indicatorColor)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Computed Properties

    private var formattedDatabaseInfo: String {
        if let version = databaseVersion, !version.isEmpty {
            return "\(databaseType.rawValue) \(version)"
        }
        return databaseType.rawValue
    }
}

// MARK: - Pulse Animation

/// Subtle pulsing animation for active states
private struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.6 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Preview

#Preview("Connected") {
    ConnectionStatusView(
        databaseType: .mariadb,
        databaseVersion: "11.1.2",
        connectionName: "Production Database",
        connectionState: .connected
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Executing") {
    ConnectionStatusView(
        databaseType: .mysql,
        databaseVersion: "8.0.35",
        connectionName: "Development",
        connectionState: .executing
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Dark Mode") {
    ConnectionStatusView(
        databaseType: .postgresql,
        databaseVersion: "16.1",
        connectionName: "Analytics DB",
        connectionState: .connected
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
    .preferredColorScheme(.dark)
}
