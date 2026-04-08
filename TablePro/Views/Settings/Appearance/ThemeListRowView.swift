import SwiftUI

internal struct ThemeListRowView: View {
    let theme: ThemeDefinition

    var body: some View {
        HStack(spacing: 8) {
            ThemePreviewCard(theme: theme, isActive: false, onSelect: {}, size: .compact)

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name)
                    .font(.system(size: ThemeEngine.shared.activeTheme.typography.medium))
                    .lineLimit(1)

                Text(theme.isBuiltIn
                    ? String(localized: "Built-in")
                    : theme.isRegistry
                        ? String(localized: "Registry")
                        : String(localized: "Custom"))
                    .font(.system(size: ThemeEngine.shared.activeTheme.typography.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
