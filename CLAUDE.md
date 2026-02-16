# TablePro - Agent Development Guide

## Project Overview

TablePro is a native macOS database client built with SwiftUI and AppKit. It's designed as a fast, lightweight alternative to TablePlus, prioritizing Apple-native frameworks and modern Swift idioms for optimal performance and maintainability.

- **Current version:** 0.4.0
- **Minimum macOS:** 14.0 (Sonoma)
- **Swift version:** 5.9
- **Architecture:** Universal Binary (arm64 + x86_64)
- **License:** GPL v3
- **Codebase:** ~210 Swift files, ~49,000 LOC

### Related Documentation Files

| File | Purpose |
|------|---------|
| `CHANGELOG.md` | Version history (Keep a Changelog format) — **mandatory** to update |
| `TRACKING.md` | Project health scorecard, issues, architecture reference |
| `ROADMAP.md` | Feature roadmap, tier-based priorities, technical debt |
| `AGENTS.md` | Simplified agent guide (CLAUDE.md is authoritative) |

## Build & Development Commands

### Building

```bash
# Build for current architecture (development)
xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build -skipPackagePluginValidation

# Build for specific architecture (release)
scripts/build-release.sh arm64       # Apple Silicon only
scripts/build-release.sh x86_64      # Intel only
scripts/build-release.sh both        # Universal binary

# Clean build
xcodebuild -project TablePro.xcodeproj -scheme TablePro clean

# Build and run
xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build -skipPackagePluginValidation && open build/Debug/TablePro.app
```

> **Note:** `-skipPackagePluginValidation` is required because the SwiftLint plugin
> bundled with CodeEditSourceEditor needs explicit trust for CLI builds.

### Linting & Formatting

```bash
# Run SwiftLint (check for code issues)
swiftlint lint

# Auto-fix SwiftLint issues
swiftlint --fix

# Run SwiftFormat (format code)
swiftformat .

# Check formatting without applying
swiftformat --lint .
```

### Testing

```bash
# Run all tests
xcodebuild -project TablePro.xcodeproj -scheme TablePro test -skipPackagePluginValidation

# Run specific test class
xcodebuild -project TablePro.xcodeproj -scheme TablePro test -skipPackagePluginValidation -only-testing:TableProTests/TestClassName

# Run specific test method
xcodebuild -project TablePro.xcodeproj -scheme TablePro test -skipPackagePluginValidation -only-testing:TableProTests/TestClassName/testMethodName
```

### Creating DMG

```bash
# Create distributable DMG (after building)
scripts/create-dmg.sh
```

## Code Style Guidelines

### Architecture Principles

- **Separation of Concerns**: Keep business logic in models/view models, not in views
- **Value Types First**: Prefer `struct` over `class` unless reference semantics are needed
- **Composition**: Use protocols and extensions for shared behavior instead of inheritance
- **Immutability**: Use `let` by default; only use `var` when mutation is required
- **Actor Isolation**: Use `@MainActor` for UI-bound types, custom actors for concurrent operations

### SPM Dependencies

Managed via Xcode's SPM integration (no standalone `Package.swift`):

**Direct dependencies:**

- **CodeEditSourceEditor** (`main` branch) — tree-sitter-powered code editor component
- **Sparkle** (2.8.1) — auto-update framework with EdDSA signing

**Transitive dependencies (via CodeEditSourceEditor):**

- **CodeEditLanguages** (0.1.20) — SQL language grammar
- **CodeEditTextView** (0.12.1) — text view API, e.g. `replaceCharacters`
- **CodeEditSymbols** (0.2.3) — symbol definitions
- **SwiftTreeSitter** (0.25.0) — tree-sitter Swift bindings
- **tree-sitter** (0.25.10) — tree-sitter core parser
- **SwiftCollections** (1.3.0) — Apple collection types
- **TextFormation** (0.9.0) / **TextStory** (0.9.1) — text utilities
- **Rearrange** (2.0.0) — code rearrangement
- **SwiftLintPlugin** (0.63.1) — code linting plugin

