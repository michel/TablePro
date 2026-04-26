use async_trait::async_trait;

use crate::connection::{ConnectOptions, Connection};
use crate::error::DriverError;

#[async_trait]
pub trait DatabaseDriver: Send + Sync {
    fn id(&self) -> &'static str;
    fn display_name(&self) -> &'static str;
    fn default_port(&self) -> u16;

    fn is_file_based(&self) -> bool {
        false
    }

    async fn connect(&self, opts: ConnectOptions) -> Result<Box<dyn Connection>, DriverError>;
}
