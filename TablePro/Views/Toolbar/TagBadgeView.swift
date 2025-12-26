//
//  TagBadgeView.swift
//  TablePro
//
//  Tag badge for toolbar display.
//

import SwiftUI

/// Compact badge showing the connection's tag
struct TagBadgeView: View {
    let tag: ConnectionTag

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.system(size: 9, weight: .semibold))

            Text(tag.name.uppercased())
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(tag.color.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tag.color.color.opacity(0.2))
        )
        .help("Tag: \(tag.name)")
    }
}

// MARK: - Preview

#Preview("Tag Badges") {
    VStack(spacing: 12) {
        TagBadgeView(tag: ConnectionTag(name: "local", isPreset: true, color: .green))
        TagBadgeView(tag: ConnectionTag(name: "production", isPreset: true, color: .red))
        TagBadgeView(tag: ConnectionTag(name: "development", isPreset: true, color: .blue))
        TagBadgeView(tag: ConnectionTag(name: "testing", isPreset: true, color: .orange))
    }
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
