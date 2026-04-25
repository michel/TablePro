use std::collections::HashMap;

use oo7::Keyring;
use uuid::Uuid;

use crate::error::StorageError;

const SCHEMA: &str = "com.tablepro.Linux.Password";

pub async fn store_password(id: Uuid, password: &str, label: &str) -> Result<(), StorageError> {
    let keyring = open().await?;
    keyring
        .create_item(label, &attrs_for(id), password.as_bytes(), true)
        .await
        .map_err(map_err)?;
    Ok(())
}

pub async fn load_password(id: Uuid) -> Result<Option<String>, StorageError> {
    let keyring = match open().await {
        Ok(k) => k,
        Err(_) => return Ok(None),
    };
    let items = keyring.search_items(&attrs_for(id)).await.map_err(map_err)?;
    let Some(item) = items.into_iter().next() else {
        return Ok(None);
    };
    let secret = item.secret().await.map_err(map_err)?;
    let s = String::from_utf8(secret.to_vec()).map_err(|e| StorageError::Schema(format!("secret utf8: {e}")))?;
    Ok(Some(s))
}

pub async fn delete_password(id: Uuid) -> Result<(), StorageError> {
    let keyring = open().await?;
    keyring.delete(&attrs_for(id)).await.map_err(map_err)?;
    Ok(())
}

async fn open() -> Result<Keyring, StorageError> {
    Keyring::new()
        .await
        .map_err(|e| StorageError::Schema(format!("secret service unavailable: {e}")))
}

fn attrs_for(id: Uuid) -> HashMap<&'static str, String> {
    let mut m = HashMap::new();
    m.insert("xdg:schema", SCHEMA.to_string());
    m.insert("connection-id", id.to_string());
    m
}

fn map_err(e: oo7::Error) -> StorageError {
    StorageError::Schema(format!("secret service: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn attrs_include_schema_and_connection_id() {
        let id = Uuid::new_v4();
        let a = attrs_for(id);
        assert_eq!(a.get("xdg:schema").map(String::as_str), Some(SCHEMA));
        assert_eq!(
            a.get("connection-id").map(String::as_str),
            Some(id.to_string().as_str())
        );
    }

    #[tokio::test]
    #[ignore]
    async fn round_trip_via_secret_service() {
        let id = Uuid::new_v4();
        store_password(id, "test-secret", "tablepro-spike").await.unwrap();
        let loaded = load_password(id).await.unwrap();
        assert_eq!(loaded.as_deref(), Some("test-secret"));
        delete_password(id).await.unwrap();
        let after = load_password(id).await.unwrap();
        assert!(after.is_none());
    }
}
