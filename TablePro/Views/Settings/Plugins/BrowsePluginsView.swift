//
//  BrowsePluginsView.swift
//  TablePro
//

import SwiftUI

struct BrowsePluginsView: View {
    private let registryClient = RegistryClient.shared
    private let pluginManager = PluginManager.shared
    private let installTracker = PluginInstallTracker.shared
    private let downloadCountService = DownloadCountService.shared

    @State private var searchText = ""
    @State private var selectedCategory: RegistryCategory?
    @State private var selectedPluginId: String?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            searchAndFilterBar
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            contentView
        }
        .task {
            if registryClient.fetchState == .idle {
                await registryClient.fetchManifest()
            }
            await downloadCountService.fetchCounts(for: registryClient.manifest)
        }
        .alert("Installation Failed", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Search & Filter

    @ViewBuilder
    private var searchAndFilterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search plugins...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(title: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }

                    ForEach(RegistryCategory.allCases) { category in
                        FilterChip(
                            title: category.displayName,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch registryClient.fetchState {
        case .idle, .loading:
            VStack {
                Spacer()
                ProgressView("Loading plugins...")
                Spacer()
            }
            .frame(maxWidth: .infinity)

        case .loaded:
            let plugins = registryClient.search(query: searchText, category: selectedCategory)
            if plugins.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "puzzlepiece.extension")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No plugins found")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(plugins) { plugin in
                            VStack(spacing: 0) {
                                RegistryPluginRow(
                                    plugin: plugin,
                                    isInstalled: isPluginInstalled(plugin.id),
                                    installProgress: installTracker.state(for: plugin.id),
                                    downloadCount: downloadCountService.downloadCount(for: plugin.id),
                                    onInstall: { installPlugin(plugin) },
                                    onToggleDetail: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedPluginId = selectedPluginId == plugin.id ? nil : plugin.id
                                        }
                                    }
                                )

                                if selectedPluginId == plugin.id {
                                    RegistryPluginDetailView(
                                        plugin: plugin,
                                        isInstalled: isPluginInstalled(plugin.id),
                                        installProgress: installTracker.state(for: plugin.id),
                                        downloadCount: downloadCountService.downloadCount(for: plugin.id),
                                        onInstall: { installPlugin(plugin) }
                                    )
                                }

                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "wifi.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Failed to load plugin registry")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task {
                        await registryClient.fetchManifest(forceRefresh: true)
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func isPluginInstalled(_ pluginId: String) -> Bool {
        pluginManager.plugins.contains { $0.id == pluginId }
    }

    private func installPlugin(_ plugin: RegistryPlugin) {
        Task {
            installTracker.beginInstall(pluginId: plugin.id)
            do {
                _ = try await pluginManager.installFromRegistry(plugin) { fraction in
                    installTracker.updateProgress(pluginId: plugin.id, fraction: fraction)
                    if fraction >= 1.0 {
                        installTracker.markInstalling(pluginId: plugin.id)
                    }
                }
                installTracker.completeInstall(pluginId: plugin.id)
            } catch {
                installTracker.failInstall(pluginId: plugin.id, error: error.localizedDescription)
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }
}
