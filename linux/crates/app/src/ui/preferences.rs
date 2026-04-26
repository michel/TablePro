use relm4::adw::prelude::*;
use relm4::{adw, gtk};

use crate::services::preferences::{self, Preferences};

pub fn present(parent: &impl IsA<gtk::Widget>) {
    let window = adw::PreferencesDialog::builder()
        .title(crate::tr!("Preferences"))
        .build();

    let general = adw::PreferencesPage::builder()
        .title(crate::tr!("General"))
        .icon_name("preferences-system-symbolic")
        .build();

    let browse_group = adw::PreferencesGroup::builder()
        .title(crate::tr!("Data browser"))
        .description(crate::tr!(
            "Tunes the row paginator and destructive-action confirmation."
        ))
        .build();

    let current = preferences::load();

    let page_size_row = adw::SpinRow::with_range(100.0, 100_000.0, 100.0);
    page_size_row.set_title(&crate::tr!("Default page size"));
    page_size_row.set_subtitle(&crate::tr!("Rows fetched per request when browsing a table"));
    page_size_row.set_value(current.default_page_size as f64);

    let confirm_row = adw::SwitchRow::builder()
        .title(crate::tr!("Confirm before deleting rows"))
        .subtitle(crate::tr!("Show a confirmation dialog before each destructive action"))
        .build();
    confirm_row.set_active(current.confirm_destructive);

    browse_group.add(&page_size_row);
    browse_group.add(&confirm_row);
    general.add(&browse_group);

    let editor = adw::PreferencesPage::builder()
        .title(crate::tr!("Editor"))
        .icon_name("text-editor-symbolic")
        .build();

    let editor_group = adw::PreferencesGroup::builder().title(crate::tr!("SQL editor")).build();

    let font_size_row = adw::SpinRow::with_range(8.0, 32.0, 1.0);
    font_size_row.set_title(&crate::tr!("Editor font size"));
    font_size_row.set_value(current.editor_font_size as f64);

    editor_group.add(&font_size_row);
    editor.add(&editor_group);

    window.add(&general);
    window.add(&editor);

    let page_size_for_save = page_size_row.clone();
    let confirm_for_save = confirm_row.clone();
    let font_size_for_save = font_size_row.clone();
    window.connect_closed(move |_| {
        let prefs = Preferences {
            default_page_size: page_size_for_save.value() as u64,
            confirm_destructive: confirm_for_save.is_active(),
            editor_font_size: font_size_for_save.value() as u32,
        };
        preferences::save(&prefs);
    });

    window.present(Some(parent));
}
