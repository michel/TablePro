use std::collections::HashMap;

use oo7::Keyring;
use secrecy::SecretString;
use uuid::Uuid;

use crate::error::StorageError;

const SCHEMA: &str = "com.tablepro.linux.Password";

const KIND_DB_PASSWORD: &str = "db_password";
const KIND_SSH_PASSWORD: &str = "ssh_password";
const KIND_SSH_PASSPHRASE: &str = "ssh_passphrase";

pub async fn store_password(id: Uuid, password: &str, label: &str) -> Result<(), StorageError> {
    store_secret(id, KIND_DB_PASSWORD, password, label).await
}

pub async fn load_password(id: Uuid) -> Result<Option<SecretString>, StorageError> {
    load_secret(id, KIND_DB_PASSWORD).await
}

pub async fn delete_password(id: Uuid) -> Result<(), StorageError> {
    delete_secret(id, KIND_DB_PASSWORD).await
}

pub async fn store_ssh_password(id: Uuid, password: &str, label: &str) -> Result<(), StorageError> {
    store_secret(id, KIND_SSH_PASSWORD, password, label).await
}

pub async fn load_ssh_password(id: Uuid) -> Result<Option<SecretString>, StorageError> {
    load_secret(id, KIND_SSH_PASSWORD).await
}

pub async fn delete_ssh_password(id: Uuid) -> Result<(), StorageError> {
    delete_secret(id, KIND_SSH_PASSWORD).await
}

pub async fn store_ssh_passphrase(id: Uuid, passphrase: &str, label: &str) -> Result<(), StorageError> {
    store_secret(id, KIND_SSH_PASSPHRASE, passphrase, label).await
}

pub async fn load_ssh_passphrase(id: Uuid) -> Result<Option<SecretString>, StorageError> {
    load_secret(id, KIND_SSH_PASSPHRASE).await
}

pub async fn delete_ssh_passphrase(id: Uuid) -> Result<(), StorageError> {
    delete_secret(id, KIND_SSH_PASSPHRASE).await
}

async fn store_secret(id: Uuid, kind: &str, value: &str, label: &str) -> Result<(), StorageError> {
    let keyring = open().await?;
    keyring
        .create_item(label, &attrs_for(id, kind), value.as_bytes(), true)
        .await
        .map_err(map_err)?;
    Ok(())
}

async fn load_secret(id: Uuid, kind: &str) -> Result<Option<SecretString>, StorageError> {
    let keyring = match open().await {
        Ok(k) => k,
        Err(_) => return Ok(None),
    };
    let items = keyring.search_items(&attrs_for(id, kind)).await.map_err(map_err)?;
    let Some(item) = items.into_iter().next() else {
        return Ok(None);
    };
    let secret = item.secret().await.map_err(map_err)?;
    let s = String::from_utf8(secret.to_vec()).map_err(|e| StorageError::Schema(format!("secret utf8: {e}")))?;
    Ok(Some(SecretString::new(s.into())))
}

async fn delete_secret(id: Uuid, kind: &str) -> Result<(), StorageError> {
    let keyring = open().await?;
    keyring.delete(&attrs_for(id, kind)).await.map_err(map_err)?;
    Ok(())
}

async fn open() -> Result<Keyring, StorageError> {
    Keyring::new()
        .await
        .map_err(|e| StorageError::Schema(format!("secret service unavailable: {e}")))
}

fn map_err(e: oo7::Error) -> StorageError {
    StorageError::Schema(format!("secret service: {e}"))
}

fn attrs_for(id: Uuid, kind: &str) -> HashMap<&'static str, String> {
    let mut m = HashMap::new();
    m.insert("xdg:schema", SCHEMA.to_string());
    m.insert("connection-id", id.to_string());
    m.insert("kind", kind.to_string());
    m
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn attrs_include_schema_connection_id_and_kind() {
        let id = Uuid::new_v4();
        let a = attrs_for(id, KIND_DB_PASSWORD);
        assert_eq!(a.get("xdg:schema").map(String::as_str), Some(SCHEMA));
        assert_eq!(
            a.get("connection-id").map(String::as_str),
            Some(id.to_string().as_str())
        );
        assert_eq!(a.get("kind").map(String::as_str), Some(KIND_DB_PASSWORD));
    }

    #[test]
    fn attrs_distinguish_kinds() {
        let id = Uuid::new_v4();
        let db = attrs_for(id, KIND_DB_PASSWORD);
        let ssh = attrs_for(id, KIND_SSH_PASSWORD);
        let pp = attrs_for(id, KIND_SSH_PASSPHRASE);
        assert_ne!(db.get("kind"), ssh.get("kind"));
        assert_ne!(ssh.get("kind"), pp.get("kind"));
    }

    #[tokio::test]
    #[ignore]
    async fn round_trip_via_secret_service() {
        use secrecy::ExposeSecret;
        let id = Uuid::new_v4();
        store_password(id, "test-secret", "tablepro-spike").await.unwrap();
        let loaded = load_password(id).await.unwrap();
        assert_eq!(
            loaded.map(|s| s.expose_secret().to_string()),
            Some("test-secret".to_string())
        );
        delete_password(id).await.unwrap();
        let after = load_password(id).await.unwrap();
        assert!(after.is_none());
    }
}
