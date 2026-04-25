# Roadmap

## Where we are

**Phase 0 — Foundation.** Stack picked, spike validated, docs written. No production code yet.

The spike at `~/Workspaces/tablepro-linux-spike` proved that Rust + GTK4 + libadwaita + sqlx + GtkColumnView can render and scroll 100,000 rows smoothly. That answered the only question worth answering before committing. The spike is throwaway and will be deleted; the real codebase is built fresh inside `linux/crates/`.

## Phase 0 — Foundation (4–6 weeks)

Goal: a workspace that compiles, has CI, and has the contracts in place that the rest of the project will fill in.

- [ ] Cargo workspace skeleton: `app`, `core`, `storage`, `drivers/postgres`, `drivers/sqlite`, `drivers/mysql`
- [ ] `core::DatabaseDriver`, `core::Connection`, `core::DriverRegistry` traits (final shape, not stubs)
- [ ] `storage`: libsecret wrapper (`oo7` crate), `gio::Settings` schema, JSON connection store, with full test coverage
- [ ] One end-to-end smoke test: `tablepro-app` connects to PostgreSQL via the registered driver and prints the table list to stderr
- [ ] CI: `cargo build`, `cargo test`, `cargo clippy --deny warnings`, `cargo fmt --check` on Ubuntu 24.04
- [ ] Flatpak manifest skeleton, builds locally with `flatpak-builder`
- [ ] `rustfmt.toml`, `clippy.toml`, `rust-toolchain.toml` set
- [ ] Pre-commit hook (rustfmt + clippy)

Exit criterion: a fresh contributor can clone the repo, follow [README.md](README.md), and reach a working `cargo run` against a local PostgreSQL in under 15 minutes.

## Phase 1 — MVP (2–3 months)

Goal: an app a developer would use daily for the three most common engines.

- [ ] Connection list with libsecret-backed credentials, group support, colour tags
- [ ] `AdwNavigationSplitView` shell — sidebar, content area, header bar with connect / disconnect / refresh
- [ ] Table list (filtered, sorted, searchable)
- [ ] Browse a table: pagination, basic where-filter, column resize, column reorder
- [ ] SQL editor: GtkSourceView 5 + tree-sitter-sql, run query, results grid
- [ ] Single-row insert / update / delete with explicit save
- [ ] Three drivers: PostgreSQL, SQLite, MySQL / MariaDB
- [ ] Flathub nightly publishing

Out: AI chat, ER diagram, schema editor, multi-tab queries, history search. Those land in Phase 2.

## Phase 2 — Parity push (3–4 months)

Goal: feature parity with the macOS app for the bundled engines.

- [ ] Remaining bundled drivers: ClickHouse, MSSQL (tiberius), Redis (fred), MongoDB
- [ ] Multi-tab result viewer with `AdwTabView`
- [ ] ER diagram (Cairo + GTK)
- [ ] Schema editor (create / alter / drop tables, indexes, FKs)
- [ ] Import / export (CSV, JSON, SQL, XLSX)
- [ ] Query history with FTS (SQLite FTS5, same approach as macOS)
- [ ] Schema-aware autocomplete
- [ ] SSH tunnelling via `russh`
- [ ] AI chat with streaming markdown rendering
- [ ] Vim mode in the editor (custom impl on top of GtkSourceView)

## Phase 3 — Polish and distribution (1–2 months)

Goal: the app feels first-class on every mainstream Linux desktop.

- [ ] KDE / Plasma testing pass; accept Adwaita styling on KDE as the policy
- [ ] Wayland-specific bug fixes; HiDPI testing across DEs
- [ ] AppImage + `.deb` + `.rpm` builds via CI
- [ ] AUR PKGBUILD (community-maintained, mirror in repo)
- [ ] Flathub stable channel
- [ ] Marketing site Linux page, screenshots, install matrix

## Out of scope, explicitly

| Item | Why |
|---|---|
| Plugin system | Maintenance burden. Drivers are static. See [docs/decisions/0001-no-plugin-system.md](docs/decisions/0001-no-plugin-system.md). |
| Windows / macOS builds | Separate apps in this monorepo for those platforms. |
| Embedded scripting (JS / Python / Lua) | SQL is enough. Adds attack surface and no users have asked. |
| Cross-platform binaries from this codebase | Zero shared code with macOS / iOS by design. |

## Phase B — Repository restructure (deferred)

Once the Linux MVP ships and is stable, the top-level repository layout migrates to:

```
apps/macos/        (move TablePro/, TableProTests/, Plugins/, Libs/, LocalPackages/)
apps/ios/          (move TableProMobile/)
apps/linux/        (move from linux/)
packages/          (move Packages/TableProCore/)
```

This is a separate undertaking and is not blocking Phase 0 or Phase 1. It moves only after Linux is real and there is a reason to flatten the platform tree.
