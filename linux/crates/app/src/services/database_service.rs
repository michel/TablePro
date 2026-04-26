use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use uuid::Uuid;

use tablepro_core::Connection;

static SERVICE: OnceLock<DatabaseService> = OnceLock::new();

pub fn instance() -> &'static DatabaseService {
    SERVICE.get_or_init(DatabaseService::new)
}

pub struct DatabaseService {
    connections: Mutex<HashMap<Uuid, Arc<dyn Connection>>>,
    active: Mutex<Option<Uuid>>,
}

impl DatabaseService {
    fn new() -> Self {
        Self {
            connections: Mutex::new(HashMap::new()),
            active: Mutex::new(None),
        }
    }

    pub fn add(&self, id: Uuid, connection: Box<dyn Connection>) {
        let arc: Arc<dyn Connection> = Arc::from(connection);
        self.connections.lock().expect("database_service lock").insert(id, arc);
        *self.active.lock().expect("database_service lock") = Some(id);
    }

    pub fn get(&self, id: Uuid) -> Option<Arc<dyn Connection>> {
        self.connections
            .lock()
            .expect("database_service lock")
            .get(&id)
            .cloned()
    }

    pub fn active(&self) -> Option<Arc<dyn Connection>> {
        let id = self.active_id()?;
        self.get(id)
    }

    pub fn active_id(&self) -> Option<Uuid> {
        *self.active.lock().expect("database_service lock")
    }

    pub fn remove(&self, id: Uuid) {
        self.connections.lock().expect("database_service lock").remove(&id);
        let mut active = self.active.lock().expect("database_service lock");
        if *active == Some(id) {
            *active = None;
        }
    }

    pub fn clear_all(&self) {
        self.connections.lock().expect("database_service lock").clear();
        *self.active.lock().expect("database_service lock") = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn instance_is_singleton() {
        let a = instance() as *const _;
        let b = instance() as *const _;
        assert_eq!(a, b);
    }
}
