use common::{Config, Result};
use tracing::info;
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    info!("Starting watcher-signer service");

    // Load configuration
    let _config = Config::from_env()?;
    info!("Configuration loaded");

    // TODO: Start actors

    info!("Watcher-signer service started");

    // Keep running
    tokio::signal::ctrl_c().await.map_err(anyhow::Error::from)?;
    info!("Shutting down");

    Ok(())
}
