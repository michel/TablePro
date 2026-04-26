use std::sync::Arc;

use relm4::adw::prelude::*;
use relm4::prelude::*;
use relm4::{adw, gtk};
use uuid::Uuid;

use tablepro_core::{ConnectOptions, DriverRegistry, TableInfo};
use tablepro_storage::{SavedConnection, save_connections, store_password};

use crate::services::connection_holder;

pub struct ConnectDialog {
    registry: Arc<DriverRegistry>,
    drivers: Vec<DriverEntry>,
    driver_combo: adw::ComboRow,
    host: adw::EntryRow,
    port: adw::EntryRow,
    database: adw::EntryRow,
    username: adw::EntryRow,
    password: adw::PasswordEntryRow,
    submit: gtk::Button,
    status: gtk::Label,
}

#[derive(Debug, Clone)]
struct DriverEntry {
    id: String,
    display_name: String,
}

pub struct ConnectDialogInit {
    pub registry: Arc<DriverRegistry>,
}

#[derive(Debug)]
pub enum ConnectDialogInput {
    DriverChanged(u32),
    Submit,
    Closed,
}

#[derive(Debug)]
pub enum ConnectDialogOutput {
    Connected { tables: Vec<TableInfo>, driver_id: String },
    Closed,
}

#[derive(Debug)]
pub enum ConnectDialogCmd {
    Result(Result<(SavedConnection, Vec<TableInfo>), String>),
}

#[relm4::component(pub)]
impl Component for ConnectDialog {
    type Init = ConnectDialogInit;
    type Input = ConnectDialogInput;
    type Output = ConnectDialogOutput;
    type CommandOutput = ConnectDialogCmd;

    view! {
        adw::Dialog {
            set_title: "Connect",
            set_content_width: 480,

            connect_closed => ConnectDialogInput::Closed,

            #[wrap(Some)]
            set_child = &adw::ToolbarView {
                add_top_bar = &adw::HeaderBar {},

                #[wrap(Some)]
                set_content = &gtk::Box {
                    set_orientation: gtk::Orientation::Vertical,
                    set_spacing: 12,
                    set_margin_top: 24,
                    set_margin_bottom: 24,
                    set_margin_start: 24,
                    set_margin_end: 24,

                    adw::PreferencesGroup {
                        add: &model.driver_combo,
                        add: &model.host,
                        add: &model.port,
                        add: &model.database,
                        add: &model.username,
                        add: &model.password,
                    },

                    append: &model.submit,
                    append: &model.status,
                },
            },
        }
    }

    fn init(init: Self::Init, root: Self::Root, sender: ComponentSender<Self>) -> ComponentParts<Self> {
        let mut drivers: Vec<DriverEntry> = init
            .registry
            .iter()
            .map(|d| DriverEntry {
                id: d.id().to_string(),
                display_name: d.display_name().to_string(),
            })
            .collect();
        drivers.sort_by(|a, b| a.display_name.cmp(&b.display_name));

        let names: Vec<String> = drivers.iter().map(|d| d.display_name.clone()).collect();
        let names_ref: Vec<&str> = names.iter().map(String::as_str).collect();
        let driver_model = gtk::StringList::new(&names_ref);

        let driver_combo = adw::ComboRow::builder().title("Driver").model(&driver_model).build();
        let sender_for_combo = sender.clone();
        driver_combo.connect_selected_notify(move |row| {
            sender_for_combo.input(ConnectDialogInput::DriverChanged(row.selected()));
        });

        let host = adw::EntryRow::builder().title("Host").text("localhost").build();
        let port = adw::EntryRow::builder().title("Port").text("5432").build();
        let database = adw::EntryRow::builder().title("Database").text("postgres").build();
        let username = adw::EntryRow::builder().title("Username").text("postgres").build();
        let password = adw::PasswordEntryRow::builder().title("Password").build();
        password.set_text("test");

        let submit = gtk::Button::builder()
            .label("Connect")
            .halign(gtk::Align::End)
            .margin_top(12)
            .build();
        submit.add_css_class("suggested-action");
        submit.add_css_class("pill");
        let sender_for_submit = sender.clone();
        submit.connect_clicked(move |_| {
            sender_for_submit.input(ConnectDialogInput::Submit);
        });

        let status = gtk::Label::builder().wrap(true).xalign(0.0).margin_top(8).build();
        status.add_css_class("dim-label");

        let model = ConnectDialog {
            registry: init.registry,
            drivers: drivers.clone(),
            driver_combo,
            host,
            port,
            database,
            username,
            password,
            submit,
            status,
        };
        let widgets = view_output!();

        if let Some(first) = drivers.first() {
            apply_form_visibility(
                &first.id,
                &model.host,
                &model.port,
                &model.database,
                &model.username,
                &model.password,
            );
            root.set_title(&format!("Connect to {}", first.display_name));
        }

        ComponentParts { model, widgets }
    }

