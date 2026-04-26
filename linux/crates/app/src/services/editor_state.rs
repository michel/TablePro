use std::path::PathBuf;

use serde::{Deserialize, Serialize};

const MAX_QUERY_BYTES: usize = 256 * 1024;
const MAX_TABS: usize = 32;

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
    if state.tabs.len() > MAX_TABS {
        state.tabs.truncate(MAX_TABS);
    }
    for tab in &mut state.tabs {
        if tab.query.len() > MAX_QUERY_BYTES {
            tab.query.truncate(MAX_QUERY_BYTES);
        }
    }
    if (state.active_idx as usize) >= state.tabs.len() {
        state.active_idx = 0;
    }
    state
}

pub fn save(state: &EditorState) {
    let Some(path) = config_path() else { return };
    if let Some(parent) = path.parent()
        && std::fs::create_dir_all(parent).is_err()
    {
        return;
    }
    let trimmed = trim_for_save(state);
    let Ok(json) = serde_json::to_vec_pretty(&trimmed) else {
        return;
    };
    let tmp = path.with_extension("json.tmp");
    if std::fs::write(&tmp, json).is_ok() {
        let _ = std::fs::rename(tmp, path);
    }
}

fn trim_for_save(state: &EditorState) -> EditorState {
    let mut clone = state.clone();
    if clone.tabs.len() > MAX_TABS {
        clone.tabs.truncate(MAX_TABS);
    }
    for tab in &mut clone.tabs {
        if tab.query.len() > MAX_QUERY_BYTES {
            tab.query.truncate(MAX_QUERY_BYTES);
        }
    }
    if (clone.active_idx as usize) >= clone.tabs.len() {
        clone.active_idx = 0;
    }
    clone
}

fn config_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
    Some(base.join("tablepro").join("editor.json"))
}
