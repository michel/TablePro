use std::sync::Arc;

use relm4::adw::prelude::*;
use relm4::factory::FactoryVecDeque;
use relm4::gtk::{gio, glib};
use relm4::prelude::*;
use relm4::{ComponentController, Controller, adw, gtk};

use tablepro_core::{ColumnInfo, DriverRegistry, QueryResult, TableInfo, Value};
use tablepro_storage::SavedConnection;
use uuid::Uuid;

use super::connect_dialog::{ConnectDialog, ConnectDialogInit, ConnectDialogOutput};
use super::connection_row::{ConnectionRow, ConnectionRowOutput};
use super::edit_dialog::{EditDialog, EditDialogInit, EditDialogOutput};
use super::editor::SqlEditor;
use super::grid::build_column_view;
use super::insert_dialog::{InsertDialog, InsertDialogInit, InsertDialogOutput};
use super::sidebar_row::{SidebarRow, SidebarRowOutput};
use crate::services::database_service::ConnectionHealth;
use crate::services::{connection_service, database_service};
use crate::sql_dialect::{placeholder_for, quote_ident};

const PAGE_SIZE_OPTIONS: &[u64] = &[100, 500, 1_000, 5_000, 10_000];
const DEFAULT_PAGE_SIZE: u64 = 1_000;

pub struct App {
    registry: Arc<DriverRegistry>,
    window: adw::ApplicationWindow,
    sidebar_factory: FactoryVecDeque<SidebarRow>,
    sidebar_schemas: std::rc::Rc<std::cell::RefCell<Vec<Option<String>>>>,
    content_holder: adw::ToolbarView,
    toast_overlay: adw::ToastOverlay,
    reconnect_banner: adw::Banner,
    connections_factory: FactoryVecDeque<ConnectionRow>,
    connections_popover: gtk::Popover,
    edit_button: gtk::Button,
    health_pill: gtk::Label,
    health_state: Option<ConnectionHealth>,
    row_op_spinner: gtk::Spinner,
    read_only_badge: gtk::Label,
    table_search: gtk::SearchEntry,
    paginator_label: gtk::Label,
    prev_button: gtk::Button,
    next_button: gtk::Button,
    insert_button: gtk::Button,
    edit_row_button: gtk::Button,
    delete_button: gtk::Button,
    grid_holder: gtk::Box,
    grid_search: gtk::SearchEntry,
    grid_search_bar: gtk::SearchBar,
    browse_view: gtk::Box,
    dialog: Option<Controller<ConnectDialog>>,
    editor: Option<Controller<SqlEditor>>,
    insert_dialog: Option<Controller<InsertDialog>>,
    edit_dialog: Option<Controller<EditDialog>>,
    current_table: Option<String>,
    current_schema: Option<String>,
    current_offset: u64,
    current_columns: Vec<ColumnInfo>,
    current_result: Option<QueryResult>,
    current_selection: Option<gtk::MultiSelection>,
    current_driver_id: Option<String>,
    current_sort: Option<(usize, bool)>,
    current_total_rows: Option<u64>,
    page_size: u64,
    table_names: Vec<String>,
    saved_connections: Vec<SavedConnection>,
    connected: bool,
}

#[derive(Debug)]
pub enum AppMsg {
    OpenConnect,
    Connected {
        tables: Vec<TableInfo>,
        driver_id: String,
    },
    DialogClosed,
    SelectTable {
        schema: Option<String>,
        name: String,
    },
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
    RowOperationCommitted(Option<UndoBatch>),
    RowOpStarted,
    ExecuteUndo(UndoBatch),
    CellEdited {
        table: String,
        row_position: u32,
        col_index: usize,
        new_value: String,
    },
    ReloadConnections,
    ConnectionsLoaded(Vec<SavedConnection>),
    OpenSaved(SavedConnection),
    DeleteConnection(Uuid),
    OpenEditor,
    Disconnect,
    PollHealth,
    RefreshPage,
    ShowShortcuts,
    ShowAbout,
    ShowPreferences,
    SortChanged(usize),
    PageSizeChanged(u64),
    RowCountLoaded(String, u64),
    FindInResults,
    ExportCsv,
    ExportJson,
    CopyToClipboard(String),
    SetCellNull {
        table: String,
        row_position: u32,
        col_index: usize,
    },
    DeleteRowAt {
        table: String,
        row_position: u32,
    },
    CopyRowAsInsert {
        row_position: u32,
    },
}

#[derive(Debug, Clone, Copy)]
enum ExportFormat {
    Csv,
    Json,
}

#[derive(Debug, Clone)]
pub struct UndoBatch {
    pub label: String,
    pub statements: Vec<(String, Vec<Value>)>,
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
                    set_title_widget: Some(&adw::WindowTitle::new("TablePro Linux", env!("CARGO_PKG_VERSION"))),

                    #[name = "new_connection_button"]
                    pack_start = &gtk::Button {
                        set_icon_name: "network-server-symbolic",
                        set_tooltip_text: Some("New connection"),
                        connect_clicked => AppMsg::OpenConnect,
                    },

                    #[name = "saved_connections_button"]
                    pack_start = &gtk::MenuButton {
                        set_icon_name: "folder-open-symbolic",
                        set_tooltip_text: Some("Open saved connection"),

                        #[wrap(Some)]
                        #[name = "connections_popover"]
                        set_popover = &gtk::Popover {},
                    },

                    #[name = "read_only_badge"]
                    pack_end = &gtk::Label {
                        set_visible: false,
                        set_label: "Read-only",
                        set_margin_end: 6,
                        add_css_class: "warning",
                    },

                    #[name = "health_pill"]
                    pack_end = &gtk::Label {
                        set_visible: false,
                        set_margin_end: 6,
                        add_css_class: "caption-heading",
                    },

                    #[name = "row_op_spinner"]
                    pack_end = &gtk::Spinner {
                        set_visible: false,
                        set_margin_end: 6,
                        set_tooltip_text: Some("Saving…"),
                    },

                    #[name = "edit_button"]
                    pack_end = &gtk::Button {
                        set_icon_name: "edit-symbolic",
                        set_tooltip_text: Some("SQL editor"),
                        set_sensitive: false,
                        connect_clicked => AppMsg::OpenEditor,
                    },

