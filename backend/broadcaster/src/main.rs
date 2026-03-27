use common::{BroadcasterConfig, Result};
use tracing::info;
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    info!("Starting broadcaster service");

    // Load configuration
    let _config = BroadcasterConfig::from_env()?;
    info!("Configuration loaded");

    // TODO: Start event loop

    info!("Broadcaster service started");

    // Keep running
    tokio::signal::ctrl_c().await.map_err(anyhow::Error::from)?;
    info!("Shutting down");

    Ok(())
}
