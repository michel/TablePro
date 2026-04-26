use relm4::adw::prelude::*;
use relm4::{ComponentController, ComponentSender, adw, gtk};

use super::{App, AppMsg, StatusKind, UndoBatch, build_shortcuts_window};

impl App {
    pub(super) fn show_welcome_page(&self, _sender: ComponentSender<Self>) {
        // Welcome lives outside the ViewStack — it's the disconnected mode.
        // The ViewSwitcherBar is hidden via on_disconnect so the welcome
        // view occupies the full toolbar surface.
        self.content_holder.set_content(Some(self.welcome_view.widget()));
    }

    /// Replaces the Browse view-stack page's content with a busy spinner +
    /// title + description. The ViewSwitcher tabs stay visible (we're still
    /// inside the connected ViewStack), only the Browse page's inner stack
    /// swaps.
    ///
    /// Uses `adw::StatusPage` with a spinner as its child for native
    /// styling (margins, typography, accessibility) — matches the idiom
    /// of `set_status_page` for visual consistency.
    pub(super) fn set_loading_page(&self, title: &str, description: &str) {
        let spinner = gtk::Spinner::builder()
            .spinning(true)
            .width_request(32)
            .height_request(32)
            .halign(gtk::Align::Center)
            .build();
        let page = adw::StatusPage::builder()
            .title(title)
            .description(description)
            .child(&spinner)
            .build();
        self.replace_browse_status_child("loading", &page);
        self.view_stack.set_visible_child_name("browse");
    }

    /// Same idea as `set_loading_page`: swap the Browse page's inner stack
    /// to show a status page (Select-a-table / Failed / etc).
    pub(super) fn set_status_page(&self, kind: StatusKind, title: &str, description: &str) {
        let page = adw::StatusPage::builder()
            .title(title)
            .description(description)
            .icon_name(kind.icon())
            .build();
        self.replace_browse_status_child("status", &page);
        self.view_stack.set_visible_child_name("browse");
    }

    /// Helper: removes the previous child registered under `name` (if any)
    /// from the Browse inner stack, adds the new one, and shows it.
    fn replace_browse_status_child(&self, name: &str, child: &impl IsA<gtk::Widget>) {
        if let Some(prev) = self.browse_inner_stack.child_by_name(name) {
            self.browse_inner_stack.remove(&prev);
        }
        self.browse_inner_stack.add_named(child, Some(name));
        self.browse_inner_stack.set_visible_child_name(name);
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
