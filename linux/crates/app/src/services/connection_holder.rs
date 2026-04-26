use std::sync::{Arc, OnceLock, RwLock};

use tablepro_core::Connection;

static ACTIVE: OnceLock<RwLock<Option<Arc<dyn Connection>>>> = OnceLock::new();

fn cell() -> &'static RwLock<Option<Arc<dyn Connection>>> {
    ACTIVE.get_or_init(|| RwLock::new(None))
}

pub fn set(connection: Box<dyn Connection>) {
    *cell().write().expect("connection_holder write") = Some(Arc::from(connection));
}

pub fn get() -> Option<Arc<dyn Connection>> {
    cell().read().expect("connection_holder read").clone()
}

pub fn clear() {
    *cell().write().expect("connection_holder write") = None;
}
