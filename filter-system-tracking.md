# Filter System — Tracking

> Analysis date: 2025-02-25
> Status: Active tracking document for bugs, improvements, and features

---

## Architecture Overview

```
Presentation Layer
  FilterPanelView / FilterRowView / QuickSearchField
  FilterSettingsPopover / SQLPreviewSheet / MainStatusBarView

State Layer (ObservableObject)
  FilterStateManager  ←→  FilterPresetStorage / FilterSettingsStorage

Coordinator Layer
  MainContentCoordinator+Filtering
  MainContentCoordinator+FKNavigation
  MainContentCommandActions

SQL Generation Layer
  FilterSQLGenerator   (WHERE clause builder)
  TableQueryBuilder    (full SELECT assembly)

Storage Layer
  FilterSettingsStorage  (UserDefaults — behavior settings + per-table last filters)
  FilterPresetStorage    (UserDefaults — named presets)
  QueryTab.filterState   (in-memory TabFilterState snapshot)
```

### Key Files

| File                                                              | Purpose                                                      |
| ----------------------------------------------------------------- | ------------------------------------------------------------ |
| `Models/TableFilter.swift`                                        | `FilterOperator` (18 cases), `TableFilter`, `TabFilterState` |
| `Models/FilterState.swift`                                        | `FilterStateManager` (ObservableObject), `FilterLogicMode`   |
| `Models/FilterPreset.swift`                                       | `FilterPreset`, `FilterPresetStorage`                        |
| `Core/Database/FilterSQLGenerator.swift`                          | `[TableFilter]` → SQL WHERE clause                           |
| `Core/Services/TableQueryBuilder.swift`                           | `buildFilteredQuery`, `buildQuickSearchQuery`                |
| `Core/Storage/FilterSettingsStorage.swift`                        | Behavior defaults + per-table last filters                   |
| `Views/Filter/FilterPanelView.swift`                              | Panel container: header, list, footer                        |
| `Views/Filter/FilterRowView.swift`                                | Single filter row UI                                         |
| `Views/Filter/QuickSearchField.swift`                             | Cross-column search field                                    |
| `Views/Filter/FilterSettingsPopover.swift`                        | Default settings popover                                     |
| `Views/Filter/SQLPreviewSheet.swift`                              | WHERE clause preview modal                                   |
| `Views/Main/Extensions/MainContentCoordinator+Filtering.swift`    | Filter/search query execution                                |
| `Views/Main/Extensions/MainContentCoordinator+FKNavigation.swift` | FK-driven filter application                                 |
| `Views/Main/MainContentCommandActions.swift`                      | Menu/keyboard routing                                        |

---

## Bugs

### BUG-1: AND/OR logic mode ignored in query execution

- **Severity:** High
- **Status:** Fixed
- **Location:** `MainContentCoordinator+Filtering.swift` → `applyFilters()`
- **Description:** `TableQueryBuilder.buildFilteredQuery` calls `FilterSQLGenerator.generateWhereClause(from: filters)` without passing `logicMode`, which defaults to `.and`. The `filterLogicMode` property from `FilterStateManager` is only passed to `generatePreviewSQL()` (used by the SQL Preview Sheet). This means the user can set OR mode in the UI, see correct OR-based SQL in the preview, but the actual executed query always uses AND.
- **Fix:** Added `logicMode` parameter to `TableQueryBuilder.buildFilteredQuery`, passed `filterStateManager.filterLogicMode` in `applyFilters` and `rebuildTableQuery`.

### BUG-2: Per-tab filter state not preserved across tab switches

- **Severity:** High
- **Status:** Fixed
- **Location:** `MainContentCoordinator+TabSwitch.swift` (missing calls)
- **Description:** `QueryTab.filterState: TabFilterState` and `FilterStateManager.saveToTabState()/restoreFromTabState()` exist but are never called during tab switching. `FilterStateManager` is a single shared instance, so switching tabs loses the previous tab's filter state (including visibility — opening filters on table B then navigating to table A would leave the panel visible). Also `quickSearchText` and `filterLogicMode` were not persisted per-tab.
- **Fix:** Added `quickSearchText` and `filterLogicMode` to `TabFilterState`. Wired `saveToTabState()`/`restoreFromTabState()` into `handleTabChange` for both old and new tabs.

### BUG-3: PostgreSQL LIKE escape character missing

- **Severity:** Medium
- **Status:** Open
- **Location:** `FilterSQLGenerator.swift` → `escapeLikeWildcards()`, `TableQueryBuilder.swift` → `buildQuickSearchQuery()`
- **Description:** `%` is escaped to `\%` and `_` to `\_`, but no `ESCAPE '\'` clause is emitted in the SQL. MySQL/MariaDB default to `\` as the LIKE escape character so it works there. PostgreSQL does not — `\%` is treated as literal backslash + percent. Affects `contains`, `notContains`, `startsWith`, `endsWith` operators and quick search on PostgreSQL when values contain `%` or `_`.
- **Fix:** Append `ESCAPE '\'` to all LIKE expressions, or use PostgreSQL's standard `ESCAPE` clause.

