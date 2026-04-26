use std::sync::Arc;

use tablepro_core::{ConnectOptions, DriverRegistry, TableInfo};
use tablepro_storage::{SavedConnection, load_password};

use super::database_service;

pub async fn open_saved(registry: Arc<DriverRegistry>, saved: SavedConnection) -> Result<Vec<TableInfo>, String> {
    let driver = registry
        .get(&saved.driver_id)
        .ok_or_else(|| format!("driver {} not registered", saved.driver_id))?;
    let password = load_password(saved.id).await.ok().flatten().unwrap_or_default();
    let id = saved.id;
    let opts = ConnectOptions {
        host: saved.host,
        port: saved.port,
        database: saved.database,
        username: saved.username,
        password,
        use_tls: saved.use_tls,
    };
    let conn = driver.connect(opts).await.map_err(|e| format!("connect: {e}"))?;
    let tables = conn.list_tables().await.map_err(|e| format!("list_tables: {e}"))?;
    database_service::instance().add(id, conn);
    Ok(tables)
}
