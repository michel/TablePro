use relm4::adw::prelude::*;
use relm4::prelude::*;
use relm4::{adw, gtk};
use sourceview5::prelude::*;

use tablepro_core::QueryResult;

use super::grid::build_column_view;
use crate::services::connection_holder;

pub struct SqlEditor {
    source_view: sourceview5::View,
    run_button: gtk::Button,
    results_holder: gtk::Box,
    status: gtk::Label,
}

#[derive(Debug)]
pub enum SqlEditorInput {
    Run,
    ShowResult(QueryResult),
    ShowError(String),
}

#[relm4::component(pub)]
impl SimpleComponent for SqlEditor {
    type Init = ();
    type Input = SqlEditorInput;
    type Output = ();

    view! {
        gtk::Box {
            set_orientation: gtk::Orientation::Vertical,

            gtk::Box {
                set_orientation: gtk::Orientation::Horizontal,
                set_spacing: 8,
                set_margin_top: 8,
                set_margin_bottom: 8,
                set_margin_start: 8,
                set_margin_end: 8,

                gtk::Label {
                    set_label: "SQL",
                    set_halign: gtk::Align::Start,
                    set_hexpand: true,
                    add_css_class: "heading",
                },

                #[name = "status"]
                gtk::Label {
                    set_halign: gtk::Align::End,
                    add_css_class: "dim-label",
                },

                #[name = "run_button"]
                gtk::Button {
                    set_label: "Run",
                    add_css_class: "suggested-action",
                    connect_clicked => SqlEditorInput::Run,
                },
            },

            gtk::Paned {
                set_orientation: gtk::Orientation::Vertical,
                set_position: 280,
                set_vexpand: true,
                set_hexpand: true,

                #[wrap(Some)]
                set_start_child = &gtk::ScrolledWindow {
                    set_min_content_height: 200,

                    #[wrap(Some)]
                    #[name = "source_view"]
                    set_child = &sourceview5::View {
                        set_show_line_numbers: true,
                        set_monospace: true,
                        set_auto_indent: true,
                        set_highlight_current_line: true,
                        set_tab_width: 4,
                        set_top_margin: 8,
                        set_bottom_margin: 8,
                        set_left_margin: 8,
                        set_right_margin: 8,
                    },
                },

                #[wrap(Some)]
                #[name = "results_holder"]
                set_end_child = &gtk::Box {
                    set_orientation: gtk::Orientation::Vertical,
                },
            },
        }
    }

    fn init(_: Self::Init, _root: Self::Root, sender: ComponentSender<Self>) -> ComponentParts<Self> {
        let widgets = view_output!();

        let lang_manager = sourceview5::LanguageManager::default();
        if let Some(lang) = lang_manager.language("sql") {
            let buffer = sourceview5::Buffer::with_language(&lang);
            buffer.set_text("SELECT 1;");
            widgets.source_view.set_buffer(Some(&buffer));
        }
        if let Some(scheme) = sourceview5::StyleSchemeManager::default().scheme("Adwaita-dark")
            && let Ok(buffer) = widgets.source_view.buffer().downcast::<sourceview5::Buffer>()
        {
            buffer.set_style_scheme(Some(&scheme));
        }

        let model = SqlEditor {
            source_view: widgets.source_view.clone(),
            run_button: widgets.run_button.clone(),
            results_holder: widgets.results_holder.clone(),
            status: widgets.status.clone(),
        };
        let _ = sender;
        ComponentParts { model, widgets }
    }

    fn update(&mut self, msg: Self::Input, sender: ComponentSender<Self>) {
        match msg {
            SqlEditorInput::Run => {
                let buffer = self.source_view.buffer();
                let (start, end) = buffer.bounds();
                let sql = buffer.text(&start, &end, false).to_string();
                let trimmed = sql.trim().to_string();
                if trimmed.is_empty() {
                    self.status.set_label("empty query");
                    return;
                }

                let conn = match connection_holder::get() {
                    Some(c) => c,
                    None => {
                        self.status.set_label("no active connection");
                        return;
                    }
                };

                self.run_button.set_sensitive(false);
                self.status.set_label("Running…");
                clear_box(&self.results_holder);

                let started = std::time::Instant::now();
                let sender_clone = sender.clone();
                sender.command(move |_, shutdown| {
                    shutdown
                        .register(async move {
                            let result = conn.query(&trimmed).await;
                            let elapsed = started.elapsed();
                            match result {
                                Ok(query_result) => {
                                    tracing::info!(
                                        rows = query_result.rows.len(),
                                        elapsed_ms = elapsed.as_millis(),
                                        "query ok"
                                    );
                                    sender_clone.input(SqlEditorInput::ShowResult(query_result));
                                }
                                Err(e) => {
                                    tracing::warn!(error = %e, "query failed");
                                    sender_clone
                                        .input(SqlEditorInput::ShowError(super::error_text::driver_message(&e)));
                                }
                            }
                        })
                        .drop_on_shutdown()
                });
            }

            SqlEditorInput::ShowResult(result) => {
                self.run_button.set_sensitive(true);
                let label = if result.truncated {
                    format!("{} row(s) (truncated)", result.rows.len())
                } else {
                    format!("{} row(s)", result.rows.len())
                };
                self.status.set_label(&label);
                clear_box(&self.results_holder);
                if result.rows.is_empty() {
                    let placeholder = adw::StatusPage::builder()
                        .title("No rows")
                        .description("Query returned no rows.")
                        .icon_name("view-grid-symbolic")
                        .vexpand(true)
                        .build();
                    self.results_holder.append(&placeholder);
                } else {
                    let (column_view, _selection) = build_column_view(&result, &result.columns, "", None);
                    let scrolled = gtk::ScrolledWindow::builder()
                        .child(&column_view)
                        .hexpand(true)
                        .vexpand(true)
                        .build();
                    self.results_holder.append(&scrolled);
                }
            }

            SqlEditorInput::ShowError(msg) => {
                self.run_button.set_sensitive(true);
                self.status.set_label("error");
                clear_box(&self.results_holder);
                let err_page = adw::StatusPage::builder()
                    .title("Query failed")
                    .description(&msg)
                    .icon_name("dialog-error-symbolic")
                    .vexpand(true)
                    .build();
                self.results_holder.append(&err_page);
            }
        }
    }
}

fn clear_box(b: &gtk::Box) {
    while let Some(child) = b.first_child() {
        b.remove(&child);
    }
}
