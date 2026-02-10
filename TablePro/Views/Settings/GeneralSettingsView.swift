//
//  GeneralSettingsView.swift
//  TablePro
//
//  Settings for startup behavior and confirmations
//

import Sparkle
import SwiftUI

struct GeneralSettingsView: View {
    @Binding var settings: GeneralSettings
    @ObservedObject var updaterBridge: UpdaterBridge

    var body: some View {
        Form {
            Picker("When TablePro starts:", selection: $settings.startupBehavior) {
                ForEach(StartupBehavior.allCases) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }

            Section("Query Execution") {
                HStack {
                    Text("Query timeout:")
                    Stepper(
                        value: $settings.queryTimeoutSeconds,
                        in: 0...600,
                        step: 10
                    ) {
                        Text(settings.queryTimeoutSeconds == 0
                            ? "No limit"
                            : "\(settings.queryTimeoutSeconds) seconds")
                    }
                }
                .help("Maximum time to wait for a query to complete. Set to 0 for no limit. Applied to new connections.")
            }

            Section("Software Update") {
                Toggle("Automatically check for updates", isOn: $settings.automaticallyCheckForUpdates)
                    .onChange(of: settings.automaticallyCheckForUpdates) { newValue in
                        updaterBridge.updater.automaticallyChecksForUpdates = newValue
                    }

                Button("Check for Updates...") {
                    updaterBridge.checkForUpdates()
                }
                .disabled(!updaterBridge.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            updaterBridge.updater.automaticallyChecksForUpdates = settings.automaticallyCheckForUpdates
        }
    }
}

#Preview {
    GeneralSettingsView(
        settings: .constant(.default),
        updaterBridge: UpdaterBridge()
    )
    .frame(width: 450, height: 300)
}