    fn update(&mut self, msg: Self::Input, sender: ComponentSender<Self>, root: &Self::Root) {
        match msg {
            ConnectDialogInput::DriverChanged(idx) => {
                let Some(entry) = self.drivers.get(idx as usize) else {
                    return;
                };
                apply_form_visibility(
                    &entry.id,
                    &self.host,
                    &self.port,
                    &self.database,
                    &self.username,
                    &self.password,
                );
                root.set_title(&format!("Connect to {}", entry.display_name));
            }

            ConnectDialogInput::Submit => {
                self.submit.set_sensitive(false);
                self.status.set_label("Connecting…");

                let idx = self.driver_combo.selected() as usize;
                let Some(entry) = self.drivers.get(idx).cloned() else {
                    self.status.set_label("no driver selected");
                    self.submit.set_sensitive(true);
                    return;
                };

                let driver = match self.registry.get(&entry.id) {
                    Some(d) => d,
                    None => {
                        self.status.set_label(&format!("driver {} not registered", entry.id));
                        self.submit.set_sensitive(true);
                        return;
                    }
                };

                let opts = ConnectOptions {
                    host: self.host.text().to_string(),
                    port: self.port.text().parse().unwrap_or_else(|_| driver.default_port()),
                    database: self.database.text().to_string(),
                    username: self.username.text().to_string(),
                    password: self.password.text().to_string(),
                    use_tls: false,
                };
                let label = if entry.id == "sqlite" {
                    opts.database.clone()
                } else {
                    format!("{}@{}", opts.username, opts.host)
                };
                let driver_id = entry.id.clone();

                sender.command(move |out, shutdown| {
                    shutdown
                        .register(async move {
                            let result = match driver.connect(opts.clone()).await {
                                Ok(conn) => match conn.list_tables().await {
                                    Ok(tables) => {
                                        let saved = SavedConnection {
                                            id: Uuid::new_v4(),
                                            name: label.clone(),
                                            driver_id: driver_id.clone(),
                                            host: opts.host.clone(),
                                            port: opts.port,
                                            database: opts.database.clone(),
                                            username: opts.username.clone(),
                                            use_tls: opts.use_tls,
                                        };
                                        match save_one(&saved).await {
                                            Ok(()) => {
                                                let _ = store_password(saved.id, &opts.password, &label).await;
                                                connection_holder::set(conn);
                                                Ok((saved, tables))
                                            }
                                            Err(e) => Err(format!("save: {e}")),
                                        }
                                    }
                                    Err(e) => Err(format!("list_tables: {e}")),
                                },
                                Err(e) => Err(format!("connect: {e}")),
                            };
                            out.send(ConnectDialogCmd::Result(result)).ok();
                        })
                        .drop_on_shutdown()
                });
            }

            ConnectDialogInput::Closed => {
                let _ = sender.output(ConnectDialogOutput::Closed);
            }
        }
    }

    fn update_cmd(&mut self, msg: Self::CommandOutput, sender: ComponentSender<Self>, root: &Self::Root) {
        let ConnectDialogCmd::Result(result) = msg;
        self.submit.set_sensitive(true);
        match result {
            Ok((saved, tables)) => {
                tracing::info!(driver = %saved.driver_id, table_count = tables.len(), "connected");
                let _ = sender.output(ConnectDialogOutput::Connected {
                    tables,
                    driver_id: saved.driver_id,
                });
                root.close();
            }
            Err(e) => {
                tracing::warn!(error = %e, "connect failed");
                self.status.set_label(&e);
            }
        }
    }
}

fn apply_form_visibility(
    driver_id: &str,
    host: &adw::EntryRow,
    port: &adw::EntryRow,
    database: &adw::EntryRow,
    username: &adw::EntryRow,
    password: &adw::PasswordEntryRow,
) {
    let is_file_based = driver_id == "sqlite";
    host.set_visible(!is_file_based);
    port.set_visible(!is_file_based);
    username.set_visible(!is_file_based);
    password.set_visible(!is_file_based);
    database.set_title(if is_file_based { "File path" } else { "Database" });
}

async fn save_one(connection: &SavedConnection) -> Result<(), tablepro_storage::StorageError> {
    let mut existing = tablepro_storage::load_connections().await.unwrap_or_default();
    existing.retain(|c| c.id != connection.id);
    existing.push(connection.clone());
    save_connections(&existing).await
}