                    #[name = "primary_menu_button"]
                    pack_end = &gtk::MenuButton {
                        set_icon_name: "open-menu-symbolic",
                        set_tooltip_text: Some("Main menu"),
                    },
                },

                #[wrap(Some)]
                #[name = "split_view"]
                set_content = &adw::NavigationSplitView {
                    set_min_sidebar_width: 220.0,
                    set_max_sidebar_width: 360.0,

                    #[wrap(Some)]
                    set_sidebar = &adw::NavigationPage {
                        set_title: "Tables",

                        #[wrap(Some)]
                        set_child = &gtk::Box {
                            set_orientation: gtk::Orientation::Vertical,

                            #[name = "table_search"]
                            gtk::SearchEntry {
                                set_placeholder_text: Some("Filter tables…"),
                                set_margin_top: 12,
                                set_margin_bottom: 6,
                                set_margin_start: 12,
                                set_margin_end: 12,
                            },

                            #[name = "sidebar_scroll"]
                            gtk::ScrolledWindow {
                                set_hscrollbar_policy: gtk::PolicyType::Never,
                                set_vexpand: true,
                            },
                        },
                    },

                    #[wrap(Some)]
                    set_content = &adw::NavigationPage {
                        set_title: "Data",

                        #[wrap(Some)]
                        #[name = "toast_overlay"]
                        set_child = &adw::ToastOverlay {
                            #[wrap(Some)]
                            #[name = "content_holder"]
                            set_child = &adw::ToolbarView {
                                #[name = "reconnect_banner"]
                                add_top_bar = &adw::Banner {
                                    set_revealed: false,
                                    set_use_markup: false,
                                    set_button_label: Some("Retry"),
                                },

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
            },
        }
    }

    fn init(registry: Self::Init, root: Self::Root, sender: ComponentSender<Self>) -> ComponentParts<Self> {
        let widgets = view_output!();

        let restored = crate::services::window_state::load();
        widgets.window.set_default_size(restored.width, restored.height);
        if restored.maximized {
            widgets.window.maximize();
        }
        widgets.window.connect_close_request(|w| {
            crate::services::window_state::save(crate::services::window_state::WindowState {
                width: w.default_width(),
                height: w.default_height(),
                maximized: w.is_maximized(),
            });
            glib::Propagation::Proceed
        });

        let breakpoint = adw::Breakpoint::new(adw::BreakpointCondition::new_length(
            adw::BreakpointConditionLengthType::MaxWidth,
            600.0,
            adw::LengthUnit::Sp,
        ));
        breakpoint.add_setter(&widgets.split_view, "collapsed", Some(&true.into()));
        widgets.window.add_breakpoint(breakpoint);

        let sidebar_schemas: std::rc::Rc<std::cell::RefCell<Vec<Option<String>>>> =
            std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));

        let sidebar_factory: FactoryVecDeque<SidebarRow> = FactoryVecDeque::builder()
            .launch(
                gtk::ListBox::builder()
                    .selection_mode(gtk::SelectionMode::Single)
                    .activate_on_single_click(true)
                    .css_classes(["navigation-sidebar"])
                    .build(),
            )
            .forward(sender.input_sender(), |out| match out {
                SidebarRowOutput::Selected { schema, name } => AppMsg::SelectTable { schema, name },
            });

        let sidebar_listbox = sidebar_factory.widget();
        widgets.sidebar_scroll.set_child(Some(sidebar_listbox));

        let search_for_filter = widgets.table_search.clone();
        sidebar_listbox.set_filter_func(move |row| {
            let query = search_for_filter.text().to_lowercase();
            if query.is_empty() {
                return true;
            }
            row.downcast_ref::<adw::ActionRow>()
                .map(|r| r.title().to_lowercase().contains(&query))
                .unwrap_or(true)
        });
        let listbox_for_invalidate = sidebar_listbox.clone();
        widgets.table_search.connect_search_changed(move |_| {
            listbox_for_invalidate.invalidate_filter();
        });

        let schemas_for_header = sidebar_schemas.clone();
        sidebar_listbox.set_header_func(move |row, before| {
            let schemas = schemas_for_header.borrow();
            let total_distinct: std::collections::BTreeSet<&str> =
                schemas.iter().filter_map(|s| s.as_deref()).collect();
            if total_distinct.len() < 2 {
                row.set_header(gtk::Widget::NONE);
                return;
            }
            let idx = row.index();
            let current = schemas.get(idx as usize).and_then(|s| s.as_deref());
            let prev_idx = before.map(|b| b.index());
            let prev = prev_idx
                .and_then(|i| schemas.get(i as usize))
                .and_then(|s| s.as_deref());
            let needs = match (current, prev) {
                (Some(c), Some(p)) => c != p,
                (Some(_), None) => true,
                _ => false,
            };
            if needs {
                let header = gtk::Label::builder()
                    .label(current.unwrap_or(""))
                    .xalign(0.0)
                    .margin_top(8)
                    .margin_bottom(4)
                    .margin_start(12)
                    .margin_end(12)
                    .build();
                header.add_css_class("heading");
                header.add_css_class("dim-label");
                row.set_header(Some(&header));
            } else {
                row.set_header(gtk::Widget::NONE);
            }
        });

        let connections_factory: FactoryVecDeque<ConnectionRow> = FactoryVecDeque::builder()
            .launch(
                gtk::ListBox::builder()
                    .selection_mode(gtk::SelectionMode::None)
                    .css_classes(["boxed-list"])
                    .build(),
            )
            .forward(sender.input_sender(), |out| match out {
                ConnectionRowOutput::Open(saved) => AppMsg::OpenSaved(saved),
                ConnectionRowOutput::Delete(id) => AppMsg::DeleteConnection(id),
            });

        let popover_content = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .spacing(8)
            .margin_top(12)
            .margin_bottom(12)
            .margin_start(12)
            .margin_end(12)
            .build();
        let header = gtk::Label::builder()
            .label(crate::tr!("Saved Connections"))
            .halign(gtk::Align::Start)
            .build();
        header.add_css_class("heading");
        popover_content.append(&header);

        let scroll = gtk::ScrolledWindow::builder()
            .child(connections_factory.widget())
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
        paginator_label.set_accessible_role(gtk::AccessibleRole::Status);

        let page_size_labels: Vec<String> = PAGE_SIZE_OPTIONS
            .iter()
            .map(|n| {
                if *n >= 1_000 {
                    format!("{} K", n / 1_000)
                } else {
                    n.to_string()
                }
            })
            .collect();
        let page_size_strs: Vec<&str> = page_size_labels.iter().map(String::as_str).collect();
        let page_size_combo = gtk::DropDown::from_strings(&page_size_strs);
        let default_idx = PAGE_SIZE_OPTIONS
            .iter()
            .position(|n| *n == DEFAULT_PAGE_SIZE)
            .unwrap_or(2) as u32;
        page_size_combo.set_selected(default_idx);
        page_size_combo.set_tooltip_text(Some("Rows per page"));
        let sender_for_size = sender.clone();
        page_size_combo.connect_selected_notify(move |dd| {
            let idx = dd.selected() as usize;
            if let Some(&size) = PAGE_SIZE_OPTIONS.get(idx) {
                sender_for_size.input(AppMsg::PageSizeChanged(size));
            }
        });

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
        let export_menu = gio::Menu::new();
        export_menu.append(Some("Export as CSV…"), Some("win.export-csv"));
        export_menu.append(Some("Export as JSON…"), Some("win.export-json"));
        let export_button = gtk::MenuButton::builder()
            .icon_name("document-save-symbolic")
            .tooltip_text("Export results")
            .menu_model(&export_menu)
            .build();
        export_button.add_css_class("flat");

        paginator_bar.append(&prev_button);
        paginator_bar.append(&next_button);
        paginator_bar.append(&paginator_label);
        paginator_bar.append(&spacer);
        paginator_bar.append(&page_size_combo);
        paginator_bar.append(&export_button);
        paginator_bar.append(&insert_button);
        paginator_bar.append(&edit_row_button);
        paginator_bar.append(&delete_button);

        let grid_holder = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .vexpand(true)
            .build();

        let grid_search = gtk::SearchEntry::builder().placeholder_text("Find in results").build();
        let grid_search_bar = gtk::SearchBar::builder()
            .child(&grid_search)
            .show_close_button(true)
            .search_mode_enabled(false)
            .build();
        grid_search_bar.connect_entry(&grid_search);

        let browse_view = gtk::Box::builder().orientation(gtk::Orientation::Vertical).build();
        browse_view.append(&paginator_bar);
        browse_view.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
        browse_view.append(&grid_search_bar);
        browse_view.append(&grid_holder);
        grid_search_bar.set_key_capture_widget(Some(&browse_view));

        let model = App {
            registry,
            window: root.clone(),
            sidebar_factory,
            sidebar_schemas,
            content_holder: widgets.content_holder.clone(),
            toast_overlay: widgets.toast_overlay.clone(),
            reconnect_banner: widgets.reconnect_banner.clone(),
            connections_factory,
            connections_popover: widgets.connections_popover.clone(),
            edit_button: widgets.edit_button.clone(),
            health_pill: widgets.health_pill.clone(),
            health_state: None,
            row_op_spinner: widgets.row_op_spinner.clone(),
            read_only_badge: widgets.read_only_badge.clone(),
            table_search: widgets.table_search.clone(),
            paginator_label,
            prev_button,
            next_button,
            insert_button,
            edit_row_button,
            delete_button,
            grid_holder,
            grid_search,
            grid_search_bar,
            browse_view,
            dialog: None,
            editor: None,
            insert_dialog: None,
            edit_dialog: None,
            current_table: None,
            current_schema: None,
            current_offset: 0,
            current_columns: Vec::new(),
            current_result: None,
            current_selection: None,
            current_driver_id: None,
            current_sort: None,
            current_total_rows: None,
            page_size: crate::services::preferences::load().default_page_size,
            table_names: Vec::new(),
            saved_connections: Vec::new(),
            connected: false,
        };
        sender.input(AppMsg::ReloadConnections);
        model.show_welcome_page(sender.clone());

        widgets
            .new_connection_button
            .update_property(&[gtk::accessible::Property::Label("New connection")]);
        widgets
            .saved_connections_button
            .update_property(&[gtk::accessible::Property::Label("Open saved connection")]);
        widgets
            .edit_button
            .update_property(&[gtk::accessible::Property::Label("SQL editor")]);
        widgets
            .primary_menu_button
            .update_property(&[gtk::accessible::Property::Label("Main menu")]);

        widgets.primary_menu_button.set_menu_model(Some(&primary_menu_model()));
        install_window_actions(&widgets.window, sender.clone());
        install_window_shortcuts(&widgets.window);

        let banner_sender = sender.clone();
        widgets.reconnect_banner.connect_button_clicked(move |_| {
            banner_sender.input(AppMsg::RefreshPage);
        });

        let poll_sender = sender.clone();
        glib::timeout_add_seconds_local(1, move || {
            poll_sender.input(AppMsg::PollHealth);
            glib::ControlFlow::Continue
        });

        ComponentParts { model, widgets }
    }

    fn update(&mut self, msg: Self::Input, sender: ComponentSender<Self>) {
        match msg {
            AppMsg::OpenConnect => self.on_open_connect(sender),
            AppMsg::Connected { tables, driver_id } => self.on_connected(tables, driver_id, sender),
            AppMsg::Disconnect => self.on_disconnect(sender),
            AppMsg::DialogClosed => self.dialog = None,
            AppMsg::SelectTable { schema, name } => self.on_select_table(schema, name, sender),
            AppMsg::ColumnsLoaded(table, columns) => self.on_columns_loaded(table, columns, sender),
            AppMsg::PrevPage => self.on_prev_page(sender),
            AppMsg::NextPage => self.on_next_page(sender),
            AppMsg::RowsLoaded(table, offset, result) => self.on_rows_loaded(table, offset, result, sender),
            AppMsg::LoadFailed(msg) => self.on_load_failed(msg),
            AppMsg::InsertRow => self.on_insert_row(sender),
            AppMsg::InsertCommitted => self.on_insert_committed(sender),
            AppMsg::EditSelectedRow => self.on_edit_selected_row(sender),
            AppMsg::EditCommitted => self.on_edit_committed(sender),
            AppMsg::DeleteSelectedRow => self.on_delete_selected_row(sender),
            AppMsg::RowOperationCommitted(undo) => {
                self.set_row_op_in_flight(false);
                let label = undo
                    .as_ref()
                    .map(|u| u.label.clone())
                    .unwrap_or_else(|| "Rows updated".to_string());
                if let Some(u) = undo {
                    self.show_undoable_toast(&label, u, sender.clone());
                } else {
                    self.show_toast(&label);
                }
                self.fetch_current_page(sender);
            }
            AppMsg::RowOpStarted => self.set_row_op_in_flight(true),
            AppMsg::ExecuteUndo(batch) => {
                self.set_row_op_in_flight(true);
                self.show_toast("Undoing…");
                run_undo_batch(sender, batch);
            }
            AppMsg::CellEdited {
                table,
                row_position,
                col_index,
                new_value,
            } => self.on_cell_edited(table, row_position, col_index, new_value, sender),
            AppMsg::ReloadConnections => self.on_reload_connections(sender),
            AppMsg::ConnectionsLoaded(connections) => {
                let conns = connections;
                self.on_connections_loaded(&conns, sender);
            }
            AppMsg::OpenEditor => self.on_open_editor(),
            AppMsg::PollHealth => self.on_poll_health(),
            AppMsg::RefreshPage => self.fetch_current_page(sender),
            AppMsg::ShowShortcuts => self.on_show_shortcuts(),
            AppMsg::ShowAbout => self.on_show_about(),
            AppMsg::ShowPreferences => super::preferences::present(&self.window),
            AppMsg::SortChanged(col_idx) => self.on_sort_changed(col_idx, sender),
            AppMsg::PageSizeChanged(size) => self.on_page_size_changed(size, sender),
            AppMsg::RowCountLoaded(table, count) => self.on_row_count_loaded(table, count),
            AppMsg::FindInResults => self.on_find_in_results(),
            AppMsg::ExportCsv => self.on_export(ExportFormat::Csv),
            AppMsg::ExportJson => self.on_export(ExportFormat::Json),
            AppMsg::CopyToClipboard(text) => self.on_copy_to_clipboard(text),
            AppMsg::SetCellNull {
                table,
                row_position,
                col_index,
            } => self.on_set_cell_null(table, row_position, col_index, sender),
            AppMsg::DeleteRowAt { table, row_position } => self.on_delete_row_at(table, row_position, sender),
            AppMsg::CopyRowAsInsert { row_position } => self.on_copy_row_as_insert(row_position),
            AppMsg::DeleteConnection(id) => self.on_delete_connection(id, sender),
            AppMsg::OpenSaved(saved) => self.on_open_saved(saved, sender),
        }
    }
}

