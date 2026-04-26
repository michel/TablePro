use relm4::adw::prelude::*;
use relm4::{Component, ComponentController, ComponentSender, adw};

use tablepro_core::Value;
use tablepro_core::sql_dialect::{placeholder_for, quote_ident};

use crate::services::database_service;
use crate::ui::edit_dialog::{EditDialog, EditDialogInit, EditDialogOutput};
use crate::ui::error_text;
use crate::ui::insert_dialog::{InsertDialog, InsertDialogInit, InsertDialogOutput};

use super::{
    App, AppMsg, UndoBatch, build_insert_for_row, execute_many_then_refetch, execute_then_refetch, preview_pk,
    selected_positions, value_to_sql_literal,
};

impl App {
    pub(super) fn set_row_op_in_flight(&self, in_flight: bool) {
        self.row_op_spinner.set_visible(in_flight);
        if in_flight {
            self.row_op_spinner.start();
        } else {
            self.row_op_spinner.stop();
        }
    }

    pub(super) fn on_insert_row(&mut self, sender: ComponentSender<Self>) {
        let Some(table) = self.current_table.clone() else {
            return;
        };
        if self.current_columns.is_empty() {
            return;
        }
        let driver_id = self.driver_id().to_string();
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

    pub(super) fn on_insert_committed(&mut self, sender: ComponentSender<Self>) {
        self.insert_dialog = None;
        self.show_toast(&crate::tr!("Row inserted"));
        self.fetch_current_page(sender);
    }

    pub(super) fn on_edit_selected_row(&mut self, sender: ComponentSender<Self>) {
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
            self.show_error_alert(
                &crate::tr!("Cannot edit"),
                &crate::tr!("Select exactly one row to edit."),
            );
            return;
        }
        let position = positions[0] as usize;
        if position >= result.rows.len() {
            return;
        }
        let row = result.rows[position].clone();
        let driver_id = self.driver_id().to_string();
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

    pub(super) fn on_edit_committed(&mut self, sender: ComponentSender<Self>) {
        self.edit_dialog = None;
        self.show_toast(&crate::tr!("Row updated"));
        self.fetch_current_page(sender);
    }

    pub(super) fn on_delete_selected_row(&mut self, sender: ComponentSender<Self>) {
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
                &crate::tr!("Cannot delete"),
                &error_text::build_sql_message(&tablepro_core::sql_dialect::BuildSqlError::NoPrimaryKey),
            );
            return;
        }
        let driver_id = self.driver_id().to_string();

        let preview = if positions.len() == 1 {
            let row = &result.rows[positions[0] as usize];
            crate::tr!("Delete row where {pk}?").replace("{pk}", &preview_pk(&self.current_columns, &pk_indexes, row))
        } else {
            crate::tr!("Delete {n} rows?").replace("{n}", &positions.len().to_string())
        };
        let confirm_label = if positions.len() == 1 {
            crate::tr!("Delete")
        } else {
            crate::tr!("Delete {n}").replace("{n}", &positions.len().to_string())
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

    pub(super) fn on_cell_edited(
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
        let (sql, params) = match tablepro_core::sql_dialect::build_single_cell_update(
            &driver_id,
            &table,
            &self.current_columns,
            &row,
            col_index,
            value,
        ) {
            Ok(t) => t,
            Err(e) => {
                self.show_error_alert(&crate::tr!("Cannot update cell"), &error_text::build_sql_message(&e));
                return;
            }
        };
        let undo = tablepro_core::sql_dialect::build_single_cell_update(
            &driver_id,
            &table,
            &self.current_columns,
            &row,
            col_index,
            original_value,
        )
        .ok()
        .map(|(s, p)| UndoBatch {
            label: crate::tr!("Cell updated"),
            statements: vec![(s, p)],
        });
        self.set_row_op_in_flight(true);
        execute_then_refetch(sender, sql, params, undo);
    }

    pub(super) fn refresh_crud_buttons(&self) {
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
    pub(super) fn confirm_and_execute_many(
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
            crate::tr!("1 row deleted")
        } else {
            crate::tr!("{n} rows deleted").replace("{n}", &positions.len().to_string())
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
            crate::tr!("Delete row?")
        } else {
            crate::tr!("Delete {n} rows?").replace("{n}", &positions.len().to_string())
        };
        let dialog = adw::AlertDialog::new(Some(&alert_title), Some(preview));
        dialog.add_response("cancel", &crate::tr!("Cancel"));
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

    pub(super) fn on_copy_to_clipboard(&self, text: String) {
        self.window.clipboard().set_text(&text);
        self.show_toast(&crate::tr!("Copied to clipboard"));
    }

    pub(super) fn on_set_cell_null(
        &mut self,
        table: String,
        row_position: u32,
        col_index: usize,
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
        let original_value = row[col_index].clone();
        let (sql, params) = match tablepro_core::sql_dialect::build_single_cell_update(
            &driver_id,
            &table,
            &self.current_columns,
            &row,
            col_index,
            Value::Null,
        ) {
            Ok(t) => t,
            Err(e) => {
                self.show_error_alert(&crate::tr!("Cannot set NULL"), &error_text::build_sql_message(&e));
                return;
            }
        };
        let undo = tablepro_core::sql_dialect::build_single_cell_update(
            &driver_id,
            &table,
            &self.current_columns,
            &row,
            col_index,
            original_value,
        )
        .ok()
        .map(|(s, p)| UndoBatch {
            label: crate::tr!("Cell cleared"),
            statements: vec![(s, p)],
        });
        self.set_row_op_in_flight(true);
        execute_then_refetch(sender, sql, params, undo);
    }

    pub(super) fn on_delete_row_at(&mut self, table: String, row_position: u32, sender: ComponentSender<Self>) {
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
                &crate::tr!("Cannot delete"),
                &error_text::build_sql_message(&tablepro_core::sql_dialect::BuildSqlError::NoPrimaryKey),
            );
            return;
        }
        let driver_id = self.driver_id().to_string();
        let preview = result
            .rows
            .get(row_position as usize)
            .map(|r| {
                crate::tr!("Delete row where {pk}?").replace("{pk}", &preview_pk(&self.current_columns, &pk_indexes, r))
            })
            .unwrap_or_else(|| crate::tr!("Delete row?"));
        self.confirm_and_execute_many(
            sender,
            &table,
            &driver_id,
            &pk_indexes,
            &[row_position],
            &result.rows,
            &preview,
            &crate::tr!("Delete"),
        );
    }

    pub(super) fn on_copy_row_as_insert(&self, row_position: u32) {
        let Some(result) = self.current_result.as_ref() else {
            return;
        };
        let Some(table) = self.current_table.as_ref() else {
            return;
        };
        let Some(row) = result.rows.get(row_position as usize) else {
            return;
        };
        let driver_id = self.driver_id().to_string();
        let cols: Vec<String> = self
            .current_columns
            .iter()
            .map(|c| tablepro_core::sql_dialect::quote_ident(&driver_id, &c.name))
            .collect();
        let values: Vec<String> = row.iter().map(value_to_sql_literal).collect();
        let sql = format!(
            "INSERT INTO {} ({}) VALUES ({});",
            tablepro_core::sql_dialect::quote_ident(&driver_id, table),
            cols.join(", "),
            values.join(", "),
        );
        self.window.clipboard().set_text(&sql);
        self.show_toast(&crate::tr!("INSERT statement copied"));
    }
}
