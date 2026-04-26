use relm4::adw::prelude::*;
use relm4::{Component, ComponentController, ComponentSender};

use tablepro_core::TableInfo;
use tablepro_storage::SavedConnection;
use uuid::Uuid;

use crate::services::database_service::ConnectionHealth;
use crate::services::{connection_service, database_service};
use crate::ui::connect_dialog::{ConnectDialog, ConnectDialogInit, ConnectDialogOutput};

use super::{App, AppMsg, StatusKind, qualified_label};

impl App {
    pub(super) fn on_open_connect(&mut self, sender: ComponentSender<Self>) {
        let dialog = ConnectDialog::builder()
            .launch(ConnectDialogInit {
                registry: self.registry.clone(),
            })
            .forward(sender.input_sender(), |out| match out {
                ConnectDialogOutput::Connected { tables, driver_id } => AppMsg::Connected { tables, driver_id },
                ConnectDialogOutput::Closed => AppMsg::DialogClosed,
            });
        dialog.widget().present(Some(&self.window));
        self.dialog = Some(dialog);
    }

    pub(super) fn on_connected(&mut self, tables: Vec<TableInfo>, driver_id: String, sender: ComponentSender<Self>) {
        self.dialog = None;
        self.connected = true;
        self.current_driver_id = Some(driver_id.clone());
        self.split_view.set_show_sidebar(true);
        self.disconnect_action.set_enabled(true);
        self.table_search.set_text("");
        // Enter the connected ViewStack: ViewSwitcher tabs in headerbar,
        // Browse content in main area. Editor page is added lazily on
        // first AppMsg::OpenEditor.
        self.title_stack.set_visible_child_name("switcher");
        self.view_stack.set_visible_child_name("browse");
        self.content_holder.set_content(Some(&self.view_stack));
        self.table_names = tables.iter().map(|t| t.name.clone()).collect();
        tracing::info!(driver = %driver_id, table_count = tables.len(), "workspace ready");
        self.repopulate_sidebar(&tables);
        self.push_schema_words();
        self.refresh_window_title();
        self.set_status_page(
            StatusKind::Info,
            &crate::tr!("Select a table"),
            &crate::tr!("Pick a table from the sidebar to load its rows."),
        );
        sender.input(AppMsg::ReloadConnections);
    }

    pub(super) fn on_disconnect(&mut self, sender: ComponentSender<Self>) {
        let svc = database_service::instance();
        if let Some(id) = svc.active_id() {
            svc.remove(id);
        } else {
            svc.clear_all();
        }
        self.cancel_all_editor_runs();
        self.schema_buffer.set_text(crate::ui::editor::SQL_KEYWORDS);
        self.current_table = None;
        self.current_schema = None;
        self.current_offset = 0;
        self.current_columns.clear();
        self.current_result = None;
        self.current_selection = None;
        self.current_driver_id = None;
        self.connected = false;
        self.split_view.set_show_sidebar(false);
        self.disconnect_action.set_enabled(false);
        self.refresh_crud_buttons();
        self.refresh_window_title();
        self.table_search.set_text("");
        self.sidebar_schemas.borrow_mut().clear();
        self.sidebar_factory.guard().clear();
        // Reset the Browse inner stack to its default "Select a table"
        // status so the next connection doesn't briefly flash the prior
        // session's grid before fetching fresh rows.
        self.browse_inner_stack.set_visible_child_name("status");
        self.show_welcome_page(sender);
        tracing::info!("disconnected");
    }

    pub(super) fn on_reload_connections(&self, sender: ComponentSender<Self>) {
        let sender_clone = sender.clone();
        sender.command(move |_, shutdown| {
            shutdown
                .register(async move {
                    if let Ok(connections) = tablepro_storage::load_connections().await {
                        sender_clone.input(AppMsg::ConnectionsLoaded(connections));
                    }
                })
                .drop_on_shutdown()
        });
    }

    pub(super) fn on_connections_loaded(&mut self, connections: &[SavedConnection], sender: ComponentSender<Self>) {
        self.saved_connections = connections.to_vec();
        let mut guard = self.connections_factory.guard();
        guard.clear();
        for saved in connections {
            guard.push_back(saved.clone());
        }
        drop(guard);
        let _ = self
            .welcome_view
            .sender()
            .send(crate::ui::welcome_view::WelcomeViewInput::SetConnections(
                self.saved_connections.clone(),
            ));
        if !self.connected {
            self.show_welcome_page(sender);
        }
    }

