use std::cell::RefCell;
use std::rc::Rc;

use gtk4::prelude::*;
use gtk4::{self as gtk};

use tablepro_core::{ColumnInfo, QueryResult, Value};

use super::row_object::RowObject;
use crate::ui::app::AppMsg;

pub type FilterSetter = Rc<dyn Fn(&str)>;

pub fn build_column_view(
    result: &QueryResult,
    schema_columns: &[ColumnInfo],
    table: &str,
    edit_sender: Option<relm4::Sender<AppMsg>>,
    sort: Option<(usize, bool)>,
    sort_sender: Option<relm4::Sender<AppMsg>>,
) -> (gtk::ColumnView, gtk::MultiSelection, FilterSetter) {
    let store = gtk4::gio::ListStore::new::<RowObject>();
    for row in &result.rows {
        store.append(&RowObject::new(row.clone()));
    }
    let filter_text: Rc<RefCell<String>> = Rc::new(RefCell::new(String::new()));
    let filter_text_for_filter = filter_text.clone();
    let filter = gtk::CustomFilter::new(move |item| {
        let query = filter_text_for_filter.borrow();
        if query.is_empty() {
            return true;
        }
        let Some(row) = item.downcast_ref::<RowObject>() else {
            return true;
        };
        let needle = query.to_lowercase();
        row.cells_clone()
            .iter()
            .any(|v| value_to_display_text(v).to_lowercase().contains(&needle))
    });
    let filter_model = gtk::FilterListModel::new(Some(store), Some(filter.clone()));
    let selection = gtk::MultiSelection::new(Some(filter_model));

    let filter_for_setter = filter.clone();
    let setter: FilterSetter = Rc::new(move |q: &str| {
        filter_text.replace(q.to_string());
        filter_for_setter.changed(gtk::FilterChange::Different);
    });
    let column_view = gtk::ColumnView::builder()
        .model(&selection)
        .show_row_separators(true)
        .show_column_separators(true)
        .build();

    let mut columns: Vec<gtk::ColumnViewColumn> = Vec::with_capacity(result.columns.len());
    for (i, column) in result.columns.iter().enumerate() {
        let editable = is_cell_editable(schema_columns.get(i).unwrap_or(column));
        let sort_indicator = sort.and_then(|(c, asc)| if c == i { Some(asc) } else { None });
        let col = build_column(
            column,
            i,
            editable,
            table.to_string(),
            edit_sender.clone(),
            sort_indicator,
            sort_sender.clone(),
        );
        column_view.append_column(&col);
        columns.push(col);
    }

    if let Some(app_sender) = sort_sender
        && let Some(view_sorter) = column_view
            .sorter()
            .and_then(|s| s.downcast::<gtk::ColumnViewSorter>().ok())
    {
        view_sorter.connect_primary_sort_column_notify(move |sorter| {
            let Some(active) = sorter.primary_sort_column() else {
                return;
            };
            for (idx, col) in columns.iter().enumerate() {
                if col == &active {
                    app_sender.send(AppMsg::SortChanged(idx)).ok();
                    break;
                }
            }
        });
    }

    (column_view, selection, setter)
}

fn build_column(
    info: &ColumnInfo,
    idx: usize,
    editable: bool,
    table: String,
    sender: Option<relm4::Sender<AppMsg>>,
    sort_indicator: Option<bool>,
    sort_sender: Option<relm4::Sender<AppMsg>>,
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
                let position = POSITION_SLOT.get(label).unwrap_or(0);
                let original = label.text().to_string();
                SNAPSHOT_SLOT.set(label, EditSnapshot { position, original });
                return;
            }
            let Some(snap) = SNAPSHOT_SLOT.take(label) else {
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

    let editable_for_bind = editable_for_setup;
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
        let value = row.cell_value(idx);
        let is_null = matches!(value, Value::Null);
        let text = if editable_for_bind {
            value_to_edit_text(&value)
        } else {
            value_to_display_text(&value)
        };
        label.set_text(&text);
        if is_null && !editable_for_bind {
            label.add_css_class("dim-label");
        } else {
            label.remove_css_class("dim-label");
        }
        POSITION_SLOT.set(&label, item.position());
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
        POSITION_SLOT.take(&label);
        SNAPSHOT_SLOT.take(&label);
    });

    let title = match sort_indicator {
        Some(true) => format!("{} \u{2191}", info.name),
        Some(false) => format!("{} \u{2193}", info.name),
        None => info.name.clone(),
    };
    let column = gtk::ColumnViewColumn::builder()
        .title(&title)
        .factory(&factory)
        .resizable(true)
        .expand(true)
        .build();
    if sort_sender.is_some() {
        let dummy = gtk::CustomSorter::new(|_, _| gtk::Ordering::Equal);
        column.set_sorter(Some(&dummy));
    }
    column
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

