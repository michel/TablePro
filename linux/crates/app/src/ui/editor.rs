use relm4::adw::prelude::*;
use relm4::gtk::glib;
use relm4::prelude::*;
use relm4::{adw, gtk};
use sourceview5::prelude::*;
use tokio_util::sync::CancellationToken;

use tablepro_core::QueryResult;

use super::grid::build_column_view;
use crate::services::database_service;

pub struct SqlEditor {
    source_view: sourceview5::View,
    run_button: gtk::Button,
    cancel_button: gtk::Button,
    running_spinner: gtk::Spinner,
    results_holder: gtk::Box,
    status: gtk::Label,
    cancel_token: Option<CancellationToken>,
    schema_buffer: gtk::TextBuffer,
}

#[derive(Debug)]
pub enum SqlEditorInput {
    Run,
    Cancel,
    ShowResult(QueryResult, u128),
    ShowError(String),
    ShowCancelled,
    SetSchemaWords(Vec<String>),
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

                #[name = "cursor_info"]
                gtk::Label {
                    set_halign: gtk::Align::End,
                    add_css_class: "dim-label",
                    add_css_class: "monospace",
                    set_margin_end: 8,
                },

                #[name = "running_spinner"]
                gtk::Spinner {
                    set_visible: false,
                    set_spinning: true,
                    set_size_request: (20, 20),
                },

                #[name = "status"]
                gtk::Label {
                    set_halign: gtk::Align::End,
                    add_css_class: "dim-label",
                },

                #[name = "cancel_button"]
                gtk::Button {
                    set_label: &crate::tr!("Cancel"),
                    set_visible: false,
                    add_css_class: "destructive-action",
                    connect_clicked => SqlEditorInput::Cancel,
                },

                #[name = "run_button"]
                gtk::Button {
                    set_label: &crate::tr!("Run"),
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
        apply_editor_scheme(&widgets.source_view);
        let view_for_theme = widgets.source_view.clone();
        adw::StyleManager::default().connect_dark_notify(move |_| {
            apply_editor_scheme(&view_for_theme);
        });

        let font_size = crate::services::preferences::load().editor_font_size;
        apply_editor_font_size(&widgets.source_view, font_size);

        let schema_buffer = gtk::TextBuffer::new(None);
        schema_buffer.set_text(SQL_KEYWORDS);
        let provider = sourceview5::CompletionWords::new(Some("SQL"));
        provider.register(&schema_buffer);
        if let Ok(view_buffer) = widgets.source_view.buffer().downcast::<sourceview5::Buffer>() {
            provider.register(&view_buffer);
        }
        let completion = widgets.source_view.completion();
        completion.add_provider(&provider);

        let cursor_info = widgets.cursor_info.clone();
        let view_for_cursor = widgets.source_view.clone();
        let update_cursor = move || {
            let buffer = view_for_cursor.buffer();
            let mark = buffer.get_insert();
            let iter = buffer.iter_at_mark(&mark);
            let line = iter.line() + 1;
            let col = iter.line_offset() + 1;
            cursor_info.set_label(&format!("Ln {line}, Col {col}"));
        };
        update_cursor();
        widgets
            .source_view
            .buffer()
            .connect_cursor_position_notify(move |_| update_cursor());

        let run_shortcut = gtk::Shortcut::builder()
            .trigger(&gtk::ShortcutTrigger::parse_string("<Primary>Return").expect("valid trigger"))
            .action(&gtk::CallbackAction::new({
                let sender = sender.clone();
                move |_, _| {
                    sender.input(SqlEditorInput::Run);
                    glib::Propagation::Stop
                }
            }))
            .build();
        let controller = gtk::ShortcutController::new();
        controller.add_shortcut(run_shortcut);
        widgets.source_view.add_controller(controller);

        let drop_target = gtk::DropTarget::new(gtk::gio::File::static_type(), gtk::gdk::DragAction::COPY);
        let view_for_drop = widgets.source_view.clone();
        drop_target.connect_drop(move |_, value, _, _| {
            if let Ok(file) = value.get::<gtk::gio::File>()
                && let Some(path) = file.path()
                && let Ok(text) = std::fs::read_to_string(&path)
            {
                view_for_drop.buffer().set_text(&text);
                return true;
            }
            false
        });
        widgets.source_view.add_controller(drop_target);

        let model = SqlEditor {
            source_view: widgets.source_view.clone(),
            run_button: widgets.run_button.clone(),
            cancel_button: widgets.cancel_button.clone(),
            running_spinner: widgets.running_spinner.clone(),
            results_holder: widgets.results_holder.clone(),
            status: widgets.status.clone(),
            cancel_token: None,
            schema_buffer,
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
                    self.status.set_label(&crate::tr!("empty query"));
                    return;
                }

                let conn = match database_service::instance().active() {
                    Some(c) => c,
                    None => {
                        self.status.set_label(&crate::tr!("no active connection"));
                        return;
                    }
                };

                if let Some(prev) = self.cancel_token.take() {
                    prev.cancel();
                }
                let token = CancellationToken::new();
                self.cancel_token = Some(token.clone());

                self.run_button.set_sensitive(false);
                self.cancel_button.set_visible(true);
                self.running_spinner.set_visible(true);
                self.status.set_label(&crate::tr!("Running…"));
                clear_box(&self.results_holder);

                let started = std::time::Instant::now();
                let sender_clone = sender.clone();
                sender.command(move |_, shutdown| {
                    shutdown
                        .register(async move {
                            let statements = split_sql_statements(&trimmed);
                            let msg = tokio::select! {
                                biased;
                                _ = token.cancelled() => SqlEditorInput::ShowCancelled,
                                result = run_statements(conn, statements) => {
                                    let elapsed = started.elapsed();
                                    match result {
                                        Ok(query_result) => {
                                            tracing::info!(
                                                rows = query_result.rows.len(),
                                                elapsed_ms = elapsed.as_millis(),
                                                "query ok"
                                            );
                                            SqlEditorInput::ShowResult(query_result, elapsed.as_millis())
                                        }
                                        Err(e) => {
                                            tracing::warn!(error = %e, "query failed");
                                            SqlEditorInput::ShowError(e)
                                        }
                                    }
                                }
                            };
                            sender_clone.input(msg);
                        })
                        .drop_on_shutdown()
                });
            }

