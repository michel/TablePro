use std::sync::Arc;

use relm4::adw::prelude::*;
use relm4::prelude::*;
use relm4::{ComponentController, Controller, adw, gtk};

use tablepro_core::{ColumnInfo, DriverRegistry, QueryResult, TableInfo, Value};
use tablepro_storage::SavedConnection;
use uuid::Uuid;

use super::connect_dialog::{ConnectDialog, ConnectDialogInit, ConnectDialogOutput};
use super::edit_dialog::{EditDialog, EditDialogInit, EditDialogOutput};
use super::editor::SqlEditor;
use super::grid::build_column_view;
use super::insert_dialog::{InsertDialog, InsertDialogInit, InsertDialogOutput};
use crate::runtime;
use crate::services::{connection_holder, connection_service};

const PAGE_SIZE: u64 = 1000;

pub struct App {
    registry: Arc<DriverRegistry>,
    window: adw::ApplicationWindow,
    sidebar: gtk::ListBox,
    content_holder: adw::ToolbarView,
    connections_listbox: gtk::ListBox,
    connections_popover: gtk::Popover,
    edit_button: gtk::Button,
    disconnect_button: gtk::Button,
    table_search: gtk::SearchEntry,
    paginator_label: gtk::Label,
    prev_button: gtk::Button,
    next_button: gtk::Button,
    insert_button: gtk::Button,
    edit_row_button: gtk::Button,
    delete_button: gtk::Button,
    grid_holder: gtk::Box,
    browse_view: gtk::Box,
    dialog: Option<Controller<ConnectDialog>>,
    editor: Option<Controller<SqlEditor>>,
    insert_dialog: Option<Controller<InsertDialog>>,
    edit_dialog: Option<Controller<EditDialog>>,
    current_table: Option<String>,
    current_offset: u64,
    current_columns: Vec<ColumnInfo>,
    current_result: Option<QueryResult>,
    current_selection: Option<gtk::SingleSelection>,
    current_driver_id: Option<String>,
    connected: bool,
}

#[derive(Debug)]
pub enum AppMsg {
    OpenConnect,
    Connected { tables: Vec<TableInfo>, driver_id: String },
    DialogClosed,
    SelectTable(String),
    ColumnsLoaded(String, Vec<ColumnInfo>),
    RowsLoaded(String, u64, QueryResult),
    LoadFailed(String),
    PrevPage,
    NextPage,
    InsertRow,
    InsertCommitted,
    EditSelectedRow,
    EditCommitted,
    DeleteSelectedRow,
    RowOperationCommitted,
    ReloadConnections,
    ConnectionsLoaded(Vec<SavedConnection>),
    OpenSaved(SavedConnection),
    DeleteConnection(Uuid),
    OpenEditor,
    Disconnect,
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

                    #[name = "edit_button"]
                    pack_end = &gtk::Button {
                        set_icon_name: "edit-symbolic",
                        set_tooltip_text: Some("SQL editor"),
                        set_sensitive: false,
                        connect_clicked => AppMsg::OpenEditor,
                    },