    pub(super) fn on_poll_health(&mut self) {
        let current = database_service::instance().active_health();
        if current != self.health_state {
            self.refresh_health_banner(current.clone());
            self.health_state = current;
        }
    }

    pub(super) fn on_delete_connection(&self, id: Uuid, sender: ComponentSender<Self>) {
        let sender_clone = sender.clone();
        sender.command(move |_, shutdown| {
            shutdown
                .register(async move {
                    let _ = tablepro_storage::delete_connection(id).await;
                    let _ = tablepro_storage::delete_password(id).await;
                    let _ = tablepro_storage::delete_ssh_password(id).await;
                    let _ = tablepro_storage::delete_ssh_passphrase(id).await;
                    sender_clone.input(AppMsg::ReloadConnections);
                })
                .drop_on_shutdown()
        });
    }

    pub(super) fn on_open_saved(&self, saved: SavedConnection, sender: ComponentSender<Self>) {
        self.connections_popover.popdown();
        self.set_loading_page(
            &crate::tr!("Connecting…"),
            &crate::tr!("Opening {name}").replace("{name}", &saved.name),
        );
        let driver_id = saved.driver_id.clone();
        let registry = self.registry.clone();
        let sender_clone = sender.clone();
        sender.command(move |_, shutdown| {
            shutdown
                .register(async move {
                    match connection_service::open_saved(registry, saved).await {
                        Ok(tables) => sender_clone.input(AppMsg::Connected { tables, driver_id }),
                        Err(e) => sender_clone.input(AppMsg::LoadFailed(e)),
                    }
                })
                .drop_on_shutdown()
        });
    }

    pub(super) fn repopulate_sidebar(&mut self, tables: &[TableInfo]) {
        {
            let mut schemas = self.sidebar_schemas.borrow_mut();
            schemas.clear();
            schemas.extend(tables.iter().map(|t| t.schema.clone()));
        }
        let mut guard = self.sidebar_factory.guard();
        guard.clear();
        for table in tables {
            guard.push_back(table.clone());
        }
        drop(guard);
        self.sidebar_factory.widget().invalidate_headers();
    }

    /// Surfaces connection health via `adw::Banner` only when degraded —
    /// healthy/disconnected states show no chrome, matching GNOME apps that
    /// reserve banners for "abnormal, user-actionable" situations (Files
    /// uses the same pattern for unmounted volumes).
    pub(super) fn refresh_health_banner(&self, health: Option<ConnectionHealth>) {
        match health {
            Some(ConnectionHealth::Reconnecting { attempt }) => {
                self.reconnect_banner.set_title(
                    &crate::tr!("Connection lost — reconnecting (attempt {n}, will keep retrying)")
                        .replace("{n}", &attempt.to_string()),
                );
                self.reconnect_banner.set_revealed(true);
            }
            _ => self.reconnect_banner.set_revealed(false),
        }
    }

    pub(super) fn refresh_window_title(&self) {
        // Subtitle composes user-facing connection name (e.g. "Production")
        // with driver, then table when one is selected. Window title (the
        // OS-level string used by the shell) keeps the "— TablePro" suffix
        // so it remains identifiable across multiple windows.
        let metadata = database_service::instance().active_metadata();
        let connection_name = metadata.as_ref().map(|m| m.name.as_str());
        let (os_title, subtitle) = match (connection_name, &self.current_driver_id, &self.current_table) {
            (Some(name), Some(driver), Some(table)) => {
                let label = qualified_label(self.current_schema.as_deref(), table);
                (
                    format!("{label} · {name} — TablePro"),
                    format!("{label} · {name} · {driver}"),
                )
            }
            (Some(name), Some(driver), None) => (format!("{name} — TablePro"), format!("{name} · {driver}")),
            (None, Some(driver), _) => (format!("{driver} — TablePro"), driver.clone()),
            _ => ("TablePro".to_string(), String::new()),
        };
        self.window.set_title(Some(&os_title));
        self.window_title.set_subtitle(&subtitle);
    }
}