> **Note:** CodeEditSourceEditor tracks `main` branch (not a tagged release).
> Pin to a tagged release once 0.16.0 ships.

> The SwiftLint plugin bundled with CodeEditSourceEditor requires
> `-skipPackagePluginValidation` for CLI builds (see Build Commands above).

### Native C Libraries

The project bundles C database client libraries via bridging headers:

- **CMariaDB** (`TablePro/Core/Database/CMariaDB/`) — C bridge for MariaDB/MySQL connector
- **CLibPQ** (`TablePro/Core/Database/CLibPQ/`) — C bridge for PostgreSQL libpq
- **Static libraries** (`Libs/`) — pre-built `libmariadb*.a` for arm64/x86_64/universal (Git LFS tracked)

### File Structure

Top-level layout:

- **`TablePro/`** — Main source code
  - **`Core/`** — Business logic, database drivers, services
  - **`Views/`** — SwiftUI + AppKit UI components (no business logic)
  - **`Models/`** — Data structures, domain entities (prefer `struct`, `enum`)
  - **`ViewModels/`** — `@Observable` classes (Swift 5.9+) or `ObservableObject`
  - **`Extensions/`** — Type extensions, protocol conformances
  - **`Theme/`** — Design tokens, constants, toolbar tokens
  - **`Resources/`** — Localization (`Localizable.xcstrings`), assets
  - **`Assets.xcassets/`** — Image catalog (app icon, database icons, accent color)
  - **`AppDelegate.swift`** — App lifecycle (AppKit)
  - **`OpenTableApp.swift`** — Main app entry point (`@main`)
  - **`ContentView.swift`** — Root SwiftUI view
- **`Libs/`** — Pre-built static libraries (Git LFS)
- **`scripts/`** — Build automation (`build-release.sh`, `create-dmg.sh`)
- **`.github/workflows/`** — CI/CD (GitHub Actions)

#### Core Directory (63 files)

```
TablePro/Core/
├── Autocomplete/             # SQL autocompletion engine
│   ├── CompletionEngine.swift        # Core completion logic (framework-agnostic)
│   ├── SQLCompletionProvider.swift   # SQL-specific provider
│   ├── SQLContextAnalyzer.swift      # Query context analysis
│   ├── SQLSchemaProvider.swift       # Schema metadata provider
│   └── SQLKeywords.swift             # SQL keyword definitions
├── ChangeTracking/           # Data modification tracking
│   ├── DataChangeManager.swift       # Change lifecycle management
│   ├── DataChangeModels.swift        # Change data structures
│   ├── DataChangeUndoManager.swift   # Undo/redo support
│   └── SQLStatementGenerator.swift   # Generate INSERT/UPDATE/DELETE
├── Database/                 # Database connectivity
│   ├── DatabaseDriver.swift          # Driver protocol & factory
│   ├── DatabaseManager.swift         # Connection pool & lifecycle
│   ├── MySQLDriver.swift             # MySQL implementation
│   ├── PostgreSQLDriver.swift        # PostgreSQL implementation
│   ├── SQLiteDriver.swift            # SQLite implementation
│   ├── MariaDBConnection.swift       # MariaDB C connector wrapper
│   ├── LibPQConnection.swift         # libpq wrapper (PostgreSQL)
│   ├── ConnectionHealthMonitor.swift # 30s ping + auto-reconnect
│   ├── FilterSQLGenerator.swift      # Dynamic WHERE clause builder
│   ├── SQLEscaping.swift             # SQL injection prevention
│   ├── CMariaDB/                     # C bridge (module.modulemap)
│   └── CLibPQ/                       # C bridge (module.modulemap)
├── KeyboardHandling/         # Keyboard input processing
├── SSH/                      # SSH tunneling support
│   ├── SSHTunnelManager.swift        # Tunnel lifecycle
│   └── SSHConfigParser.swift         # ~/.ssh/config parser
├── SchemaTracking/           # Table structure modifications
│   ├── StructureChangeManager.swift  # Schema change tracking
│   ├── StructureUndoManager.swift    # Schema undo/redo
│   └── SchemaStatementGenerator.swift # Generate ALTER TABLE
├── Services/                 # Utility services
│   ├── AnalyticsService.swift        # Anonymous usage analytics
│   ├── ExportService.swift           # CSV/JSON/SQL/XLSX export
│   ├── ImportService.swift           # Data import handling
│   ├── LicenseManager.swift          # License validation
│   ├── SQLFormatterService.swift     # SQL formatting
│   ├── TabPersistenceService.swift   # Tab state persistence
│   ├── XLSXWriter.swift              # Excel export (pure Swift)
│   └── ...                           # Clipboard, dates, DDL, etc.
├── Storage/                  # Persistent data storage
│   ├── AppSettingsManager.swift      # Settings management
│   ├── ConnectionStorage.swift       # Keychain persistence
│   ├── QueryHistoryStorage.swift     # FTS5 search database
│   └── ...                           # Filters, tabs, templates, tags
├── Utilities/                # Helpers (alerts, decompression, SQL parsing)
└── Validation/               # Settings validation
```

