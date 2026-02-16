//
//  TabSettingsView.swift
//  TablePro
//
//  Settings for tab behavior
//

import SwiftUI

struct TabSettingsView: View {
    @Binding var settings: TabSettings

    var body: some View {
        Form {
            Section("Tab Behavior") {
                Toggle("Reuse clean table tab", isOn: $settings.reuseCleanTableTab)
                    .help("When enabled, clicking a new table replaces the current clean table tab instead of opening a new tab")

                Text(
                    "When enabled, clicking a table in the sidebar will replace the current tab if it has no unsaved changes and you haven't interacted with it (sorted, filtered, etc.)."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    TabSettingsView(settings: .constant(.default))
}
