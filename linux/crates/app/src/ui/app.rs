use std::sync::Arc;

use relm4::adw::prelude::*;
use relm4::prelude::*;
use relm4::{ComponentController, Controller, adw, gtk};

use tablepro_core::{DriverRegistry, QueryResult, TableInfo};
use tablepro_storage::SavedConnection;
use uuid::Uuid;

use super::connect_dialog::{ConnectDialog, ConnectDialogInit, ConnectDialogOutput};
use super::grid::build_column_view;
use crate::runtime;
use crate::services::{connection_holder, connection_service};

pub struct App {
    registry: Arc<DriverRegistry>,
    window: adw::ApplicationWindow,
    sidebar: gtk::ListBox,
    content_holder: adw::ToolbarView,
    connections_listbox: gtk::ListBox,
    connections_popover: gtk::Popover,
    dialog: Option<Controller<ConnectDialog>>,
    selected: Option<String>,
}

#[derive(Debug)]
pub enum AppMsg {
    OpenConnect,
    Connected { tables: Vec<TableInfo>, driver_id: String },
    DialogClosed,
    SelectTable(String),
    RowsLoaded(String, QueryResult),
    LoadFailed(String),
    ReloadConnections,
    ConnectionsLoaded(Vec<SavedConnection>),
    OpenSaved(SavedConnection),
    DeleteConnection(Uuid),
}

#[relm4::component(pub)]
impl SimpleComponent for App {
    type Init = Arc<DriverRegistry>;
    type Input = AppMsg;
    type Output = ();

    view! {
        #[name = "window"]
        adw::ApplicationWindow {
            set_title: Some("TablePro Linux"),
            set_default_width: 1200,
            set_default_height: 760,

            adw::ToolbarView {
                add_top_bar = &adw::HeaderBar {
                    set_title_widget: Some(&adw::WindowTitle::new("TablePro Linux", "Phase 0")),

                    pack_start = &gtk::Button {
                        set_icon_name: "network-server-symbolic",
                        set_tooltip_text: Some("New connection"),
                        connect_clicked => AppMsg::OpenConnect,
                    },

                    pack_start = &gtk::MenuButton {
                        set_icon_name: "folder-open-symbolic",
                        set_tooltip_text: Some("Open saved connection"),

                        #[wrap(Some)]
                        #[name = "connections_popover"]
                        set_popover = &gtk::Popover {},
                    },
                },

                #[wrap(Some)]
                set_content = &adw::NavigationSplitView {
                    #[wrap(Some)]
                    set_sidebar = &adw::NavigationPage {
                        set_title: "Tables",

                        #[wrap(Some)]
                        set_child = &gtk::ScrolledWindow {
                            set_hscrollbar_policy: gtk::PolicyType::Never,
                            set_vexpand: true,

                            #[wrap(Some)]
                            #[name = "sidebar"]
                            set_child = &gtk::ListBox {
                                set_selection_mode: gtk::SelectionMode::Single,
                                set_activate_on_single_click: true,
                                add_css_class: "navigation-sidebar",
                            },
                        },
                    },

                    #[wrap(Some)]
                    set_content = &adw::NavigationPage {
                        set_title: "Data",

                        #[wrap(Some)]
                        #[name = "content_holder"]
                        set_child = &adw::ToolbarView {
                            #[wrap(Some)]
                            set_content = &adw::StatusPage {
                                set_icon_name: Some("network-server-symbolic"),
                                set_title: "Connect to a database",
                                set_description: Some("Click the server icon for a new connection or the folder icon to open a saved one."),
                            },
                        },
                    },
                },
            },
        }
    }