### BUG-4: SQLite regex silently degrades to LIKE

- **Severity:** Low
- **Status:** Open
- **Location:** `FilterSQLGenerator.swift` → `generateCondition()`, regex case
- **Description:** The `regex` operator on SQLite falls back to `LIKE '%pattern%'`, treating the regex pattern as a LIKE substring. This produces incorrect results for any regex containing `.*`, `^`, `$`, `+`, etc. No warning is shown to the user.
- **Fix options:** (a) Disable the regex operator for SQLite connections, (b) Show a warning/tooltip, or (c) Register a custom `REGEXP` function via `sqlite3_create_function`.

---

## Improvements

### IMP-1: Quick search and filter rows cannot be combined

- **Priority:** Medium
- **Status:** Open
- **Description:** Quick search (`applyQuickSearch`) and filter rows (`applyFilters`) are separate execution paths that each replace the query entirely. There is no way to apply both simultaneously (e.g., filter `status = 'active'` AND quick search for "john").
- **Proposal:** When both are active, combine the filter WHERE clause with the quick search condition using AND.

### IMP-2: Filter presets are global, not scoped

- **Priority:** Low
- **Status:** Open
- **Description:** `FilterPresetStorage` uses a single global UserDefaults key. Presets built for one table/database appear for all tables/databases. A preset referencing column `email` will appear (and fail at runtime) for a table without that column.
- **Proposal options:** (a) Scope presets per table name, (b) Scope per connection+table, (c) Validate preset columns against current table and show warnings.

### IMP-3: Cache FilterSettingsStorage reads

- **Priority:** Low
- **Status:** Superseded by PERF-4
- **Location:** `FilterStateManager` → `addFilter()`, `addFilterForColumn()`
- **Description:** Both methods call `FilterSettingsStorage.shared.loadSettings()` (UserDefaults read + JSON decode) on every invocation. For typical usage this is negligible, but could be cached in the `FilterStateManager` instance and invalidated when settings change.

### IMP-4: Filter row height hardcoded at 40pt

- **Priority:** Low
- **Status:** Open
- **Location:** `FilterPanelView.swift` → `filterList`
- **Description:** The max-height formula `min(CGFloat(count) * 40 + 8, 160)` assumes 40pt per row. Dynamic Type or accessibility font sizes could make rows taller, causing clipping.
- **Proposal:** Use `GeometryReader` or measure actual row height dynamically.

### IMP-5: FK navigation bypasses FilterStateManager API

- **Priority:** Low
- **Status:** Open
- **Location:** `MainContentCoordinator+FKNavigation.swift`
- **Description:** FK navigation directly sets `filterStateManager.filters`, `.appliedFilters`, `.isVisible` properties instead of using the public methods (`addFilter`, `applyAllFilters`, etc.). While functional, this bypasses any validation or side-effects those methods may add in the future.
- **Proposal:** Add a dedicated `setFKFilter(_ filter: TableFilter)` method on `FilterStateManager`.

---

## Feature Ideas

### FEAT-1: Filter by column from context menu

- **Priority:** Medium
- **Description:** Right-click a cell in the data grid → "Filter by this value" → auto-creates and applies an equality filter for that column/value. Similar to how FK navigation works but for any cell.

### FEAT-2: Filter history / recent filters

- **Priority:** Low
- **Description:** Track recently applied filter combinations (beyond per-table last filters) so users can quickly re-apply previous filter sets.

### FEAT-3: Date/time-aware filter operators

- **Priority:** Low
- **Description:** Add operators like `before`, `after`, `today`, `this week`, `last N days` that generate date-aware SQL. Currently users must manually write date comparisons.

### FEAT-4: Filter row drag-to-reorder

- **Priority:** Low
- **Description:** Allow reordering filter rows via drag-and-drop to control grouping and visual organization.

### FEAT-5: Filter groups / nested conditions

- **Priority:** Low
- **Description:** Support grouped conditions like `(A AND B) OR (C AND D)`. Currently only flat AND or flat OR is supported via `FilterLogicMode`.

### FEAT-6: Quick search highlight matches in grid

- **Priority:** Low
- **Description:** When quick search is active, highlight matching cells/text in the data grid results.

### FEAT-7: Column type-aware value input

- **Priority:** Low
- **Description:** For boolean columns show a toggle, for date columns show a date picker, for enum/set columns show a dropdown. Currently all values are plain text input.

---

## Performance Issues

### PERF-1: Quick search keystroke fires @Published on every character (HIGH)
- **Status:** Fixed
- **Location:** `QuickSearchField.swift`, `FilterPanelView.swift`
- **Description:** `$filterState.quickSearchText` is bound directly to the TextField. Every keystroke fires `objectWillChange` on `FilterStateManager`, causing re-render of FilterPanelView, all FilterRowViews, MainEditorContentView, and MainStatusBarView. The actual query only runs on Enter, but the entire view hierarchy re-evaluates on every character.
- **Fix:** Use `@State private var localText` in QuickSearchField, only sync to `filterState.quickSearchText` on submit/clear. Sync from parent on `onAppear` and `onChange(of: searchText)` for tab-switch restore.