#### Views Directory (106 files)

```
TablePro/Views/
├── Components/               # Reusable UI (empty states, pagination, key events)
├── Connection/               # Connection form, color picker, tags
├── DatabaseSwitcher/         # Database switching UI
├── Editor/                   # SQL editor & query UI
│   ├── SQLEditorView.swift              # SwiftUI wrapper for CodeEditSourceEditor
│   ├── SQLEditorCoordinator.swift       # TextViewCoordinator (find panel workarounds)
│   ├── SQLEditorTheme.swift             # Source of truth for colors/fonts
│   ├── TableProEditorTheme.swift        # Adapter → CodeEdit's EditorTheme protocol
│   ├── SQLCompletionAdapter.swift       # Bridges CompletionEngine → CodeSuggestionDelegate
│   ├── EditorTabBar.swift               # Pure SwiftUI tab bar
│   ├── QueryEditorView.swift            # Query editor container
│   ├── CreateTableView.swift            # Table creation wizard
│   ├── HistoryPanelController.swift     # Query history panel (AppKit)
│   └── ...                              # Column editors, templates, preview
├── Export/                   # Export dialog, format-specific options (CSV/JSON/SQL/XLSX)
├── Filter/                   # Filter builder panel, quick search, SQL preview
├── History/                  # Query history list, data provider
├── Import/                   # Import dialog, progress, error display
├── Main/                     # Main content coordinator
│   ├── MainContentCoordinator.swift     # Core coordinator class
│   ├── MainContentNotificationHandler.swift # Notification handling
│   ├── Child/                           # Child views
│   │   ├── MainEditorContentView.swift
│   │   ├── MainStatusBarView.swift
│   │   ├── QueryTabContentView.swift
│   │   └── TableTabContentView.swift
│   └── Extensions/                      # Coordinator extensions
│       ├── MainContentCoordinator+Alerts.swift
│       ├── MainContentCoordinator+Filtering.swift
│       ├── MainContentCoordinator+MultiStatement.swift
│       ├── MainContentCoordinator+Navigation.swift
│       ├── MainContentCoordinator+Pagination.swift
│       ├── MainContentCoordinator+RowOperations.swift
│       └── MainContentView+Bindings.swift
├── Results/                  # Data grid (NSTableView), cell editors
│   ├── DataGridView.swift               # Main data grid
│   ├── CellTextField.swift              # Text input cell
│   ├── BooleanCellEditor.swift          # Boolean toggle
│   ├── DatePickerCellEditor.swift       # Date/time picker popover
│   ├── EnumPopoverController.swift      # ENUM dropdown selector
│   ├── SetPopoverController.swift       # SET multi-select popover
│   ├── ForeignKeyPopoverController.swift # FK lookup dropdown
│   ├── JSONEditorPopoverController.swift # JSON/JSONB editor
│   └── ...                              # Key handling, context menus
├── RightSidebar/             # Right sidebar panel
├── Settings/                 # Settings views (General, Appearance, Editor, etc.)
├── Sidebar/                  # Left sidebar, table operations
├── Structure/                # Table structure editor, DDL view
└── Toolbar/                  # Toolbar (connection status, switcher, execution)
```

