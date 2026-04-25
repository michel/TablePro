use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::StorageError;

const CURRENT_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SavedConnection {
    pub id: Uuid,
    pub name: String,
    pub driver_id: String,
    pub host: String,
    pub port: u16,
    pub database: String,
    pub username: String,
    pub use_tls: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct ConnectionsFile {
    version: u32,
    connections: Vec<SavedConnection>,
}

pub async fn load_connections() -> Result<Vec<SavedConnection>, StorageError> {
    load_from(&connections_path()?).await
}

pub async fn save_connections(connections: &[SavedConnection]) -> Result<(), StorageError> {
    save_to(&connections_path()?, connections).await
}

pub(crate) async fn load_from(path: &Path) -> Result<Vec<SavedConnection>, StorageError> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let bytes = tokio::fs::read(path).await?;
    let file: ConnectionsFile = serde_json::from_slice(&bytes)?;
    if file.version != CURRENT_VERSION {
        return Err(StorageError::Schema(format!(
            "connections.json version {} not supported (expected {})",
            file.version, CURRENT_VERSION,
        )));
    }
    Ok(file.connections)
}

pub(crate) async fn save_to(path: &Path, connections: &[SavedConnection]) -> Result<(), StorageError> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let file = ConnectionsFile {
        version: CURRENT_VERSION,
        connections: connections.to_vec(),
    };
    let json = serde_json::to_vec_pretty(&file)?;
    let tmp = path.with_extension("json.tmp");
    tokio::fs::write(&tmp, &json).await?;
    tokio::fs::rename(&tmp, path).await?;
    Ok(())
}

fn connections_path() -> Result<PathBuf, StorageError> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|h| {
                let mut p = PathBuf::from(h);
                p.push(".config");
                p
            })
        })
        .ok_or_else(|| StorageError::Schema("neither XDG_CONFIG_HOME nor HOME is set".into()))?;
    Ok(base.join("tablepro").join("connections.json"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn sample_connection() -> SavedConnection {
        SavedConnection {
            id: Uuid::new_v4(),
            name: "Local Postgres".into(),
            driver_id: "postgres".into(),
            host: "localhost".into(),
            port: 5432,
            database: "postgres".into(),
            username: "postgres".into(),
            use_tls: false,
        }
    }

    #[tokio::test]
    async fn load_returns_empty_when_file_missing() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("connections.json");
        let result = load_from(&path).await.unwrap();
        assert!(result.is_empty());
    }

    #[tokio::test]
    async fn save_then_load_round_trips() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("connections.json");
        let original = vec![sample_connection()];
        save_to(&path, &original).await.unwrap();
        let loaded = load_from(&path).await.unwrap();
        assert_eq!(original, loaded);
    }

    #[tokio::test]
    async fn save_creates_parent_directory() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("nested/dir/connections.json");
        save_to(&path, &[]).await.unwrap();
        assert!(path.exists());
    }

    #[tokio::test]
    async fn load_rejects_unknown_version() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("connections.json");
        tokio::fs::write(&path, r#"{"version":999,"connections":[]}"#)
            .await
            .unwrap();
        let err = load_from(&path).await.unwrap_err();
        assert!(matches!(err, StorageError::Schema(_)));
    }
}