impl App {
    fn on_open_connect(&mut self, sender: ComponentSender<Self>) {
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

    fn on_connected(&mut self, tables: Vec<TableInfo>, driver_id: String, sender: ComponentSender<Self>) {
        self.dialog = None;
        self.connected = true;
        self.current_driver_id = Some(driver_id.clone());
        self.edit_button.set_sensitive(true);
        self.window.action_set_enabled("win.disconnect", true);
        self.table_search.set_text("");
        self.table_names = tables.iter().map(|t| t.name.clone()).collect();
        tracing::info!(driver = %driver_id, table_count = tables.len(), "workspace ready");
        self.repopulate_sidebar(&tables);
        self.push_schema_words();
        self.refresh_window_title();
        self.set_status_page(
            "Select a table",
            &format!("Connected to {driver_id}. Pick a table from the left to load up to 100,000 rows."),
        );
        sender.input(AppMsg::ReloadConnections);
    }

    fn on_disconnect(&mut self, sender: ComponentSender<Self>) {
        let svc = database_service::instance();
        if let Some(id) = svc.active_id() {
            svc.remove(id);
        } else {
            svc.clear_all();
        }
        self.editor = None;
        self.current_table = None;
        self.current_schema = None;
        self.current_offset = 0;
        self.current_columns.clear();
        self.current_result = None;
        self.current_selection = None;
        self.current_driver_id = None;
        self.connected = false;
        self.edit_button.set_sensitive(false);
        self.window.action_set_enabled("win.disconnect", false);
        self.refresh_crud_buttons();
        self.refresh_window_title();
        self.table_search.set_text("");
        self.sidebar_schemas.borrow_mut().clear();
        self.sidebar_factory.guard().clear();
        self.show_welcome_page(sender);
        tracing::info!("disconnected");
    }

    fn on_select_table(&mut self, schema: Option<String>, name: String, sender: ComponentSender<Self>) {
        self.editor = None;
        self.current_table = Some(name.clone());
        self.current_schema = schema.clone();
        self.current_offset = 0;
        self.current_columns.clear();
        self.current_sort = None;
        self.current_total_rows = None;
        self.refresh_window_title();
        let label = qualified_label(schema.as_deref(), &name);
        self.set_loading_page("Loading…", &format!("Fetching rows from {label}"));
        self.fetch_current_page(sender.clone());
        self.fetch_columns(schema.clone(), name.clone(), sender.clone());
        self.fetch_row_count(schema, name, sender);
    }

    fn fetch_row_count(&self, schema: Option<String>, table: String, sender: ComponentSender<Self>) {
        let Some(conn) = database_service::instance().active() else {
            return;
        };
        let driver_id = self.current_driver_id.clone().unwrap_or_else(|| "postgres".to_string());
        let table_for_async = table.clone();
        let sender_clone = sender.clone();
        sender.command(move |_, shutdown| {
            shutdown
                .register(async move {
                    let qualified = match schema {
                        Some(s) => format!(
                            "{}.{}",
                            crate::sql_dialect::quote_ident(&driver_id, &s),
                            crate::sql_dialect::quote_ident(&driver_id, &table_for_async)
                        ),
                        None => crate::sql_dialect::quote_ident(&driver_id, &table_for_async),
                    };
                    let sql = format!("SELECT COUNT(*) FROM {qualified}");
                    if let Ok(qr) = conn.query(&sql).await
                        && let Some(row) = qr.rows.first()
                        && let Some(value) = row.first()
                    {
                        let count = match value {
                            tablepro_core::Value::Int(i) if *i >= 0 => Some(*i as u64),
                            tablepro_core::Value::Decimal(d) => d.to_string().parse::<u64>().ok(),
                            _ => None,
                        };
                        if let Some(count) = count {
                            sender_clone.input(AppMsg::RowCountLoaded(table_for_async, count));
                        }
                    }
                })
                .drop_on_shutdown()
        });
    }

    fn on_columns_loaded(&mut self, table: String, columns: Vec<ColumnInfo>, sender: ComponentSender<Self>) {
        if self.current_table.as_deref() != Some(&table) {
            return;
        }
        self.current_columns = columns;
        self.refresh_crud_buttons();
        self.push_schema_words();
        if self.current_result.is_some() {
            self.fetch_current_page(sender);
        }
    }

    fn push_schema_words(&self) {
        if let Some(editor) = self.editor.as_ref() {
            let mut words: Vec<String> = self.table_names.clone();
            for c in &self.current_columns {
                words.push(c.name.clone());
            }
            words.sort_unstable();
            words.dedup();
            editor
                .sender()
                .send(super::editor::SqlEditorInput::SetSchemaWords(words))
                .ok();
        }
    }

    fn on_prev_page(&mut self, sender: ComponentSender<Self>) {
        if self.current_offset >= self.page_size {
            self.current_offset -= self.page_size;
            self.fetch_current_page(sender);
        }
    }

    fn on_next_page(&mut self, sender: ComponentSender<Self>) {
        self.current_offset += self.page_size;
        self.fetch_current_page(sender);
    }

    fn on_sort_changed(&mut self, col_idx: usize, sender: ComponentSender<Self>) {
        let next = match self.current_sort {
            Some((c, asc)) if c == col_idx => Some((c, !asc)),
            _ => Some((col_idx, true)),
        };
        self.current_sort = next;
        self.current_offset = 0;
        self.fetch_current_page(sender);
    }

    fn on_page_size_changed(&mut self, size: u64, sender: ComponentSender<Self>) {
        if self.page_size == size {
            return;
        }
        self.page_size = size;
        self.current_offset = 0;
        self.fetch_current_page(sender);
    }

    fn on_row_count_loaded(&mut self, table: String, count: u64) {
        if self.current_table.as_deref() != Some(&table) {
            return;
        }
        self.current_total_rows = Some(count);
        self.update_paginator_label();
    }

    fn update_paginator_label(&self) {
        let Some(result) = self.current_result.as_ref() else {
            self.paginator_label.set_label("");
            return;
        };
        let n_rows = result.rows.len();
        if n_rows == 0 {
            self.paginator_label
                .set_label(&format!("No rows at offset {}", self.current_offset));
            return;
        }
        let start = self.current_offset + 1;
        let end = self.current_offset + n_rows as u64;
        let label = match self.current_total_rows {
            Some(total) => format!("Rows {start} – {end} of {total}"),
            None => format!("Rows {start} – {end}"),
        };
        self.paginator_label.set_label(&label);
    }

    fn on_rows_loaded(&mut self, table: String, offset: u64, result: QueryResult, sender: ComponentSender<Self>) {
        if self.current_table.as_deref() != Some(&table) {
            return;
        }
        let n_rows = result.rows.len();
        let n_cols = result.columns.len();
        tracing::info!(table = %table, offset, rows = n_rows, cols = n_cols, "rows loaded");

        clear_box(&self.grid_holder);
        let read_only = database_service::instance().is_active_read_only();
        let edit_sender = if read_only {
            None
        } else {
            Some(sender.input_sender().clone())
        };
        let (column_view, selection, filter_setter) = build_column_view(
            &result,
            &self.current_columns,
            &table,
            edit_sender,
            self.current_sort,
            Some(sender.input_sender().clone()),
            database_service::instance().active_id(),
        );
        let setter = filter_setter.clone();
        self.grid_search.connect_search_changed(move |entry| {
            setter(&entry.text());
        });
        filter_setter(&self.grid_search.text());
        self.current_selection = Some(selection);
        self.current_result = Some(result.clone());
        let scrolled = gtk::ScrolledWindow::builder()
            .child(&column_view)
            .hexpand(true)
            .vexpand(true)
            .build();
        self.grid_holder.append(&scrolled);
        self.refresh_crud_buttons();

        self.update_paginator_label();
        self.prev_button.set_sensitive(offset > 0);
        self.next_button.set_sensitive(n_rows as u64 == self.page_size);

        self.content_holder.set_content(Some(&self.browse_view));
    }

    fn on_load_failed(&self, msg: String) {
        tracing::warn!(error = %msg, "load failed");
        self.set_row_op_in_flight(false);
        self.set_status_page("Failed", &msg);
    }

    fn set_row_op_in_flight(&self, in_flight: bool) {
        self.row_op_spinner.set_visible(in_flight);
        if in_flight {
            self.row_op_spinner.start();
        } else {
            self.row_op_spinner.stop();
        }
    }

    fn on_insert_row(&mut self, sender: ComponentSender<Self>) {
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

    fn on_insert_committed(&mut self, sender: ComponentSender<Self>) {
        self.insert_dialog = None;
        self.show_toast("Row inserted");
        self.fetch_current_page(sender);
    }

    fn on_edit_selected_row(&mut self, sender: ComponentSender<Self>) {
        let Some(table) = self.current_table.clone() else {
            return;
        };
        let Some(selection) = self.current_selection.clone() else {
            return;
        };
        let Some(result) = self.current_result.clone() else {
            return;
        };
        let positions = selected_positions(&selection);
        if positions.len() != 1 {
            self.show_error_alert("Cannot edit", "Select exactly one row to edit.");
            return;
        }
        let position = positions[0] as usize;
        if position >= result.rows.len() {
            return;
        }
        let row = result.rows[position].clone();
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

    fn on_edit_committed(&mut self, sender: ComponentSender<Self>) {
        self.edit_dialog = None;
        self.show_toast("Row updated");
        self.fetch_current_page(sender);
    }

    fn on_delete_selected_row(&mut self, sender: ComponentSender<Self>) {
        let Some(table) = self.current_table.clone() else {
            return;
        };
        let Some(selection) = self.current_selection.clone() else {
            return;
        };
        let Some(result) = self.current_result.clone() else {
            return;
        };
        let positions = selected_positions(&selection);
        if positions.is_empty() {
            return;
        }
        let pk_indexes: Vec<usize> = self
            .current_columns
            .iter()
            .enumerate()
            .filter(|(_, c)| c.primary_key)
            .map(|(i, _)| i)
            .collect();
        if pk_indexes.is_empty() {
            self.show_error_alert(
                "Cannot delete",
                &super::error_text::build_sql_message(&crate::sql_dialect::BuildSqlError::NoPrimaryKey),
            );
            return;
        }
        let driver_id = self.current_driver_id.clone().unwrap_or_else(|| "postgres".to_string());

        let preview = if positions.len() == 1 {
            let row = &result.rows[positions[0] as usize];
            format!(
                "Delete row where {}?",
                preview_pk(&self.current_columns, &pk_indexes, row)
            )
        } else {
            format!("Delete {} rows?", positions.len())
        };
        let confirm_label = if positions.len() == 1 {
            "Delete".to_string()
        } else {
            format!("Delete {}", positions.len())
        };

        self.confirm_and_execute_many(
            sender,
            &table,
            &driver_id,
            &pk_indexes,
            &positions,
            &result.rows,
            &preview,
            &confirm_label,
        );
    }

    fn on_cell_edited(
        &mut self,
        table: String,
        row_position: u32,
        col_index: usize,
        new_value: String,
        sender: ComponentSender<Self>,
    ) {
        if self.current_table.as_deref() != Some(&table) {
            return;
        }
        let (Some(driver_id), Some(result)) = (self.current_driver_id.clone(), self.current_result.clone()) else {
            return;
        };
        let Some(row) = result.rows.get(row_position as usize).cloned() else {
            return;
        };
        if col_index >= self.current_columns.len() {
            return;
        }
        let col = &self.current_columns[col_index];

        let value = if new_value.is_empty() && col.nullable {
            Value::Null
        } else {
            Value::Text(new_value)
        };
        let original_value = row[col_index].clone();
        let (sql, params) = match crate::sql_dialect::build_single_cell_update(
            &driver_id,
            &table,
            &self.current_columns,
            &row,
            col_index,
            value,
        ) {
            Ok(t) => t,
            Err(e) => {
                self.show_error_alert("Cannot update cell", &super::error_text::build_sql_message(&e));
                return;
            }
        };
        let undo = crate::sql_dialect::build_single_cell_update(
            &driver_id,
            &table,
            &self.current_columns,
            &row,
            col_index,
            original_value,
        )
        .ok()
        .map(|(s, p)| UndoBatch {
            label: "Cell updated".into(),
            statements: vec![(s, p)],
        });
        self.set_row_op_in_flight(true);
        execute_then_refetch(sender, sql, params, undo);
    }

    fn on_reload_connections(&self, sender: ComponentSender<Self>) {
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

    fn on_connections_loaded(&mut self, connections: &[SavedConnection], sender: ComponentSender<Self>) {
        self.saved_connections = connections.to_vec();
        let mut guard = self.connections_factory.guard();
        guard.clear();
        for saved in connections {
            guard.push_back(saved.clone());
        }
        drop(guard);
        if !self.connected {
            self.show_welcome_page(sender);
        }
    }

    fn on_open_editor(&mut self) {
        if database_service::instance().active().is_none() {
            self.set_status_page("No connection", "Connect to a database first to run SQL.");
            return;
        }
        let editor = SqlEditor::builder().launch(()).detach();
        self.content_holder.set_content(Some(editor.widget()));
        self.editor = Some(editor);
        self.push_schema_words();
    }

    fn on_poll_health(&mut self) {
        let current = database_service::instance().active_health();
        if current != self.health_state {
            self.refresh_health_pill(current.clone());
            self.health_state = current;
        }
    }

    fn on_delete_connection(&self, id: Uuid, sender: ComponentSender<Self>) {
        let sender_clone = sender.clone();
        sender.command(move |_, shutdown| {
            shutdown
                .register(async move {
                    let _ = tablepro_storage::delete_connection(id).await;
                    let _ = tablepro_storage::delete_password(id).await;
                    sender_clone.input(AppMsg::ReloadConnections);
                })
                .drop_on_shutdown()
        });
    }

    fn on_open_saved(&self, saved: SavedConnection, sender: ComponentSender<Self>) {
        self.connections_popover.popdown();
        self.set_loading_page("Connecting…", &format!("Opening {}", saved.name));
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

    fn repopulate_sidebar(&mut self, tables: &[TableInfo]) {
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

    fn show_welcome_page(&self, sender: ComponentSender<Self>) {
        if self.saved_connections.is_empty() {
            let page = adw::StatusPage::builder()
                .icon_name("network-server-symbolic")
                .title(crate::tr!("Connect to a database"))
                .description(crate::tr!("Add a connection to get started."))
                .build();
            let new_btn = gtk::Button::builder()
                .label(crate::tr!("New connection"))
                .halign(gtk::Align::Center)
                .build();
            new_btn.add_css_class("suggested-action");
            new_btn.add_css_class("pill");
            let s = sender;
            new_btn.connect_clicked(move |_| s.input(AppMsg::OpenConnect));
            page.set_child(Some(&new_btn));
            self.content_holder.set_content(Some(&page));
            return;
        }

        let scroller = gtk::ScrolledWindow::builder()
            .hexpand(true)
            .vexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .build();
        let outer = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .spacing(12)
            .margin_top(24)
            .margin_bottom(24)
            .margin_start(24)
            .margin_end(24)
            .halign(gtk::Align::Center)
            .build();
        outer.set_size_request(560, -1);

        let header = gtk::Label::builder()
            .label(crate::tr!("Saved connections"))
            .xalign(0.0)
            .build();
        header.add_css_class("title-2");
        outer.append(&header);

        let group = adw::PreferencesGroup::new();
        for saved in &self.saved_connections {
            let subtitle = if saved.driver_id == "sqlite" {
                format!("sqlite · {}", saved.database)
            } else {
                format!("{} · {}@{}:{}", saved.driver_id, saved.username, saved.host, saved.port)
            };
            let row = adw::ActionRow::builder()
                .title(&saved.name)
                .subtitle(&subtitle)
                .activatable(true)
                .build();
            let saved_clone = saved.clone();
            let s = sender.clone();
            row.connect_activated(move |_| s.input(AppMsg::OpenSaved(saved_clone.clone())));
            group.add(&row);
        }
        outer.append(&group);

        let new_btn = gtk::Button::builder()
            .label(crate::tr!("New connection"))
            .halign(gtk::Align::Center)
            .margin_top(8)
            .build();
        new_btn.add_css_class("suggested-action");
        new_btn.add_css_class("pill");
        let s = sender;
        new_btn.connect_clicked(move |_| s.input(AppMsg::OpenConnect));
        outer.append(&new_btn);

        scroller.set_child(Some(&outer));
        self.content_holder.set_content(Some(&scroller));
    }

    fn set_loading_page(&self, title: &str, description: &str) {
        let page = adw::StatusPage::builder().title(title).description(description).build();
        let spinner = gtk::Spinner::new();
        spinner.set_spinning(true);
        spinner.set_size_request(48, 48);
        page.set_child(Some(&spinner));
        self.content_holder.set_content(Some(&page));
    }

    fn set_status_page(&self, title: &str, description: &str) {
        let icon = if title.eq_ignore_ascii_case("failed") || title.to_lowercase().contains("error") {
            "dialog-error-symbolic"
        } else if title.contains("No connection") {
            "network-server-symbolic"
        } else {
            "view-grid-symbolic"
        };
        let page = adw::StatusPage::builder()
            .title(title)
            .description(description)
            .icon_name(icon)
            .build();
        self.content_holder.set_content(Some(&page));
    }

    fn fetch_current_page(&self, sender: ComponentSender<App>) {
        let Some(table) = self.current_table.clone() else {
            return;
        };
        let schema = self.current_schema.clone();
        let offset = self.current_offset;
        let limit = self.page_size;
        let Some(conn) = database_service::instance().active() else {
            sender.input(AppMsg::LoadFailed("no active connection".into()));
            return;
        };
        let driver_id = self.current_driver_id.clone().unwrap_or_else(|| "postgres".to_string());
        let order_by = self.current_sort.and_then(|(idx, asc)| {
            self.current_columns.get(idx).map(|c| {
                let name = crate::sql_dialect::quote_ident(&driver_id, &c.name);
                let dir = if asc { "ASC" } else { "DESC" };
                format!("{name} {dir}")
            })
        });
        let sender_clone = sender.clone();
        sender.command(move |_, shutdown| {
            shutdown
                .register(async move {
                    let result = match &order_by {
                        Some(order) => {
                            let qualified = match &schema {
                                Some(s) => format!(
                                    "{}.{}",
                                    crate::sql_dialect::quote_ident(&driver_id, s),
                                    crate::sql_dialect::quote_ident(&driver_id, &table)
                                ),
                                None => crate::sql_dialect::quote_ident(&driver_id, &table),
                            };
                            let sql =
                                format!("SELECT * FROM {qualified} ORDER BY {order} LIMIT {limit} OFFSET {offset}");
                            conn.query(&sql).await
                        }
                        None => conn.fetch_rows(schema.as_deref(), &table, offset, limit).await,
                    };
                    match result {
                        Ok(query_result) => sender_clone.input(AppMsg::RowsLoaded(table, offset, query_result)),
                        Err(e) => sender_clone.input(AppMsg::LoadFailed(super::error_text::driver_message(&e))),
                    }
                })
                .drop_on_shutdown()
        });
    }

    fn fetch_columns(&self, schema: Option<String>, table: String, sender: ComponentSender<App>) {
        let Some(conn) = database_service::instance().active() else {
            return;
        };
        let sender_clone = sender.clone();
        sender.command(move |_, shutdown| {
            shutdown
                .register(async move {
                    if let Ok(columns) = conn.fetch_columns(schema.as_deref(), &table).await {
                        sender_clone.input(AppMsg::ColumnsLoaded(table, columns));
                    }
                })
                .drop_on_shutdown()
        });
    }

    fn refresh_health_pill(&self, health: Option<ConnectionHealth>) {
        let pill = &self.health_pill;
        pill.remove_css_class("success");
        pill.remove_css_class("warning");
        match &health {
            None => {
                pill.set_visible(false);
            }
            Some(ConnectionHealth::Healthy) => {
                pill.set_visible(true);
                pill.set_label("Connected");
                pill.add_css_class("success");
            }
            Some(ConnectionHealth::Reconnecting { attempt }) => {
                pill.set_visible(true);
                pill.set_label(&format!("Reconnecting · attempt {attempt} · retrying"));
                pill.add_css_class("warning");
            }
        }
        match health {
            Some(ConnectionHealth::Reconnecting { attempt }) => {
                self.reconnect_banner.set_title(&format!(
                    "Connection lost — reconnecting (attempt {attempt}, will keep retrying)",
                ));
                self.reconnect_banner.set_revealed(true);
            }
            _ => self.reconnect_banner.set_revealed(false),
        }
    }

    fn refresh_crud_buttons(&self) {
        let read_only = database_service::instance().is_active_read_only();
        let connected = database_service::instance().active().is_some();
        self.read_only_badge.set_visible(connected && read_only);
        self.insert_button.set_visible(!read_only);
        self.edit_row_button.set_visible(!read_only);
        self.delete_button.set_visible(!read_only);
        if read_only {
            return;
        }
        let has_table = self.current_table.is_some() && !self.current_columns.is_empty();
        let has_row = has_table && self.current_result.is_some();
        self.insert_button.set_sensitive(has_table);
        self.edit_row_button.set_sensitive(has_row);
        self.delete_button.set_sensitive(has_row);
    }

    #[allow(clippy::too_many_arguments)]
    fn confirm_and_execute_many(
        &self,
        sender: ComponentSender<App>,
        table: &str,
        driver_id: &str,
        pk_indexes: &[usize],
        positions: &[u32],
        rows: &[Vec<Value>],
        preview: &str,
        confirm_label: &str,
    ) {
        let where_clause: String = pk_indexes
            .iter()
            .enumerate()
            .map(|(i, col_idx)| {
                let name = &self.current_columns[*col_idx].name;
                let placeholder = placeholder_for(driver_id, i);
                format!("{} = {}", quote_ident(driver_id, name), placeholder)
            })
            .collect::<Vec<_>>()
            .join(" AND ");
        let sql = format!("DELETE FROM {} WHERE {}", quote_ident(driver_id, table), where_clause);

        let mut batches: Vec<Vec<Value>> = Vec::with_capacity(positions.len());
        let mut undo_statements: Vec<(String, Vec<Value>)> = Vec::with_capacity(positions.len());
        for pos in positions {
            let Some(row) = rows.get(*pos as usize) else {
                continue;
            };
            batches.push(pk_indexes.iter().map(|i| row[*i].clone()).collect());
            undo_statements.push(build_insert_for_row(driver_id, table, &self.current_columns, row));
        }

        let undo_label = if positions.len() == 1 {
            "1 row deleted".to_string()
        } else {
            format!("{} rows deleted", positions.len())
        };
        let undo = if undo_statements.is_empty() {
            None
        } else {
            Some(UndoBatch {
                label: undo_label,
                statements: undo_statements,
            })
        };

        if !crate::services::preferences::load().confirm_destructive {
            sender.input(AppMsg::RowOpStarted);
            execute_many_then_refetch(sender, sql, batches, undo);
            return;
        }

        let alert_title = if positions.len() == 1 {
            "Delete row?".to_string()
        } else {
            format!("Delete {} rows?", positions.len())
        };
        let dialog = adw::AlertDialog::new(Some(&alert_title), Some(preview));
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("delete", confirm_label);
        dialog.set_response_appearance("delete", adw::ResponseAppearance::Destructive);
        dialog.set_default_response(Some("cancel"));
        dialog.set_close_response("cancel");

        let sender_clone = sender;
        dialog.connect_response(None, move |dialog, response| {
            dialog.close();
            if response != "delete" {
                return;
            }
            let sql = sql.clone();
            let batches = batches.clone();
            let undo = undo.clone();
            sender_clone.input(AppMsg::RowOpStarted);
            execute_many_then_refetch(sender_clone.clone(), sql, batches, undo);
        });
        dialog.present(Some(&self.window));
    }

    fn refresh_window_title(&self) {
        let title = match (&self.current_driver_id, &self.current_table) {
            (Some(driver), Some(table)) => {
                let label = qualified_label(self.current_schema.as_deref(), table);
                format!("{label} · {driver} — TablePro")
            }
            (Some(driver), None) => format!("{driver} — TablePro"),
            _ => "TablePro Linux".to_string(),
        };
        self.window.set_title(Some(&title));
    }

    fn show_toast(&self, msg: &str) {
        self.toast_overlay.add_toast(adw::Toast::new(msg));
    }

    fn show_undoable_toast(&self, msg: &str, batch: UndoBatch, sender: ComponentSender<Self>) {
        let toast = adw::Toast::builder()
            .title(msg)
            .timeout(10)
            .button_label("Undo")
            .build();
        let s = sender;
        let batch_clone = batch;
        toast.connect_button_clicked(move |t| {
            s.input(AppMsg::ExecuteUndo(batch_clone.clone()));
            t.dismiss();
        });
        self.toast_overlay.add_toast(toast);
    }

    fn show_error_alert(&self, title: &str, message: &str) {
        let dialog = adw::AlertDialog::new(Some(title), Some(message));
        dialog.add_response("ok", "OK");
        dialog.set_default_response(Some("ok"));
        dialog.set_close_response("ok");
        dialog.present(Some(&self.window));
    }
}

fn value_to_sql_literal(v: &Value) -> String {
    match v {
        Value::Null => "NULL".into(),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::Float(f) => f.to_string(),
        Value::Decimal(d) => d.to_string(),
        Value::Text(s) => format!("'{}'", s.replace('\'', "''")),
        Value::Bytes(_) => "/* bytes omitted */ NULL".into(),
        Value::Date(d) => format!("'{}'", d.format("%Y-%m-%d")),
        Value::Time(t) => format!("'{}'", t.format("%H:%M:%S")),
        Value::DateTime(dt) => format!("'{}'", dt.format("%Y-%m-%d %H:%M:%S")),
        Value::TimestampTz(ts) => format!("'{}'", ts.to_rfc3339()),
        Value::Uuid(u) => format!("'{u}'"),
        Value::Json(j) => format!("'{}'", j.to_string().replace('\'', "''")),
    }
}

fn render_csv(result: &QueryResult) -> Vec<u8> {
    let mut out = String::new();
    let cols: Vec<&str> = result.columns.iter().map(|c| c.name.as_str()).collect();
    out.push_str(&cols.iter().map(|c| csv_escape(c)).collect::<Vec<_>>().join(","));
    out.push('\n');
    for row in &result.rows {
        let cells: Vec<String> = row
            .iter()
            .map(|v| csv_escape(&super::grid::value_to_display_text(v)))
            .collect();
        out.push_str(&cells.join(","));
        out.push('\n');
    }
    out.into_bytes()
}

fn csv_escape(s: &str) -> String {
    if s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r') {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

fn render_json(result: &QueryResult) -> Vec<u8> {
    let cols: Vec<&str> = result.columns.iter().map(|c| c.name.as_str()).collect();
    let rows: Vec<serde_json::Value> = result
        .rows
        .iter()
        .map(|row| {
            let mut obj = serde_json::Map::new();
            for (i, col) in cols.iter().enumerate() {
                let v = row.get(i).cloned().unwrap_or(Value::Null);
                obj.insert((*col).to_string(), value_to_json(&v));
            }
            serde_json::Value::Object(obj)
        })
        .collect();
    serde_json::to_vec_pretty(&rows).unwrap_or_default()
}

fn value_to_json(v: &Value) -> serde_json::Value {
    use serde_json::Value as J;
    match v {
        Value::Null => J::Null,
        Value::Bool(b) => J::Bool(*b),
        Value::Int(i) => J::from(*i),
        Value::Float(f) => J::from(*f),
        Value::Text(s) => J::String(s.clone()),
        Value::Bytes(b) => J::String(format!("<{} bytes>", b.len())),
        Value::Date(d) => J::String(d.to_string()),
        Value::Time(t) => J::String(t.to_string()),
        Value::DateTime(dt) => J::String(dt.to_string()),
        Value::TimestampTz(ts) => J::String(ts.to_rfc3339()),
        Value::Decimal(d) => J::String(d.to_string()),
        Value::Uuid(u) => J::String(u.to_string()),
        Value::Json(j) => j.clone(),
    }
}

fn selected_positions(selection: &gtk::MultiSelection) -> Vec<u32> {
    let bitset = selection.selection();
    let mut out = Vec::with_capacity(bitset.size() as usize);
    for i in 0..bitset.size() {
        out.push(bitset.nth(i as u32));
    }
    out.sort_unstable();
    out
}

fn execute_many_then_refetch(
    sender: ComponentSender<App>,
    sql: String,
    batches: Vec<Vec<Value>>,
    undo: Option<UndoBatch>,
) {
    let Some(conn) = database_service::instance().active() else {
        sender.input(AppMsg::LoadFailed("no active connection".into()));
        return;
    };
    let sender_clone = sender.clone();
    sender.command(move |_, shutdown| {
        shutdown
            .register(async move {
                let mut total: u64 = 0;
                for params in &batches {
                    match conn.execute_params(&sql, params).await {
                        Ok(exec) => total += exec.rows_affected,
                        Err(e) => {
                            tracing::warn!(error = %e, "execute (multi) failed");
                            sender_clone.input(AppMsg::LoadFailed(super::error_text::driver_message(&e)));
                            return;
                        }
                    }
                }
                tracing::info!(rows = total, "multi-execute ok");
                sender_clone.input(AppMsg::RowOperationCommitted(undo));
            })
            .drop_on_shutdown()
    });
}

fn execute_then_refetch(sender: ComponentSender<App>, sql: String, params: Vec<Value>, undo: Option<UndoBatch>) {
    let Some(conn) = database_service::instance().active() else {
        sender.input(AppMsg::LoadFailed("no active connection".into()));
        return;
    };
    let sender_clone = sender.clone();
    sender.command(move |_, shutdown| {
        shutdown
            .register(async move {
                match conn.execute_params(&sql, &params).await {
                    Ok(exec) => {
                        tracing::info!(rows = exec.rows_affected, "execute ok");
                        sender_clone.input(AppMsg::RowOperationCommitted(undo));
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "execute failed");
                        sender_clone.input(AppMsg::LoadFailed(super::error_text::driver_message(&e)));
                    }
                }
            })
            .drop_on_shutdown()
    });
}

fn run_undo_batch(sender: ComponentSender<App>, batch: UndoBatch) {
    let Some(conn) = database_service::instance().active() else {
        sender.input(AppMsg::LoadFailed("no active connection".into()));
        return;
    };
    let sender_clone = sender.clone();
    sender.command(move |_, shutdown| {
        shutdown
            .register(async move {
                for (sql, params) in batch.statements.iter() {
                    if let Err(e) = conn.execute_params(sql, params).await {
                        tracing::warn!(error = %e, "undo failed");
                        sender_clone.input(AppMsg::LoadFailed(super::error_text::driver_message(&e)));
                        return;
                    }
                }
                tracing::info!(count = batch.statements.len(), "undo ok");
                sender_clone.input(AppMsg::RowOperationCommitted(None));
            })
            .drop_on_shutdown()
    });
}

fn build_insert_for_row(driver_id: &str, table: &str, columns: &[ColumnInfo], row: &[Value]) -> (String, Vec<Value>) {
    let cols: Vec<String> = columns.iter().map(|c| quote_ident(driver_id, &c.name)).collect();
    let placeholders: Vec<String> = (0..columns.len()).map(|i| placeholder_for(driver_id, i)).collect();
    let sql = format!(
        "INSERT INTO {} ({}) VALUES ({})",
        quote_ident(driver_id, table),
        cols.join(", "),
        placeholders.join(", "),
    );
    (sql, row.to_vec())
}

fn preview_pk(columns: &[ColumnInfo], pk_indexes: &[usize], row: &[Value]) -> String {
    pk_indexes
        .iter()
        .map(|i| {
            let name = &columns[*i].name;
            let raw = super::grid::value_to_display_text(&row[*i]);
            let value = match &row[*i] {
                Value::Text(_) => format!("'{raw}'"),
                _ => raw,
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

fn qualified_label(schema: Option<&str>, table: &str) -> String {
    match schema {
        Some(s) => format!("{s}.{table}"),
        None => table.to_string(),
    }
}

fn primary_menu_model() -> gio::Menu {
    let menu = gio::Menu::new();
    let connection_section = gio::Menu::new();
    connection_section.append(Some(&crate::tr!("Disconnect")), Some("win.disconnect"));
    menu.append_section(None, &connection_section);
    let prefs_section = gio::Menu::new();
    prefs_section.append(Some(&crate::tr!("Preferences")), Some("win.preferences"));
    menu.append_section(None, &prefs_section);
    let app_section = gio::Menu::new();
    app_section.append(Some(&crate::tr!("Keyboard Shortcuts")), Some("win.shortcuts"));
    app_section.append(Some(&crate::tr!("About TablePro")), Some("win.about"));
    app_section.append(Some(&crate::tr!("Quit")), Some("win.quit"));
    menu.append_section(None, &app_section);
    menu
}

fn install_window_actions(window: &adw::ApplicationWindow, sender: ComponentSender<App>) {
    let group = gio::SimpleActionGroup::new();

    let shortcuts_sender = sender.clone();
    let shortcuts = gio::ActionEntry::builder("shortcuts")
        .activate(move |_, _, _| shortcuts_sender.input(AppMsg::ShowShortcuts))
        .build();

    let about_sender = sender.clone();
    let about = gio::ActionEntry::builder("about")
        .activate(move |_, _, _| about_sender.input(AppMsg::ShowAbout))
        .build();

    let window_for_quit = window.clone();
    let quit = gio::ActionEntry::builder("quit")
        .activate(move |_, _, _| window_for_quit.close())
        .build();

    let editor_sender = sender.clone();
    let open_editor = gio::ActionEntry::builder("open-editor")
        .activate(move |_, _, _| editor_sender.input(AppMsg::OpenEditor))
        .build();

    let disconnect_sender = sender.clone();
    let disconnect = gio::ActionEntry::builder("disconnect")
        .activate(move |_, _, _| disconnect_sender.input(AppMsg::Disconnect))
        .build();

    let prefs_sender = sender.clone();
    let preferences = gio::ActionEntry::builder("preferences")
        .activate(move |_, _, _| prefs_sender.input(AppMsg::ShowPreferences))
        .build();

    let refresh_sender = sender.clone();
    let refresh = gio::ActionEntry::builder("refresh-page")
        .activate(move |_, _, _| refresh_sender.input(AppMsg::RefreshPage))
        .build();

    let find_sender = sender.clone();
    let find = gio::ActionEntry::builder("find-in-results")
        .activate(move |_, _, _| find_sender.input(AppMsg::FindInResults))
        .build();

    let csv_sender = sender.clone();
    let export_csv = gio::ActionEntry::builder("export-csv")
        .activate(move |_, _, _| csv_sender.input(AppMsg::ExportCsv))
        .build();

    let json_sender = sender;
    let export_json = gio::ActionEntry::builder("export-json")
        .activate(move |_, _, _| json_sender.input(AppMsg::ExportJson))
        .build();

    group.add_action_entries([
        shortcuts,
        about,
        quit,
        open_editor,
        disconnect,
        preferences,
        refresh,
        find,
        export_csv,
        export_json,
    ]);
    window.insert_action_group("win", Some(&group));
    window.action_set_enabled("win.disconnect", false);
}

fn install_window_shortcuts(window: &adw::ApplicationWindow) {
    let controller = gtk::ShortcutController::new();
    controller.set_scope(gtk::ShortcutScope::Global);
    controller.add_shortcut(make_shortcut("<Primary>question", "win.shortcuts"));
    controller.add_shortcut(make_shortcut("<Primary>slash", "win.shortcuts"));
    controller.add_shortcut(make_shortcut("<Primary>q", "win.quit"));
    controller.add_shortcut(make_shortcut("<Primary>w", "win.quit"));
    controller.add_shortcut(make_shortcut("<Primary>e", "win.open-editor"));
    controller.add_shortcut(make_shortcut("F5", "win.refresh-page"));
    controller.add_shortcut(make_shortcut("<Primary>f", "win.find-in-results"));
    controller.add_shortcut(make_shortcut("<Primary>comma", "win.preferences"));
    window.add_controller(controller);
}

fn make_shortcut(trigger: &str, action: &str) -> gtk::Shortcut {
    gtk::Shortcut::builder()
        .trigger(&gtk::ShortcutTrigger::parse_string(trigger).expect("valid trigger"))
        .action(&gtk::NamedAction::new(action))
        .build()
}

fn build_shortcuts_window(parent: &adw::ApplicationWindow) -> gtk::ShortcutsWindow {
    let window = gtk::ShortcutsWindow::builder()
        .modal(true)
        .transient_for(parent)
        .build();
    let section = gtk::ShortcutsSection::builder().section_name("application").build();

    let general = gtk::ShortcutsGroup::builder().title("General").build();
    general.append(&shortcut_entry("<Primary>e", "Open SQL editor"));
    general.append(&shortcut_entry("<Primary>f", "Find in results"));
    general.append(&shortcut_entry("F5", "Refresh table"));
    general.append(&shortcut_entry("<Primary>comma", "Open Preferences"));
    general.append(&shortcut_entry("<Primary>question", "Show keyboard shortcuts"));
    general.append(&shortcut_entry("<Primary>q", "Quit"));
    general.append(&shortcut_entry("<Primary>w", "Close window"));
    section.append(&general);

    let editor = gtk::ShortcutsGroup::builder().title("SQL editor").build();
    editor.append(&shortcut_entry("<Primary>Return", "Run query"));
    editor.append(&shortcut_entry("Escape", "Cancel running query"));
    section.append(&editor);

    let dialogs = gtk::ShortcutsGroup::builder().title("Dialogs").build();
    dialogs.append(&shortcut_entry("Escape", "Close dialog"));
    section.append(&dialogs);

    window.add_section(&section);
    window
}

fn shortcut_entry(accel: &str, title: &str) -> gtk::ShortcutsShortcut {
    gtk::ShortcutsShortcut::builder()
        .accelerator(accel)
        .title(title)
        .build()
}

impl App {
    fn on_show_shortcuts(&self) {
        build_shortcuts_window(&self.window).present();
    }

    fn on_copy_to_clipboard(&self, text: String) {
        self.window.clipboard().set_text(&text);
        self.show_toast("Copied to clipboard");
    }

    fn on_set_cell_null(&mut self, table: String, row_position: u32, col_index: usize, sender: ComponentSender<Self>) {
        if self.current_table.as_deref() != Some(&table) {
            return;
        }
        let (Some(driver_id), Some(result)) = (self.current_driver_id.clone(), self.current_result.clone()) else {
            return;
        };
        let Some(row) = result.rows.get(row_position as usize).cloned() else {
            return;
        };
        if col_index >= self.current_columns.len() {
            return;
        }
        let original_value = row[col_index].clone();
        let (sql, params) = match crate::sql_dialect::build_single_cell_update(
            &driver_id,
            &table,
            &self.current_columns,
            &row,
            col_index,
            Value::Null,
        ) {
            Ok(t) => t,
            Err(e) => {
                self.show_error_alert("Cannot set NULL", &super::error_text::build_sql_message(&e));
                return;
            }
        };
        let undo = crate::sql_dialect::build_single_cell_update(
            &driver_id,
            &table,
            &self.current_columns,
            &row,
            col_index,
            original_value,
        )
        .ok()
        .map(|(s, p)| UndoBatch {
            label: "Cell cleared".into(),
            statements: vec![(s, p)],
        });
        self.set_row_op_in_flight(true);
        execute_then_refetch(sender, sql, params, undo);
    }

    fn on_delete_row_at(&mut self, table: String, row_position: u32, sender: ComponentSender<Self>) {
        if self.current_table.as_deref() != Some(&table) {
            return;
        }
        let Some(result) = self.current_result.clone() else {
            return;
        };
        let pk_indexes: Vec<usize> = self
            .current_columns
            .iter()
            .enumerate()
            .filter(|(_, c)| c.primary_key)
            .map(|(i, _)| i)
            .collect();
        if pk_indexes.is_empty() {
            self.show_error_alert(
                "Cannot delete",
                &super::error_text::build_sql_message(&crate::sql_dialect::BuildSqlError::NoPrimaryKey),
            );
            return;
        }
        let driver_id = self.current_driver_id.clone().unwrap_or_else(|| "postgres".to_string());
        let preview = result
            .rows
            .get(row_position as usize)
            .map(|r| {
                format!(
                    "Delete row where {}?",
                    preview_pk(&self.current_columns, &pk_indexes, r)
                )
            })
            .unwrap_or_else(|| "Delete row?".into());
        self.confirm_and_execute_many(
            sender,
            &table,
            &driver_id,
            &pk_indexes,
            &[row_position],
            &result.rows,
            &preview,
            "Delete",
        );
    }

    fn on_copy_row_as_insert(&self, row_position: u32) {
        let Some(result) = self.current_result.as_ref() else {
            return;
        };
        let Some(table) = self.current_table.as_ref() else {
            return;
        };
        let Some(row) = result.rows.get(row_position as usize) else {
            return;
        };
        let driver_id = self.current_driver_id.clone().unwrap_or_else(|| "postgres".to_string());
        let cols: Vec<String> = self
            .current_columns
            .iter()
            .map(|c| crate::sql_dialect::quote_ident(&driver_id, &c.name))
            .collect();
        let values: Vec<String> = row.iter().map(value_to_sql_literal).collect();
        let sql = format!(
            "INSERT INTO {} ({}) VALUES ({});",
            crate::sql_dialect::quote_ident(&driver_id, table),
            cols.join(", "),
            values.join(", "),
        );
        self.window.clipboard().set_text(&sql);
        self.show_toast("INSERT statement copied");
    }

    fn on_export(&self, format: ExportFormat) {
        let Some(result) = self.current_result.clone() else {
            self.show_toast("Nothing to export");
            return;
        };
        let suggested = match format {
            ExportFormat::Csv => "table.csv",
            ExportFormat::Json => "table.json",
        };
        let filter = gtk::FileFilter::new();
        match format {
            ExportFormat::Csv => {
                filter.set_name(Some("CSV files"));
                filter.add_mime_type("text/csv");
                filter.add_suffix("csv");
            }
            ExportFormat::Json => {
                filter.set_name(Some("JSON files"));
                filter.add_mime_type("application/json");
                filter.add_suffix("json");
            }
        };
        let filters = gio::ListStore::new::<gtk::FileFilter>();
        filters.append(&filter);
        let dialog = gtk::FileDialog::builder()
            .title(match format {
                ExportFormat::Csv => "Export as CSV",
                ExportFormat::Json => "Export as JSON",
            })
            .modal(true)
            .initial_name(suggested)
            .default_filter(&filter)
            .filters(&filters)
            .build();
        let parent = self.window.clone();
        let toast_overlay = self.toast_overlay.clone();
        dialog.save(Some(&parent), gtk::gio::Cancellable::NONE, move |outcome| {
            let Ok(file) = outcome else { return };
            let Some(path) = file.path() else { return };
            let bytes = match format {
                ExportFormat::Csv => render_csv(&result),
                ExportFormat::Json => render_json(&result),
            };
            match std::fs::write(&path, bytes) {
                Ok(()) => toast_overlay.add_toast(adw::Toast::new(&format!("Exported to {}", path.display()))),
                Err(e) => toast_overlay.add_toast(adw::Toast::new(&format!("Export failed: {e}"))),
            }
        });
    }

    fn on_find_in_results(&self) {
        if !self.grid_search_bar.is_search_mode() {
            self.grid_search_bar.set_search_mode(true);
        }
        self.grid_search.grab_focus();
    }

    fn on_show_about(&self) {
        let dialog = adw::AboutDialog::builder()
            .application_name(crate::tr!("TablePro Linux"))
            .application_icon("com.tablepro.Linux")
            .developer_name(crate::tr!("TablePro Authors"))
            .version(env!("CARGO_PKG_VERSION"))
            .website("https://github.com/TableProApp/TablePro")
            .issue_url("https://github.com/TableProApp/TablePro/issues")
            .support_url("https://github.com/TableProApp/TablePro/discussions")
            .copyright(crate::tr!("© 2025–2026 TablePro Authors"))
            .license_type(gtk::License::Agpl30)
            .comments(crate::tr!(
                "A native Linux database client built with GTK4 + libadwaita."
            ))
            .build();
        dialog.set_developers(&["TablePro Authors https://github.com/TableProApp/TablePro"]);
        dialog.set_translator_credits(&crate::tr!("translator-credits"));
        dialog.present(Some(&self.window));
    }
}
