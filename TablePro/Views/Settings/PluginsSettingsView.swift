//
//  PluginsSettingsView.swift
//  TablePro
//

import SwiftUI

struct PluginsSettingsView: View {
    @State private var selectedTab: PluginsSubTab = .installed

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Installed").tag(PluginsSubTab.installed)
                Text("Browse").tag(PluginsSubTab.browse)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)

            switch selectedTab {
            case .installed:
                InstalledPluginsView()
            case .browse:
                BrowsePluginsView()
            }
        }
    }
}

private enum PluginsSubTab: Hashable {
    case installed
    case browse
}

#Preview {
    PluginsSettingsView()
        .frame(width: 550, height: 500)
}
