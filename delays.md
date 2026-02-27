# Delay Audit — TablePro

All `Task.sleep`, `asyncAfter`, and polling loops in the codebase, organized by severity.

---

## Critical — Affects tab creation / user-visible lag

| #   | File                                        | Line | Delay                   | Code                                                                                       | Status |
| --- | ------------------------------------------- | ---- | ----------------------- | ------------------------------------------------------------------------------------------ | ------ |
| 1   | `Views/MainContentView.swift`               | 410  | **300ms**               | `Task.sleep(nanoseconds: 300_000_000)` before opening restored tabs                        | DONE   |
| 2   | `Views/MainContentView.swift`               | 415  | **100ms/tab**           | `Task.sleep(nanoseconds: 100_000_000)` between each restored tab open                      | DONE   |
| 3   | `Core/Services/TabPersistenceService.swift` | 205  | **100ms × 50 = 5s max** | Polling loop: `waitForConnectionAndExecute` polls connection every 100ms, up to 50 retries | DONE   |
| 4   | `AppDelegate.swift`                         | 259  | **300ms**               | `asyncAfter(deadline: .now() + 0.3)` before posting `.openSQLFiles` after connection       | DONE   |
| 5   | `AppDelegate.swift`                         | 277  | **100ms**               | `asyncAfter(deadline: .now() + 0.1)` before opening main window during auto-reconnect      | DONE   |
| 6   | `AppDelegate.swift`                         | 310  | **100ms**               | `asyncAfter(deadline: .now() + 0.1)` before closing restored main windows                  | DONE   |

### Details

**#1-2: Tab restoration delays** (`MainContentView.initializeAndRestoreTabs`)

```swift
Task { @MainActor in
    try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms wait
    for tab in remainingTabs {
        WindowOpener.shared.openNativeTab(payload)
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms between tabs
    }
}
```

With 5 tabs: 300ms + 4×100ms = **700ms** of hardcoded delay. Could be replaced with event-driven readiness signals or reduced delays.

**#3: Connection polling loop** (`TabPersistenceService.waitForConnectionAndExecute`)

```swift
while retryCount < 50 {
    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms per poll
    retryCount += 1
    if session.isConnected { onReady(); return }
}
```

Could be replaced with `DatabaseManager.$activeSessions` publisher — react to connection state change instead of polling.

**#4: SQL file open delay** (`AppDelegate.handleDatabaseDidConnect`)

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    NotificationCenter.default.post(name: .openSQLFiles, object: urls)
}
```

300ms arbitrary delay to "allow coordinator to finish setup." Could use a readiness signal instead.

**#5-6: Window management delays** (`AppDelegate`)
Small 100ms delays for window ordering. Low impact individually but add up.

---

## Moderate — Editor / autocomplete responsiveness

| #   | File                                        | Line | Delay     | Code                                                        | Status |
| --- | ------------------------------------------- | ---- | --------- | ----------------------------------------------------------- | ------ |
| 7   | `Views/Editor/SQLCompletionAdapter.swift`   | 57   | **50ms**  | `Task.sleep(nanoseconds: 50_000_000)` autocomplete debounce | OK     |
| 8   | `Views/Editor/SQLEditorCoordinator.swift`   | 93   | **50ms**  | `asyncAfter(deadline: .now() + 0.05)` frame change throttle | OK     |
| 9   | `Core/Services/TabPersistenceService.swift` | 67   | **500ms** | `Task.sleep(nanoseconds: 500_000_000)` tab save debounce    | OK     |
| 10  | `Core/Services/TabPersistenceService.swift` | 256  | **500ms** | `Task.sleep(nanoseconds: 500_000_000)` query save debounce  | OK     |

These debounces are correctly tuned — they prevent excessive I/O or computation without visible lag.

---

## Low — UI feedback & search debounce

| #   | File                                      | Line | Delay     | Code                          | Status |
| --- | ----------------------------------------- | ---- | --------- | ----------------------------- | ------ |
| 11  | `Views/Editor/HistoryPanelView.swift`     | 309  | **150ms** | Search debounce               | OK     |
| 12  | `Views/History/HistoryDataProvider.swift` | 85   | **150ms** | Search debounce               | OK     |
| 13  | `Views/Settings/AISettingsView.swift`     | 517  | **800ms** | Model fetch debounce          | OK     |
| 14  | `Views/Editor/HistoryPanelView.swift`     | 325  | **50ms**  | Selection update after delete | OK     |
| 15  | `Views/Editor/HistoryPanelView.swift`     | 347  | **1s**    | "Copied!" feedback reset      | OK     |
| 16  | `Views/Components/SQLReviewPopover.swift` | 178  | **2s**    | "Copied" feedback reset       | OK     |
| 17  | `Views/Filter/SQLPreviewSheet.swift`      | 82   | **2s**    | "Copied" feedback reset       | OK     |
| 18  | `Views/AIChat/AIChatCodeBlockView.swift`  | 45   | **2s**    | "Copied" feedback reset       | OK     |

All fine — standard UI patterns for debounce and feedback.

---

## Background — Connection health & services (non-blocking, correct behavior)

| #   | File                                          | Line   | Delay              | Code                          | Status |
| --- | --------------------------------------------- | ------ | ------------------ | ----------------------------- | ------ |
| 19  | `Core/Database/ConnectionHealthMonitor.swift` | 107    | **30s loop**       | Health ping every 30s         | OK     |
| 20  | `Core/Database/ConnectionHealthMonitor.swift` | 178    | **2/4/8s**         | Reconnect exponential backoff | OK     |
| 21  | `Core/Database/DatabaseManager.swift`         | 574    | **2s**             | VPN reconnect grace period    | OK     |
| 22  | `Core/SSH/SSHTunnelManager.swift`             | 74     | **30s loop**       | SSH tunnel health check       | OK     |
| 23  | `Core/SSH/SSHTunnelManager.swift`             | 385    | **250ms poll**     | Port reachability probe       | OK     |
| 24  | `Views/Main/MainContentCoordinator.swift`     | 1308   | **5s**             | Schema provider grace period  | OK     |
| 25  | `Core/Services/LicenseManager.swift`          | 92     | **7d loop**        | License revalidation          | OK     |
| 26  | `Core/Services/AnalyticsService.swift`        | 63, 67 | **10s + 24h loop** | Analytics heartbeat           | OK     |

---

## UI Workarounds — Welcome window suppression

| #   | File                            | Line    | Delay                  | Code                                    | Status |
| --- | ------------------------------- | ------- | ---------------------- | --------------------------------------- | ------ |
| 27  | `AppDelegate.swift`             | 229-240 | **100/300/600/1000ms** | Staggered welcome window close attempts | OK     |
| 28  | `Views/WelcomeWindowView.swift` | 348     | **20ms poll**          | Window focus retry loop                 | OK     |

SwiftUI window lifecycle workarounds — fragile but necessary until Apple provides better APIs.

---

## Fix Priority

1. **#3** — Replace connection polling with reactive `$activeSessions` publisher (eliminates up to 5s delay)
2. **#1-2** — Reduce/eliminate tab restoration delays (saves 300-700ms on app launch)
3. **#4** — Replace arbitrary 300ms file-open delay with readiness check
4. **#5-6** — Minor AppDelegate delays (low priority, 100ms each)
