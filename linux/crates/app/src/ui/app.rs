use std::sync::Arc;

use relm4::adw::prelude::*;
use relm4::prelude::*;
use relm4::{ComponentController, Controller, adw, gtk};

use tablepro_core::{DriverRegistry, QueryResult, TableInfo};

use super::connect_dialog::{ConnectDialog, ConnectDialogInit, ConnectDialogOutput};
use super::grid::build_column_view;
use crate::runtime;
use crate::services::connection_holder;

pub struct App {
    registry: Arc<DriverRegistry>,
    window: adw::ApplicationWindow,
    sidebar: gtk::ListBox,
    content_holder: adw::ToolbarView,
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
                        set_tooltip_text: Some("Connect"),
                        connect_clicked => AppMsg::OpenConnect,
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
                                set_description: Some("Click the server icon in the header to start."),
                            },
                        },
                    },
                },
            },
        }
    }

    fn init(registry: Self::Init, root: Self::Root, sender: ComponentSender<Self>) -> ComponentParts<Self> {
        let widgets = view_output!();
        let model = App {
            registry,
            window: root.clone(),
            sidebar: widgets.sidebar.clone(),
            content_holder: widgets.content_holder.clone(),
            dialog: None,
            selected: None,
        };
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
                self.set_status_page("Query failed", &msg);
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
