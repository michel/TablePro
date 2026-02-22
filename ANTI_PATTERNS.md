# TablePro Anti-Patterns & macOS Incorrect Approaches

Audit date: 2026-02-22 | Total issues: 56 | Fixed: 48 | Deferred: 8

## Status Legend

- FIXED — Merged to main
- DEFERRED — Too invasive for automated fix; requires manual refactoring

---

## 1. SwiftUI Anti-Patterns (13 issues)

| ID   | Issue                                                                                                | Severity | Status   | Commit               |
| ---- | ---------------------------------------------------------------------------------------------------- | -------- | -------- | -------------------- |
| S-01 | `@StateObject` for singleton/shared instances in child views — should be `@ObservedObject`           | High     | FIXED    | `e41cce9`            |
| S-02 | `@StateObject` re-creates instances on each parent re-render (WelcomeWindowView, ConnectionFormView) | High     | FIXED    | `e41cce9`            |
| S-03 | Multiple `.sheet(isPresented:)` on same view — only last one works reliably                          | Medium   | DEFERRED | —                    |
| S-04 | `ForEach(enumerated())` without stable ID — use `ForEach(array.indices)` or identifiable             | Medium   | FIXED    | `752388b`, `004419a` |
| S-05 | `@State` storing `Task` handles without cancellation on disappear                                    | High     | FIXED    | `57dd77f`            |
| S-06 | Duplicate default initializers on `@StateObject` properties in MainContentView                       | Low      | FIXED    | `714dbf4`            |
| S-07 | `withAnimation` inside model layer (FilterState) — animation belongs in view                         | Medium   | FIXED    | `1778917`            |
| S-08 | Deprecated single-param `onChange(of:)` — migrate to two-param closure                               | Medium   | FIXED    | `57dd77f`            |
| S-09 | Deprecated `.foregroundColor()` — use `.foregroundStyle()`                                           | Low      | FIXED    | `b6fd684`            |
| S-10 | `ForEach(Range)` without explicit `.id()` — unstable for dynamic ranges                              | Low      | FIXED    | `5fac119`            |
| S-11 | `.onAppear { Task { } }` — use `.task` modifier instead                                              | Medium   | FIXED    | `59b02a5`            |
| S-12 | Missing `private` on `@StateObject var coordinator` in MainContentView                               | Low      | FIXED    | `b2ad3f3`            |
| S-13 | I/O in `.onAppear` without re-entry guard — use `.task`                                              | Low      | FIXED    | `7c57858`            |

## 2. AppKit Anti-Patterns (13 issues)

| ID   | Issue                                                                           | Severity | Status | Commit    |
| ---- | ------------------------------------------------------------------------------- | -------- | ------ | --------- |
| A-01 | NSTextStorage mutations without `beginEditing()`/`endEditing()` batching        | High     | FIXED  | `112b8c7` |
| A-02 | Regex patterns compiled on every invocation instead of cached as `static let`   | Medium   | FIXED  | `f56eb48` |
| A-03 | `UpdaterBridge` retain cycle via `.assign(to:on:)` — use `[weak self]` sink     | High     | FIXED  | `9b4b10a` |
| A-04 | `SQLEditorCoordinator` leaked NotificationCenter observer (no cleanup)          | High     | FIXED  | `8685966` |
| A-05 | Data population in `makeNSView` instead of `updateNSView` (NSViewRepresentable) | Medium   | FIXED  | `38dc6d0` |
| A-06 | Missing `dismantleNSView` for observer cleanup in DataGridView                  | High     | FIXED  | `31dd7de` |
| A-07 | `ShortcutRecorderView` closures not refreshed in `updateNSView`                 | Medium   | FIXED  | `41eb974` |
| A-09 | `AppDelegate` inverted boolean logic (`!condition == false`)                    | Low      | FIXED  | `3134453` |
| A-11 | Magic key code integers (126, 125, 36, 53) instead of named constants           | Low      | FIXED  | `a53d2f2` |
| A-12 | Superfluous empty `Coordinator` class in `DoubleClickView`                      | Low      | FIXED  | `3af7628` |
| A-13 | `DatePickerCellEditor` uses raw `NSViewController` instead of proper subclass   | Medium   | FIXED  | `12ecd8e` |

## 3. Concurrency Anti-Patterns (12 issues)

| ID   | Issue                                                          | Severity | Status   | Commit    |
| ---- | -------------------------------------------------------------- | -------- | -------- | --------- |
| C-01 | Bare `Task {}` not inheriting `@MainActor` context (Swift 5.9) | Critical | FIXED    | `ce46339` |
| C-02 | `RunLoop.current.run(until:)` blocking main thread             | Critical | DEFERRED | —         |
| C-03 | Silent error swallowing in empty `catch {}` blocks             | High     | FIXED    | `564eea6` |
| C-04 | `queue.sync` potential deadlock in MariaDB/LibPQ connections   | Critical | DEFERRED | —         |
| C-05 | `nonisolated(unsafe)` TOCTOU in SQLiteDriver                   | High     | DEFERRED | —         |
| C-06 | `Task {}` in `defer` blocks — not guaranteed to run            | Medium   | FIXED    | (direct)  |
| C-08 | `DispatchQueue.main.async` instead of `Task { @MainActor in }` | Medium   | FIXED    | `11f49d0` |
| C-09 | `DispatchWorkItem` debounce pattern — use `Task`-based pattern | Low      | FIXED    | `0371f5b` |
| C-10 | Timer + Task + GCD triple-dispatch in AnalyticsService         | Medium   | FIXED    | `a52b0e3` |
| C-11 | GCD completion-handler API instead of async/await wrappers     | Low      | FIXED    | `d903746` |
| C-12 | Timer + Task hybrid in LicenseManager                          | Medium   | FIXED    | `a52b0e3` |