            SqlEditorInput::Cancel => {
                if let Some(token) = self.cancel_token.take() {
                    token.cancel();
                }
            }

            SqlEditorInput::ShowResult(result, elapsed_ms) => {
                self.cancel_token = None;
                self.run_button.set_sensitive(true);
                self.cancel_button.set_visible(false);
                self.running_spinner.set_visible(false);
                let n = result.rows.len().to_string();
                let ms = elapsed_ms.to_string();
                let label = if result.truncated {
                    crate::tr!("{n} row(s) in {ms} ms (truncated)")
                        .replace("{n}", &n)
                        .replace("{ms}", &ms)
                } else {
                    crate::tr!("{n} row(s) in {ms} ms")
                        .replace("{n}", &n)
                        .replace("{ms}", &ms)
                };
                self.status.set_label(&label);
                clear_box(&self.results_holder);
                if result.rows.is_empty() {
                    let placeholder = adw::StatusPage::builder()
                        .title(crate::tr!("No rows"))
                        .description(crate::tr!("Query returned no rows."))
                        .icon_name("view-grid-symbolic")
                        .vexpand(true)
                        .build();
                    self.results_holder.append(&placeholder);
                } else {
                    let (column_view, _selection, _filter) =
                        build_column_view(&result, &result.columns, "", None, None, None, None);
                    let scrolled = gtk::ScrolledWindow::builder()
                        .child(&column_view)
                        .hexpand(true)
                        .vexpand(true)
                        .build();
                    self.results_holder.append(&scrolled);
                }
            }

            SqlEditorInput::ShowError(msg) => {
                self.cancel_token = None;
                self.run_button.set_sensitive(true);
                self.cancel_button.set_visible(false);
                self.running_spinner.set_visible(false);
                self.status.set_label(&crate::tr!("error"));
                clear_box(&self.results_holder);
                let err_page = adw::StatusPage::builder()
                    .title(crate::tr!("Query failed"))
                    .description(&msg)
                    .icon_name("dialog-error-symbolic")
                    .vexpand(true)
                    .build();
                self.results_holder.append(&err_page);
            }

            SqlEditorInput::SetSchemaWords(words) => {
                let mut text = String::from(SQL_KEYWORDS);
                for w in &words {
                    text.push(' ');
                    text.push_str(w);
                }
                self.schema_buffer.set_text(&text);
            }

            SqlEditorInput::ShowCancelled => {
                self.cancel_token = None;
                self.run_button.set_sensitive(true);
                self.cancel_button.set_visible(false);
                self.running_spinner.set_visible(false);
                self.status.set_label(&crate::tr!("cancelled"));
                clear_box(&self.results_holder);
                let cancelled_page = adw::StatusPage::builder()
                    .title("Query cancelled")
                    .description("The running query was stopped.")
                    .icon_name("process-stop-symbolic")
                    .vexpand(true)
                    .build();
                self.results_holder.append(&cancelled_page);
            }
        }
    }
}

fn clear_box(b: &gtk::Box) {
    while let Some(child) = b.first_child() {
        b.remove(&child);
    }
}

async fn run_statements(
    conn: std::sync::Arc<dyn tablepro_core::Connection>,
    statements: Vec<String>,
) -> Result<QueryResult, String> {
    if statements.is_empty() {
        return Ok(QueryResult {
            columns: Vec::new(),
            rows: Vec::new(),
            truncated: false,
        });
    }
    let last_idx = statements.len() - 1;
    let mut last_result = QueryResult {
        columns: Vec::new(),
        rows: Vec::new(),
        truncated: false,
    };
    for (i, sql) in statements.into_iter().enumerate() {
        if i == last_idx {
            last_result = conn
                .query(&sql)
                .await
                .map_err(|e| super::error_text::driver_message(&e))?;
        } else {
            conn.query(&sql)
                .await
                .map_err(|e| super::error_text::driver_message(&e))?;
        }
    }
    Ok(last_result)
}