    fn init(registry: Self::Init, root: Self::Root, sender: ComponentSender<Self>) -> ComponentParts<Self> {
        let widgets = view_output!();

        let connections_listbox = gtk::ListBox::builder().selection_mode(gtk::SelectionMode::None).build();
        connections_listbox.add_css_class("boxed-list");

        let popover_content = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .spacing(8)
            .margin_top(12)
            .margin_bottom(12)
            .margin_start(12)
            .margin_end(12)
            .build();
        let header = gtk::Label::builder()
            .label("Saved Connections")
            .halign(gtk::Align::Start)
            .build();
        header.add_css_class("heading");
        popover_content.append(&header);

        let scroll = gtk::ScrolledWindow::builder()
            .child(&connections_listbox)
            .min_content_width(320)
            .min_content_height(120)
            .max_content_height(400)
            .propagate_natural_height(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .build();
        popover_content.append(&scroll);
        widgets.connections_popover.set_child(Some(&popover_content));

        let model = App {
            registry,
            window: root.clone(),
            sidebar: widgets.sidebar.clone(),
            content_holder: widgets.content_holder.clone(),
            connections_listbox,
            connections_popover: widgets.connections_popover.clone(),
            dialog: None,
            selected: None,
        };
        sender.input(AppMsg::ReloadConnections);
        ComponentParts { model, widgets }
    }

    fn update(&mut self, msg: Self::Input, sender: ComponentSender<Self>) {
        match msg {
            AppMsg::OpenConnect => {
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

            AppMsg::Connected { tables, driver_id } => {
                self.dialog = None;
                tracing::info!(driver = %driver_id, table_count = tables.len(), "workspace ready");
                rebuild_sidebar(&self.sidebar, &tables, sender.clone());
                self.set_status_page(
                    "Select a table",
                    &format!("Connected to {driver_id}. Pick a table from the left to load up to 100,000 rows."),
                );
                sender.input(AppMsg::ReloadConnections);
            }

            AppMsg::DialogClosed => {
                self.dialog = None;
            }

            AppMsg::SelectTable(name) => {
                self.selected = Some(name.clone());
                self.set_status_page("Loading…", &format!("Fetching rows from {name}"));
                let conn = match connection_holder::get() {
                    Some(c) => c,
                    None => {
                        sender.input(AppMsg::LoadFailed("no active connection".into()));
                        return;
                    }
                };
                let table = name.clone();
                let table_for_send = name.clone();
                let (tx, rx) = async_channel::bounded(1);
                runtime::handle().spawn(async move {
                    let result = conn.fetch_rows(&table, 0, 100_000).await;
                    let _ = tx.send(result).await;
                });
                let sender_recv = sender.clone();
                glib::spawn_future_local(async move {
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(query_result) => sender_recv.input(AppMsg::RowsLoaded(table_for_send, query_result)),
                            Err(e) => sender_recv.input(AppMsg::LoadFailed(format!("{e}"))),
                        }
                    }
                });
            }

            AppMsg::RowsLoaded(table, result) => {
                let n_rows = result.rows.len();
                let n_cols = result.columns.len();
                tracing::info!(table = %table, rows = n_rows, cols = n_cols, "rows loaded");
                let column_view = build_column_view(&result);
                let scrolled = gtk::ScrolledWindow::builder()
                    .child(&column_view)
                    .hexpand(true)
                    .vexpand(true)
                    .build();
                self.content_holder.set_content(Some(&scrolled));
            }

            AppMsg::LoadFailed(msg) => {
                tracing::warn!(error = %msg, "load failed");
                self.set_status_page("Failed", &msg);
            }

            AppMsg::ReloadConnections => {
                let (tx, rx) = async_channel::bounded(1);
                runtime::handle().spawn(async move {
                    let _ = tx.send(tablepro_storage::load_connections().await).await;
                });
                let sender_recv = sender.clone();
                glib::spawn_future_local(async move {
                    if let Ok(Ok(connections)) = rx.recv().await {
                        sender_recv.input(AppMsg::ConnectionsLoaded(connections));
                    }
                });
            }

            AppMsg::ConnectionsLoaded(connections) => {
                rebuild_connections_listbox(
                    &self.connections_listbox,
                    &connections,
                    sender.clone(),
                    self.connections_popover.clone(),
                );
            }

            AppMsg::DeleteConnection(id) => {
                let (tx, rx) = async_channel::bounded(1);
                runtime::handle().spawn(async move {
                    let _ = tablepro_storage::delete_connection(id).await;
                    let _ = tablepro_storage::delete_password(id).await;
                    let _ = tx.send(()).await;
                });
                let sender_recv = sender.clone();
                glib::spawn_future_local(async move {
                    if rx.recv().await.is_ok() {
                        sender_recv.input(AppMsg::ReloadConnections);
                    }
                });
            }

            AppMsg::OpenSaved(saved) => {
                self.connections_popover.popdown();
                self.set_status_page("Connecting…", &format!("Opening {}", saved.name));
                let driver_id = saved.driver_id.clone();
                let registry = self.registry.clone();
                let saved_for_task = saved.clone();
                let (tx, rx) = async_channel::bounded(1);
                runtime::handle().spawn(async move {
                    let result = connection_service::open_saved(registry, saved_for_task).await;
                    let _ = tx.send(result).await;
                });
                let sender_recv = sender.clone();
                glib::spawn_future_local(async move {
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(tables) => sender_recv.input(AppMsg::Connected { tables, driver_id }),
                            Err(e) => sender_recv.input(AppMsg::LoadFailed(e)),
                        }
                    }
                });
            }
        }
    }
}

