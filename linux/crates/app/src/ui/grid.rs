use gtk4::prelude::*;
use gtk4::{self as gtk, pango};

use tablepro_core::{ColumnInfo, QueryResult, Value};

use super::row_object::RowObject;

pub fn build_column_view(result: &QueryResult) -> gtk::ColumnView {
    let store = gtk4::gio::ListStore::new::<RowObject>();
    for row in &result.rows {
        let cells = row.iter().map(value_to_string).collect();
        store.append(&RowObject::new(cells));
    }
    let selection = gtk::SingleSelection::new(Some(store));
    let column_view = gtk::ColumnView::builder()
        .model(&selection)
        .show_row_separators(true)
        .show_column_separators(true)
        .build();

    for (i, column) in result.columns.iter().enumerate() {
        column_view.append_column(&build_column(column, i));
    }

    column_view
}

fn build_column(info: &ColumnInfo, idx: usize) -> gtk::ColumnViewColumn {
    let factory = gtk::SignalListItemFactory::new();
    factory.connect_setup(|_, item| {
        let Some(item) = item.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let label = gtk::Label::builder()
            .xalign(0.0)
            .ellipsize(pango::EllipsizeMode::End)
            .single_line_mode(true)
            .margin_start(8)
            .margin_end(8)
            .build();
        item.set_child(Some(&label));
    });
    factory.connect_bind(move |_, item| {
        let Some(item) = item.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let Some(row) = item.item().and_downcast::<RowObject>() else {
            return;
        };
        let Some(label) = item.child().and_downcast::<gtk::Label>() else {
            return;
        };
        label.set_label(&row.cell(idx));
    });
    gtk::ColumnViewColumn::builder()
        .title(&info.name)
        .factory(&factory)
        .resizable(true)
        .expand(true)
        .build()
}

fn value_to_string(value: &Value) -> String {
    match value {
        Value::Null => "NULL".into(),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::Float(f) => f.to_string(),
        Value::Text(s) => s.clone(),
        Value::Bytes(b) => format!("<{} bytes>", b.len()),
    }
}
