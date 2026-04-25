use std::sync::Arc;

use gtk4::prelude::*;
use libadwaita as adw;

use tablepro_core::DriverRegistry;

mod runtime;

const APP_ID: &str = "com.tablepro.Linux";

fn main() -> glib::ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env().add_directive(tracing::Level::INFO.into()))
        .with_target(false)
        .init();

    let registry = build_registry();
    tracing::info!(drivers = registry.len(), "starting tablepro-app");
    let _ = runtime::handle();

    let app = adw::Application::builder().application_id(APP_ID).build();
    app.connect_activate(build_ui);
    app.run()
}

fn build_registry() -> DriverRegistry {
    let mut r = DriverRegistry::new();
    r.register(Arc::new(drivers_postgres::PgDriver));
    r
}

fn build_ui(app: &adw::Application) {
    let header = adw::HeaderBar::new();
    header.set_title_widget(Some(&adw::WindowTitle::new("TablePro Linux", "Phase 0")));

    let placeholder = adw::StatusPage::builder()
        .icon_name("network-server-symbolic")
        .title("TablePro Linux")
        .description("Phase 0 scaffold. Connection UI lands in Phase 1.")
        .build();

    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(&placeholder));

    adw::ApplicationWindow::builder()
        .application(app)
        .default_width(1100)
        .default_height(720)
        .content(&toolbar)
        .build()
        .present();
}
