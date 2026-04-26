use gtk4::prelude::*;
use gtk4::{self as gtk};

use tablepro_core::{ColumnInfo, QueryResult, Value};

use super::row_object::RowObject;
use crate::ui::app::AppMsg;

pub fn build_column_view(
    result: &QueryResult,
    schema_columns: &[ColumnInfo],
    table: &str,
    sender: Option<relm4::Sender<AppMsg>>,
) -> (gtk::ColumnView, gtk::SingleSelection) {
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
        let editable = is_cell_editable(schema_columns.get(i).unwrap_or(column));
        column_view.append_column(&build_column(column, i, editable, table.to_string(), sender.clone()));
    }

    (column_view, selection)
}

fn build_column(
    info: &ColumnInfo,
    idx: usize,
    editable: bool,
    table: String,
    sender: Option<relm4::Sender<AppMsg>>,
) -> gtk::ColumnViewColumn {
    let factory = gtk::SignalListItemFactory::new();
    let editable_for_setup = editable && sender.is_some();
    let sender_for_setup = sender.clone();
    let table_for_setup = table;

    factory.connect_setup(move |_, item| {
        let Some(item) = item.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let label = gtk::EditableLabel::builder()
            .xalign(0.0)
            .hexpand(true)
            .margin_start(8)
            .margin_end(8)
            .build();
        label.set_editable(editable_for_setup);
        item.set_child(Some(&label));

        if !editable_for_setup {
            return;
        }
        let Some(sender_clone) = sender_for_setup.clone() else {
            return;
        };
        let table_clone = table_for_setup.clone();

        label.connect_editing_notify(move |label| {
            if label.is_editing() {
                let position = unsafe { label.data::<u32>("tp-position").map(|p| *p.as_ref()).unwrap_or(0) };
                let original = label.text().to_string();
                let snapshot = EditSnapshot { position, original };
                unsafe {
                    label.set_data("tp-snapshot", snapshot);
                }
                return;
            }
            let snap = unsafe { label.steal_data::<EditSnapshot>("tp-snapshot") };
            let Some(snap) = snap else {
                return;
            };
            let new_value = label.text().to_string();
            if new_value == snap.original {
                return;
            }
            sender_clone
                .send(AppMsg::CellEdited {
                    table: table_clone.clone(),
                    row_position: snap.position,
                    col_index: idx,
                    new_value,
                })
                .ok();
        });
    });

    factory.connect_bind(move |_, item| {
        let Some(item) = item.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let Some(row) = item.item().and_downcast::<RowObject>() else {
            return;
        };
        let Some(label) = item.child().and_downcast::<gtk::EditableLabel>() else {
            return;
        };
        let text = row.cell(idx);
        label.set_text(&text);
        unsafe {
            label.set_data("tp-position", item.position());
        }
    });

    factory.connect_unbind(|_, item| {
        let Some(item) = item.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let Some(label) = item.child().and_downcast::<gtk::EditableLabel>() else {
            return;
        };
        if label.is_editing() {
            label.stop_editing(false);
        }
        unsafe {
            let _: Option<u32> = label.steal_data("tp-position");
            let _: Option<EditSnapshot> = label.steal_data("tp-snapshot");
        }
    });

    gtk::ColumnViewColumn::builder()
        .title(&info.name)
        .factory(&factory)
        .resizable(true)
        .expand(true)
        .build()
}

fn is_cell_editable(col: &ColumnInfo) -> bool {
    !col.primary_key && !is_bytes_type(&col.data_type)
}

fn is_bytes_type(s: &str) -> bool {
    let lower = s.to_ascii_lowercase();
    lower.contains("blob") || lower.contains("bytea") || lower == "binary" || lower == "varbinary"
}

#[derive(Debug)]
struct EditSnapshot {
    position: u32,
    original: String,
}

pub fn value_to_string(value: &Value) -> String {
    match value {
        Value::Null => "NULL".into(),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::Float(f) => f.to_string(),
        Value::Text(s) => s.clone(),
        Value::Bytes(b) => format!("<{} bytes>", b.len()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn col(data_type: &str, primary_key: bool) -> ColumnInfo {
        ColumnInfo {
            name: "x".into(),
            data_type: data_type.into(),
            nullable: true,
            primary_key,
        }
    }

    #[test]
    fn editable_for_normal_column() {
        assert!(is_cell_editable(&col("text", false)));
        assert!(is_cell_editable(&col("integer", false)));
    }

    #[test]
    fn not_editable_for_primary_key() {
        assert!(!is_cell_editable(&col("integer", true)));
    }

    #[test]
    fn not_editable_for_bytes() {
        assert!(!is_cell_editable(&col("bytea", false)));
        assert!(!is_cell_editable(&col("blob", false)));
        assert!(!is_cell_editable(&col("longblob", false)));
        assert!(!is_cell_editable(&col("BINARY", false)));
        assert!(!is_cell_editable(&col("varbinary", false)));
    }

    #[test]
    fn bytes_type_detection() {
        assert!(is_bytes_type("BYTEA"));
        assert!(is_bytes_type("blob"));
        assert!(is_bytes_type("LONGBLOB"));
        assert!(is_bytes_type("mediumblob"));
        assert!(is_bytes_type("tinyblob"));
        assert!(is_bytes_type("VARBINARY"));
        assert!(is_bytes_type("binary"));
        assert!(!is_bytes_type("text"));
        assert!(!is_bytes_type("integer"));
    }

    #[test]
    fn value_to_string_variants() {
        assert_eq!(value_to_string(&Value::Null), "NULL");
        assert_eq!(value_to_string(&Value::Bool(true)), "true");
        assert_eq!(value_to_string(&Value::Int(42)), "42");
        assert_eq!(value_to_string(&Value::Text("hello".into())), "hello");
        assert_eq!(value_to_string(&Value::Bytes(vec![0u8; 16])), "<16 bytes>");
    }
}
