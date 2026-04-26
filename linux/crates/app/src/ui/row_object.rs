use std::cell::RefCell;

use gtk4::glib;
use gtk4::subclass::prelude::*;

use tablepro_core::Value;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct RowObject {
        pub cells: RefCell<Vec<Value>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for RowObject {
        const NAME: &'static str = "TableProRowObject";
        type Type = super::RowObject;
    }

    impl ObjectImpl for RowObject {}
}

glib::wrapper! {
    pub struct RowObject(ObjectSubclass<imp::RowObject>);
}

impl RowObject {
    pub fn new(cells: Vec<Value>) -> Self {
        let obj: Self = glib::Object::new();
        *obj.imp().cells.borrow_mut() = cells;
        obj
    }

    pub fn cell_value(&self, idx: usize) -> Value {
        self.imp().cells.borrow().get(idx).cloned().unwrap_or(Value::Null)
    }
}
