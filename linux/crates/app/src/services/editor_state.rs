use std::path::PathBuf;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

const MAX_QUERY_BYTES: usize = 256 * 1024;
const MAX_TABS: usize = 32;

static SAVE_LOCK: Mutex<()> = Mutex::new(());

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct EditorState {
    pub tabs: Vec<EditorTab>,
    pub active_idx: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EditorTab {
    pub query: String,
}

pub fn load() -> EditorState {
    let Some(path) = config_path() else {
        return EditorState::default();
    };
    let mut state: EditorState = std::fs::read(path)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default();
    clamp(&mut state);
    state
}

pub fn save(state: &EditorState) {
    let Some(path) = config_path() else { return };
    if let Some(parent) = path.parent()
        && std::fs::create_dir_all(parent).is_err()
    {
        return;
    }
    let mut snapshot = state.clone();
    clamp(&mut snapshot);
    let Ok(json) = serde_json::to_vec_pretty(&snapshot) else {
        return;
    };
    let _guard = SAVE_LOCK.lock();
    let tmp = path.with_extension(format!("json.{}.tmp", std::process::id()));
    if std::fs::write(&tmp, json).is_ok() {
        let _ = std::fs::rename(tmp, path);
    }
}

fn clamp(state: &mut EditorState) {
    if state.tabs.len() > MAX_TABS {
        state.tabs.truncate(MAX_TABS);
    }
    for tab in &mut state.tabs {
        if tab.query.len() > MAX_QUERY_BYTES {
            let boundary = floor_char_boundary(&tab.query, MAX_QUERY_BYTES);
            tab.query.truncate(boundary);
        }
    }
    if (state.active_idx as usize) >= state.tabs.len() {
        state.active_idx = 0;
    }
}

fn floor_char_boundary(s: &str, idx: usize) -> usize {
    if idx >= s.len() {
        return s.len();
    }
    let mut b = idx;
    while b > 0 && !s.is_char_boundary(b) {
        b -= 1;
    }
    b
}

fn config_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
    Some(base.join("tablepro").join("editor.json"))
}
