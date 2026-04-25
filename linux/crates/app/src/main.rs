use std::sync::Arc;

use relm4::RelmApp;

use tablepro_core::DriverRegistry;

mod runtime;
mod ui;

const APP_ID: &str = "com.tablepro.Linux";

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env().add_directive(tracing::Level::INFO.into()))
        .with_target(false)
        .init();

    let registry = Arc::new(build_registry());
    tracing::info!(drivers = registry.len(), "starting tablepro-app");
    let _ = runtime::handle();

    let app = RelmApp::new(APP_ID);
    app.run::<ui::App>(registry);
}

fn build_registry() -> DriverRegistry {
    let mut r = DriverRegistry::new();
    r.register(Arc::new(drivers_postgres::PgDriver));
    r
}
