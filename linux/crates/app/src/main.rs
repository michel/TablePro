use std::sync::Arc;

use relm4::RelmApp;

use tablepro_core::DriverRegistry;

mod i18n;
mod services;
mod ui;

const APP_ID: &str = "com.tablepro.linux";

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env().add_directive(tracing::Level::INFO.into()))
        .with_target(false)
        .init();

    i18n::init();

    let prefs = services::preferences::load();
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .enable_all()
        .build()
        .expect("history runtime");
    runtime.block_on(async {
        if let Err(e) = tablepro_storage::query_history::init().await {
            tracing::warn!(error = %e, "history init failed; feature disabled");
        } else if let Err(e) = tablepro_storage::query_history::prune_older_than(prefs.history_retention_days).await {
            tracing::warn!(error = %e, "history prune failed");
        }
    });
    // Keep the runtime alive for the process lifetime so the sqlx pool's
    // background reaper task keeps running. Dropping here would cancel it.
    std::mem::forget(runtime);

    let registry = Arc::new(build_registry());
    tracing::info!(drivers = registry.len(), "starting tablepro-app");

    let app = RelmApp::new(APP_ID);
    app.run::<ui::App>(registry);
}

fn build_registry() -> DriverRegistry {
    let mut r = DriverRegistry::new();
    r.register(Arc::new(drivers_mysql::MysqlDriver));
    r.register(Arc::new(drivers_postgres::PgDriver));
    r.register(Arc::new(drivers_sqlite::SqliteDriver));
    r
}
