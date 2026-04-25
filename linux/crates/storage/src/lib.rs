mod connections;
mod error;

pub use connections::{SavedConnection, load_connections, save_connections};
pub use error::StorageError;