#### Models Directory (28 files)

```
TablePro/Models/
├── DatabaseConnection.swift   # Connection configuration
├── QueryResult.swift          # Query result set
├── QueryTab.swift             # Tab state (sort, pagination, filters)
├── AppSettings.swift          # App settings model
├── License.swift              # License model
├── FilterState.swift          # Current filter state
├── ExportModels.swift         # Export options/state
├── ImportModels.swift         # Import options/state
├── Schema/                    # Schema modification models
│   ├── ColumnDefinition.swift
│   ├── ForeignKeyDefinition.swift
│   ├── IndexDefinition.swift
│   ├── SchemaChange.swift
│   └── ...
└── ...                        # Sessions, tags, metadata, templates
```

### Imports

- **Order**: System frameworks (alphabetically), then third-party, then local
- **Specificity**: Import only what you need (`import struct Foundation.URL`)
- **TestableImport**: Use `@testable import` only in test targets
- **Blank line**: Required after imports before code begins

```swift
import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
struct ContentView: View {
```

### Formatting (Apple Style Guide)

- **Indentation**: 4 spaces (never tabs except Makefile/pbxproj)
- **Line length**: Aim for 120 characters (SwiftFormat `--maxwidth 120`); SwiftLint warns at 180, errors at 300
- **Braces**: K&R style - opening brace on same line, closing brace on new line
- **Wrapping**: Break before first argument when wrapping function calls/declarations
- **Semicolons**: Never use (not idiomatic Swift)
- **Trailing commas**: Omit in collections (SwiftFormat enforces)
- **Line endings**: LF only (Unix-style), never CRLF
- **File endings**: Single newline at EOF
- **Vertical whitespace**: Maximum 2 consecutive empty lines between declarations

### Naming Conventions (Apple API Design Guidelines)

- **Types**: UpperCamelCase (`DatabaseConnection`, `QueryResultSet`)
- **Functions/Variables**: lowerCamelCase (`executeQuery()`, `connectionString`)
- **Constants**: lowerCamelCase (`maxRetryAttempts`, `defaultTimeout`)
- **Enums**: UpperCamelCase type, lowerCamelCase cases (`DatabaseType.postgresql`)
- **Protocols**: Noun for capability (`DatabaseDriver`), `-able`/`-ible` for behavior (`Connectable`)
- **Boolean properties**: Use `is`/`has`/`can` prefix (`isConnected`, `hasValidCredentials`)
- **Factory methods**: Use `make` prefix (`makeConnection()`)
- **Acronyms**: Treat as words (`JsonEncoder`, not `JSONEncoder` - except SDK types)

### Type Inference & Explicit Types

- **Use inference**: When type is obvious from context
    ```swift
    let connection = DatabaseConnection(host: "localhost") // Good
    let connections: [DatabaseConnection] = [] // Explicit needed for empty collection
    ```
- **Be explicit**: For empty collections, complex generics, or when clarity helps
- **Avoid redundancy**: Don't repeat type in initialization (`var name: String = String()` → `var name = ""`)
- **Self**: Omit `self.` unless required for closure capture or property/parameter disambiguation

### Access Control

