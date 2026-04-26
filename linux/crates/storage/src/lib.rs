mod connections;
mod error;
mod secrets;

pub use connections::{
    SavedConnection, SavedSshAuth, SavedSshConfig, delete_connection, load_connections, save_connections,
};
pub use error::StorageError;
pub use secrets::{
    delete_password, delete_ssh_passphrase, delete_ssh_password, load_password, load_ssh_passphrase, load_ssh_password,
    store_password, store_ssh_passphrase, store_ssh_password,
};
