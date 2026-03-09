//
//  RegistryPluginRow.swift
//  TablePro
//

import SwiftUI

struct RegistryPluginRow: View {
    let plugin: RegistryPlugin
    let isInstalled: Bool
    let installProgress: InstallProgress?
    let isExpanded: Bool
    let onInstall: () -> Void
    let onToggleDetail: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: plugin.iconName ?? "puzzlepiece")
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(plugin.name)
                        .fontWeight(.medium)

                    if plugin.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    }
                }

                HStack(spacing: 6) {
                    Text("v\(plugin.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\u{2022}")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)

                    Text(plugin.author.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            actionButton
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleDetail()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isInstalled {
            Text("Installed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        } else if let progress = installProgress {
            switch progress.phase {
            case .downloading(let fraction):
                ProgressView(value: fraction)
                    .frame(width: 60)
                    .progressViewStyle(.linear)

            case .installing:
                ProgressView()
                    .controlSize(.small)

            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .failed:
                Button("Retry") {
                    onInstall()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            Button("Install") {
                onInstall()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
