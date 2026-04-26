use relm4::adw::prelude::*;
use relm4::{ComponentSender, adw, gtk};

use super::{App, AppMsg, UndoBatch, build_shortcuts_window};

impl App {
    pub(super) fn show_welcome_page(&self, sender: ComponentSender<Self>) {
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
            new_btn.grab_focus();
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
            .valign(gtk::Align::Center)
            .build();
        outer.set_size_request(560, -1);

        let group = adw::PreferencesGroup::builder()
            .title(crate::tr!("Saved connections"))
            .build();
        let header_new_btn = gtk::Button::builder()
            .icon_name("list-add-symbolic")
            .tooltip_text(crate::tr!("New connection"))
            .valign(gtk::Align::Center)
            .build();
        header_new_btn.add_css_class("flat");
        let s_header = sender.clone();
        header_new_btn.connect_clicked(move |_| s_header.input(AppMsg::OpenConnect));
        group.set_header_suffix(Some(&header_new_btn));
        let mut first_row: Option<adw::ActionRow> = None;
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

            let delete = gtk::Button::builder()
                .icon_name("user-trash-symbolic")
                .valign(gtk::Align::Center)
                .tooltip_text(crate::tr!("Remove connection"))
                .build();
            delete.add_css_class("flat");
            let saved_id = saved.id;
            let s_del = sender.clone();
            delete.connect_clicked(move |_| s_del.input(AppMsg::DeleteConnection(saved_id)));
            row.add_suffix(&delete);

            let saved_clone = saved.clone();
            let s = sender.clone();
            row.connect_activated(move |_| s.input(AppMsg::OpenSaved(saved_clone.clone())));
            if first_row.is_none() {
                first_row = Some(row.clone());
            }
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
        if let Some(row) = first_row {
            row.grab_focus();
        }
    }

    pub(super) fn set_loading_page(&self, title: &str, description: &str) {
        let spinner = gtk::Spinner::new();
        spinner.set_spinning(true);
        spinner.set_size_request(48, 48);

        let title_label = gtk::Label::builder().label(title).build();
        title_label.add_css_class("title-2");
        let description_label = gtk::Label::builder()
            .label(description)
            .wrap(true)
            .justify(gtk::Justification::Center)
            .build();
        description_label.add_css_class("dim-label");

        let outer = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .spacing(12)
            .halign(gtk::Align::Center)
            .valign(gtk::Align::Center)
            .hexpand(true)
            .vexpand(true)
            .build();
        outer.append(&spinner);
        outer.append(&title_label);
        outer.append(&description_label);
        self.content_holder.set_content(Some(&outer));
    }

    pub(super) fn set_status_page(&self, title: &str, description: &str) {
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

    pub(super) fn show_toast(&self, msg: &str) {
        self.toast_overlay.add_toast(adw::Toast::new(msg));
    }

    pub(super) fn show_undoable_toast(&self, msg: &str, batch: UndoBatch, sender: ComponentSender<Self>) {
        let toast = adw::Toast::builder()
            .title(msg)
            .timeout(10)
            .button_label(crate::tr!("Undo"))
            .build();
        let s = sender;
        let batch_clone = batch;
        toast.connect_button_clicked(move |t| {
            s.input(AppMsg::ExecuteUndo(batch_clone.clone()));
            t.dismiss();
        });
        self.toast_overlay.add_toast(toast);
    }

    pub(super) fn show_error_alert(&self, title: &str, message: &str) {
        let dialog = adw::AlertDialog::new(Some(title), Some(message));
        dialog.add_response("ok", "OK");
        dialog.set_default_response(Some("ok"));
        dialog.set_close_response("ok");
        dialog.present(Some(&self.window));
    }

    pub(super) fn on_show_shortcuts(&self) {
        build_shortcuts_window(&self.window).present();
    }

    pub(super) fn on_show_about(&self) {
        let dialog = adw::AboutDialog::builder()
            .application_name(crate::tr!("TablePro"))
            .application_icon("com.tablepro.linux")
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
