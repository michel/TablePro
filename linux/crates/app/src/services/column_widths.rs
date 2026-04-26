use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

use uuid::Uuid;

type Widths = HashMap<String, i32>;
type Tables = HashMap<String, Widths>;
type Connections = HashMap<String, Tables>;

static CACHE: Mutex<Option<Connections>> = Mutex::new(None);

pub fn load(connection_id: Uuid, table: &str, column: &str) -> Option<i32> {
    let mut guard = CACHE.lock().ok()?;
    let map = guard.get_or_insert_with(load_from_disk);
    map.get(&connection_id.to_string())?.get(table)?.get(column).copied()
}

pub fn save(connection_id: Uuid, table: &str, column: &str, width: i32) {
    let mut guard = match CACHE.lock() {
        Ok(g) => g,
        Err(_) => return,
    };
    let map = guard.get_or_insert_with(load_from_disk);
    map.entry(connection_id.to_string())
        .or_default()
        .entry(table.to_string())
        .or_default()
        .insert(column.to_string(), width);
    let snapshot = map.clone();
    drop(guard);
    std::thread::spawn(move || {
        if let Err(e) = save_to_disk(&snapshot) {
            tracing::warn!(error = %e, "column_widths: persist failed");
        }
    });
}

fn load_from_disk() -> Connections {
    let Some(path) = config_path() else {
        return HashMap::new();
    };
    let Ok(bytes) = std::fs::read(path) else {
        return HashMap::new();
    };
    serde_json::from_slice(&bytes).unwrap_or_default()
}

fn save_to_disk(map: &Connections) -> std::io::Result<()> {
    let Some(path) = config_path() else {
        return Ok(());
    };
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_vec_pretty(map).unwrap_or_default();
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, json)?;
    std::fs::rename(tmp, path)
}

fn config_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
    Some(base.join("tablepro").join("column_widths.json"))
}