impl App {
    fn set_status_page(&self, title: &str, description: &str) {
        let page = adw::StatusPage::builder()
            .title(title)
            .description(description)
            .icon_name("view-grid-symbolic")
            .build();
        self.content_holder.set_content(Some(&page));
    }
}

fn rebuild_sidebar(listbox: &gtk::ListBox, tables: &[TableInfo], sender: ComponentSender<App>) {
    while let Some(child) = listbox.first_child() {
        listbox.remove(&child);
    }
    for table in tables {
        let row = adw::ActionRow::builder().title(&table.name).activatable(true).build();
        let name = table.name.clone();
        let sender_for_row = sender.clone();
        row.connect_activated(move |_| {
            sender_for_row.input(AppMsg::SelectTable(name.clone()));
        });
        listbox.append(&row);
    }
}

fn rebuild_connections_listbox(
    listbox: &gtk::ListBox,
    saved: &[SavedConnection],
    sender: ComponentSender<App>,
    popover: gtk::Popover,
) {
    while let Some(child) = listbox.first_child() {
        listbox.remove(&child);
    }
    if saved.is_empty() {
        let empty = adw::ActionRow::builder()
            .title("No saved connections")
            .subtitle("Open a connection to save it here.")
            .activatable(false)
            .build();
        listbox.append(&empty);
        return;
    }
    for s in saved {
        let subtitle = if s.driver_id == "sqlite" {
            format!("sqlite · {}", s.database)
        } else {
            format!("{} · {}@{}:{}", s.driver_id, s.username, s.host, s.port)
        };
        let row = adw::ActionRow::builder()
            .title(&s.name)
            .subtitle(&subtitle)
            .activatable(true)
            .build();

        let delete = gtk::Button::builder()
            .icon_name("user-trash-symbolic")
            .valign(gtk::Align::Center)
            .tooltip_text("Remove connection")
            .build();
        delete.add_css_class("flat");
        let saved_id = s.id;
        let sender_for_delete = sender.clone();
        delete.connect_clicked(move |_| {
            sender_for_delete.input(AppMsg::DeleteConnection(saved_id));
        });
        row.add_suffix(&delete);

        let saved_clone = s.clone();
        let sender_for_row = sender.clone();
        let popover_for_row = popover.clone();
        row.connect_activated(move |_| {
            sender_for_row.input(AppMsg::OpenSaved(saved_clone.clone()));
            popover_for_row.popdown();
        });
        listbox.append(&row);
    }
}
