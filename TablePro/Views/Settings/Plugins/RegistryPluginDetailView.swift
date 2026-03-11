//
//  RegistryPluginDetailView.swift
//  TablePro
//

import SwiftUI

struct RegistryPluginDetailView: View {
    let plugin: RegistryPlugin
    let isInstalled: Bool
    let installProgress: InstallProgress?
    let downloadCount: Int?
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plugin.summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                detailItem(label: "Category", value: plugin.category.displayName)

                if let minVersion = plugin.minAppVersion {
                    detailItem(label: "Requires", value: "v\(minVersion)+")
                }

                if let downloadCount {
                    detailItem(
                        label: String(localized: "Downloads"),
                        value: formattedDownloadCount(downloadCount)
                    )
                }
            }

            HStack(spacing: 16) {
                detailItem(label: "Author", value: plugin.author.name)

                if let homepage = plugin.homepage, let url = URL(string: homepage) {
                    Link(destination: url) {
                        HStack(spacing: 2) {
                            Text("Homepage")
                                .font(.caption)
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                        }
                    }
                }
            }

            if plugin.isVerified {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text("Verified by TablePro")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            if !isInstalled, installProgress == nil {
                Button("Install Plugin") {
                    onInstall()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.leading, 34)
        .padding(.vertical, 8)
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private func formattedDownloadCount(_ count: Int) -> String {
        Self.decimalFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    @ViewBuilder
    private func detailItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.caption)
        }
    }
}
