# OpenTable Roadmap

A native macOS MySQL database client built with SwiftUI.

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

### Inline Cell Editing
- [x] Double-click to edit cells
- [x] NULL value display with placeholder (italic, gray)
- [x] Empty string display with "Empty" placeholder
- [x] DEFAULT value support
- [x] Modified cell highlighting (yellow background)

### SQL Function Support
- [x] NOW() and CURRENT_TIMESTAMP() recognition
- [x] Other datetime functions (CURDATE, CURTIME, UTC_TIMESTAMP, etc.)
- [x] Functions execute as SQL, not string literals

### Context Menu Actions
- [x] Set Value → NULL / Empty / Default
- [x] Copy cell value
- [x] Copy row / selected rows
- [x] Delete row (with undo)

### Change Management
- [x] Track pending changes before commit
- [x] Generate UPDATE/INSERT/DELETE SQL
- [x] Commit all changes at once
- [x] Discard changes with restore

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

### Data Export
- [ ] Export to CSV
- [ ] Export to JSON
- [ ] Export to SQL (INSERT statements)
- [ ] Copy as INSERT statement

### Query History
- [ ] Auto-save executed queries
- [ ] Query history panel
- [ ] Re-run previous queries
- [ ] Favorite/bookmark queries

### Table Structure
- [ ] View table columns and types
- [ ] View indexes
- [ ] View foreign keys
- [ ] CREATE TABLE statement preview

---

## 📋 Milestone 4: Advanced Features (Planned)

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

- PostgreSQL support
- SQLite support
- Dark/Light theme toggle
- Query auto-complete
- ER diagram visualization
- Data import from CSV/JSON
- Stored procedure execution
- Query explain/analyze

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 0.1.0 | Dec 2024 | Initial release with core features |
| 0.2.0 | Dec 2024 | Data grid editing, SQL function support |
