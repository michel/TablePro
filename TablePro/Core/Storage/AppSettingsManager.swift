//
//  AppSettingsManager.swift
//  TablePro
//
//  Observable settings manager for real-time UI updates.
//  Uses @Published properties with didSet for immediate persistence.
//

import Combine
import Foundation

/// Observable settings manager for immediate persistence and live updates
@MainActor
final class AppSettingsManager: ObservableObject {
    static let shared = AppSettingsManager()

    // MARK: - Published Settings

    @Published var general: GeneralSettings {
        didSet {
            general.language.apply()
            storage.saveGeneral(general)
            notifyChange(domain: "general", notification: .generalSettingsDidChange)
        }
    }

    @Published var appearance: AppearanceSettings {
        didSet {
            storage.saveAppearance(appearance)
            appearance.theme.apply()
            notifyChange(domain: "appearance", notification: .appearanceSettingsDidChange)
        }
    }

    @Published var editor: EditorSettings {
        didSet {
            storage.saveEditor(editor)
            // Update cached theme values for thread-safe access
            SQLEditorTheme.reloadFromSettings(editor)
            notifyChange(domain: "editor", notification: .editorSettingsDidChange)
        }
    }

    @Published var dataGrid: DataGridSettings {
        didSet {
            // Validate and sanitize before saving
            var validated = dataGrid
            validated.nullDisplay = dataGrid.validatedNullDisplay
            validated.defaultPageSize = dataGrid.validatedDefaultPageSize

            storage.saveDataGrid(validated)
            // Update date formatting service with new format
            DateFormattingService.shared.updateFormat(validated.dateFormat)
            notifyChange(domain: "dataGrid", notification: .dataGridSettingsDidChange)
        }
    }

    @Published var history: HistorySettings {
        didSet {
            // Validate before saving
            var validated = history
            validated.maxEntries = history.validatedMaxEntries
            validated.maxDays = history.validatedMaxDays

            storage.saveHistory(validated)
            // Apply history settings immediately (cleanup if auto-cleanup enabled)
            Task { await applyHistorySettingsImmediately() }
            notifyChange(domain: "history", notification: .historySettingsDidChange)
        }
    }

    @Published var tabs: TabSettings {
        didSet {
            storage.saveTabs(tabs)
            notifyChange(domain: "tabs", notification: .tabSettingsDidChange)
        }
    }

    @Published var keyboard: KeyboardSettings {
        didSet {
            storage.saveKeyboard(keyboard)
            notifyChange(domain: "keyboard", notification: .keyboardSettingsDidChange)
        }
    }

    @Published var ai: AISettings {
        didSet {
            storage.saveAI(ai)
            notifyChange(domain: "ai", notification: .aiSettingsDidChange)
        }
    }

    private let storage = AppSettingsStorage.shared

    // MARK: - Initialization

    private init() {
        // Load all settings on initialization
        self.general = storage.loadGeneral()
        self.appearance = storage.loadAppearance()
        self.editor = storage.loadEditor()
        self.dataGrid = storage.loadDataGrid()
        self.history = storage.loadHistory()
        self.tabs = storage.loadTabs()
        self.keyboard = storage.loadKeyboard()
        self.ai = storage.loadAI()

        // Apply appearance settings immediately
        appearance.theme.apply()
        general.language.apply()

        // Load editor theme settings into cache (pass settings directly to avoid circular dependency)
        SQLEditorTheme.reloadFromSettings(editor)

        // Initialize DateFormattingService with current format
        DateFormattingService.shared.updateFormat(dataGrid.dateFormat)
    }

    // MARK: - Notification Propagation

    /// Notify listeners that settings have changed
    /// Posts both domain-specific and generic notifications
    private func notifyChange(domain: String, notification: Notification.Name) {
        let changeInfo = SettingsChangeInfo(domain: domain, changedKeys: nil)

        // Post domain-specific notification
        NotificationCenter.default.post(
            name: notification,
            object: self,
            userInfo: [SettingsChangeInfo.userInfoKey: changeInfo]
        )

        // Post generic notification for listeners that want all settings changes
        NotificationCenter.default.post(
            name: .settingsDidChange,
            object: self,
            userInfo: [SettingsChangeInfo.userInfoKey: changeInfo]
        )
    }

    /// Apply history settings immediately (triggered on settings change)
    private func applyHistorySettingsImmediately() async {
        // This will be called by QueryHistoryManager
        // We post a notification and let the manager handle the actual cleanup
        // This keeps the settings manager decoupled from history storage implementation
    }

    // MARK: - Actions

    /// Reset all settings to defaults
    func resetToDefaults() {
        general = .default
        appearance = .default
        editor = .default
        dataGrid = .default
        history = .default
        tabs = .default
        keyboard = .default
        ai = .default
        storage.resetToDefaults()
    }
}
