use std::cell::RefCell;

use gtk4::glib;
use gtk4::subclass::prelude::*;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct RowObject {
        pub cells: RefCell<Vec<String>>,
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
    pub fn new(cells: Vec<String>) -> Self {
        let obj: Self = glib::Object::new();
        *obj.imp().cells.borrow_mut() = cells;
        obj
    }

    pub fn cell(&self, idx: usize) -> String {
        self.imp().cells.borrow().get(idx).cloned().unwrap_or_default()
    }
}
