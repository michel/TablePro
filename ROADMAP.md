# OpenTable Roadmap

A native macOS database client built with SwiftUI for MySQL, MariaDB, PostgreSQL, and SQLite.

## ✅ Milestone 1: Core Foundation (Completed)

### Connection Management
- [x] Multiple database connection profiles
- [x] Secure credential storage (Keychain)
- [x] Connection testing before save
- [x] SSH tunnel support

### Database Browsing
- [x] Table list sidebar with icons (tables vs views)
- [x] Active table highlighting synced with tabs
- [x] Table context menu (SELECT queries, copy name)
- [x] Database refresh functionality

### Query Editor
- [x] SQL syntax highlighting
- [x] Multi-tab query interface
- [x] Query execution with results display
- [x] Keyboard shortcuts (⌘+Enter to execute)

---

## ✅ Milestone 2: Data Grid & Editing (Completed)

### High-Performance Data Grid
- [x] NSTableView-based grid for performance
- [x] Row numbers column
- [x] Column resizing and reordering
- [x] Alternating row colors
- [x] Native column sorting (click header, native arrow indicators)
- [x] 100% native NSTableView sorting via sortDescriptorsDidChange
- [x] TablePlus-style cell focus (click cell → Enter to edit)

### Inline Cell Editing
- [x] Double-click to edit cells
- [x] Single-click to focus cell, Enter to edit (TablePlus behavior)
- [x] NULL value display with placeholder (italic, gray)
- [x] Empty string display with "Empty" placeholder
- [x] DEFAULT value support
- [x] Modified cell highlighting (yellow background)
- [x] Per-tab change tracking (preserved when switching tabs)

### SQL Function Support
- [x] NOW() and CURRENT_TIMESTAMP() recognition
- [x] Other datetime functions (CURDATE, CURTIME, UTC_TIMESTAMP, etc.)
- [x] Functions execute as SQL, not string literals

### Context Menu Actions
- [x] Set Value → NULL / Empty / Default
- [x] Copy cell value
- [x] Copy row / selected rows
- [x] Copy column name (header right-click)
- [x] Delete row (with undo)

### Change Management
- [x] Track pending changes before commit
- [x] Generate UPDATE/INSERT/DELETE SQL
- [x] Commit all changes at once
- [x] Discard changes with restore
- [x] Confirm discard when closing tab with changes

---

## ✅ Milestone 3: Enhanced Features (Completed)

### SQL Autocomplete
- [x] Context-aware keyword suggestions
- [x] Table name completion
- [x] Column completion (with table.column support)
- [x] Table alias support
- [x] Function completion (50+ SQL functions)
- [x] Keyboard navigation (↑↓↵Esc)
- [x] Manual trigger (Ctrl+Space)
- [x] Refactored with dedicated `CompletionEngine`
- [x] Improved completion window controller

### SQL Editor Improvements
- [x] Line numbers with custom `LineNumberView`
- [x] Enhanced syntax highlighting with `SyntaxHighlighter`
- [x] Centralized editor coordination with `EditorCoordinator`
- [x] Custom `EditorTextView` with integrated features
- [x] Dedicated `SQLEditorTheme` for theming
- [x] Improved autocomplete integration

### Data Export
- [x] Export to CSV
- [x] Export to JSON
- [x] Copy to clipboard (tab-separated)
- [ ] Export to SQL (INSERT statements)

### Table Structure
- [x] View table columns and types
- [x] View indexes
- [x] View foreign keys
- [ ] CREATE TABLE statement preview

---

## ✅ Milestone 4: Data Management (Completed)

### Insert/Delete Operations
- [x] Add new row with DEFAULT values (⌘+I)
- [x] Bulk delete selected rows (⌘+Delete or Backspace)
- [x] Duplicate row (⌘+D)
- [x] Truncate table (⌥+Delete)

### Keyboard Navigation
- [x] Tab → next cell
- [x] Shift+Tab → previous cell
- [x] Arrow keys → navigate cells (with Shift for range selection)
- [x] Escape → cancel editing / clear selection
- [x] Cmd+Z → undo cell change / row insertion / row deletion
- [x] Cmd+Shift+Z → redo undone changes
- [x] Enter → edit focused cell

### Multi-Row Selection
- [x] Click to select single row
- [x] Shift+Click for range selection
- [x] Cmd+Click to toggle individual rows
- [x] Shift+Arrow keys for range selection

---

## 📋 Milestone 5: Advanced Features (Planned)

### Query Builder
- [ ] Visual query builder
- [ ] JOIN builder
- [ ] WHERE clause builder
- [ ] ORDER BY / LIMIT UI

### Data Filtering
- [ ] Column filters
- [ ] Quick search across results
- [ ] Filter presets

### Schema Management
- [ ] Create/alter tables (GUI)
- [ ] Manage indexes
- [ ] Manage foreign keys

---

## 🔮 Future Ideas

### Query & Editor Enhancements
- Query history with search
- Query explain/analyze
- Query snippets/templates
- Multi-statement execution with batch results
- Query bookmarks/favorites

### Data Management
- Data import from CSV/JSON
- Bulk edit with formulas
- Column widths memory (per table)
- Filter presets and saved filters
- Quick search across results

### Schema & Structure
- ER diagram visualization
- CREATE TABLE statement preview
- Table relationships graph

### User Experience
- Connection groups/folders
- Dark mode theme customization
- Favorite/pinned tables
- Custom keyboard shortcuts
- Multi-window support

### Advanced Features
- Stored procedure execution
- Database migration tools
- SQL formatting/beautification
- Column statistics and data profiling
- Redis / MongoDB support

---