- Always specify access modifiers explicitly (`private`, `fileprivate`, `internal`, `public`)
- Prefer `private` over `fileprivate` unless cross-type access needed
- Use `private(set)` for read-only public properties
- IBOutlets should be `private` or `fileprivate`
- **Extension access modifiers**: Always specify access level on the extension itself, not individual members
    ```swift
    // Bad
    extension NSEvent {
        public var semanticKeyCode: KeyCode? { ... }
    }

    // Good
    public extension NSEvent {
        var semanticKeyCode: KeyCode? { ... }
    }
    ```

### Optionals & Error Handling

- Avoid force unwrapping (`!`) and force casting (`as!`) - use SwiftLint warnings as guide
- Prefer `if let` or `guard let` for unwrapping
- Use `guard` for early returns to reduce nesting
- Fatal errors must include descriptive messages
- Don't use force try (`try!`) except in tests or guaranteed scenarios
- **Safe casting**: Never use force cast (`as!`), always use conditional casting
    ```swift
    // Bad
    let value = param as! SQLFunctionLiteral

    // Good
    if let value = param as? SQLFunctionLiteral {
        return value.property
    }

    // Better (with optional chaining)
    return (param as? SQLFunctionLiteral)?.property ?? defaultValue
    ```

### Property Declarations

- Stored properties: attributes on same line unless long
- Computed properties: attributes on same line
- Function attributes: Place on previous line (`@MainActor`, `@discardableResult`)

```swift
@Published var isConnected: Bool = false
private var connectionPool: [Connection] = []

@MainActor
func updateUI() {
```

### Closures & Functions

- Implicit returns preferred for single-expression closures/computed properties
- Strip unused closure arguments (use `_` for unused)
- Remove `self` in closures unless required for capture semantics
- Prefer trailing closure syntax when last parameter
- **Avoid unused optional bindings**: Use `!= nil` instead of `let _ =` for existence checks
    ```swift
    // Bad
    guard let _ = textContainer else { return nil }

    // Good
    guard textContainer != nil else { return nil }
    ```

### Collections

- Use `isEmpty` instead of `count == 0`
- Use `contains(_:)` over `filter { }.count > 0`
- Use `first(where:)` over `filter { }.first`
- Use `allSatisfy(_:)` when checking all elements
- **Remove unused enumeration**: Don't use `.enumerated()` when index is not needed
    ```swift
    // Bad
    items.enumerated().map { _, item in item.value }

    // Good
    items.map { item in item.value }
    // Or with key path:
    items.map(\.value)
    ```

### Operators & Spacing

- Space around binary operators: `a + b`, `x = y`
- No space for ranges: `0..<10`, `0...9`
- Type delimiter space after colon: `var name: String`
- Guard/else on same line: `guard condition else {`

### Code Organization

- Maximum function body: 160 lines (warning), 250 (error)
- Maximum type body: 1100 lines (warning), 1500 (error)
- Maximum file length: 1200 lines (warning), 1800 (error)
- Cyclomatic complexity: 40 (warning), 60 (error)
- Organize declarations within types: properties → init → methods

### Refactoring Large Files

When files approach or exceed SwiftLint limits, follow these strategies:

#### 1. Extension Pattern for Large Types

Extract logical sections into separate extension files:

- Place extensions in `Extensions/` subfolder within the same directory
- Naming: `TypeName+Category.swift` (e.g., `MainContentCoordinator+RowOperations.swift`)
- Group related functionality (pagination, filtering, row operations, etc.)
- Keep the main file focused on core type definition and primary responsibilities

**Current example (see File Structure above for full listing):**
```
TablePro/Views/Main/
├── MainContentCoordinator.swift          # Core class definition
└── Extensions/
    ├── MainContentCoordinator+Alerts.swift
    ├── MainContentCoordinator+Filtering.swift
    ├── MainContentCoordinator+MultiStatement.swift
    ├── MainContentCoordinator+Navigation.swift
    ├── MainContentCoordinator+Pagination.swift
    ├── MainContentCoordinator+RowOperations.swift
    └── MainContentView+Bindings.swift
```