## 4. macOS API Anti-Patterns (18 issues)

| ID   | Issue                                                                     | Severity | Status   | Commit    |
| ---- | ------------------------------------------------------------------------- | -------- | -------- | --------- |
| M-01 | `SecItemAdd` return value not checked — failed writes silently lost       | Critical | FIXED    | `45b3272` |
| M-02 | Missing `kSecAttrService` on Keychain queries — potential collisions      | High     | FIXED    | `551d9b8` |
| M-03 | Wrong `kSecAttrAccessible` policy for macOS background access             | High     | FIXED    | `26863dc` |
| M-04 | Large JSON in `UserDefaults` — should use file-based storage              | Medium   | DEFERRED | —         |
| M-05 | Deprecated `URL.path` — use `path(percentEncoded:)`                       | Low      | FIXED    | `31f41fb` |
| M-06 | `NSHomeDirectory()` string concatenation instead of URL-based paths       | Medium   | FIXED    | `4a39da8` |
| M-07 | Scattered `NSPasteboard.general` calls — consolidate to ClipboardService  | Medium   | FIXED    | `44b80c5` |
| M-08 | Manual dark-mode color branching instead of semantic NSColors             | Medium   | FIXED    | `0d30008` |
| M-09 | Fixed status colors (Color.green/.red) instead of adaptive system colors  | Low      | FIXED    | `51c5ceb` |
| M-10 | Hardcoded font sizes instead of DesignConstants tokens                    | Low      | FIXED    | `7b0f257` |
| M-11 | `Bundle.main.infoDictionary` repeated access — centralize in extension    | Low      | FIXED    | `6977398` |
| M-12 | Deprecated `NSWorkspace.selectFile` — use `activateFileViewerSelecting`   | Low      | FIXED    | `bc0b9a7` |
| M-13 | Duplicate `ExportServiceState` wrapper — observe `ExportService` directly | Medium   | FIXED    | `85ac52a` |
| M-14 | Combine pipelines in NotificationHandler — should use async sequences     | Low      | DEFERRED | —         |
| M-15 | Missing `removeObserver(self)` in `applicationWillTerminate`              | Medium   | FIXED    | `13d8c5f` |
| M-16 | ConnectionStorage re-decodes from UserDefaults on every call              | Medium   | FIXED    | `663b702` |
| M-17 | Force-unwrap on Application Support directory URL                         | Medium   | FIXED    | `4f95119` |
| M-18 | `templatesURL` recomputed from FileManager every access                   | Low      | FIXED    | `48ba5f4` |

## 5. Accessibility Anti-Patterns (2 issues)

| ID     | Issue                                           | Severity | Status   | Commit |
| ------ | ----------------------------------------------- | -------- | -------- | ------ |
| ACC-01 | Missing accessibility labels on custom controls | Medium   | DEFERRED | —      |
| ACC-02 | Editor ignores system Large Text setting        | Medium   | DEFERRED | —      |

---

## Additional Build Fixes (not in original audit)

| Issue                                                  | Commit    |
| ------------------------------------------------------ | --------- |
| `.accentColor` not a `ShapeStyle` member — use `.tint` | `2e610b4` |
| Invalid `private(set)` on `@StateObject` property      | `b2ad3f3` |
| Swift type-checker timeout from long onChange chain    | `d27b100` |

---

## Deferred Issues Detail

### C-02: RunLoop blocking (Critical)

`RunLoop.current.run(until:)` blocks the main thread in SSH tunnel setup. Requires redesigning the tunnel establishment flow to be fully async.

### C-04: queue.sync deadlock (Critical)

`MariaDBConnection` and `LibPQConnection` use `queue.sync` which can deadlock if called from the queue itself. Requires changing the `DatabaseDriver` protocol to async.

### C-05: nonisolated(unsafe) TOCTOU (High)

`SQLiteDriver` uses `nonisolated(unsafe)` with TOCTOU race conditions. Requires actor-based isolation.

### S-03: Multiple .sheet modifiers (Medium)

Multiple `.sheet(isPresented:)` on the same view only activates the last one. Requires refactoring to enum-based `.sheet(item:)` pattern.

### M-04: Large JSON in UserDefaults (Medium)

Query tab state serialized as large JSON in UserDefaults. Requires migration to file-based storage.

### M-14: Combine → async sequences (Low)

NotificationHandler uses Combine publishers. Should migrate to `AsyncStream`/`for await` patterns.

### ACC-01: Accessibility labels (Medium)

Custom controls (DataGridView cells, filter chips, toolbar buttons) lack accessibility labels.

### ACC-02: Large Text support (Medium)

SQL editor uses fixed font sizes, ignoring system accessibility text size preferences.
