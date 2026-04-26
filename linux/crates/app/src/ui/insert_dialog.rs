use relm4::adw::prelude::*;
use relm4::prelude::*;
use relm4::{adw, gtk};

use tablepro_core::{ColumnInfo, Value};

use crate::services::connection_holder;
use crate::sql_dialect::{placeholder_for, quote_ident};

pub struct InsertDialog {
    table: String,
    driver_id: String,
    columns: Vec<ColumnInfo>,
    rows: Vec<adw::EntryRow>,
    submit: gtk::Button,
    status: gtk::Label,
}

pub struct InsertDialogInit {
    pub table: String,
    pub columns: Vec<ColumnInfo>,
    pub driver_id: String,
}

#[derive(Debug)]
pub enum InsertDialogInput {
    Submit,
    Closed,
    ShowError(String),
    Inserted,
}

#[derive(Debug)]
pub enum InsertDialogOutput {
    Inserted,
}

#[relm4::component(pub)]
impl SimpleComponent for InsertDialog {
    type Init = InsertDialogInit;
    type Input = InsertDialogInput;
    type Output = InsertDialogOutput;

    view! {
        adw::Dialog {
            set_content_width: 480,
            connect_closed => InsertDialogInput::Closed,

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
        for col in &init.columns {
            let title = if col.nullable {
                col.name.clone()
            } else {
                format!("{} *", col.name)
            };
            let row = adw::EntryRow::builder().title(&title).build();
            rows.push(row);
        }

        let submit = gtk::Button::builder()
            .label("Insert")
            .halign(gtk::Align::End)
            .margin_top(12)
            .build();
        submit.add_css_class("suggested-action");
        submit.add_css_class("pill");
        let sender_for_submit = sender.clone();
        submit.connect_clicked(move |_| sender_for_submit.input(InsertDialogInput::Submit));

        let status = gtk::Label::builder().wrap(true).xalign(0.0).margin_top(8).build();
        status.add_css_class("dim-label");

        root.set_title(&format!("Insert into {}", init.table));

        let model = InsertDialog {
            table: init.table,
            driver_id: init.driver_id,
            columns: init.columns,
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
            InsertDialogInput::Submit => {
                let Some(conn) = connection_holder::get() else {
                    self.status.set_label("no active connection");
                    return;
                };
                let cols: Vec<String> = self
                    .columns
                    .iter()
                    .map(|c| quote_ident(&self.driver_id, &c.name))
                    .collect();
                let placeholders: Vec<String> = (0..self.columns.len())
                    .map(|i| placeholder_for(&self.driver_id, i))
                    .collect();
                let params: Vec<Value> = self
                    .rows
                    .iter()
                    .zip(self.columns.iter())
                    .map(|(row, col)| {
                        let text = row.text().to_string();
                        if text.is_empty() && col.nullable {
                            Value::Null
                        } else {
                            Value::Text(text)
                        }
                    })
                    .collect();
                let sql = format!(
                    "INSERT INTO {} ({}) VALUES ({})",
                    quote_ident(&self.driver_id, &self.table),
                    cols.join(", "),
                    placeholders.join(", "),
                );

                self.submit.set_sensitive(false);
                self.status.set_label("Inserting…");

                let sender_clone = sender.clone();
                sender.command(move |_, shutdown| {
                    shutdown
                        .register(async move {
                            match conn.execute_params(&sql, &params).await {
                                Ok(_) => sender_clone.input(InsertDialogInput::Inserted),
                                Err(e) => sender_clone
                                    .input(InsertDialogInput::ShowError(super::error_text::driver_message(&e))),
                            }
                        })
                        .drop_on_shutdown()
                });
            }

            InsertDialogInput::ShowError(e) => {
                self.submit.set_sensitive(true);
                self.status.set_label(&e);
            }

            InsertDialogInput::Inserted => {
                let _ = sender.output(InsertDialogOutput::Inserted);
            }

            InsertDialogInput::Closed => {}
        }
    }
}
