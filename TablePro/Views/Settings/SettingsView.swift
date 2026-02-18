//
//  SettingsView.swift
//  TablePro
//
//  Main settings view using macOS native TabView style
//

import SwiftUI

/// Main settings view with tab-based navigation (macOS Settings style)
struct SettingsView: View {
    @StateObject private var settingsManager = AppSettingsManager.shared
    @EnvironmentObject var updaterBridge: UpdaterBridge

    var body: some View {
        TabView {
            GeneralSettingsView(settings: $settingsManager.general, updaterBridge: updaterBridge)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AppearanceSettingsView(settings: $settingsManager.appearance)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            EditorSettingsView(settings: $settingsManager.editor)
                .tabItem {
                    Label("Editor", systemImage: "doc.text")
                }

            DataGridSettingsView(settings: $settingsManager.dataGrid)
                .tabItem {
                    Label("Data Grid", systemImage: "tablecells")
                }

            TabSettingsView(settings: $settingsManager.tabs)
                .tabItem {
                    Label("Tabs", systemImage: "rectangle.on.rectangle")
                }

            KeyboardSettingsView(settings: $settingsManager.keyboard)
                .tabItem {
                    Label("Keyboard", systemImage: "keyboard")
                }

            HistorySettingsView(settings: $settingsManager.history)
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            AISettingsView(settings: $settingsManager.ai)
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            LicenseSettingsView()
                .tabItem {
                    Label("License", systemImage: "key")
                }
        }
        .frame(width: 620, height: 450)
    }
}

#Preview {
    SettingsView()
        .environmentObject(UpdaterBridge())
}
