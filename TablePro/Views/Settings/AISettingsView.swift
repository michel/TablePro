//
//  AISettingsView.swift
//  TablePro
//
//  Settings tab for AI provider configuration, feature routing, and context options.
//

import SwiftUI

/// AI settings tab in the Settings window
struct AISettingsView: View {
    @Binding var settings: AISettings

    @State private var selectedProviderID: UUID?
    @State private var editingAPIKey: String = ""
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?
    @State private var fetchedModels: [UUID: [String]] = [:]
    @State private var isFetchingModels: [UUID: Bool] = [:]
    @State private var modelFetchError: String?

    private enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            providersSection
            featureRoutingSection
            contextSection
            privacySection
        }
        .formStyle(.grouped)
    }

    // MARK: - Providers Section

    private var providersSection: some View {
        Section {
            ForEach(settings.providers) { provider in
                providerRow(provider)
            }

            Button {
                addProvider()
            } label: {
                Label(String(localized: "Add Provider"), systemImage: "plus")
            }

            if let selectedID = selectedProviderID,
               let index = settings.providers.firstIndex(where: { $0.id == selectedID }) {
                providerDetailEditor(index: index)
            }
        } header: {
            Text("Providers")
        }
    }

    private func providerRow(_ provider: AIProviderConfig) -> some View {
        HStack {
            Image(systemName: iconForProviderType(provider.type))
                .foregroundStyle(provider.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name.isEmpty ? provider.type.displayName : provider.name)
                    .fontWeight(.medium)
                Text(provider.model.isEmpty ? String(localized: "No model selected") : provider.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !provider.isEnabled {
                Text("Disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                selectedProviderID = provider.id
                loadAPIKeyForProvider(provider)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)

            Button {
                removeProvider(provider.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private func providerDetailEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(String(localized: "Name"), text: $settings.providers[index].name)
                .textFieldStyle(.roundedBorder)

            Picker(String(localized: "Type"), selection: $settings.providers[index].type) {
                ForEach(AIProviderType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .onChange(of: settings.providers[index].type) { newType in
                let currentEndpoint = settings.providers[index].endpoint
                let allDefaults = AIProviderType.allCases.map(\.defaultEndpoint)
                if currentEndpoint.isEmpty || allDefaults.contains(currentEndpoint) {
                    settings.providers[index].endpoint = newType.defaultEndpoint
                }
            }

            if settings.providers[index].type.requiresAPIKey {
                SecureField("API Key", text: $editingAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: editingAPIKey) { newValue in
                        AIKeyStorage.shared.saveAPIKey(newValue, for: settings.providers[index].id)
                    }
            }

            TextField("Endpoint", text: $settings.providers[index].endpoint)
                .textFieldStyle(.roundedBorder)

            modelField(index: index)

            HStack {
                Toggle(String(localized: "Enabled"), isOn: $settings.providers[index].isEnabled)

                Spacer()

                Button {
                    testProvider(at: index)
                } label: {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: testResultIcon)
                                .foregroundStyle(testResultColor)
                        }
                        Text("Test")
                    }
                }
                .disabled(isTesting)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Feature Routing Section

    private var featureRoutingSection: some View {
        Section {
            ForEach(AIFeature.allCases) { feature in
                HStack {
                    Text(feature.displayName)
                    Spacer()
                    Picker("", selection: featureRouteBinding(for: feature)) {
                        Text(String(localized: "Default")).tag(UUID?.none as UUID?)
                        ForEach(settings.providers.filter(\.isEnabled)) { provider in
                            Text(provider.name.isEmpty ? provider.type.displayName : provider.name)
                                .tag(UUID?.some(provider.id) as UUID?)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        } header: {
            Text("Feature Routing")
        }
    }

    // MARK: - Context Section

    private var contextSection: some View {
        Section {
            Toggle(String(localized: "Include database schema"), isOn: $settings.includeSchema)
            Toggle(String(localized: "Include current query"), isOn: $settings.includeCurrentQuery)
            Toggle(String(localized: "Include query results"), isOn: $settings.includeQueryResults)

            Stepper(
                String(localized: "Max schema tables: \(settings.maxSchemaTables)"),
                value: $settings.maxSchemaTables,
                in: 1...100
            )
        } header: {
            Text("Context")
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            Picker(
                String(localized: "Default connection policy"),
                selection: $settings.defaultConnectionPolicy
            ) {
                ForEach(AIConnectionPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
        } header: {
            Text("Privacy")
        }
    }

    // MARK: - Model Picker

    private func modelField(index: Int) -> some View {
        let providerID = settings.providers[index].id
        let models = fetchedModels[providerID] ?? []

        return VStack(alignment: .leading, spacing: 4) {
            if models.isEmpty {
                HStack {
                    Text("Model")
                    Spacer()
                    if isFetchingModels[providerID] == true {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(String(localized: "Click to load models"))
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear {
                    fetchModels(at: index)
                }
            } else {
                Picker("Model", selection: $settings.providers[index].model) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            if let error = modelFetchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func fetchModels(at index: Int) {
        let config = settings.providers[index]
        let providerID = config.id
        let apiKey = AIKeyStorage.shared.loadAPIKey(for: providerID)
        let provider = AIProviderFactory.createProvider(for: config, apiKey: apiKey)

        isFetchingModels[providerID] = true
        modelFetchError = nil

        Task {
            do {
                let models = try await provider.fetchAvailableModels()
                fetchedModels[providerID] = models

                // Auto-select first model if field is empty
                if settings.providers[index].model.isEmpty, let first = models.first {
                    settings.providers[index].model = first
                }

                isFetchingModels[providerID] = false
            } catch {
                modelFetchError = error.localizedDescription
                isFetchingModels[providerID] = false
            }
        }
    }

    // MARK: - Helpers

    private func addProvider() {
        let newProvider = AIProviderConfig()
        settings.providers.append(newProvider)
        selectedProviderID = newProvider.id
        editingAPIKey = ""
    }

    private func removeProvider(_ id: UUID) {
        settings.providers.removeAll { $0.id == id }
        AIKeyStorage.shared.deleteAPIKey(for: id)
        if selectedProviderID == id {
            selectedProviderID = nil
        }
        // Clean up feature routing references
        for key in settings.featureRouting.keys {
            if settings.featureRouting[key]?.providerID == id {
                settings.featureRouting.removeValue(forKey: key)
            }
        }
    }

    private func loadAPIKeyForProvider(_ provider: AIProviderConfig) {
        editingAPIKey = AIKeyStorage.shared.loadAPIKey(for: provider.id) ?? ""
        testResult = nil
    }

    private func testProvider(at index: Int) {
        let config = settings.providers[index]
        let apiKey = AIKeyStorage.shared.loadAPIKey(for: config.id)
        let provider = AIProviderFactory.createProvider(for: config, apiKey: apiKey)

        isTesting = true
        testResult = nil

        Task {
            do {
                let success = try await provider.testConnection()
                isTesting = false
                testResult = success ? .success : .failure(String(localized: "Connection test failed"))
            } catch {
                isTesting = false
                testResult = .failure(error.localizedDescription)
            }
        }
    }

    private func featureRouteBinding(for feature: AIFeature) -> Binding<UUID?> {
        Binding(
            get: { settings.featureRouting[feature.rawValue]?.providerID },
            set: { newValue in
                if let providerID = newValue {
                    let model = settings.providers.first(where: { $0.id == providerID })?.model ?? ""
                    settings.featureRouting[feature.rawValue] = AIFeatureRoute(
                        providerID: providerID,
                        model: model
                    )
                } else {
                    settings.featureRouting.removeValue(forKey: feature.rawValue)
                }
            }
        )
    }

    private func iconForProviderType(_ type: AIProviderType) -> String {
        switch type {
        case .claude: return "brain"
        case .openAI: return "cpu"
        case .openRouter: return "arrow.triangle.branch"
        case .ollama: return "desktopcomputer"
        case .custom: return "gearshape"
        }
    }

    private var testResultIcon: String {
        switch testResult {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .none: return "bolt.horizontal"
        }
    }

    private var testResultColor: Color {
        switch testResult {
        case .success: return .green
        case .failure: return .red
        case .none: return .secondary
        }
    }
}
