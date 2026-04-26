use relm4::adw::prelude::*;
use relm4::{ComponentController, ComponentSender, adw, gtk};

use super::{App, AppMsg, StatusKind, UndoBatch, build_shortcuts_window};

impl App {
    pub(super) fn show_welcome_page(&self, _sender: ComponentSender<Self>) {
        // Delegated to the WelcomeView managed sub-component, which keeps
        // its widget tree across calls (factory diffs rows incrementally
        // instead of rebuilding the whole tree on every welcome show).
        self.content_holder.set_content(Some(self.welcome_view.widget()));
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

    pub(super) fn set_status_page(&self, kind: StatusKind, title: &str, description: &str) {
        let page = adw::StatusPage::builder()
            .title(title)
            .description(description)
            .icon_name(kind.icon())
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
