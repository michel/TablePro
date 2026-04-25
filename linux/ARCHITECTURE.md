# Architecture

TablePro Linux is a layered Rust workspace with strict, one-directional dependencies. The shape is chosen so that adding a database engine touches one crate, replacing the GUI framework would touch one crate, and the domain layer never imports either.

## Crate layout

```
linux/
├── Cargo.toml                     workspace manifest
├── flatpak/                       Flatpak manifest, icons, .desktop file
└── crates/
    ├── app/                       binary, GTK4 entry point, Relm4 components
    ├── core/                      domain types and traits, no GUI deps
    ├── storage/                   libsecret, gio::Settings, file persistence
    └── drivers/
        ├── postgres/              sqlx-postgres impl
        ├── mysql/                 sqlx-mysql impl
        ├── sqlite/                sqlx-sqlite impl
        └── ...                    one crate per database engine
```

## Dependency graph

```
                       ┌─────────┐
                       │   app   │  binary, all GUI code
                       └────┬────┘
                  ┌─────────┼──────────────────┐
                  ▼         ▼                  ▼
             ┌────────┐ ┌─────────┐   ┌──────────────────┐
             │  core  │ │ storage │   │   drivers/*      │
             └────────┘ └────┬────┘   └─────────┬────────┘
                             │                   │
                             └────►  ┌────────┐  ◄
                                     │  core  │
                                     └────────┘
```

Rules, enforced by review:

- `core` depends on **no other workspace crate**. Only the standard library and small utility crates (`async-trait`, `serde`, `thiserror`).
- `storage` depends on `core` only.
- Each `drivers/<engine>` crate depends on `core` only. **Drivers never depend on each other.**
- `app` depends on `core`, `storage`, and every `drivers/*`. It is the only crate that knows about every driver.
- No reverse dependencies. `core` never imports anything from `drivers/*` or `app`.

Consequences:

- Adding a driver does not touch `core`, `storage`, or any other driver.
- Replacing the GUI framework would require rewriting only `app`.
- Drivers can be unit-tested against `core` traits without pulling GTK.
- The build graph is shallow — incremental rebuilds stay fast.

## Composition root

The driver registry is built once in `app::main` before the GTK application starts running:

```rust
fn build_registry() -> DriverRegistry {
    let mut r = DriverRegistry::new();
    r.register(Arc::new(drivers_postgres::PgDriver));
    r.register(Arc::new(drivers_mysql::MysqlDriver));
    r.register(Arc::new(drivers_sqlite::SqliteDriver));
    r
}
```

Adding a new driver = adding one workspace member + one `register` call. There is no runtime discovery, no ABI versioning, no plugin manifest. The trade-off is documented in [docs/decisions/0001-no-plugin-system.md](docs/decisions/0001-no-plugin-system.md).

## Async architecture

Two runtimes coexist:

- **glib's main context** runs the UI. Single-threaded. Owns all GTK widgets.
- **tokio runtime** (one shared instance, owned by a worker thread) runs all DB driver work.

Bridging is per-call and one-directional:

1. UI handler captures the current state, builds a request struct.
2. UI handler creates an `async_channel`, spawns work on the tokio runtime: `RT.spawn(async move { ... tx.send(result).await })`.
3. UI handler attaches a `glib::spawn_future_local(async move { let result = rx.recv().await; ... })` to handle the reply on the GTK thread.

This pattern is canonical for gtk4-rs apps using tokio drivers. It avoids forcing tokio to drive GTK or forcing GTK widgets across thread boundaries.

The `app::runtime` module owns the single `OnceLock<tokio::runtime::Runtime>` and exposes a small helper. UI code does not touch `tokio` types directly except through this helper.

## UI architecture: Relm4

The `app` crate uses [Relm4](https://relm4.org) for component-based UI structure.

- **Component**: a unit of UI with explicit `Init`, `Input`, `Output`, `CmdOutput` types. State is private. All transitions go through `update`.
- **AsyncComponent**: same shape, but `init` and `update` may be `async`. Used for components that load data on creation.
- **Factory**: drives a list / grid of homogeneous child components from a model. Used for the table sidebar and similar lists.
- **CmdOutput**: how a component receives async results. The tokio bridge sends `CmdOutput` messages back into the component's update loop.

See [docs/state-management.md](docs/state-management.md) for the patterns and naming we use.

## Driver contract

Every driver crate exports a single zero-sized struct that implements `core::DatabaseDriver`. The trait is async (via `async_trait`), small, and stable.

```rust
#[async_trait::async_trait]
pub trait DatabaseDriver: Send + Sync {
    fn id(&self) -> &'static str;
    fn display_name(&self) -> &'static str;
    fn default_port(&self) -> u16;
    async fn connect(&self, opts: ConnectOptions) -> Result<Box<dyn Connection>, DriverError>;
}
```

A `Connection` exposes the operations that `app` needs: list tables, fetch rows, run a query, etc. The full surface is defined in `core::connection`.

The full step-by-step guide for adding a driver lives in [docs/adding-drivers.md](docs/adding-drivers.md).

## Out of scope

- **Plugin system**. Drivers are static. The macOS plugin model does not transfer.
- **In-process scripting**. No embedded JavaScript / Python / Lua. SQL is enough.
- **Cross-platform builds**. Linux only. macOS / iOS have their own targets.
- **Hot reload**. Compile-time only. Use `cargo watch` during development.
