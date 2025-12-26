//
//  ConnectionBadgeView.swift
//  TablePro
//
//  Environment badge showing connection type (LOCAL, SSH, PROD, STAGING).
//  Uses a capsule shape with color-coded background.
//

import SwiftUI

/// Compact badge showing the connection environment type
struct ConnectionBadgeView: View {
    let environment: ConnectionEnvironment

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: environment.iconName)
                .font(.system(size: 9, weight: .semibold))

            Text(environment.rawValue)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(environment.foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(environment.backgroundColor)
        )
        .help("Connection environment: \(environment.rawValue)")
    }
}

// MARK: - Preview

#Preview("All Environments") {
    HStack(spacing: 12) {
        ConnectionBadgeView(environment: .local)
        ConnectionBadgeView(environment: .ssh)
        ConnectionBadgeView(environment: .production)
        ConnectionBadgeView(environment: .staging)
    }
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Dark Mode") {
    HStack(spacing: 12) {
        ConnectionBadgeView(environment: .local)
        ConnectionBadgeView(environment: .ssh)
    }
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
    .preferredColorScheme(.dark)
}
