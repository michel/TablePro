use relm4::adw::prelude::*;
use relm4::gtk::gio;
use relm4::{ComponentSender, gtk};

use tablepro_core::{ColumnInfo, QueryResult};

use crate::services::database_service;
use crate::ui::editor::update_schema_buffer;
use crate::ui::grid::build_column_view;

use super::{App, AppMsg, ExportFormat, StatusKind, clear_box, qualified_label, render_csv, render_json};

impl App {
    pub(super) fn on_select_table(&mut self, schema: Option<String>, name: String, sender: ComponentSender<Self>) {
        self.current_table = Some(name.clone());
        self.current_schema = schema.clone();
        self.current_offset = 0;
        self.current_columns.clear();
        self.current_sort = None;
        self.current_total_rows = None;
        self.refresh_window_title();
        let label = qualified_label(schema.as_deref(), &name);
        self.set_loading_page(
            &crate::tr!("Loading…"),
            &crate::tr!("Fetching rows from {table}").replace("{table}", &label),
        );
        self.fetch_current_page(sender.clone());
        self.fetch_columns(schema.clone(), name.clone(), sender.clone());
        self.fetch_row_count(schema, name, sender);
    }

    pub(super) fn fetch_row_count(&self, schema: Option<String>, table: String, sender: ComponentSender<Self>) {
        let Some(conn) = database_service::instance().active() else {
            return;
        };
        let driver_id = self.driver_id().to_string();
        let table_for_async = table.clone();
        let sender_clone = sender.clone();
        sender.command(move |_, shutdown| {
            shutdown
                .register(async move {
                    let qualified = match schema {
                        Some(s) => format!(
                            "{}.{}",
                            tablepro_core::sql_dialect::quote_ident(&driver_id, &s),
                            tablepro_core::sql_dialect::quote_ident(&driver_id, &table_for_async)
                        ),
                        None => tablepro_core::sql_dialect::quote_ident(&driver_id, &table_for_async),
                    };
                    let sql = format!("SELECT COUNT(*) FROM {qualified}");
                    if let Ok(qr) = conn.query(&sql).await
                        && let Some(row) = qr.rows.first()
                        && let Some(value) = row.first()
                    {
                        let count = match value {
                            tablepro_core::Value::Int(i) if *i >= 0 => Some(*i as u64),
                            tablepro_core::Value::Float(f) if *f >= 0.0 && f.is_finite() => Some(*f as u64),
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

    pub(super) fn on_columns_loaded(&mut self, table: String, columns: Vec<ColumnInfo>, sender: ComponentSender<Self>) {
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

    pub(super) fn push_schema_words(&self) {
        let mut words: Vec<String> = self.table_names.clone();
        for c in &self.current_columns {
            words.push(c.name.clone());
        }
        words.sort_unstable();
        words.dedup();
        update_schema_buffer(&self.schema_buffer, &words);
    }

    pub(super) fn on_prev_page(&mut self, sender: ComponentSender<Self>) {
        if self.current_offset >= self.page_size {
            self.current_offset -= self.page_size;
            self.fetch_current_page(sender);
        }
    }

    pub(super) fn on_next_page(&mut self, sender: ComponentSender<Self>) {
        self.current_offset += self.page_size;
        self.fetch_current_page(sender);
    }

    pub(super) fn on_sort_changed(&mut self, col_idx: usize, sender: ComponentSender<Self>) {
        let next = match self.current_sort {
            Some((c, asc)) if c == col_idx => Some((c, !asc)),
            _ => Some((col_idx, true)),
        };
        self.current_sort = next;
        self.current_offset = 0;
        self.fetch_current_page(sender);
    }

    pub(super) fn on_page_size_changed(&mut self, size: u64, sender: ComponentSender<Self>) {
        if self.page_size == size {
            return;
        }
        self.page_size = size;
        self.current_offset = 0;
        self.fetch_current_page(sender);
    }

    pub(super) fn on_row_count_loaded(&mut self, table: String, count: u64) {
        if self.current_table.as_deref() != Some(&table) {
            return;
        }
        self.current_total_rows = Some(count);
        self.update_paginator_label();
    }

    pub(super) fn update_paginator_label(&self) {
        let Some(result) = self.current_result.as_ref() else {
            self.paginator_label.set_label("");
            return;
        };
        let n_rows = result.rows.len();
        if n_rows == 0 {
            self.paginator_label
                .set_label(&crate::tr!("No rows at offset {n}").replace("{n}", &self.current_offset.to_string()));
            return;
        }
        let start = self.current_offset + 1;
        let end = self.current_offset + n_rows as u64;
        let label = match self.current_total_rows {
            Some(total) => crate::tr!("Rows {start} – {end} of {total}")
                .replace("{start}", &start.to_string())
                .replace("{end}", &end.to_string())
                .replace("{total}", &total.to_string()),
            None => crate::tr!("Rows {start} – {end}")
                .replace("{start}", &start.to_string())
                .replace("{end}", &end.to_string()),
        };
        self.paginator_label.set_label(&label);
    }

    pub(super) fn on_rows_loaded(&mut self, table: String, offset: u64, result: QueryResult) {
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
            Some(self.grid_sender.clone())
        };
        let (column_view, selection, filter_setter) = build_column_view(
            &result,
            &self.current_columns,
            &table,
            edit_sender,
            self.current_sort,
            Some(self.grid_sender.clone()),
            database_service::instance().active_id(),
        );
        if let Some(prev) = self.grid_search_handler.take() {
            self.grid_search.disconnect(prev);
        }
        let setter = filter_setter.clone();
        let id = self.grid_search.connect_search_changed(move |entry| {
            setter(&entry.text());
        });
        self.grid_search_handler = Some(id);
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

    pub(super) fn on_load_failed(&self, msg: String) {
        tracing::warn!(error = %msg, "load failed");
        self.set_row_op_in_flight(false);
        self.set_status_page(StatusKind::Error, &crate::tr!("Failed"), &msg);
    }

    pub(super) fn fetch_current_page(&self, sender: ComponentSender<App>) {
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
        let driver_id = self.driver_id().to_string();
        let order_by = self.current_sort.and_then(|(idx, asc)| {
            self.current_columns.get(idx).map(|c| {
                let name = tablepro_core::sql_dialect::quote_ident(&driver_id, &c.name);
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
                                    tablepro_core::sql_dialect::quote_ident(&driver_id, s),
                                    tablepro_core::sql_dialect::quote_ident(&driver_id, &table)
                                ),
                                None => tablepro_core::sql_dialect::quote_ident(&driver_id, &table),
                            };
                            let sql =
                                format!("SELECT * FROM {qualified} ORDER BY {order} LIMIT {limit} OFFSET {offset}");
                            conn.query(&sql).await
                        }
                        None => conn.fetch_rows(schema.as_deref(), &table, offset, limit).await,
                    };
                    match result {
                        Ok(query_result) => sender_clone.input(AppMsg::RowsLoaded(table, offset, query_result)),
                        Err(e) => sender_clone.input(AppMsg::LoadFailed(crate::ui::error_text::driver_message(&e))),
                    }
                })
                .drop_on_shutdown()
        });
    }

    pub(super) fn fetch_columns(&self, schema: Option<String>, table: String, sender: ComponentSender<App>) {
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

    pub(super) fn on_export(&self, format: ExportFormat) {
        let Some(result) = self.current_result.clone() else {
            self.show_toast(&crate::tr!("Nothing to export"));
            return;
        };
        let suggested = match format {
            ExportFormat::Csv => "table.csv",
            ExportFormat::Json => "table.json",
        };
        let filter = gtk::FileFilter::new();
        match format {
            ExportFormat::Csv => {
                filter.set_name(Some(&crate::tr!("CSV files")));
                filter.add_mime_type("text/csv");
                filter.add_suffix("csv");
            }
            ExportFormat::Json => {
                filter.set_name(Some(&crate::tr!("JSON files")));
                filter.add_mime_type("application/json");
                filter.add_suffix("json");
            }
        };
        let filters = gio::ListStore::new::<gtk::FileFilter>();
        filters.append(&filter);
        let dialog = gtk::FileDialog::builder()
            .title(match format {
                ExportFormat::Csv => crate::tr!("Export as CSV"),
                ExportFormat::Json => crate::tr!("Export as JSON"),
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
                Ok(()) => toast_overlay.add_toast(relm4::adw::Toast::new(
                    &crate::tr!("Exported to {path}").replace("{path}", &path.display().to_string()),
                )),
                Err(e) => toast_overlay.add_toast(relm4::adw::Toast::new(
                    &crate::tr!("Export failed: {error}").replace("{error}", &e.to_string()),
                )),
            }
        });
    }

    pub(super) fn on_find_in_results(&self) {
        if !self.grid_search_bar.is_search_mode() {
            self.grid_search_bar.set_search_mode(true);
        }
        self.grid_search.grab_focus();
    }
}
