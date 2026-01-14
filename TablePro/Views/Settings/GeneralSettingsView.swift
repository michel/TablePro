//
//  GeneralSettingsView.swift
//  TablePro
//
//  Settings for startup behavior and confirmations
//

import SwiftUI

struct GeneralSettingsView: View {
    @Binding var settings: GeneralSettings

    var body: some View {
        Form {
            Picker("When TablePro starts:", selection: $settings.startupBehavior) {
                ForEach(StartupBehavior.allCases) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }

            Section("Confirmations") {
                Toggle("Confirm before disconnecting", isOn: $settings.confirmBeforeDisconnecting)

                Toggle(
                    "Confirm before dangerous queries (DROP, TRUNCATE, DELETE)",
                    isOn: $settings.confirmBeforeDangerousQuery
                )

                Toggle(
                    "Confirm before closing with unsaved changes",
                    isOn: $settings.confirmBeforeClosingUnsaved
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    GeneralSettingsView(settings: .constant(.default))
        .frame(width: 450, height: 300)
}
