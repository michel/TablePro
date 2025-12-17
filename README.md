# OpenTable

A native macOS database client built with SwiftUI. A fast, lightweight alternative to TablePlus for managing MySQL, PostgreSQL, MariaDB, and SQLite databases.

## Features

### Multi-Database Support
- **MySQL** and **MariaDB** via CLI integration
- **PostgreSQL** via CLI integration
- **SQLite** with native libsqlite3 support

### Connection Management
- Multiple saved connection profiles
- Secure credential storage using macOS Keychain
- Connection testing before save
- SSH tunnel support

### Query Editor
- SQL syntax highlighting (keywords, strings, numbers, comments)
- Multi-tab query interface with query and table tabs
- Execute queries with `Cmd+Enter`
- Query-at-cursor execution (runs only the statement at cursor position)

### SQL Autocomplete
- Context-aware suggestions based on query position
- Table and column name completion with alias support
- 50+ SQL functions organized by category (aggregate, date/time, string, numeric)
- SQL snippets for common query patterns
- Keyboard navigation with `Up/Down/Enter/Escape`
- Manual trigger with `Ctrl+Space`

### High-Performance Data Grid
- NSTableView-based grid for handling large datasets
- Row numbers column
- Column resizing and reordering
- Alternating row colors for readability
- Multiple row selection

### Inline Cell Editing
- Double-click to edit any cell
- NULL value display with italic gray placeholder
- Empty string and DEFAULT value support
- Modified cells highlighted with yellow background
- Context menu: Set NULL/Empty/Default, Copy value

### Change Management
- Track pending changes before commit
- Auto-generate UPDATE/INSERT/DELETE statements
- Commit all changes with `Cmd+S`
- Discard changes and restore original values

### SQL Function Support
- Recognizes datetime functions: `NOW()`, `CURRENT_TIMESTAMP()`, `CURDATE()`, etc.
- Functions execute as SQL expressions, not string literals

### Data Export
- Export to CSV with proper escaping
- Export to JSON (pretty-printed)
- Copy to clipboard as tab-separated values

### Query History
- Auto-save executed queries (up to 100 entries)
- Query history panel (`Cmd+Shift+H`)
- Re-run previous queries with one click
- Tracks connection, row count, execution time, and status

### Table Structure View
- View columns with types, nullable status, and defaults
- View indexes with primary/unique indicators
- View foreign keys with ON DELETE/UPDATE rules
- Toggle between Data and Structure views

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Enter` | Execute query |
| `Cmd+S` | Save/commit changes |
| `Cmd+R` | Refresh data |
| `Cmd+W` | Close tab |
| `Cmd+N` | New connection |
| `Cmd+E` | Export to CSV |
| `Cmd+Shift+E` | Export to JSON |
| `Cmd+Shift+H` | Query history |
| `Ctrl+Space` | Trigger autocomplete |

## Requirements

- macOS 13.0 or later
- For MySQL/MariaDB: `mysql` CLI client (typically at `/opt/homebrew/bin/mysql`)
- For PostgreSQL: `psql` CLI client (typically at `/opt/homebrew/bin/psql`)
- For SQLite: No additional requirements (uses native libsqlite3)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/OpenTable.git
   ```

2. Open `OpenTable.xcodeproj` in Xcode

3. Build and run (`Cmd+R`)

## Architecture

```
OpenTable/
├── Core/
│   ├── Autocomplete/     # SQL autocompletion system
│   ├── Database/         # Database drivers and manager
│   ├── Export/           # CSV/JSON export
│   └── Storage/          # Keychain + UserDefaults persistence
├── Models/               # Data models (Connection, QueryResult, etc.)
├── Theme/                # Theme definitions
└── Views/
    ├── Connection/       # Connection form
    ├── Editor/           # Query editor and tabs
    ├── Results/          # Data grid
    ├── Sidebar/          # Table browser
    └── Structure/        # Table structure view
```

### Design Patterns

- **Protocol-Oriented Database Layer**: `DatabaseDriver` protocol with MySQL, PostgreSQL, and SQLite implementations
- **Factory Pattern**: `DatabaseDriverFactory` creates the appropriate driver based on connection type
- **Singleton Services**: `DatabaseManager`, `ConnectionStorage`, `QueryHistoryManager`
- **NSViewRepresentable**: SwiftUI wrappers for AppKit components (NSTextView, NSTableView)

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 0.2.0 | Dec 2024 | Data grid editing, SQL function support, autocomplete |
| 0.1.0 | Dec 2024 | Initial release with core features |

## License

MIT License

## Author

Ngo Quoc Dat
