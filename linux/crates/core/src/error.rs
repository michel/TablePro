use thiserror::Error;

#[derive(Debug, Error)]
pub enum DriverError {
    #[error("connection refused")]
    ConnectionRefused,

    #[error("authentication failed")]
    AuthFailed,

    #[error("TLS handshake failed: {0}")]
    Tls(String),

    #[error("query failed: {message}")]
    Query { message: String, sqlstate: Option<String> },

    #[error("connection closed unexpectedly")]
    Disconnected,

    #[error("driver internal error: {0}")]
    Internal(String),
}
