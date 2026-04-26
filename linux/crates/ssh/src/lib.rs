use std::path::PathBuf;
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_util::sync::CancellationToken;

use russh::ChannelMsg;
use russh::client::{self, Config, Handle};
use russh::keys::{PrivateKeyWithHashAlg, load_secret_key};

const LOCAL_BIND_HOST: &str = "127.0.0.1";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SshConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth: SshAuth,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum SshAuth {
    Password { password: String },
    PrivateKey { path: PathBuf, passphrase: Option<String> },
}

#[derive(Debug, Error)]
pub enum SshError {
    #[error("connect: {0}")]
    Connect(String),
    #[error("authentication failed")]
    Auth,
    #[error("read private key {path}: {source}")]
    Key {
        path: PathBuf,
        #[source]
        source: russh::keys::Error,
    },
    #[error("local bind: {0}")]
    Bind(#[source] std::io::Error),
    #[error("ssh: {0}")]
    Ssh(#[from] russh::Error),
}

pub struct SshTunnel {
    local_port: u16,
    cancel: CancellationToken,
    _task: tokio::task::JoinHandle<()>,
}

impl SshTunnel {
    pub async fn open(cfg: SshConfig, remote_host: String, remote_port: u16) -> Result<Self, SshError> {
        let session = Arc::new(connect_and_auth(&cfg).await?);
        let listener = TcpListener::bind((LOCAL_BIND_HOST, 0)).await.map_err(SshError::Bind)?;
        let local_port = listener.local_addr().map_err(SshError::Bind)?.port();

        tracing::info!(
            ssh_host = %cfg.host,
            ssh_port = cfg.port,
            local_port,
            remote_host = %remote_host,
            remote_port,
            "ssh tunnel listening"
        );

        let cancel = CancellationToken::new();
        let task = tokio::spawn(forwarder_loop(
            listener,
            session,
            remote_host,
            remote_port,
            cancel.clone(),
        ));

        Ok(Self {
            local_port,
            cancel,
            _task: task,
        })
    }

    pub fn local_port(&self) -> u16 {
        self.local_port
    }

    pub fn local_host(&self) -> &'static str {
        LOCAL_BIND_HOST
    }
}

impl Drop for SshTunnel {
    fn drop(&mut self) {
        self.cancel.cancel();
    }
}

struct ClientHandler;

impl client::Handler for ClientHandler {
    type Error = russh::Error;

    async fn check_server_key(&mut self, key: &russh::keys::ssh_key::PublicKey) -> Result<bool, Self::Error> {
        tracing::warn!(
            fingerprint = %key.fingerprint(russh::keys::ssh_key::HashAlg::Sha256),
            "ssh: accepting any server host key (strict host-key checking not yet implemented)"
        );
        Ok(true)
    }
}

async fn connect_and_auth(cfg: &SshConfig) -> Result<Handle<ClientHandler>, SshError> {
    let config = Arc::new(Config {
        nodelay: true,
        ..Default::default()
    });
    let mut session = client::connect(config, (cfg.host.as_str(), cfg.port), ClientHandler)
        .await
        .map_err(|e| SshError::Connect(e.to_string()))?;

    let auth = match &cfg.auth {
        SshAuth::Password { password } => session.authenticate_password(&cfg.username, password).await?,
        SshAuth::PrivateKey { path, passphrase } => {
            let key = load_secret_key(path, passphrase.as_deref()).map_err(|e| SshError::Key {
                path: path.clone(),
                source: e,
            })?;
            let hash = session.best_supported_rsa_hash().await?.flatten();
            session
                .authenticate_publickey(&cfg.username, PrivateKeyWithHashAlg::new(Arc::new(key), hash))
                .await?
        }
    };

    if !auth.success() {
        return Err(SshError::Auth);
    }
    Ok(session)
}

async fn forwarder_loop(
    listener: TcpListener,
    session: Arc<Handle<ClientHandler>>,
    remote_host: String,
    remote_port: u16,
    cancel: CancellationToken,
) {
    loop {
        tokio::select! {
            _ = cancel.cancelled() => {
                tracing::debug!("ssh tunnel cancelled");
                return;
            }
            accept = listener.accept() => match accept {
                Ok((socket, peer)) => {
                    let session = session.clone();
                    let remote_host = remote_host.clone();
                    let cancel = cancel.clone();
                    tokio::spawn(async move {
                        if let Err(e) = forward_one(session, socket, peer, remote_host, remote_port, cancel).await {
                            tracing::warn!(error = %e, "ssh forward failed");
                        }
                    });
                }
                Err(e) => {
                    tracing::warn!(error = %e, "ssh listener accept failed");
                    return;
                }
            },
        }
    }
}

async fn forward_one(
    session: Arc<Handle<ClientHandler>>,
    mut socket: TcpStream,
    peer: std::net::SocketAddr,
    remote_host: String,
    remote_port: u16,
    cancel: CancellationToken,
) -> Result<(), russh::Error> {
    let mut channel = session
        .channel_open_direct_tcpip(
            remote_host,
            u32::from(remote_port),
            peer.ip().to_string(),
            u32::from(peer.port()),
        )
        .await?;

    let mut buf = vec![0u8; 65536];
    let mut local_eof = false;
    loop {
        tokio::select! {
            _ = cancel.cancelled() => {
                let _ = channel.eof().await;
                return Ok(());
            }
            r = socket.read(&mut buf), if !local_eof => {
                match r {
                    Ok(0) => {
                        local_eof = true;
                        let _ = channel.eof().await;
                    }
                    Ok(n) => {
                        if channel.data(&buf[..n]).await.is_err() {
                            return Ok(());
                        }
                    }
                    Err(_) => return Ok(()),
                }
            }
            msg = channel.wait() => match msg {
                Some(ChannelMsg::Data { data }) => {
                    if socket.write_all(&data).await.is_err() {
                        return Ok(());
                    }
                }
                Some(ChannelMsg::ExtendedData { .. }) => {}
                Some(ChannelMsg::Eof) | Some(ChannelMsg::Close) | None => {
                    let _ = socket.shutdown().await;
                    return Ok(());
                }
                Some(_) => {}
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ssh_auth_serde_round_trip_password() {
        let original = SshAuth::Password {
            password: "hunter2".into(),
        };
        let json = serde_json::to_string(&original).unwrap();
        let parsed: SshAuth = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, original);
    }

    #[test]
    fn ssh_auth_serde_round_trip_key() {
        let original = SshAuth::PrivateKey {
            path: PathBuf::from("/home/u/.ssh/id_ed25519"),
            passphrase: Some("p".into()),
        };
        let json = serde_json::to_string(&original).unwrap();
        let parsed: SshAuth = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, original);
    }
}