                    #[name = "disconnect_button"]
                    pack_end = &gtk::Button {
                        set_icon_name: "media-eject-symbolic",
                        set_tooltip_text: Some("Disconnect"),
                        set_visible: false,
                        connect_clicked => AppMsg::Disconnect,
                    },
                },

                #[wrap(Some)]
                set_content = &adw::NavigationSplitView {
                    #[wrap(Some)]
                    set_sidebar = &adw::NavigationPage {
                        set_title: "Tables",

                        #[wrap(Some)]
                        set_child = &gtk::Box {
                            set_orientation: gtk::Orientation::Vertical,

                            #[name = "table_search"]
                            gtk::SearchEntry {
                                set_placeholder_text: Some("Filter tables…"),
                                set_margin_top: 8,
                                set_margin_bottom: 4,
                                set_margin_start: 8,
                                set_margin_end: 8,
                            },

                            gtk::ScrolledWindow {
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

        let search_for_filter = widgets.table_search.clone();
        widgets.sidebar.set_filter_func(move |row| {
            let query = search_for_filter.text().to_lowercase();
            if query.is_empty() {
                return true;
            }
            row.downcast_ref::<adw::ActionRow>()
                .map(|r| r.title().to_lowercase().contains(&query))
                .unwrap_or(true)
        });
        let listbox_for_invalidate = widgets.sidebar.clone();
        widgets.table_search.connect_search_changed(move |_| {
            listbox_for_invalidate.invalidate_filter();
        });

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

        let prev_button = gtk::Button::builder()
            .icon_name("go-previous-symbolic")
            .tooltip_text("Previous page")
            .sensitive(false)
            .build();
        let next_button = gtk::Button::builder()
            .icon_name("go-next-symbolic")
            .tooltip_text("Next page")
            .sensitive(false)
            .build();
        let paginator_label = gtk::Label::builder().build();
        paginator_label.add_css_class("dim-label");

        let sender_for_prev = sender.clone();
        prev_button.connect_clicked(move |_| sender_for_prev.input(AppMsg::PrevPage));
        let sender_for_next = sender.clone();
        next_button.connect_clicked(move |_| sender_for_next.input(AppMsg::NextPage));

        let insert_button = gtk::Button::builder()
            .icon_name("list-add-symbolic")
            .tooltip_text("Insert row")
            .sensitive(false)
            .build();
        let edit_row_button = gtk::Button::builder()
            .icon_name("document-edit-symbolic")
            .tooltip_text("Edit selected row")
            .sensitive(false)
            .build();
        let delete_button = gtk::Button::builder()
            .icon_name("user-trash-symbolic")
            .tooltip_text("Delete selected row")
            .sensitive(false)
            .build();

        let sender_for_insert = sender.clone();
        insert_button.connect_clicked(move |_| sender_for_insert.input(AppMsg::InsertRow));
        let sender_for_edit = sender.clone();
        edit_row_button.connect_clicked(move |_| sender_for_edit.input(AppMsg::EditSelectedRow));
        let sender_for_delete = sender.clone();
        delete_button.connect_clicked(move |_| sender_for_delete.input(AppMsg::DeleteSelectedRow));

        let spacer = gtk::Box::builder().hexpand(true).build();

        let paginator_bar = gtk::Box::builder()
            .orientation(gtk::Orientation::Horizontal)
            .spacing(8)
            .margin_top(8)
            .margin_bottom(8)
            .margin_start(12)
            .margin_end(12)
            .build();
        paginator_bar.append(&prev_button);
        paginator_bar.append(&next_button);
        paginator_bar.append(&paginator_label);
        paginator_bar.append(&spacer);
        paginator_bar.append(&insert_button);
        paginator_bar.append(&edit_row_button);
        paginator_bar.append(&delete_button);

        let grid_holder = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .vexpand(true)
            .build();

        let browse_view = gtk::Box::builder().orientation(gtk::Orientation::Vertical).build();
        browse_view.append(&paginator_bar);
        browse_view.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
        browse_view.append(&grid_holder);

        let model = App {
            registry,
            window: root.clone(),
            sidebar: widgets.sidebar.clone(),
            content_holder: widgets.content_holder.clone(),
            connections_listbox,
            connections_popover: widgets.connections_popover.clone(),
            edit_button: widgets.edit_button.clone(),
            disconnect_button: widgets.disconnect_button.clone(),
            table_search: widgets.table_search.clone(),
            paginator_label,
            prev_button,
            next_button,
            insert_button,
            edit_row_button,
            delete_button,
            grid_holder,
            browse_view,
            dialog: None,
            editor: None,
            insert_dialog: None,
            edit_dialog: None,
            current_table: None,
            current_offset: 0,
            current_columns: Vec::new(),
            current_result: None,
            current_selection: None,
            current_driver_id: None,
            connected: false,
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
                self.connected = true;
                self.current_driver_id = Some(driver_id.clone());
                self.edit_button.set_sensitive(true);
                self.disconnect_button.set_visible(true);
                self.table_search.set_text("");
                tracing::info!(driver = %driver_id, table_count = tables.len(), "workspace ready");
                rebuild_sidebar(&self.sidebar, &tables, sender.clone());
                self.set_status_page(
                    "Select a table",
                    &format!("Connected to {driver_id}. Pick a table from the left to load up to 100,000 rows."),
                );
                sender.input(AppMsg::ReloadConnections);
            }

            AppMsg::Disconnect => {
                connection_holder::clear();
                self.editor = None;
                self.current_table = None;
                self.current_offset = 0;
                self.current_columns.clear();
                self.current_result = None;
                self.current_selection = None;
                self.current_driver_id = None;
                self.connected = false;
                self.edit_button.set_sensitive(false);
                self.disconnect_button.set_visible(false);
                self.refresh_crud_buttons();
                self.table_search.set_text("");
                while let Some(child) = self.sidebar.first_child() {
                    self.sidebar.remove(&child);
                }
                self.set_status_page(
                    "Connect to a database",
                    "Click the server icon for a new connection or the folder icon to open a saved one.",
                );
                tracing::info!("disconnected");
            }

            AppMsg::DialogClosed => {
                self.dialog = None;
            }

            AppMsg::SelectTable(name) => {
                self.editor = None;
                self.current_table = Some(name.clone());
                self.current_offset = 0;
                self.current_columns.clear();
                self.set_status_page("Loading…", &format!("Fetching rows from {name}"));
                self.fetch_current_page(sender.clone());
                self.fetch_columns(name, sender.clone());
            }

            AppMsg::ColumnsLoaded(table, columns) => {
                if self.current_table.as_deref() == Some(&table) {
                    self.current_columns = columns;
                    self.refresh_crud_buttons();
                }
            }

            AppMsg::PrevPage => {
                if self.current_offset >= PAGE_SIZE {
                    self.current_offset -= PAGE_SIZE;
                    self.fetch_current_page(sender.clone());
                }
            }

            AppMsg::NextPage => {
                self.current_offset += PAGE_SIZE;
                self.fetch_current_page(sender.clone());
            }

            AppMsg::RowsLoaded(table, offset, result) => {
                let n_rows = result.rows.len();
                let n_cols = result.columns.len();
                tracing::info!(table = %table, offset, rows = n_rows, cols = n_cols, "rows loaded");

                clear_box(&self.grid_holder);
                let (column_view, selection) = build_column_view(&result);
                self.current_selection = Some(selection);
                self.current_result = Some(result.clone());
                let scrolled = gtk::ScrolledWindow::builder()
                    .child(&column_view)
                    .hexpand(true)
                    .vexpand(true)
                    .build();
                self.grid_holder.append(&scrolled);
                self.refresh_crud_buttons();

                let label = if n_rows == 0 {
                    format!("No rows at offset {offset}")
                } else {
                    let start = offset + 1;
                    let end = offset + n_rows as u64;
                    format!("Rows {start} – {end}")
                };
                self.paginator_label.set_label(&label);
                self.prev_button.set_sensitive(offset > 0);
                self.next_button.set_sensitive(n_rows as u64 == PAGE_SIZE);

                self.content_holder.set_content(Some(&self.browse_view));
            }

            AppMsg::LoadFailed(msg) => {
                tracing::warn!(error = %msg, "load failed");
                self.set_status_page("Failed", &msg);
            }

            AppMsg::InsertRow => {
                let Some(table) = self.current_table.clone() else {
                    return;
                };
                if self.current_columns.is_empty() {
                    return;
                }
                let driver_id = self.current_driver_id.clone().unwrap_or_else(|| "postgres".to_string());
                let dialog = InsertDialog::builder()
                    .launch(InsertDialogInit {
                        table: table.clone(),
                        columns: self.current_columns.clone(),
                        driver_id,
                    })
                    .forward(sender.input_sender(), |out| match out {
                        InsertDialogOutput::Inserted => AppMsg::InsertCommitted,
                    });
                dialog.widget().present(Some(&self.window));
                self.insert_dialog = Some(dialog);
            }

            AppMsg::InsertCommitted => {
                self.insert_dialog = None;
                self.fetch_current_page(sender.clone());
            }

            AppMsg::EditSelectedRow => {
                let Some(table) = self.current_table.clone() else {
                    return;
                };
                let Some(selection) = self.current_selection.clone() else {
                    return;
                };
                let Some(result) = self.current_result.clone() else {
                    return;
                };
                let position = selection.selected();
                if position == gtk::INVALID_LIST_POSITION || (position as usize) >= result.rows.len() {
                    return;
                }
                let row = result.rows[position as usize].clone();
                let driver_id = self.current_driver_id.clone().unwrap_or_else(|| "postgres".to_string());
                let dialog = EditDialog::builder()
                    .launch(EditDialogInit {
                        table,
                        columns: self.current_columns.clone(),
                        driver_id,
                        row,
                    })
                    .forward(sender.input_sender(), |out| match out {
                        EditDialogOutput::Updated => AppMsg::EditCommitted,
                    });
                dialog.widget().present(Some(&self.window));
                self.edit_dialog = Some(dialog);
            }

            AppMsg::EditCommitted => {
                self.edit_dialog = None;
                self.fetch_current_page(sender.clone());
            }

            AppMsg::DeleteSelectedRow => {
                let Some(table) = self.current_table.clone() else {
                    return;
                };
                let Some(selection) = self.current_selection.clone() else {
                    return;
                };
                let Some(result) = self.current_result.clone() else {
                    return;
                };
                let position = selection.selected();
                if position == gtk::INVALID_LIST_POSITION || (position as usize) >= result.rows.len() {
                    return;
                }
                let row = result.rows[position as usize].clone();
                let pk_indexes: Vec<usize> = self
                    .current_columns
                    .iter()
                    .enumerate()
                    .filter(|(_, c)| c.primary_key)
                    .map(|(i, _)| i)
                    .collect();
                if pk_indexes.is_empty() {
                    self.show_error_alert("Cannot delete", "Table has no primary key.");
                    return;
                }

                let driver_id = self.current_driver_id.clone().unwrap_or_else(|| "postgres".to_string());
                let where_clause: String = pk_indexes
                    .iter()
                    .enumerate()
                    .map(|(i, col_idx)| {
                        let name = &self.current_columns[*col_idx].name;
                        let placeholder = placeholder_for(&driver_id, i);
                        format!("{} = {}", quote_ident(&driver_id, name), placeholder)
                    })
                    .collect::<Vec<_>>()
                    .join(" AND ");
                let sql = format!("DELETE FROM {} WHERE {}", quote_ident(&driver_id, &table), where_clause);
                let params: Vec<Value> = pk_indexes.iter().map(|i| row[*i].clone()).collect();
                let preview = preview_pk(&self.current_columns, &pk_indexes, &row);

                self.confirm_and_execute(
                    sender.clone(),
                    &table,
                    sql,
                    params,
                    &format!("Delete row where {preview}?"),
                );
            }

            AppMsg::RowOperationCommitted => {
                self.fetch_current_page(sender.clone());
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

            AppMsg::OpenEditor => {
                if connection_holder::get().is_none() {
                    self.set_status_page("No connection", "Connect to a database first to run SQL.");
                    return;
                }
                let editor = SqlEditor::builder().launch(()).detach();
                self.content_holder.set_content(Some(editor.widget()));
                self.editor = Some(editor);
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

    fn fetch_current_page(&self, sender: ComponentSender<App>) {
        let Some(table) = self.current_table.clone() else {
            return;
        };
        let offset = self.current_offset;
        let conn = match connection_holder::get() {
            Some(c) => c,
            None => {
                sender.input(AppMsg::LoadFailed("no active connection".into()));
                return;
            }
        };
        let table_for_task = table.clone();
        let (tx, rx) = async_channel::bounded(1);
        runtime::handle().spawn(async move {
            let result = conn.fetch_rows(&table_for_task, offset, PAGE_SIZE).await;
            let _ = tx.send(result).await;
        });
        let sender_recv = sender.clone();
        let table_for_send = table;
        glib::spawn_future_local(async move {
            if let Ok(result) = rx.recv().await {
                match result {
                    Ok(query_result) => sender_recv.input(AppMsg::RowsLoaded(table_for_send, offset, query_result)),
                    Err(e) => sender_recv.input(AppMsg::LoadFailed(format!("{e}"))),
                }
            }
        });
    }

    fn fetch_columns(&self, table: String, sender: ComponentSender<App>) {
        let conn = match connection_holder::get() {
            Some(c) => c,
            None => return,
        };
        let table_for_task = table.clone();
        let (tx, rx) = async_channel::bounded(1);
        runtime::handle().spawn(async move {
            let result = conn.fetch_columns(&table_for_task).await;
            let _ = tx.send(result).await;
        });
        let sender_recv = sender.clone();
        glib::spawn_future_local(async move {
            if let Ok(Ok(columns)) = rx.recv().await {
                sender_recv.input(AppMsg::ColumnsLoaded(table, columns));
            }
        });
    }

    fn refresh_crud_buttons(&self) {
        let has_table = self.current_table.is_some() && !self.current_columns.is_empty();
        let has_row = has_table && self.current_result.is_some();
        self.insert_button.set_sensitive(has_table);
        self.edit_row_button.set_sensitive(has_row);
        self.delete_button.set_sensitive(has_row);
    }

    fn show_error_alert(&self, title: &str, message: &str) {
        let dialog = adw::AlertDialog::new(Some(title), Some(message));
        dialog.add_response("ok", "OK");
        dialog.set_default_response(Some("ok"));
        dialog.present(Some(&self.window));
    }

    fn confirm_and_execute(
        &self,
        sender: ComponentSender<App>,
        table: &str,
        sql: String,
        params: Vec<Value>,
        preview: &str,
    ) {
        let dialog = adw::AlertDialog::new(Some("Confirm"), Some(preview));
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("delete", "Delete");
        dialog.set_response_appearance("delete", adw::ResponseAppearance::Destructive);
        dialog.set_default_response(Some("cancel"));
        dialog.set_close_response("cancel");

        let table = table.to_string();
        dialog.connect_response(None, move |dialog, response| {
            dialog.close();
            if response != "delete" {
                return;
            }
            let Some(conn) = connection_holder::get() else {
                return;
            };
            let sql = sql.clone();
            let params = params.clone();
            let table = table.clone();
            let sender_clone = sender.clone();
            let (tx, rx) = async_channel::bounded(1);
            runtime::handle().spawn(async move {
                let result = conn.execute_params(&sql, &params).await;
                let _ = tx.send((table, result)).await;
            });
            glib::spawn_future_local(async move {
                if let Ok((_, result)) = rx.recv().await {
                    match result {
                        Ok(exec) => {
                            tracing::info!(rows = exec.rows_affected, "delete ok");
                            sender_clone.input(AppMsg::RowOperationCommitted);
                        }
                        Err(e) => {
                            tracing::warn!(error = %e, "delete failed");
                            sender_clone.input(AppMsg::LoadFailed(format!("delete: {e}")));
                        }
                    }
                }
            });
        });
        dialog.present(Some(&self.window));
    }
}

fn quote_ident(driver_id: &str, name: &str) -> String {
    if driver_id == "mysql" {
        format!("`{}`", name.replace('`', ""))
    } else {
        format!("\"{}\"", name.replace('"', ""))
    }
}

fn placeholder_for(driver_id: &str, index: usize) -> String {
    if driver_id == "postgres" {
        format!("${}", index + 1)
    } else {
        "?".to_string()
    }
}

fn preview_pk(columns: &[ColumnInfo], pk_indexes: &[usize], row: &[Value]) -> String {
    pk_indexes
        .iter()
        .map(|i| {
            let name = &columns[*i].name;
            let value = match &row[*i] {
                Value::Null => "NULL".to_string(),
                Value::Bool(b) => b.to_string(),
                Value::Int(i) => i.to_string(),
                Value::Float(f) => f.to_string(),
                Value::Text(s) => format!("'{}'", s),
                Value::Bytes(b) => format!("<{} bytes>", b.len()),
            };
            format!("{name} = {value}")
        })
        .collect::<Vec<_>>()
        .join(" AND ")
}

fn clear_box(b: &gtk::Box) {
    while let Some(child) = b.first_child() {
        b.remove(&child);
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
