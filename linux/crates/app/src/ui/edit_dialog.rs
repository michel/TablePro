use relm4::adw::prelude::*;
use relm4::prelude::*;
use relm4::{adw, gtk};

use tablepro_core::{ColumnInfo, Value};

use crate::runtime;
use crate::services::connection_holder;
use crate::sql_dialect::build_full_row_update;

pub struct EditDialog {
    table: String,
    driver_id: String,
    columns: Vec<ColumnInfo>,
    original: Vec<Value>,
    rows: Vec<adw::EntryRow>,
    submit: gtk::Button,
    status: gtk::Label,
}

pub struct EditDialogInit {
    pub table: String,
    pub columns: Vec<ColumnInfo>,
    pub driver_id: String,
    pub row: Vec<Value>,
}

#[derive(Debug)]
pub enum EditDialogInput {
    Submit,
    Closed,
    ShowError(String),
    Updated,
}

#[derive(Debug)]
pub enum EditDialogOutput {
    Updated,
}

#[relm4::component(pub)]
impl SimpleComponent for EditDialog {
    type Init = EditDialogInit;
    type Input = EditDialogInput;
    type Output = EditDialogOutput;

    view! {
        adw::Dialog {
            set_content_width: 480,
            connect_closed => EditDialogInput::Closed,

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

                    #[name = "group"]
                    adw::PreferencesGroup {},

                    append: &model.submit,
                    append: &model.status,
                },
            },
        }
    }

    fn init(init: Self::Init, root: Self::Root, sender: ComponentSender<Self>) -> ComponentParts<Self> {
        let mut rows = Vec::with_capacity(init.columns.len());
        for (col, value) in init.columns.iter().zip(init.row.iter()) {
            let title = if col.primary_key {
                format!("{} (PK)", col.name)
            } else if col.nullable {
                col.name.clone()
            } else {
                format!("{} *", col.name)
            };
            let row = adw::EntryRow::builder().title(&title).build();
            row.set_text(&value_to_text(value));
            if col.primary_key {
                row.set_editable(false);
            }
            rows.push(row);
        }

        let submit = gtk::Button::builder()
            .label("Save")
            .halign(gtk::Align::End)
            .margin_top(12)
            .build();
        submit.add_css_class("suggested-action");
        submit.add_css_class("pill");
        let sender_for_submit = sender.clone();
        submit.connect_clicked(move |_| sender_for_submit.input(EditDialogInput::Submit));

        let status = gtk::Label::builder().wrap(true).xalign(0.0).margin_top(8).build();
        status.add_css_class("dim-label");

        root.set_title(&format!("Edit row in {}", init.table));

        let model = EditDialog {
            table: init.table,
            driver_id: init.driver_id,
            columns: init.columns,
            original: init.row,
            rows,
            submit,
            status,
        };
        let widgets = view_output!();
        for row in &model.rows {
            widgets.group.add(row);
        }
        ComponentParts { model, widgets }
    }

    fn update(&mut self, msg: Self::Input, sender: ComponentSender<Self>) {
        match msg {
            EditDialogInput::Submit => {
                let Some(conn) = connection_holder::get() else {
                    self.status.set_label("no active connection");
                    return;
                };

                let new_values: Vec<Value> = self
                    .columns
                    .iter()
                    .zip(self.rows.iter())
                    .map(|(col, row)| {
                        let entered = row.text().to_string();
                        if entered.is_empty() && col.nullable {
                            Value::Null
                        } else {
                            Value::Text(entered)
                        }
                    })
                    .collect();

                let (sql, params) = match build_full_row_update(
                    &self.driver_id,
                    &self.table,
                    &self.columns,
                    &self.original,
                    &new_values,
                ) {
                    Ok(t) => t,
                    Err(e) => {
                        self.status.set_label(&e.to_string());
                        return;
                    }
                };

                self.submit.set_sensitive(false);
                self.status.set_label("Saving…");

                let sender_clone = sender.clone();
                let (tx, rx) = async_channel::bounded(1);
                runtime::handle().spawn(async move {
                    let result = conn.execute_params(&sql, &params).await;
                    let _ = tx.send(result).await;
                });
                glib::spawn_future_local(async move {
                    if let Ok(result) = rx.recv().await {
                        match result {
                            Ok(_) => sender_clone.input(EditDialogInput::Updated),
                            Err(e) => sender_clone.input(EditDialogInput::ShowError(format!("{e}"))),
                        }
                    }
                });
            }

            EditDialogInput::ShowError(e) => {
                self.submit.set_sensitive(true);
                self.status.set_label(&e);
            }

            EditDialogInput::Updated => {
                let _ = sender.output(EditDialogOutput::Updated);
            }

            EditDialogInput::Closed => {}
        }
    }
}

fn value_to_text(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::Float(f) => f.to_string(),
        Value::Text(s) => s.clone(),
        Value::Bytes(b) => format!("<{} bytes>", b.len()),
    }
}
