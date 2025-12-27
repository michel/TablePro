# CLAUDE.md

Guide for working with TablePro codebase.

## Project Overview

**TablePro** - Native macOS database client (SwiftUI + AppKit). Alternative to TablePlus.

**Databases**: MySQL/MariaDB (MariaDB Connector/C), PostgreSQL (libpq), SQLite (native)

**Stack**: Swift 6, SwiftUI, async/await, Keychain, UserDefaults, NotificationCenter

## Core Philosophy

### Golden Rule: Use Native APIs First

✅ **Prefer**: SwiftUI/AppKit, Foundation, Swift Concurrency, Keychain, NotificationCenter, native DB libraries
❌ **Avoid**: Custom UI frameworks, threading systems, event buses, SQL protocol reimplementations

**Only build custom when**:
1. Native API doesn't exist
2. Native API insufficient for performance
3. Need unification layer for multiple backends

## Build

```bash
# Prerequisites
brew install mariadb-connector-c libpq

# Build
xcodebuild -project TablePro.xcodeproj -scheme TablePro build
```

## Architecture

```
Core/
├── Autocomplete/       # SQL completion (context-aware)
├── ChangeTracking/     # Cell edits → SQL generation
├── Database/           # Drivers (thin wrappers over native libs)
├── Services/           # Query execution, row ops
├── SSH/               # SSH tunnels (system ssh)
└── Storage/           # Keychain + UserDefaults + JSON files

Models/                # Pure data structures (no UI/persistence logic)

Views/                 # SwiftUI + AppKit bridges
├── Editor/           # Query editor (NSTextView for syntax highlighting)
├── Results/          # Data grid (NSTableView for performance)
└── [other views]     # Pure SwiftUI
```

## Key Patterns

### 1. Database Drivers (Thin Abstraction)

```swift
// Protocol wraps native clients
protocol DatabaseDriver {
    func connect() async throws
    func execute(query: String) async throws -> QueryResult
    // ... minimal interface
}

// Implementations delegate to native libs
MySQLDriver → MariaDB Connector/C (mysql_* functions)
PostgreSQLDriver → libpq (PQ* functions)
SQLiteDriver → SQLite C API (sqlite3_* functions)

// Factory pattern
DatabaseDriverFactory.createDriver(for: connection)
```

**Never**: Reimplement database protocols. Always delegate to native C libraries.

### 2. Session Management

```swift
@MainActor DatabaseManager.shared
├── activeSessions: [UUID: ConnectionSession]  // Persists when switching
├── currentSessionId: UUID?
└── activeDriver: DatabaseDriver?

// Usage
await DatabaseManager.shared.connectToSession(connection)
DatabaseManager.shared.execute(query: sql)
```

**Sessions preserve**: Tabs, filters, selected table when switching connections.

### 3. Storage

- **Credentials**: Keychain (`ConnectionStorage.shared.savePassword()`)
- **Configs**: UserDefaults (JSON)
- **Tab state**: JSON files per connection
- **History**: SQLite database

### 4. Events

```swift
// NotificationCenter for cross-component events
.databaseDidConnect, .executeQuery, .saveChanges, .refreshData

// SwiftUI commands for menu items
.commands { CommandGroup { ... } }
```

### 5. SwiftUI + AppKit Bridges

**Use AppKit only when necessary**:
- `SQLEditorView` → NSTextView (syntax highlighting, advanced editing)
- `DataGridView` → NSTableView (100k+ row performance)
- `SQLCompletionWindowController` → NSPanel (window positioning)

All other views: Pure SwiftUI

### 6. Autocomplete

```
SQLContextAnalyzer → detect cursor context (regex, no full parser)
SQLSchemaProvider → fetch schema from driver (cached)
SQLKeywords → static arrays
SQLCompletionProvider → combine context + schema + keywords
CompletionEngine → coordinator
```

**Non-blocking**: async/await, incremental parsing, session-cached schema

### 7. Change Tracking

```
1. Cell edit → DataChangeManager records
2. Cell highlighted (yellow)
3. Cmd+S → SQLStatementGenerator creates SQL
4. Execute in transaction
5. Success → clear, refresh | Fail → rollback, preserve
```

### 8. SSH Tunnels

```swift
// DatabaseManager handles transparently
if sshEnabled {
    tunnelPort = await SSHTunnelManager.createTunnel(...)
    // Driver connects to localhost:tunnelPort
}
```

Driver never knows about SSH.

## Coding Rules

### Concurrency
```swift
// ✅ async/await
func fetch() async throws -> [TableInfo] { ... }

// ✅ @MainActor for UI classes
@MainActor class DatabaseManager: ObservableObject { ... }

// ✅ Task for background work
Task { let data = try await fetch() }
```

### Error Handling
```swift
// ✅ Typed errors
enum DatabaseError: LocalizedError {
    case notConnected
    case queryFailed(String)
}

// ✅ Context
throw DatabaseError.queryFailed("Invalid SQL: \(query)")
```

### SwiftUI
```swift
@StateObject     // for owned objects
@ObservedObject  // for passed objects
@EnvironmentObject // for shared state

// Prefer bindings
TextField("Name", text: $connection.name)
```

### Models
- Pure structs (no UI, no persistence, no business logic)
- Codable for serialization
- Value types preferred

### Naming
- Types: `PascalCase`
- Properties/methods: `camelCase`
- One type per file (except small related types)

## Common Patterns

```swift
// Session state
guard let session = DatabaseManager.shared.currentSession else { return }
DatabaseManager.shared.updateSession(id) { session in
    session.selectedTable = "users"
}

// Async loading
Task {
    do {
        let result = try await DatabaseManager.shared.execute(query: sql)
        self.result = result
    } catch {
        self.error = error.localizedDescription
    }
}

// Notifications
NotificationCenter.default.post(name: .executeQuery, object: nil)
.onReceive(NotificationCenter.default.publisher(for: .executeQuery)) { ... }
```

## Performance

- **Large datasets**: Pagination via `fetchRows(offset:limit:)`
- **Schema**: Cache per session, invalidate on refresh
- **Main thread**: Keep free with `Task.detached` + `MainActor.run`

## Security

- **Passwords**: Always Keychain (never UserDefaults/files)
- **SQL injection**: Escape inputs (consider adding parameterized queries)
- **Logging**: Never log credentials

## Pitfalls to Avoid

❌ Reinvent native APIs (use DateFormatter, not custom)
❌ Block main thread (use async/await)
❌ UI logic in models (keep models pure)
❌ Too many singletons (consolidate or inject)
❌ Retain cycles (use `[weak self]`)

## Adding Features

1. Check if native API exists → use it
2. Design protocol if abstracting
3. Use async/await for I/O
4. Add to appropriate layer (Core/Models/Views)
5. Follow existing patterns

## Summary

> **If macOS/Swift provides it, use it. Build custom only to connect/adapt/unify native APIs.**

**Before adding code**:
- [ ] Native API available?
- [ ] Simplest solution?
- [ ] Follows existing patterns?
- [ ] async/await for I/O?
- [ ] Errors typed?
- [ ] Right layer?
- [ ] No retain cycles?
