# TablePro Project Tracking

**Generated:** February 12, 2026 | **Version:** 0.2.0 | **Codebase:** 206 files, ~47,600 LOC

---

## Overall Health Scorecard

| Area | Score | Status |
|------|-------|--------|
| Core Functionality | 9/10 | Excellent |
| Code Quality (SwiftLint) | 10/10 | Zero violations |
| Architecture | 9/10 | Clean separation of concerns |
| Test Coverage | 0/10 | **No tests exist** |
| API Backend Security | 8/10 | Rate limiting, input validation, atomic locking added; still missing RBAC |
| Documentation | 8/10 | Comprehensive, missing v0.2.0 changelog |
| Accessibility | 2/10 | Only 2 a11y labels |
| Localization | 7/10 | English + Vietnamese (637 strings), language setting in General preferences |
| Performance | 9/10 | Sophisticated optimizations |
| Dependencies | 9/10 | Minimal, well-maintained; CodeEditSourceEditor tracks `main` branch (pending 0.16.0 release) |

---

## Table of Contents

- [CRITICAL Issues](#critical-issues)
- [WARNING Issues](#warning-issues)
- [Code Quality Issues](#code-quality-issues)
- [Missing Features](#missing-features)
- [API Backend Issues](#api-backend-issues)
- [Documentation Issues](#documentation-issues)
- [Technical Debt](#technical-debt)
- [Feature Comparison vs Competitors](#feature-comparison-vs-competitors)
- [Recommended Roadmap](#recommended-roadmap)

---

## CRITICAL Issues

### C1. No Unit Tests
- **Impact:** No regression prevention, high refactoring risk
- **Details:** Zero XCTest target exists. 206 files, ~47,600 LOC completely untested
- **Priority areas:** Database drivers, SQLContextAnalyzer, DataChangeManager, ExportService
- **Action:** Create test target + add critical path tests

### C2. API: Unrestricted Admin Panel Access
- **File:** `api/app/Models/User.php:40-42`
- **Code:** `canAccessPanel()` returns `true` for ALL authenticated users
- **Impact:** Any user with an account can manage all licenses, create/suspend licenses
- **Fix:** Implement role-based access control

### ~~C3. API: No Rate Limiting on License Endpoints~~ DONE
- **File:** `api/routes/api.php`
- **Impact:** Brute force attacks possible on license key space (125-bit entropy, but still)
- **Resolution:** Added `middleware('throttle:60,1')` to API route group (60 req/min per IP)

### ~~C4. App Crashes: fatalError on Missing Resources~~ DONE
- **Files:**
  - `TablePro/Core/Services/LicenseSignatureVerifier.swift` — now optional key + Logger error + throws LicenseError
  - `TablePro/Core/Storage/QueryHistoryStorage.swift` — now logs error + returns early (graceful nil db)
  - `TablePro/Core/Storage/TableTemplateStorage.swift` — now optional URL + throws StorageError.directoryUnavailable
- **Resolution:** Replaced all 3 fatalError calls with graceful error handling

### ~~C5. Documentation Changelog Missing v0.2.0~~ DONE
- **File:** `tablepro.app/docs/changelog.mdx` + `tablepro.app/docs/vi/changelog.mdx`
- **Resolution:** Added v0.2.0 entry to both English and Vietnamese changelog pages (11 features, 7 fixes, 1 improvement)

### ~~C6. macOS 13 Launch Crash (asyncAndWait symbol missing)~~ DONE
- **Impact:** App crashes at launch on macOS 13 with `Symbol not found: _$sSo17OS_dispatch_queueC8DispatchE12asyncAndWait`
- **Root cause:** CodeEditSourceEditor 0.15.2 calls `DispatchQueue.main.asyncAndWait(execute:)` which requires macOS 14+; app targets macOS 13.5
- **Resolution:** Updated CodeEditSourceEditor SPM dependency from version `0.15.2` to tracking `main` branch (commit `1fa4d3c`), which replaces `asyncAndWait` with `sync`

---

## WARNING Issues

### ~~W1. API: License Key Input Validation Too Weak~~ DONE
- **Files:** `api/app/Http/Requests/Api/V1/*.php`
- **Resolution:** Added `max:29` + regex format validation for `license_key` (`XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`) and hex regex for `machine_id` (`/^[a-f0-9]{64}$/i`) across all 3 request files; updated tests accordingly

### W2. API: Private Key in Webroot-Accessible Location
- **File:** `api/.env` → `LICENSE_PRIVATE_KEY_PATH=keys/license_private.pem`
- **Fix:** Move to system-protected location outside webroot (e.g., `/etc/tablepro/`)

### ~~W3. API: Non-Atomic Activation Limit Check~~ DONE
- **File:** `api/app/Http/Controllers/Api/V1/LicenseController.php`
- **Resolution:** Wrapped activation logic in `DB::transaction()` with `lockForUpdate()` on the license row — serializes concurrent requests to prevent exceeding the activation limit

### W4. 41 Missing Screenshot Images in Documentation
- **Affected pages:** Settings, filtering, import/export, history, appearance, installation
- **Examples:** `filter-panel-dark.png`, `settings-general.png`, `import-dialog.png`, etc.
- **Fix:** Generate and commit missing image files

### ~~W5. Xcode SWIFT_VERSION Mismatch~~ DONE
- **Resolution:** Updated both Debug and Release `SWIFT_VERSION` from `5.0` to `5.9` in `project.pbxproj` to match `.swiftformat` target

### ~~W6. PostgreSQL Constraint Name Assumption~~ DONE
- **File:** `TablePro/Core/SchemaTracking/SchemaStatementGenerator.swift:415-420`
- **Issue:** Assumes PK constraint name follows `{table}_pkey` convention
- **Resolution:** `DatabaseManager.fetchPrimaryKeyConstraintName()` queries the actual name from `pg_constraint` before generating SQL; `SchemaStatementGenerator` accepts an optional `primaryKeyConstraintName` parameter and falls back to `{table}_pkey` convention only as a last resort

### ~~W7. Static Libraries Committed to Git~~ DONE
- **Files:** `Libs/libmariadb*.a` (540KB - 1.1MB each)
- **Resolution:** Migrated to Git LFS tracking (`Libs/*.a` rule in `.gitattributes`); removed stale `.gitignore` entries

### W8. Large Untracked Directories
- `api/` (143MB) and `tablepro.app/` (465MB) are untracked in the main repo
- `api/vendor/` (133MB) and `tablepro.app/node_modules/` (388MB) should be .gitignore'd
- **Fix:** Add to `.gitignore` or move to separate repos

### W9. Build Log Committed
- **File:** `build-arm64.log` (1.1MB) with disk I/O errors
- **Fix:** Remove and add `*.log` to `.gitignore`

---

## Code Quality Issues

### TODOs in Code (2 items)

| File | Description | Priority |
|------|-------------|----------|
| `Views/Editor/SQLEditorCoordinator.swift:62` | Remove find panel z-order workaround when CodeEditSourceEditor fixes upstream | Low |
| `Core/SchemaTracking/SchemaStatementGenerator.swift:415` | Enhance DatabaseDriver protocol for constraint name queries | Medium |

### Force Unwraps (Safe but Notable)

| File | Lines | Context |
|------|-------|---------|
| `Core/Autocomplete/SQLContextAnalyzer.swift` | 177, 185, 193, 201 | `try!` on fallback regex — guarded by `assertionFailure` + `try?` primary |
| `Core/Services/LicenseAPIClient.swift` | 18 | Hardcoded URL — always valid, SwiftLint disabled |

### ~~Print Statements (3 remaining)~~ DONE

- **Resolution:** Replaced `print()` with `logger.debug()` in documentation example (ResponderChainActions.swift); removed `print()` from `#Preview` blocks (DatabaseSwitcherSheet.swift)

### ~~Anti-Patterns~~ DONE

- **Resolution:** Replaced `.count > 0` with `!.isEmpty` in documentation example; replaced 12 `filter { }.count` patterns with `count(where:)` across 7 files (DataChangeManager, RowOperationsManager, FilterState, QueryTab, ExportModels)

### Large Files Approaching Limits

| File | Lines | Limit (warn/error) |
|------|-------|---------------------|
| `Views/Main/MainContentCoordinator.swift` | 1387 | 1200/1800 (already split into 6 extensions) |
| `Core/Services/ExportService.swift` | 990 | 1200/1800 |
| `Core/Database/MariaDBConnection.swift` | 987 | 1200/1800 |
| `Views/Results/DataGridView.swift` | 972 | 1200/1800 |
| `Views/Editor/CreateTableView.swift` | 910 | 1200/1800 |

---

## Missing Features

### Tier 1 — Critical Gaps (Daily Developer Use)

| Feature | Priority | Effort | Notes |
|---------|----------|--------|-------|
| Stored Procedure/Function Browser | HIGH | Large | No sidebar section, no `information_schema.routines` query |
| Trigger Management | HIGH | Medium | No triggers tab in TableStructureView |
| ~~Enum Column Editor~~ | ~~HIGH~~ | ~~Small~~ | **DONE** — Searchable dropdown for ENUM, multi-select checkbox for SET, with PostgreSQL `pg_enum` + SQLite CHECK constraint support |
| File-based CSV/JSON Import | HIGH | Medium | SQL file import exists (`ImportDialog`), but no CSV/JSON file import yet (clipboard CSV paste works) |

### Tier 2 — High-Priority Gaps (Weekly Developer Use)

| Feature | Priority | Effort | Notes |
|---------|----------|--------|-------|
| Schema Compare/Diff | MEDIUM | Large | No UI for comparing schemas |
| ER Diagram | MEDIUM | Large | No visual entity-relationship diagram |
| User/Role Management | MEDIUM | Large | No sidebar section for Users/Roles |
| SQLite Table Recreation for ALTER | MEDIUM | Medium | Throws `unsupportedOperation` for most ALTER TABLE |
| Keyboard Shortcut Customization | MEDIUM | Medium | All shortcuts hardcoded |
| ~~Connection Health Monitoring~~ | ~~MEDIUM~~ | ~~Medium~~ | **DONE** — 30s periodic ping (SELECT 1) for MySQL/PostgreSQL, 3-retry exponential backoff (2s/4s/8s), toolbar Reconnect button |

### Tier 3 — Nice-to-Have

| Feature | Status |
|---------|--------|
| Custom Editor Themes | System light/dark only |
| Code Folding | CodeEditSourceEditor limitation |
| Regex Find/Replace | Not implemented |
| Split Editor View | Not implemented |
| Visual Query Builder | Not implemented |
| Column Statistics | Not implemented |
| Data Generator/Faker | Not implemented |
| Cloud Sync (iCloud) | Not implemented |
| Plugin/Extension System | Not implemented |

---

## API Backend Issues

### Architecture Summary
- **Framework:** Laravel 12.50 (PHP 8.2+)
- **Admin Panel:** Filament 5.2
- **Database:** SQLite (dev), supports MySQL/PostgreSQL (prod)
- **Tests:** 11 Pest tests covering core flows

### Security Issues

| # | Issue | Severity | File |
|---|-------|----------|------|
| 1 | Admin panel: no role-based access | CRITICAL | `app/Models/User.php:40-42` |
| 2 | No rate limiting on API | WARNING | `routes/api.php` |
| 3 | Private key in webroot | WARNING | `storage/keys/` |
| 4 | Debug mode enabled | WARNING | `.env` (APP_DEBUG=true for prod) |
| 5 | License key format not validated | WARNING | `Http/Requests/Api/V1/*.php` |
| 6 | Machine ID not hex-validated | WARNING | `Http/Requests/Api/V1/*.php` |
| 7 | Non-atomic activation limit | WARNING | `LicenseController.php:61-65` |

### Missing API Features

| Feature | Priority |
|---------|----------|
| Rate limit response headers (X-RateLimit-*) | HIGH |
| OpenAPI/Swagger documentation | HIGH |
| Email notifications for expiring licenses | MEDIUM |
| Audit trail for admin actions | MEDIUM |
| Key rotation mechanism | MEDIUM |
| Offline license validation | LOW |
| License transfer between machines | LOW |
| Usage analytics dashboard | LOW |

### Missing Tests

| Test Case | Priority |
|-----------|----------|
| Expired license validation | HIGH |
| Concurrent activation attempts | HIGH |
| Admin panel authorization | HIGH |
| Rate limiting behavior | MEDIUM |

---

## Documentation Issues

### Summary
- **Total pages:** 54 (27 EN + 27 VI)
- **Translation coverage:** 100% parity
- **SEO/Meta:** All pages have proper front matter

### Issues Found

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | Changelog missing v0.2.0 | CRITICAL | `docs/changelog.mdx` only has v0.1.1 |
| 2 | 41 screenshot images missing | WARNING | Referenced in docs but files don't exist |
| ~~3~~ | ~~README.md is Mintlify boilerplate~~ | ~~INFO~~ | **DONE** — Replaced with project-specific content |

### Missing v0.2.0 Features from Docs Changelog
The following v0.2.0 features are documented on feature pages but missing from changelog:
- SSL/TLS connection support
- CSV clipboard paste
- Explain Query (EXPLAIN)
- Connection switcher popover
- Date/time picker
- Read-only connection mode
- Query execution timeout
- Foreign key lookup dropdown
- JSON column editor
- Excel (.xlsx) export
- View management (Create/Edit/Drop)

---

## Technical Debt

### ~~No Localization (i18n)~~ DONE
- String Catalog (`Localizable.xcstrings`) with 637 strings
- Full Vietnamese translation (100% coverage)
- Language setting in General preferences (System, English, Vietnamese)
- Requires app restart for language change to take effect
- Remaining: Add more languages (competitors support 10-20+)

### Minimal Accessibility
- Only 2 `accessibilityLabel` instances in entire codebase
- No VoiceOver support for data grid or SQL editor
- Fails WCAG 2.1 AA standards
- Effort: Medium (systematic audit needed)

### No App Notarization in CI
- Users get "unverified developer" warning on download
- Workaround: `xattr -d com.apple.quarantine TablePro.app`
- Fix: Implement notarization in CI workflow

### App Sandbox Disabled
- Required for SSH tunneling and database access
- `com.apple.security.app-sandbox: false`
- `com.apple.security.cs.disable-library-validation: true`
- Acceptable trade-off but reduces security isolation

---

## Feature Comparison vs Competitors

### vs TablePlus ($99)

| Feature | TablePro | TablePlus | Gap |
|---------|----------|-----------|-----|
| SQL Highlighting | Tree-sitter | Proprietary | — |
| Autocomplete | Context-aware | Similar | — |
| Stored Procedures | No UI | Yes | **Missing** |
| ER Diagram | No | Yes | **Missing** |
| Triggers | No | Yes | **Missing** |
| Code Folding | No | Yes | **Missing** |
| Custom Themes | System only | Full | **Partial** |
| SSH Tunneling | Full | Full | — |
| Read-only Mode | v0.2.0 | Yes | — |
| Localization | English + Vietnamese | 10+ langs | **Partial** |
| Cost | Free (GPL v3) | $99 | **Win** |

### TablePro Advantages
1. **Native macOS UI** (SwiftUI + AppKit) — faster than Electron/Java alternatives
2. **Free and open-source** (GPL v3)
3. **Universal Binary** (Apple Silicon + Intel)
4. **Lightweight** memory footprint
5. **Zero violations** in SwiftLint across 47K LOC

---

## Recommended Roadmap

### v0.3.0 — Database Object Management (3-4 weeks)
- [ ] Stored procedure/function browser
- [ ] Trigger management UI
- [x] Enum column editor dropdown
- [ ] File-based CSV import dialog
- [ ] Fix SQLite ALTER TABLE limitations

### v0.4.0 — Quality & Testing (4-6 weeks)
- [ ] Create XCTest target + critical path tests
- [ ] Accessibility audit + VoiceOver for data grid
- [ ] Code signing + notarization in CI
- [ ] API: Add rate limiting + RBAC for admin panel
- [ ] API: Fix input validation

### v0.5.0 — Advanced Features (4-5 weeks)
- [ ] Schema compare/diff
- [ ] ER diagram visualization
- [ ] Keyboard shortcut customization
- [x] Connection health monitoring + auto-reconnect
- [x] Localization infrastructure

### Immediate Actions (This Week)
1. Update docs changelog with v0.2.0
2. Add rate limiting to API endpoints
3. Fix admin panel authorization (`canAccessPanel`)
4. Replace `fatalError` calls with proper error handling
5. ~~Fix `.count > 0` anti-pattern in ResponderChainActions~~ DONE
6. Clean up git (remove build log, update .gitignore)

---

*This tracking file was auto-generated by analyzing the full project including Xcode project, API backend, and documentation site.*