fn split_sql_statements(sql: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut chars = sql.chars().peekable();
    let mut in_single = false;
    let mut in_double = false;
    let mut in_line_comment = false;
    let mut in_block_comment = false;
    while let Some(c) = chars.next() {
        if in_line_comment {
            current.push(c);
            if c == '\n' {
                in_line_comment = false;
            }
            continue;
        }
        if in_block_comment {
            current.push(c);
            if c == '*' && chars.peek() == Some(&'/') {
                current.push(chars.next().unwrap());
                in_block_comment = false;
            }
            continue;
        }
        if !in_single && !in_double {
            if c == '-' && chars.peek() == Some(&'-') {
                current.push(c);
                current.push(chars.next().unwrap());
                in_line_comment = true;
                continue;
            }
            if c == '/' && chars.peek() == Some(&'*') {
                current.push(c);
                current.push(chars.next().unwrap());
                in_block_comment = true;
                continue;
            }
        }
        match c {
            '\'' if !in_double => in_single = !in_single,
            '"' if !in_single => in_double = !in_double,
            ';' if !in_single && !in_double => {
                let trimmed = current.trim().to_string();
                if !trimmed.is_empty() {
                    out.push(trimmed);
                }
                current.clear();
                continue;
            }
            _ => {}
        }
        current.push(c);
    }
    let trimmed = current.trim().to_string();
    if !trimmed.is_empty() {
        out.push(trimmed);
    }
    out
}

const SQL_KEYWORDS: &str = "\
SELECT FROM WHERE INSERT INTO VALUES UPDATE SET DELETE \
JOIN INNER LEFT RIGHT FULL OUTER ON USING UNION INTERSECT EXCEPT \
GROUP BY ORDER HAVING LIMIT OFFSET DISTINCT ALL AS WITH \
CREATE TABLE INDEX VIEW DROP ALTER TRUNCATE \
PRIMARY KEY FOREIGN REFERENCES UNIQUE NOT NULL DEFAULT CHECK \
AND OR IS LIKE IN BETWEEN EXISTS ANY \
COUNT SUM AVG MIN MAX CASE WHEN THEN ELSE END \
TRUE FALSE ASC DESC RETURNING";

fn apply_editor_scheme(view: &sourceview5::View) {
    let scheme_name = if adw::StyleManager::default().is_dark() {
        "Adwaita-dark"
    } else {
        "Adwaita"
    };
    if let Some(scheme) = sourceview5::StyleSchemeManager::default().scheme(scheme_name)
        && let Ok(buffer) = view.buffer().downcast::<sourceview5::Buffer>()
    {
        buffer.set_style_scheme(Some(&scheme));
    }
}

fn apply_editor_font_size(view: &sourceview5::View, font_size: u32) {
    let css = format!("textview, textview text {{ font-size: {font_size}pt; }}");
    let provider = gtk::CssProvider::new();
    provider.load_from_string(&css);
    #[allow(deprecated)]
    view.style_context()
        .add_provider(&provider, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);
}

#[cfg(test)]
mod tests {
    use super::split_sql_statements;

    #[test]
    fn splits_on_top_level_semicolons() {
        let s = split_sql_statements("SELECT 1; SELECT 2");
        assert_eq!(s, vec!["SELECT 1".to_string(), "SELECT 2".to_string()]);
    }

    #[test]
    fn ignores_semicolons_in_string_literals() {
        let s = split_sql_statements("INSERT INTO t VALUES ('a;b'); SELECT 1");
        assert_eq!(s.len(), 2);
        assert!(s[0].contains("'a;b'"));
    }

    #[test]
    fn ignores_semicolons_in_double_quotes() {
        let s = split_sql_statements("SELECT \"col;name\" FROM t; SELECT 2");
        assert_eq!(s.len(), 2);
    }

    #[test]
    fn ignores_semicolons_in_line_comment() {
        let s = split_sql_statements("SELECT 1 -- comment ; here\n; SELECT 2");
        assert_eq!(s.len(), 2);
    }

    #[test]
    fn ignores_semicolons_in_block_comment() {
        let s = split_sql_statements("SELECT 1 /* hi ; bye */; SELECT 2");
        assert_eq!(s.len(), 2);
    }

    #[test]
    fn trailing_semicolon_does_not_create_empty_statement() {
        let s = split_sql_statements("SELECT 1;");
        assert_eq!(s, vec!["SELECT 1".to_string()]);
    }

    #[test]
    fn empty_input_returns_empty() {
        assert!(split_sql_statements("").is_empty());
        assert!(split_sql_statements("   \n\t  ").is_empty());
    }
}