struct WidgetSlot<T: 'static> {
    key: &'static str,
    _phantom: std::marker::PhantomData<T>,
}

impl<T: 'static> WidgetSlot<T> {
    const fn new(key: &'static str) -> Self {
        Self {
            key,
            _phantom: std::marker::PhantomData,
        }
    }

    fn set(&self, widget: &impl IsA<gtk::Widget>, value: T) {
        unsafe { widget.set_data(self.key, value) };
    }

    fn take(&self, widget: &impl IsA<gtk::Widget>) -> Option<T> {
        unsafe { widget.steal_data::<T>(self.key) }
    }
}

impl<T: 'static + Copy> WidgetSlot<T> {
    fn get(&self, widget: &impl IsA<gtk::Widget>) -> Option<T> {
        unsafe { widget.data::<T>(self.key).map(|p| *p.as_ref()) }
    }
}

const POSITION_SLOT: WidgetSlot<u32> = WidgetSlot::new("tp-position");
const SNAPSHOT_SLOT: WidgetSlot<EditSnapshot> = WidgetSlot::new("tp-snapshot");

pub fn value_to_display_text(value: &Value) -> String {
    match value {
        Value::Null => "NULL".into(),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::Float(f) => f.to_string(),
        Value::Text(s) => s.clone(),
        Value::Bytes(b) => format!("<{} bytes>", b.len()),
        Value::Date(d) => d.format("%Y-%m-%d").to_string(),
        Value::Time(t) => t.format("%H:%M:%S").to_string(),
        Value::DateTime(dt) => dt.format("%Y-%m-%d %H:%M:%S").to_string(),
        Value::TimestampTz(ts) => ts.format("%Y-%m-%d %H:%M:%S%:z").to_string(),
        Value::Decimal(d) => d.to_string(),
        Value::Uuid(u) => u.to_string(),
        Value::Json(j) => j.to_string(),
    }
}

pub fn value_to_edit_text(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        other => value_to_display_text(other),
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
    fn display_text_primitive_variants() {
        assert_eq!(value_to_display_text(&Value::Null), "NULL");
        assert_eq!(value_to_display_text(&Value::Bool(true)), "true");
        assert_eq!(value_to_display_text(&Value::Int(42)), "42");
        assert_eq!(value_to_display_text(&Value::Text("hello".into())), "hello");
        assert_eq!(value_to_display_text(&Value::Bytes(vec![0u8; 16])), "<16 bytes>");
    }

    #[test]
    fn display_text_temporal_variants() {
        let date = chrono::NaiveDate::from_ymd_opt(2026, 4, 26).unwrap();
        assert_eq!(value_to_display_text(&Value::Date(date)), "2026-04-26");

        let time = chrono::NaiveTime::from_hms_opt(14, 30, 0).unwrap();
        assert_eq!(value_to_display_text(&Value::Time(time)), "14:30:00");

        let datetime = chrono::NaiveDateTime::new(date, time);
        assert_eq!(value_to_display_text(&Value::DateTime(datetime)), "2026-04-26 14:30:00");

        let tz = chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(datetime, chrono::Utc);
        assert_eq!(
            value_to_display_text(&Value::TimestampTz(tz)),
            "2026-04-26 14:30:00+00:00"
        );
    }

    #[test]
    fn display_text_extended_variants() {
        let dec: rust_decimal::Decimal = "1234.56789".parse().unwrap();
        assert_eq!(value_to_display_text(&Value::Decimal(dec)), "1234.56789");

        let id = uuid::Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        assert_eq!(
            value_to_display_text(&Value::Uuid(id)),
            "550e8400-e29b-41d4-a716-446655440000"
        );

        let json = serde_json::json!({"a": 1, "b": [2, 3]});
        let text = value_to_display_text(&Value::Json(json));
        assert!(text.contains("\"a\":1"));
    }

    #[test]
    fn edit_text_distinguishes_null_from_text_null() {
        assert_eq!(value_to_edit_text(&Value::Null), "");
        assert_eq!(value_to_edit_text(&Value::Text("NULL".into())), "NULL");
        assert_eq!(value_to_edit_text(&Value::Int(0)), "0");
    }

    #[test]
    fn edit_text_keeps_extended_variants_visible() {
        let date = chrono::NaiveDate::from_ymd_opt(2026, 4, 26).unwrap();
        assert_eq!(value_to_edit_text(&Value::Date(date)), "2026-04-26");

        let id = uuid::Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        assert_eq!(
            value_to_edit_text(&Value::Uuid(id)),
            "550e8400-e29b-41d4-a716-446655440000"
        );
    }
}
