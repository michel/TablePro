use serde::{Deserialize, Serialize};

use super::config_io::{atomic_write_json, xdg_config_path};

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
    let Some(path) = xdg_config_path("editor.json") else {
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
    let Some(path) = xdg_config_path("editor.json") else {
        return;
    };
    let mut snapshot = state.clone();
    clamp(&mut snapshot);
    let _ = atomic_write_json(&path, &snapshot);
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