### PERF-2: Binding closure allocation per filter row per render (HIGH)
- **Status:** Fixed
- **Location:** `FilterPanelView.swift` → `filterList`, `FilterState.swift` → `binding(for:)`
- **Description:** `filterState.binding(for: filter)` creates a new `Binding<TableFilter>` with 2 closures per row on every render cycle. With 10 filters, every keystroke in quick search allocates 10 Binding objects + 20 closures. The getter also does O(n) lookup via `filters.first { $0.id == filter.id }`.
- **Fix:** Use `ForEach($filterState.filters) { $filter in ... }` — SwiftUI's built-in collection binding projection avoids closure allocation.

### PERF-3: escapeForLike called N times in columns.map loop (HIGH)
- **Status:** Fixed
- **Location:** `TableQueryBuilder.swift` → `buildQuickSearchQuery()`
- **Description:** `escapeForLike(searchText)` is called once per column inside the `.map` closure even though `searchText` never changes. With 50 columns, this runs 50 times with 4 `replacingOccurrences` calls each = 200 unnecessary String allocations.
- **Fix:** Hoist `escapeForLike(searchText)` above the `.map` call.

### PERF-4: FilterSettingsStorage + FilterPresetStorage no caching (MEDIUM)
- **Status:** Fixed
- **Location:** `FilterSettingsStorage.swift` → `loadSettings()`, `FilterPresetStorage.swift` → `loadAllPresets()`
- **Description:** Every call to `loadSettings()` creates a new JSONDecoder and decodes from UserDefaults. Called on every `addFilter()`, `addFilterForColumn()`, `restoreLastFilters()`. Similarly, `loadAllPresets()` does full JSON decode + sort on every call. `savePreset`/`deletePreset` both call `loadAllPresets()` before saving (double I/O).
- **Fix:** Add in-memory cache to both storage classes. Invalidate on write.

### PERF-5: SQL generator unnecessary String allocations (MEDIUM)
- **Status:** Fixed
- **Location:** `FilterSQLGenerator.swift`
- **Description:** (a) `escapeStringValue` runs 2 `replacingOccurrences` even when no special chars present; (b) `escapeLikeWildcards` runs 3 `replacingOccurrences` even when clean; (c) `escapeValue` calls `uppercased()` unconditionally for NULL/TRUE/FALSE check — allocates new String every time; (d) `parseListValues` creates 3 intermediate arrays.
- **Fix:** Add fast-path guards (`contains` check before replacing), use `caseInsensitiveCompare` instead of `uppercased()`, use `split` instead of `components(separatedBy:)`.

### PERF-6: NumberFormatter allocated on every status bar render (MEDIUM)
- **Status:** Fixed
- **Location:** `MainStatusBarView.swift` → `rowInfoText(for:)`
- **Description:** `NumberFormatter()` with `.decimal` style is created inside `rowInfoText` which runs on every render. Every quick search keystroke causes this allocation.
- **Fix:** Use a static cached `NumberFormatter`.

### PERF-7: selectAll fires N @Published mutations + misc (LOW-MEDIUM)
- **Status:** Fixed
- **Location:** `FilterState.swift`, `MainContentCoordinator+Filtering.swift`
- **Description:** (a) `selectAll()` mutates `filters[i]` element-by-element, firing `@Published` N times; (b) `hasActiveQuickSearch` allocates via `trimmingCharacters` on every access; (c) `getFiltersForPreview()` iterates `filters` twice; (d) `rebuildTableQuery` builds base query then discards it when filters are applied.
- **Fix:** Batch selectAll into single array assignment, allocation-free `hasActiveQuickSearch`, single-pass `getFiltersForPreview`, conditional query build in `rebuildTableQuery`.

---

## Completed

- **BUG-1** — AND/OR logic mode now propagated to query execution (2025-02-25)
- **BUG-2** — Per-tab filter state (filters, visibility, quick search, logic mode) saved/restored on tab switch (2025-02-25)
- **BUG-5** — FK navigation filter state regression: `handleTabChange` wiped FK filter on new tab; fixed with `filterStateSavedExternally` flag to pre-save old tab state, persist FK filter to new tab, and reset `quickSearchText`/`filterLogicMode` in `updateFilterState` (2025-02-25)
- **PERF-1** — Quick search local state: TextField binds to @State localText instead of @Published (2025-02-25)
- **PERF-2** — Collection binding: `ForEach($filterState.filters)` eliminates per-row closure allocation (2025-02-25)
- **PERF-3** — Hoisted `escapeForLike` out of columns.map loop (2025-02-25)
- **PERF-4** — Cached `loadSettings()` and `loadAllPresets()` with write invalidation (2025-02-25)
- **PERF-5** — Fast-path string escaping, `caseInsensitiveCompare`, `split` for list parsing (2025-02-25)
- **PERF-6** — Static `NumberFormatter` in MainStatusBarView (2025-02-25)
- **PERF-7** — Batch `selectAll`, allocation-free `hasActiveQuickSearch`, single-pass `getFiltersForPreview`, conditional `rebuildTableQuery` (2025-02-25)
