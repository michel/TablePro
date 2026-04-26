use std::path::PathBuf;
use std::sync::Arc;

use relm4::adw::prelude::*;
use relm4::prelude::*;
use relm4::{adw, gtk};
use uuid::Uuid;

use tablepro_core::{ConnectOptions, DriverRegistry, TableInfo};
use tablepro_ssh::{SshAuth, SshConfig};
use tablepro_storage::{
    SavedConnection, SavedSshAuth, SavedSshConfig, save_connections, store_password, store_ssh_passphrase,
    store_ssh_password,
};

use crate::services::connection_service;
use crate::services::database_service::{self, ReconnectParams};

const SSH_AUTH_PASSWORD: u32 = 0;
const SSH_AUTH_KEY: u32 = 1;

pub struct ConnectDialog {
    registry: Arc<DriverRegistry>,
    drivers: Vec<DriverEntry>,
    driver_combo: adw::ComboRow,
    host: adw::EntryRow,
    port: adw::EntryRow,
    database: adw::EntryRow,
    username: adw::EntryRow,
    password: adw::PasswordEntryRow,
    use_tls: adw::SwitchRow,
    read_only: adw::SwitchRow,
    ssh_enable: adw::SwitchRow,
    ssh_group: adw::PreferencesGroup,
    ssh_host: adw::EntryRow,
    ssh_port: adw::EntryRow,
    ssh_user: adw::EntryRow,
    ssh_auth_combo: adw::ComboRow,
    ssh_password: adw::PasswordEntryRow,
    ssh_key_path: adw::EntryRow,
    ssh_passphrase: adw::PasswordEntryRow,
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
    SshToggled,
    SshAuthChanged,
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
                set_content = &gtk::ScrolledWindow {
                    set_propagate_natural_height: true,

                    #[wrap(Some)]
                    set_child = &gtk::Box {
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
                            add: &model.use_tls,
                            add: &model.read_only,
                            add: &model.ssh_enable,
                        },

                        append: &model.ssh_group,
                        append: &model.submit,
                        append: &model.status,
                    },
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
        let use_tls = adw::SwitchRow::builder()
            .title("Use TLS")
            .subtitle("Require encrypted connection")
            .active(false)
            .build();

        let read_only = adw::SwitchRow::builder()
            .title("Read-only mode")
            .subtitle("Block INSERT, UPDATE, DELETE, and DDL on this connection")
            .active(false)
            .build();

        let ssh_enable = adw::SwitchRow::builder()
            .title("Use SSH tunnel")
            .subtitle("Reach the database through a bastion host")
            .active(false)
            .build();
        let sender_for_ssh = sender.clone();
        ssh_enable.connect_active_notify(move |_| {
            sender_for_ssh.input(ConnectDialogInput::SshToggled);
        });

        let ssh_group = adw::PreferencesGroup::builder()
            .title("SSH tunnel")
            .visible(false)
            .build();
        let ssh_host = adw::EntryRow::builder().title("SSH host").build();
        let ssh_port = adw::EntryRow::builder().title("SSH port").text("22").build();
        let ssh_user = adw::EntryRow::builder().title("SSH user").build();

        let auth_model = gtk::StringList::new(&["Password", "Private key"]);
        let ssh_auth_combo = adw::ComboRow::builder()
            .title("SSH auth")
            .model(&auth_model)
            .selected(SSH_AUTH_PASSWORD)
            .build();
        let sender_for_auth = sender.clone();
        ssh_auth_combo.connect_selected_notify(move |_| {
            sender_for_auth.input(ConnectDialogInput::SshAuthChanged);
        });

        let ssh_password = adw::PasswordEntryRow::builder().title("SSH password").build();
        let ssh_key_path = adw::EntryRow::builder().title("Private key path").build();
        let ssh_passphrase = adw::PasswordEntryRow::builder().title("Key passphrase").build();

