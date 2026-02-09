# Changelog

All notable changes to TablePro will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-02-09

### Added

- Migrate SQL editor to CodeEditSourceEditor (tree-sitter powered)
- Multi-statement SQL execution support
- "Show Structure" context menu for sidebar tables
- Improved filter panel UI/UX
- SwiftUI EditorTabBar (replacing AppKit NativeTabBarView)

### Fixed

- Fix Delete key on data grid row from marking table as deleted
- Code review fixes for multi-statement execution

### Changed

- Add SPM Package.resolved for CodeEditSourceEditor dependencies
- Add Claude Code project settings
- Update build/test commands with `-skipPackagePluginValidation`

## [0.1.0] - 2026-02-05

### Initial Public Release

TablePro is a native macOS database client built with SwiftUI and AppKit, designed as a fast, lightweight alternative to TablePlus.

### Features

- **Database Support**
  - MySQL/MariaDB connections
  - PostgreSQL support
  - SQLite database files
  - SSH tunneling for secure remote connections

- **SQL Editor**
  - Syntax highlighting with TreeSitter
  - Intelligent autocomplete for tables, columns, and SQL keywords
  - Multi-tab editing support
  - Query execution with result grid

- **Data Management**
  - Interactive data grid with sorting and filtering
  - Inline editing capabilities
  - Add, edit, and delete rows
  - Pagination for large result sets
  - Export data (CSV, JSON, SQL)

- **Database Explorer**
  - Browse tables, views, and schema
  - View table structure and indexes
  - Quick table information and statistics
  - Search across database objects

- **User Experience**
  - Native macOS design with SwiftUI
  - Dark mode support
  - Customizable keyboard shortcuts
  - Query history tracking
  - Multiple database connections

- **Developer Features**
  - Import/export connection configurations
  - Custom SQL query templates
  - Performance optimized for large datasets

[Unreleased]: https://github.com/datlechin/tablepro/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/datlechin/tablepro/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/datlechin/tablepro/releases/tag/v0.1.0
