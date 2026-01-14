//
//  HistorySettingsView.swift
//  TablePro
//
//  Settings for query history retention and cleanup
//

import SwiftUI

struct HistorySettingsView: View {
    @Binding var settings: HistorySettings
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section("Retention") {
                Picker("Maximum entries:", selection: $settings.maxEntries) {
                    Text("100").tag(100)
                    Text("500").tag(500)
                    Text("1,000").tag(1000)
                    Text("5,000").tag(5000)
                    Text("10,000").tag(10000)
                    Text("Unlimited").tag(0)
                }

                Picker("Keep entries for:", selection: $settings.maxDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("Forever").tag(0)
                }

                Toggle("Auto cleanup on startup", isOn: $settings.autoCleanup)
            }

            Section("Maintenance") {
                HStack {
                    Text("Clear all query history")
                    Spacer()
                    Button("Clear History...") {
                        showClearConfirmation = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Clear All History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearAllHistory()
            }
        } message: {
            Text("This will permanently delete all query history entries. This action cannot be undone.")
        }
    }

    private func clearAllHistory() {
        _ = QueryHistoryManager.shared.clearAllHistory()
    }
}

#Preview {
    HistorySettingsView(settings: .constant(.default))
        .frame(width: 450, height: 350)
}