**Extension file template:**
```swift
//
//  MainContentCoordinator+RowOperations.swift
//  TablePro
//
//  Row manipulation operations for MainContentCoordinator
//

import Foundation

extension MainContentCoordinator {
    // MARK: - Row Operations

    func addNewRow(...) {
        // Implementation
    }
}
```

#### 2. Helper Method Extraction for Long Functions

When functions exceed 160 lines:

- Extract logical blocks into private helper methods
- Use descriptive names that explain the helper's purpose
- Place helper methods near their calling function
- Consider creating helper structs for complex parameter groups

**Example:**
```swift
// Before: 200-line function
private func executeQuery(_ query: String, parameters: [Any?]) throws -> Result {
    // 200 lines of code...
}

// After: Main function + helpers
private func executeQuery(_ query: String, parameters: [Any?]) throws -> Result {
    let stmt = try prepareStatement(query)
    defer { cleanupStatement(stmt) }

    let bindings = try bindParameters(parameters, to: stmt)
    defer { bindings.cleanup() }

    try executeStatement(stmt)
    return try fetchResults(from: stmt)
}

private func bindParameters(_ parameters: [Any?], to stmt: Statement) throws -> Bindings {
    // Focused binding logic
}

private func fetchResults(from stmt: Statement) throws -> Result {
    // Focused result fetching logic
}
```

#### 3. When to Refactor

- **Proactive**: When adding features that would push limits
- **Reactive**: When SwiftLint warnings appear (before errors)
- **Strategic**: Group by domain logic, not arbitrary line counts

### Disabled SwiftLint Rules (Allowed)

See `.swiftlint.yml` for the full list. Key disabled rules: `trailing_comma`, `todo`, `opening_brace` (SwiftFormat handles it), `trailing_closure`, `force_try`, `static_over_final_class`.

## Common Patterns

### Editor Architecture (CodeEditSourceEditor)

- **`SQLEditorTheme`** is the single source of truth for editor colors and fonts
- **`TableProEditorTheme`** adapts `SQLEditorTheme` to CodeEdit's `EditorTheme` protocol
- **`CompletionEngine`** is framework-agnostic; **`SQLCompletionAdapter`** bridges it to CodeEdit's `CodeSuggestionDelegate`
- **`EditorTabBar`** is pure SwiftUI — replaced the previous AppKit `NativeTabBarView` stack
- Cursor model: `cursorPositions: [CursorPosition]` (multi-cursor support via CodeEditSourceEditor)

### Database Driver Architecture

All database operations go through the `DatabaseDriver` protocol (`Core/Database/DatabaseDriver.swift`):

- **`MySQLDriver`** — Uses `MariaDBConnection` (C connector via CMariaDB bridge)
- **`PostgreSQLDriver`** — Uses `LibPQConnection` (C connector via CLibPQ bridge)
- **`SQLiteDriver`** — Uses Foundation's `sqlite3` directly
- **`DatabaseManager`** — Connection pool, lifecycle, and the primary interface for views/coordinators
- **`ConnectionHealthMonitor`** — Periodic ping (30s), auto-reconnect with exponential backoff

When adding a new driver method, add it to the `DatabaseDriver` protocol, then implement in all three drivers.

### Change Tracking Flow

1. User edits cell → `DataChangeManager` records change
2. User clicks Save → `SQLStatementGenerator` produces INSERT/UPDATE/DELETE
3. `DataChangeUndoManager` provides undo/redo support
4. `AnyChangeManager` abstracts over the concrete manager for protocol-based usage

### Storage Patterns

- **Secrets** (connection passwords): Keychain via `ConnectionStorage`
- **User preferences**: `UserDefaults` via `AppSettingsStorage` / `AppSettingsManager`
- **Query history**: SQLite FTS5 database via `QueryHistoryStorage`
- **Tab state**: JSON persistence via `TabPersistenceService` / `TabStateStorage`
- **Filter presets**: `FilterSettingsStorage`