        ssh_group.add(&ssh_host);
        ssh_group.add(&ssh_port);
        ssh_group.add(&ssh_user);
        ssh_group.add(&ssh_auth_combo);
        ssh_group.add(&ssh_password);
        ssh_group.add(&ssh_key_path);
        ssh_group.add(&ssh_passphrase);
        apply_ssh_auth_visibility(SSH_AUTH_PASSWORD, &ssh_password, &ssh_key_path, &ssh_passphrase);

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
            use_tls,
            read_only,
            ssh_enable,
            ssh_group,
            ssh_host,
            ssh_port,
            ssh_user,
            ssh_auth_combo,
            ssh_password,
            ssh_key_path,
            ssh_passphrase,
            submit,
            status,
        };
        let widgets = view_output!();

        if let Some(first) = drivers.first() {
            if let Some(driver) = model.registry.get(&first.id) {
                apply_form_visibility(
                    driver.as_ref(),
                    &model.host,
                    &model.port,
                    &model.database,
                    &model.username,
                    &model.password,
                    &model.use_tls,
                    &model.ssh_enable,
                );
            }
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
                if let Some(driver) = self.registry.get(&entry.id) {
                    apply_form_visibility(
                        driver.as_ref(),
                        &self.host,
                        &self.port,
                        &self.database,
                        &self.username,
                        &self.password,
                        &self.use_tls,
                        &self.ssh_enable,
                    );
                }
                root.set_title(&format!("Connect to {}", entry.display_name));
            }

            ConnectDialogInput::SshToggled => {
                self.ssh_group.set_visible(self.ssh_enable.is_active());
            }

            ConnectDialogInput::SshAuthChanged => {
                apply_ssh_auth_visibility(
                    self.ssh_auth_combo.selected(),
                    &self.ssh_password,
                    &self.ssh_key_path,
                    &self.ssh_passphrase,
                );
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
                    use_tls: self.use_tls.is_active(),
                };

                let label = if entry.id == "sqlite" {
                    opts.database.clone()
                } else {
                    format!("{}@{}", opts.username, opts.host)
                };
                let driver_id = entry.id.clone();

                let ssh_inputs = if self.ssh_enable.is_active() {
                    match self.collect_ssh_inputs() {
                        Ok(inputs) => Some(inputs),
                        Err(e) => {
                            self.status.set_label(&e);
                            self.submit.set_sensitive(true);
                            return;
                        }
                    }
                } else {
                    None
                };
                let read_only = self.read_only.is_active();

                sender.command(move |out, shutdown| {
                    shutdown
                        .register(async move {
                            let result =
                                run_connect(driver.clone(), driver_id, label, opts, ssh_inputs, read_only).await;
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

#[derive(Clone)]
struct SshInputs {
    cfg: SshConfig,
    saved: SavedSshConfig,
    secret_to_store: SshSecretToStore,
}

#[derive(Clone)]
enum SshSecretToStore {
    Password(String),
    Passphrase(String),
    None,
}

impl ConnectDialog {
    fn collect_ssh_inputs(&self) -> Result<SshInputs, String> {
        let host = self.ssh_host.text().to_string();
        if host.trim().is_empty() {
            return Err("ssh: host is required".into());
        }
        let port: u16 = self.ssh_port.text().parse().unwrap_or(22);
        let username = self.ssh_user.text().to_string();
        if username.trim().is_empty() {
            return Err("ssh: username is required".into());
        }

        let (auth, saved_auth, secret) = match self.ssh_auth_combo.selected() {
            SSH_AUTH_KEY => {
                let path = self.ssh_key_path.text().to_string();
                if path.trim().is_empty() {
                    return Err("ssh: private key path is required".into());
                }
                let path_buf = PathBuf::from(path);
                let passphrase = self.ssh_passphrase.text().to_string();
                let has_passphrase = !passphrase.is_empty();
                let auth = SshAuth::PrivateKey {
                    path: path_buf.clone(),
                    passphrase: if has_passphrase { Some(passphrase.clone()) } else { None },
                };
                let saved_auth = SavedSshAuth::PrivateKey {
                    path: path_buf,
                    has_passphrase,
                };
                let secret = if has_passphrase {
                    SshSecretToStore::Passphrase(passphrase)
                } else {
                    SshSecretToStore::None
                };
                (auth, saved_auth, secret)
            }
            _ => {
                let password = self.ssh_password.text().to_string();
                let auth = SshAuth::Password {
                    password: password.clone(),
                };
                let saved_auth = SavedSshAuth::Password;
                let secret = SshSecretToStore::Password(password);
                (auth, saved_auth, secret)
            }
        };

        Ok(SshInputs {
            cfg: SshConfig {
                host: host.clone(),
                port,
                username: username.clone(),
                auth,
            },
            saved: SavedSshConfig {
                host,
                port,
                username,
                auth: saved_auth,
            },
            secret_to_store: secret,
        })
    }
}

async fn run_connect(
    driver: Arc<dyn tablepro_core::DatabaseDriver>,
    driver_id: String,
    label: String,
    opts: ConnectOptions,
    ssh: Option<SshInputs>,
    read_only: bool,
) -> Result<(SavedConnection, Vec<TableInfo>), String> {
    let stored_password = opts.password.clone();
    let ssh_for_establish = ssh.as_ref().map(|s| s.cfg.clone());
    let opts_clone = opts.clone();

    let (conn, tunnel) =
        connection_service::establish(driver.as_ref(), opts.clone(), ssh_for_establish, read_only).await?;
    let tables = conn.list_tables().await.map_err(|e| format!("list_tables: {e}"))?;

    let id = match find_existing_id(&driver_id, &opts_clone, ssh.as_ref()).await {
        Some(id) => id,
        None => Uuid::new_v4(),
    };

    let saved = SavedConnection {
        id,
        name: label.clone(),
        driver_id: driver_id.clone(),
        host: opts_clone.host.clone(),
        port: opts_clone.port,
        database: opts_clone.database.clone(),
        username: opts_clone.username.clone(),
        use_tls: opts_clone.use_tls,
        read_only,
        ssh: ssh.as_ref().map(|s| s.saved.clone()),
    };

    save_one(&saved).await.map_err(|e| format!("save: {e}"))?;
    let _ = store_password(saved.id, &stored_password, &label).await;
    if let Some(s) = &ssh {
        match &s.secret_to_store {
            SshSecretToStore::Password(p) => {
                let _ = store_ssh_password(saved.id, p, &label).await;
            }
            SshSecretToStore::Passphrase(p) => {
                let _ = store_ssh_passphrase(saved.id, p, &label).await;
            }
            SshSecretToStore::None => {}
        }
    }

    let params = ReconnectParams {
        driver: driver.clone(),
        opts: opts_clone,
        ssh: ssh.as_ref().map(|s| s.cfg.clone()),
        read_only,
    };
    database_service::instance().add(saved.id, conn, tunnel, read_only, params);
    Ok((saved, tables))
}

#[allow(clippy::too_many_arguments)]
fn apply_form_visibility(
    driver: &dyn tablepro_core::DatabaseDriver,
    host: &adw::EntryRow,
    port: &adw::EntryRow,
    database: &adw::EntryRow,
    username: &adw::EntryRow,
    password: &adw::PasswordEntryRow,
    use_tls: &adw::SwitchRow,
    ssh_enable: &adw::SwitchRow,
) {
    let file_based = driver.is_file_based();
    host.set_visible(!file_based);
    port.set_visible(!file_based);
    username.set_visible(!file_based);
    password.set_visible(!file_based);
    use_tls.set_visible(!file_based);
    ssh_enable.set_visible(!file_based);
    if file_based {
        ssh_enable.set_active(false);
    }
    database.set_title(if file_based { "File path" } else { "Database" });
}

fn apply_ssh_auth_visibility(
    selected: u32,
    password: &adw::PasswordEntryRow,
    key_path: &adw::EntryRow,
    passphrase: &adw::PasswordEntryRow,
) {
    let is_password = selected == SSH_AUTH_PASSWORD;
    password.set_visible(is_password);
    key_path.set_visible(!is_password);
    passphrase.set_visible(!is_password);
}

async fn save_one(connection: &SavedConnection) -> Result<(), tablepro_storage::StorageError> {
    let mut existing = tablepro_storage::load_connections().await.unwrap_or_default();
    existing.retain(|c| c.id != connection.id);
    existing.push(connection.clone());
    save_connections(&existing).await
}

async fn find_existing_id(driver_id: &str, opts: &ConnectOptions, ssh: Option<&SshInputs>) -> Option<Uuid> {
    let existing = tablepro_storage::load_connections().await.ok()?;
    existing
        .into_iter()
        .find(|c| {
            c.driver_id == driver_id
                && c.host == opts.host
                && c.port == opts.port
                && c.database == opts.database
                && c.username == opts.username
                && saved_ssh_matches(&c.ssh, ssh)
        })
        .map(|c| c.id)
}

fn saved_ssh_matches(saved: &Option<SavedSshConfig>, current: Option<&SshInputs>) -> bool {
    match (saved, current) {
        (None, None) => true,
        (Some(s), Some(c)) => &c.saved == s,
        _ => false,
    }
}
