# TablePro Development Roadmap

> **Auto-generated from full source code analysis** (Feb 2026)
> ~199 Swift files | ~40,000+ lines of code | v0.1.1 (current)

---

## Table of Contents

- [Project Summary](#project-summary)
- [Current Feature Status](#current-feature-status)
- [Tier 1 - Critical (Daily Developer Use)](#tier-1---critical-daily-developer-use)
- [Tier 2 - High Priority (Weekly Developer Use)](#tier-2---high-priority-weekly-developer-use)
- [Tier 3 - Medium Priority (Regular Use)](#tier-3---medium-priority-regular-use)
- [Tier 4 - Nice-to-Have (Power Users)](#tier-4---nice-to-have-power-users)
- [Tier 5 - Long-term Vision](#tier-5---long-term-vision)
- [Known Bugs & TODOs in Code](#known-bugs--todos-in-code)
- [Technical Debt](#technical-debt)
- [Architecture Reference](#architecture-reference)

---

## Project Summary

TablePro is a native macOS database client (SwiftUI + AppKit) supporting MySQL, MariaDB, PostgreSQL, and SQLite. It targets developers who need a fast, lightweight alternative to TablePlus/DBeaver/DataGrip.

### What's Already Built (v0.1.1)

| Area | Status | Key Files |
|------|--------|-----------|
| SQL Editor (CodeEditSourceEditor) | Complete | `Views/Editor/SQLEditorView.swift`, `SQLEditorCoordinator.swift` |
| Syntax Highlighting (tree-sitter) | Complete | Via CodeEditSourceEditor + `SQLEditorTheme.swift` |
| Context-Aware Autocomplete | Complete | `Core/Autocomplete/CompletionEngine.swift`, `SQLContextAnalyzer.swift` |
| Multi-Tab Editor | Complete | `Views/Editor/EditorTabBar.swift`, `Models/QueryTab.swift` |
| Query Execution (single/multi/selected) | Complete | `Views/Main/MainContentCoordinator.swift` |
| Data Grid (NSTableView) | Complete | `Views/Results/DataGridView.swift`, `DataGridCellFactory.swift` |
| Inline Cell Editing | Complete | `Views/Results/CellTextField.swift`, `BooleanCellEditor.swift` |
| Change Tracking (INSERT/UPDATE/DELETE) | Complete | `Core/ChangeTracking/DataChangeManager.swift` |
| Undo Support | Complete | `Core/ChangeTracking/DataChangeUndoManager.swift` |
| Column Sorting (server + client) | Complete | Per-tab `SortState` in `QueryTab.swift` |
| Pagination (server-side) | Complete | `PaginationState` in `QueryTab.swift` |
| Filter Panel (AND/OR, presets) | Complete | `Views/Filter/FilterPanelView.swift`, `FilterRowView.swift` |
| Table Structure Editor | Complete | `Views/Structure/TableStructureView.swift` |
| Create Table Wizard | Complete | `Views/Editor/CreateTableView.swift` |
| SQL Import (.sql, .gz) | Complete | `Views/Import/ImportDialog.swift`, `Core/Services/ImportService.swift` |
| Export (CSV, JSON, SQL) | Complete | `Views/Export/ExportDialog.swift`, `Core/Services/ExportService.swift` |
| SSH Tunneling | Complete | `Core/SSH/SSHTunnelManager.swift`, `SSHConfigParser.swift` |
| Connection Management + Keychain | Complete | `Core/Storage/ConnectionStorage.swift` |
| Query History (FTS5 search) | Complete | `Core/Storage/QueryHistoryStorage.swift` |
| Database Switcher | Complete | `Views/DatabaseSwitcher/DatabaseSwitcherSheet.swift` |
| Settings (6 tabs) | Complete | `Views/Settings/SettingsView.swift` |
| Auto-Updates (Sparkle 2) | Complete | `Core/Services/UpdaterBridge.swift` |
| Query Templates | Complete | `Views/Editor/TemplateSheets.swift` |
| SQL Formatter | Complete | `Core/Services/SQLFormatterService.swift` |
| Table Operations (truncate/drop/rename/duplicate) | Complete | `Views/Sidebar/TableOperationDialog.swift` |

---

## Current Feature Status

### Database Drivers

| Database | Driver | CRUD | Schema | SSH | Import/Export | Limitations |
|----------|--------|------|--------|-----|---------------|-------------|
| MySQL | MariaDB Connector/C | Full | Full | Yes | Full | — |
| MariaDB | MariaDB Connector/C | Full | Full | Yes | Full | — |
| PostgreSQL | libpq | Full | Full | Yes | Full | PK rename assumes `_pkey` convention |
| SQLite | Built-in | Full | Partial | N/A | Full | No ALTER COLUMN, requires table recreation |

### Editor Features

| Feature | Status | Notes |
|---------|--------|-------|
| Syntax Highlighting | Done | Tree-sitter via CodeEditSourceEditor |
| Autocomplete | Done | Tables, columns, functions, keywords, views |
| Find/Replace | Done | Native TextKit panel (with z-order workaround) |
| Multi-cursor | Done | Via CodeEditSourceEditor |
| SQL Formatting | Done | With cursor preservation (Opt+Cmd+F) |
| Line Numbers | Done | Toggle in settings |
| Word Wrap | Done | Toggle in settings |
| Code Folding | Missing | CodeEditSourceEditor limitation |
| Snippets/Macros | Missing | Templates exist but no inline snippets |
| Vim Mode | Missing | — |
| SQL Linting | Missing | No real-time error checking |

### Data Grid Features

| Feature | Status | Notes |
|---------|--------|-------|
| Inline Editing | Done | Click or Enter key |
| Tab/Shift-Tab Navigation | Done | Between cells |
| Copy (text/CSV/JSON) | Done | Cmd+C, Cmd+Shift+C, Cmd+Opt+C |
| Add/Delete Rows | Done | With undo |
| Set NULL/DEFAULT | Done | Context menu + right sidebar |
| Visual Change Indicators | Done | Red=deleted, Blue=inserted, Orange=modified |
| Boolean Cell Editor | Done | YES/NO/NULL dropdown |
| Column Sorting | Done | Server-side for tables, client-side for queries |
| Pagination | Done | Configurable page size |
| Multi-row Selection | Done | — |
| Redo | Done | Undo/redo stacks with proper clearing on new changes |
| Foreign Key Dropdown | Missing | — |
| Date/Time Picker | Missing | Text input only |
| Enum Dropdown | Missing | — |
| JSON Editor | Missing | Plain text only |
| Image Preview (BLOB) | Missing | — |

---

## Tier 1 - Critical (Daily Developer Use)

> These are features developers use every single day. Highest impact on adoption.

### 1.1 SSL/TLS Connection Support
**Priority: CRITICAL** | **Effort: Medium**

No SSL/TLS configuration is visible in the connection form UI. Many production databases require SSL connections.

- **Files to modify:** `Views/Connection/ConnectionFormView.swift`, `Models/DatabaseConnection.swift`, all drivers
- **Tasks:**
  - Add SSL toggle and certificate fields to ConnectionFormView
  - Add `SSLConfiguration` struct to DatabaseConnection model
  - Implement SSL parameters in PostgreSQLDriver (sslmode, sslcert, sslkey, sslrootcert)
  - Implement SSL parameters in MySQLDriver (MYSQL_OPT_SSL_KEY, etc.)
  - Persist SSL config in ConnectionStorage
  - Test with AWS RDS, Google Cloud SQL, DigitalOcean databases

### 1.2 CSV/JSON Import (Partially Done)
**Priority: CRITICAL** | **Effort: Medium**

CSV clipboard paste now works with proper RFC 4180 parsing. File-based CSV import needs additional UI.

- **Files modified:** `Core/Services/RowParser.swift`, `Core/Services/RowOperationsManager.swift`
- **Tasks:**
  - ~~Implement RFC 4180 CSV parser (handle quotes, escapes, multi-line values)~~ (DONE)
  - ~~Auto-detect CSV vs TSV in clipboard paste~~ (DONE)
  - ~~Header row detection~~ (DONE)
  - Add CSV file import dialog with column mapping, delimiter detection, encoding selection (Future)
  - Add JSON import (array of objects format) (Future)
  - Add preview of first N rows before import (Future)

### 1.3 ~~Complete Redo Functionality~~ (DONE)
**Status: COMPLETED**

Redo now works correctly. Fixed `canRedo()` to delegate to `DataChangeUndoManager`, wired undo/redo callbacks to DataGridView, and added proper redo stack clearing when new changes are made.

### 1.4 Query Execution Plan (EXPLAIN) ✅ DONE (Basic)
**Priority: HIGH** | **Effort: Medium**

Basic EXPLAIN support implemented. Results display in the standard data grid.

- **Files modified:** `MainContentCoordinator.swift`, `QueryEditorView.swift`, `OpenTableApp.swift`, `MainContentNotificationHandler.swift`
- **Tasks:**
  - ~~Add "Explain Query" button/shortcut~~ (DONE — ⌥⌘E, toolbar button)
  - ~~Run `EXPLAIN` for MySQL/PostgreSQL, `EXPLAIN QUERY PLAN` for SQLite~~ (DONE)
  - ~~Display results in data grid~~ (DONE)
  - Highlight full table scans, missing indexes, expensive operations (Future)
  - Optional: Visual execution plan diagram (Future)

### 1.5 Connection Switcher UI ✅ DONE
**Priority: HIGH** | **Effort: Small**

~~`ToolbarItemFactory.swift:285` has a TODO — toolbar connection switcher opens welcome window instead of a quick-switch popover.~~

- **Files modified:** `Views/Toolbar/ToolbarItemFactory.swift`, `Views/Toolbar/ConnectionSwitcherPopover.swift` (new)
- **Tasks:**
  - ~~Create connection switcher popover/dropdown~~ (DONE)
  - ~~Show active connections with status indicators~~ (DONE)
  - ~~Allow quick switching without closing current window~~ (DONE)
  - ~~Show recent connections for quick reconnect~~ (DONE)

---

## Tier 2 - High Priority (Weekly Developer Use)

> Features used frequently during development workflows.

### 2.1 Foreign Key Lookup Dropdown
**Priority: HIGH** | **Effort: Medium**

When editing a FK column, show a dropdown of valid values from the referenced table.

- **Files to modify:** `Views/Results/DataGridCellFactory.swift`, `DataGridView.swift`
- **Tasks:**
  - Detect FK columns from schema metadata
  - Fetch referenced table values (with search/pagination)
  - Show as searchable dropdown in cell editor
  - Display both ID and a display column (e.g., `id - name`)

### 2.2 Date/Time Picker for Date Columns
**Priority: HIGH** | **Effort: Small**

Currently date columns are plain text fields.

- **Files to modify:** `Views/Results/DataGridCellFactory.swift`
- **Tasks:**
  - Detect date/datetime/timestamp column types
  - Show native macOS date picker popover
  - Support common date formats
  - Allow manual text input as fallback

### 2.3 Stored Procedure/Function Browser
**Priority: HIGH** | **Effort: Large**

No UI for viewing, editing, or executing stored procedures/functions.

- **Tasks:**
  - Add sidebar section for Routines (Procedures, Functions)
  - Fetch routine definitions from `information_schema.routines`
  - Display routine source code in SQL editor tab
  - Support CREATE/ALTER/DROP for routines
  - Implement for MySQL, PostgreSQL (SQLite has no procedures)

### 2.4 Trigger Management
**Priority: HIGH** | **Effort: Medium**

No trigger management in structure view or sidebar.

- **Tasks:**
  - Add "Triggers" tab to TableStructureView
  - Fetch triggers from `information_schema.triggers` (MySQL) or `pg_trigger` (PostgreSQL)
  - Display trigger definitions
  - Support CREATE/ALTER/DROP TRIGGER
  - SQLite trigger support via `sqlite_master`

### 2.5 View Management
**Priority: HIGH** | **Effort: Medium**

Views are listed in sidebar (already detected) but can't be created/edited.

- **Tasks:**
  - Add "Create View" option to sidebar context menu
  - Open view definition in SQL editor tab
  - Support ALTER VIEW / CREATE OR REPLACE VIEW
  - Show view dependencies

### 2.6 Excel Export (.xlsx)
**Priority: HIGH** | **Effort: Medium**

Only CSV/JSON/SQL export exists. Excel is the most requested format for non-developers.

- **Tasks:**
  - Add .xlsx export option to ExportDialog
  - Use a lightweight xlsx library or implement basic OOXML writing
  - Support sheet naming, column width auto-fit
  - Optional: multiple tables → multiple sheets

---

## Tier 3 - Medium Priority (Regular Use)

> Features that improve productivity and polish.

### 3.1 JSON Column Editor
**Priority: MEDIUM** | **Effort: Medium**

JSON columns are displayed and edited as plain text.

- **Tasks:**
  - Detect JSON/JSONB column types
  - Show formatted JSON in popover/sheet with syntax highlighting
  - Validate JSON before saving
  - Support JSON path navigation
  - Tree view for nested objects

### 3.2 Schema Compare / Diff
**Priority: MEDIUM** | **Effort: Large**

Compare schema between two databases or connections.

- **Tasks:**
  - Add "Schema Compare" menu item
  - Select source and target connections/databases
  - Diff tables, columns, indexes, foreign keys
  - Generate migration SQL (ALTER statements)
  - Visual diff with additions/removals/modifications highlighted

### 3.3 ER Diagram (Entity-Relationship)
**Priority: MEDIUM** | **Effort: Large**

No visual schema relationships view.

- **Tasks:**
  - Add "ER Diagram" tab or window
  - Parse foreign key relationships from schema
  - Render tables as boxes with columns listed
  - Draw relationship lines (1:1, 1:N, N:M)
  - Allow pan/zoom, export to PNG/SVG
  - Consider using Core Graphics or a lightweight diagram framework

### 3.4 SQLite Table Recreation for Schema Changes
**Priority: MEDIUM** | **Effort: Medium**

SQLite doesn't support most ALTER TABLE operations. Code throws `DatabaseError.unsupportedOperation`.

- **Files to modify:** `Core/SchemaTracking/SchemaStatementGenerator.swift`, `Core/Database/SQLiteDriver.swift`
- **Tasks:**
  - Implement table recreation strategy:
    1. CREATE new_table with desired schema
    2. INSERT INTO new_table SELECT FROM old_table
    3. DROP old_table
    4. ALTER TABLE new_table RENAME TO old_table
  - Preserve indexes, triggers, foreign keys
  - Wrap in transaction
  - Add UI warning about SQLite limitations

### 3.5 Keyboard Shortcuts Customization
**Priority: MEDIUM** | **Effort: Medium**

All shortcuts are hardcoded. Power users expect customization.

- **Tasks:**
  - Add "Keyboard Shortcuts" settings tab
  - Map action IDs to key combinations
  - Persist in UserDefaults
  - Support conflict detection
  - Reset to defaults option

### 3.6 Read-Only Connection Mode
**Priority: MEDIUM** | **Effort: Small**

No option to mark a connection as read-only (safety for production databases).

- **Files to modify:** `Models/DatabaseConnection.swift`, `Views/Connection/ConnectionFormView.swift`
- **Tasks:**
  - Add `isReadOnly` flag to DatabaseConnection
  - Disable write operations (INSERT, UPDATE, DELETE, DROP, etc.)
  - Show read-only badge in tab bar and status bar
  - Warn user if they attempt write operations

### 3.7 Query Execution Timeout
**Priority: MEDIUM** | **Effort: Small**

No configurable query timeout. Runaway queries can hang the app.

- **Tasks:**
  - Add timeout setting to Settings > General
  - Implement per-driver timeout:
    - PostgreSQL: `statement_timeout` session variable
    - MySQL: `max_execution_time` hint or `wait_timeout`
    - SQLite: `sqlite3_busy_timeout`
  - Show cancel button during long-running queries (partially exists)

### 3.8 User/Role Management
**Priority: MEDIUM** | **Effort: Large**

No UI for managing database users, roles, or permissions.

- **Tasks:**
  - Add "Users" section to sidebar or separate panel
  - Fetch users from `mysql.user` / `pg_roles`
  - Display permissions matrix
  - Support CREATE/ALTER/DROP USER
  - GRANT/REVOKE privileges

---

## Tier 4 - Nice-to-Have (Power Users)

> Features that differentiate from competitors.

### 4.1 Data Compare Between Tables/Databases
- Compare data between two tables (same schema, different data)
- Highlight row differences
- Generate sync SQL

### 4.2 Visual Query Builder
- Drag-and-drop table joins
- Point-and-click WHERE conditions
- Generate SQL from visual representation
- Useful for non-SQL users

### 4.3 AI-Powered SQL Generation
- Natural language → SQL translation
- "Show me all orders from last month with total > $100"
- Schema-aware suggestions
- Integration with Claude API or local model

### 4.4 Split Editor View
- Side-by-side query editors
- Useful for comparing queries or editing + results simultaneously

### 4.5 Data Generator / Faker
- Generate test data for tables
- Respect column types, constraints, and foreign keys
- Configurable row count and data patterns

### 4.6 Column Statistics
- Add "Statistics" tab to structure view
- Show: cardinality, null count, min/max values, average length, distribution
- Useful for query optimization decisions

### 4.7 Custom Themes
- Beyond system light/dark
- Custom editor color schemes
- Import/export theme files

### 4.8 Connection Groups / Folders
- Hierarchical organization beyond flat tags
- Nested folders (Dev / Staging / Production)
- Group-level color coding

### 4.9 Regex Find/Replace in Editor
- Support regex patterns in find panel
- Capture groups in replacement
- Find in all open tabs

### 4.10 Table Partitions Management
- View partition info for MySQL/PostgreSQL
- Create/modify partitions
- Partition statistics

### 4.11 Scheduled Queries / Automation
- Run queries on a schedule
- Export results automatically
- Notification on completion/failure

### 4.12 Connection Health Monitoring
- Ping/keepalive for active connections
- Auto-reconnect on disconnect
- Connection pool statistics

---

## Tier 5 - Long-term Vision

> Strategic features for future major versions.

### 5.1 Cloud Sync (iCloud)
- Sync connections, settings, templates across Macs
- iCloud Keychain for credentials

### 5.2 Plugin/Extension System
- API for third-party extensions
- Custom data type editors
- Custom export formats

### 5.3 Collaboration Features
- Share queries with team members
- Shared connection configurations
- Query review/approval workflows

### 5.4 Database Migration Tool
- Version-controlled schema changes
- Up/down migration scripts
- Migration history tracking

### 5.5 Multi-Database Query
- Query across multiple databases in one statement
- Cross-database JOINs
- Federated query engine

---

## Known Bugs & TODOs in Code

### Explicit TODOs Found in Source

| # | File | Line | Description | Priority |
|---|------|------|-------------|----------|
| 1 | `Core/Services/RowParser.swift` | 98 | ~~CSV parsing not implemented, falls back to TSV~~ (FIXED) | ~~Critical~~ |
| 2 | `Views/Results/DataGridView.swift` | 305 | ~~Redo tracking not implemented~~ (FIXED) | ~~Critical~~ |
| 3 | `Views/Toolbar/ToolbarItemFactory.swift` | 285 | ~~Connection switcher opens welcome window instead of popover~~ (FIXED) | ~~High~~ |
| 4 | `Core/SchemaTracking/SchemaStatementGenerator.swift` | 415 | PostgreSQL PK rename assumes `{table}_pkey` convention | Medium |
| 5 | `Core/SchemaTracking/SchemaStatementGenerator.swift` | 427 | SQLite doesn't support PK modification (needs table recreation) | Medium |
| 6 | `Views/Editor/SQLEditorCoordinator.swift` | 62 | Find panel z-order workaround for CodeEditSourceEditor | Low |
| 7 | `Core/Database/SQLiteDriver.swift` | 565 | SQLite doesn't support DROP CONSTRAINT for foreign keys | Medium |

### Debug Code to Clean Up

- ~~**46 `print()` statements** across codebase~~ (DONE — migrated to `Logger` from `OSLog`)
- Notable files with debug prints:
  - `Views/Editor/CreateTableView.swift` (7 debug prints in duplicate table feature)
  - `Views/Sidebar/TableOperationDialog.swift` (3 debug prints)
- SwiftLint note: "No print statements rule now disabled — use Logger in the future"

### Silent Failures

- **100+ instances of `try?`** that silently swallow errors
- Most are acceptable (cleanup operations) but some in non-cleanup contexts need review
- Key files to audit: `Views/Structure/TableStructureView.swift` (JSON encoding for pasteboard)

---

## Technical Debt

### Code Quality

| Item | Description | Effort |
|------|-------------|--------|
| ~~Replace `print()` with `Logger`~~ | ~~46 print statements → OSLog Logger~~ (DONE) | ~~Small~~ |
| Audit `try?` usage | Review 100+ silent failures for appropriate error handling | Medium |
| Unit tests | **No test files found** — TestPlan exists but 0 test cases | Large |
| Localization | No `.strings` files, English only, no i18n infrastructure | Large |
| Accessibility | No VoiceOver labels found, minimal accessibility support | Medium |

### Architecture Improvements

| Item | Description | Effort |
|------|-------------|--------|
| PostgreSQL constraint querying | `SchemaStatementGenerator` assumes PK name convention | Small |
| SQLite table recreation | Implement full table recreation strategy for ALTER operations | Medium |
| Connection pooling | Current single-connection-per-session, no pool | Medium |
| Async/await migration | Some callbacks could be modernized to async/await | Medium |

### Dependencies to Monitor

| Dependency | Version | Notes |
|------------|---------|-------|
| CodeEditSourceEditor | 0.15.2+ | Find panel z-order bug needs upstream fix |
| CodeEditLanguages | Transitive | SQL grammar quality |
| Sparkle | 2.x | Auto-update framework |
| libpq | System | PostgreSQL client library |
| MariaDB Connector/C | Homebrew | MySQL/MariaDB client library |

---

## Architecture Reference

### Key Architecture Patterns

```
┌─────────────────────────────────────────────────┐
│                    SwiftUI Views                 │
│  (MainContentView, SidebarView, SettingsView)    │
├─────────────────────────────────────────────────┤
│           Coordinators / ViewModels              │
│  (MainContentCoordinator, DatabaseSwitcherVM)    │
├─────────────────────────────────────────────────┤
│              Core Services                       │
│  (ImportService, ExportService, TabPersistence)  │
├─────────────────────────────────────────────────┤
│           Database Layer                         │
│  (DatabaseDriver protocol → MySQL/PG/SQLite)     │
├─────────────────────────────────────────────────┤
│        Storage Layer                             │
│  (ConnectionStorage, QueryHistoryStorage,        │
│   AppSettingsStorage, TabStateStorage)           │
└─────────────────────────────────────────────────┘
```

### File Count by Area

| Directory | Files | Description |
|-----------|-------|-------------|
| `Views/Editor/` | ~20 | SQL editor, tabs, create table, templates |
| `Views/Results/` | ~7 | Data grid, cell editors |
| `Views/Main/` | ~10 | Main content view, coordinator, extensions |
| `Views/Filter/` | ~5 | Filter panel, rows, presets |
| `Views/Structure/` | ~5 | Table structure editor, DDL |
| `Views/Import/` | ~5 | SQL import dialog |
| `Views/Export/` | ~8 | Export dialog, format options |
| `Views/Connection/` | ~4 | Connection form, colors, tags |
| `Views/Settings/` | ~7 | All settings tabs |
| `Views/Toolbar/` | ~8 | Native toolbar integration |
| `Views/Sidebar/` | ~3 | Database object browser |
| `Views/History/` | ~4 | Query history panel |
| `Core/Database/` | ~8 | Drivers, SQL generation |
| `Core/Services/` | ~15 | Business logic services |
| `Core/Storage/` | ~8 | Persistence layer |
| `Core/Autocomplete/` | ~6 | Completion engine |
| `Core/ChangeTracking/` | ~5 | Data change management |
| `Core/SchemaTracking/` | ~3 | Schema change management |
| `Core/SSH/` | ~2 | SSH tunnel management |
| `Models/` | ~15 | Domain models |
| `Extensions/` | ~6 | Type extensions |
| `ViewModels/` | ~1 | View models |

### Critical File Map

For any developer continuing this project, start with these files:

1. **`Views/Main/MainContentCoordinator.swift`** — Business logic hub, query execution, tab management
2. **`Views/MainContentView.swift`** — Main window layout, coordinator integration
3. **`Models/QueryTab.swift`** — Tab model with all per-tab state (results, pagination, filters, changes)
4. **`Models/ConnectionSession.swift`** — Active connection session with driver, tables, tabs
5. **`Core/Database/DatabaseDriver.swift`** — Protocol all database drivers must implement
6. **`Core/Database/DatabaseManager.swift`** — Connection lifecycle management
7. **`Views/Results/DataGridView.swift`** — High-performance NSTableView wrapper
8. **`Core/ChangeTracking/DataChangeManager.swift`** — Track INSERT/UPDATE/DELETE changes
9. **`Core/Autocomplete/CompletionEngine.swift`** — Framework-agnostic autocomplete
10. **`Views/Editor/SQLEditorView.swift`** — CodeEditSourceEditor SwiftUI wrapper

---

## Implementation Priority Summary

### Phase 1: v0.2.0 — Essential Gaps (Next Release)
1. SSL/TLS connection support
2. ~~CSV clipboard paste (RFC 4180 parser + auto-detection)~~ (DONE)
3. ~~Complete redo functionality~~ (DONE)
4. ~~Connection switcher popover~~ (DONE)
5. ~~Replace `print()` with `Logger`~~ (DONE)

### Phase 2: v0.3.0 — Developer Productivity
6. ~~Query execution plan (EXPLAIN)~~ (DONE — basic)
7. Foreign key lookup dropdown
8. Date/time picker for date columns
9. JSON column editor
10. Query execution timeout

### Phase 3: v0.4.0 — Database Object Management
11. Stored procedure/function browser
12. Trigger management
13. View creation/editing
14. User/role management
15. SQLite table recreation for schema changes

### Phase 4: v0.5.0 — Import/Export & Polish
16. Excel export (.xlsx)
17. JSON import
18. Schema compare/diff
19. Read-only connection mode
20. Keyboard shortcuts customization

### Phase 5: v1.0.0 — Feature Complete
21. ER diagram
22. Visual query builder
23. Unit test coverage
24. Localization infrastructure
25. Accessibility (VoiceOver)

---

*Last updated: February 2026 | Generated by analyzing the full TablePro source code*