### Logger Usage

Use OSLog for debugging (never `print()`):

```swift
import os

private static let logger = Logger(subsystem: "com.TablePro", category: "ComponentName")
logger.debug("Connection established")
logger.error("Failed to connect: \(error.localizedDescription)")
```

### SwiftUI View Models

```swift
@StateObject private var viewModel = MyViewModel()
@EnvironmentObject private var appState: AppState
@Published var items: [Item] = []
```

### Error Propagation

Prefer throwing errors over returning optionals for failure cases

### Localization

The project uses Xcode String Catalogs (`Localizable.xcstrings`) with English + Vietnamese (637 strings):

- SwiftUI view literals (`Text("literal")`, `Button("literal")`) auto-localize
- Computed strings, AppKit code, alerts, error descriptions → use `String(localized: "text")`
- Do NOT localize technical terms (font names, database types, SQL keywords, encoding names)
- Language setting available in Settings > General (System, English, Vietnamese)

## CI/CD

GitHub Actions workflow at `.github/workflows/build.yml`:

- **Trigger:** Git tags matching `v*`
- **Jobs:**
  1. `lint` — SwiftLint strict mode
  2. `build-arm64` — ARM64 binary with mariadb-connector-c and libpq
  3. `build-x86_64` — Intel binary (installs Rosetta 2 + x86_64 Homebrew)
  4. `release` — Creates GitHub release with DMG/ZIP artifacts + Sparkle EdDSA signatures
- **Artifacts:** DMG installer, ZIP archive, architecture-specific appcast.xml
- **Release notes:** Extracted automatically from `CHANGELOG.md`

## Large Files Approaching SwiftLint Limits

Keep these files in mind when adding code — they may need extraction into extensions:

| File | ~Lines | Limit (warn/error) |
|------|--------|---------------------|
| `Views/Main/MainContentCoordinator.swift` | 1387 | 1200/1800 (already split into 7 extensions) |
| `Core/Services/ExportService.swift` | 990 | 1200/1800 |
| `Core/Database/MariaDBConnection.swift` | 987 | 1200/1800 |
| `Views/Results/DataGridView.swift` | 972 | 1200/1800 |
| `Views/Editor/CreateTableView.swift` | 910 | 1200/1800 |

## Documentation

The documentation site is located in a separate repository at `tablepro.app/docs/` (Mintlify-powered).

### When to Update Documentation

**IMPORTANT**: When adding features or making significant changes, always update the corresponding documentation.

| Change Type | Documentation to Update |
|-------------|------------------------|
| New feature | Add to relevant feature page in `docs/features/` |
| New setting/preference | Update `docs/customization/settings.mdx` or related page |
| UI changes | Update relevant page + add screenshot placeholder |
| Keyboard shortcut changes | Update `docs/features/keyboard-shortcuts.mdx` |
| Database driver changes | Update `docs/databases/` pages |
| Connection options | Update `docs/databases/overview.mdx` |
| Import/Export changes | Update `docs/features/import-export.mdx` |
| Build process changes | Update `docs/development/building.mdx` |
| Architecture changes | Update `docs/development/architecture.mdx` |

### Documentation Structure

```
tablepro.app/docs/
├── index.mdx                    # Introduction
├── quickstart.mdx               # Getting started guide
├── installation.mdx             # Installation instructions
├── changelog.mdx                # Release changelog
├── databases/                   # Database connection guides
│   ├── overview.mdx
│   ├── mysql.mdx
│   ├── postgresql.mdx
│   ├── sqlite.mdx
│   └── ssh-tunneling.mdx
├── features/                    # Feature documentation
│   ├── sql-editor.mdx
│   ├── data-grid.mdx
│   ├── autocomplete.mdx
│   ├── change-tracking.mdx
│   ├── filtering.mdx
│   ├── table-operations.mdx
│   ├── table-structure.mdx
│   ├── tabs.mdx
│   ├── import-export.mdx
│   ├── query-history.mdx
│   └── keyboard-shortcuts.mdx
├── customization/               # Settings and customization
│   ├── settings.mdx
│   ├── appearance.mdx
│   └── editor-settings.mdx
└── development/                 # Developer documentation
    ├── setup.mdx
    ├── architecture.mdx
    ├── code-style.mdx
    └── building.mdx
```

### Documentation Guidelines

- Use Mintlify MDX components (`<Tip>`, `<Warning>`, `<Note>`, `<CardGroup>`, etc.)
- Add screenshot placeholders: `{/* Screenshot: description */}`
- Use Mermaid for diagrams (use `<br>` for line breaks, not `\n`)
- Keep content accurate and up-to-date with code changes
- The docs repo is separate: `git@github.com:datlechin/tablepro.app.git`

### Preview Documentation Locally

```bash
cd tablepro.app/docs
npm i -g mint
mint dev
# Open http://localhost:3000
```

## Agent Execution Strategy

- **Always use subagents** for implementation work. Delegate coding tasks to Task subagents instead of doing them in the main context. This preserves main context tokens and prevents context exhaustion on long sessions.
- **Always parallelize** independent tasks. When multiple tasks are requested (e.g., "implement W1, W3, W5"), launch all subagents in a single message with multiple Task tool calls.
- **Main context = orchestrator only.** The main context should: read files for context, launch subagents, summarize results, and update tracking files. Never do heavy implementation (multi-file edits, large refactors) directly in the main context.
- **Subagent prompts must be self-contained.** Include file paths, the specific problem, and clear instructions so the subagent can work autonomously without needing the main conversation history.

## Notes for AI Agents

- **Never** use tabs for indentation (except Makefile/pbxproj)
- **Always** run `swiftlint lint --strict` after making changes to verify compliance
- **Always** use `String(localized:)` for new user-facing strings instead of hardcoding English text. The project uses Xcode String Catalogs (`Localizable.xcstrings`) for localization. SwiftUI view literals (`Text("literal")`, `Button("literal")`, etc.) auto-localize, but computed `String` properties, AppKit code (`NSMenuItem`, `.title`), alert messages, and error descriptions must use `String(localized: "text")`. Do NOT localize technical terms (font names, database types, SQL keywords, encoding names, format patterns).
- **Always** update `CHANGELOG.md` when adding features, fixing bugs, or making notable changes. Add entries under the `[Unreleased]` section using the existing format (Added/Fixed/Changed subsections). This is **mandatory** — do not skip it.
- **Always** update documentation when adding or changing features — this is a **mandatory** step, not optional. After implementing a feature, check the "When to Update Documentation" table above and update both English (`docs/`) and Vietnamese (`docs/vi/`) pages. Key docs to check:
  - New keyboard shortcuts → `features/keyboard-shortcuts.mdx`
  - Tab behavior changes → `features/tabs.mdx`
  - UI changes → relevant feature page + screenshot placeholder
  - New features → add to relevant page or create new page
- **Test-first correctness**: When automated tests fail, fix the **source code** to produce the correct behavior — never adjust tests to match incorrect code output. Tests define expected behavior; if code produces wrong results, the code has the bug.
- Check .swiftformat and .swiftlint.yml for authoritative rules
- Preserve existing architecture: SwiftUI + AppKit, native frameworks only
- This is macOS-only; no iOS/watchOS/tvOS code needed
- Aim for 120-character lines (SwiftFormat target); SwiftLint warns at 180, errors at 300
- All new view controllers should use SwiftUI unless AppKit is required
- When refactoring for SwiftLint compliance:
  - Extract extensions before splitting classes
  - Maintain logical grouping of related functionality
  - Preserve all existing functionality and behavior
  - Update imports in extension files as needed
  - Test that build succeeds after refactoring
- Documentation is in a separate repo (`tablepro.app/`) - commit docs changes there
