use common::{BitcoinClient, BitcoinProvider, Config, Result};
use common::starknet::StarknetBridgeClient;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::info;
use tracing_subscriber;

mod actors;

use actors::bitcoin_monitor::BitcoinMonitorActor;
use actors::deposit_processor::{DepositProcessorActor, DepositProcessorConfig};
use actors::messages::{BitcoinMonitorMsg, DepositProcessorMsg, PsbtSignerMsg, StarknetMonitorMsg};
use actors::psbt_signer::{PsbtSignerActor, PsbtSignerConfig};
use actors::starknet_monitor::{StarknetMonitorActor, StarknetMonitorConfig};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    info!("Starting watcher-signer service");

    // Load configuration
    let config = Config::from_env()?;
    info!("Configuration loaded");

    // Initialize Bitcoin client
    let bitcoin_client = BitcoinClient::new(
        &config.bitcoin_rpc_url,
        &config.bitcoin_rpc_user,
        &config.bitcoin_rpc_password,
    )?;
    let bitcoin_client_arc: Arc<dyn BitcoinProvider> = Arc::new(bitcoin_client.clone());
    info!("Bitcoin client initialized");

    // Initialize Starknet client
    let starknet_client = StarknetBridgeClient::new(
        &config.starknet_rpc_url,
        &config.bridge_contract_address,
        &config.registry_contract_address,
    )?;
    info!("Starknet client initialized");

    // Create channels for actor communication
    // Data+control channels (higher capacity for throughput)
    let (deposit_tx, deposit_rx) = mpsc::channel::<DepositProcessorMsg>(100);
    let (psbt_tx, psbt_rx) = mpsc::channel::<PsbtSignerMsg>(100);

    // Pure control channels (lower capacity for shutdown signals only)
    let (bitcoin_monitor_tx, bitcoin_monitor_rx) = mpsc::channel::<BitcoinMonitorMsg>(10);
    let (starknet_monitor_tx, starknet_monitor_rx) = mpsc::channel::<StarknetMonitorMsg>(10);

    info!("Channels created");

    // Spawn Bitcoin Monitor actor
    let bitcoin_monitor = BitcoinMonitorActor::new(
        config.bitcoin_multisig_address.clone(),
        bitcoin_client_arc,
        deposit_tx.clone(),
    );
    let bitcoin_monitor_handle = tokio::spawn(async move {
        bitcoin_monitor.run(bitcoin_monitor_rx).await;
    });
    info!("Bitcoin Monitor spawned");

    // Spawn Deposit Processor actor
    let deposit_processor_config = DepositProcessorConfig::default();
    let deposit_processor =
        DepositProcessorActor::new(deposit_processor_config, starknet_client.clone());
    let deposit_processor_handle = tokio::spawn(async move {
        deposit_processor.run(deposit_rx).await;
    });
    info!("Deposit Processor spawned");

    // Spawn Starknet Monitor actor
    let starknet_monitor_config = StarknetMonitorConfig {
        poll_interval_secs: config.starknet_poll_interval_secs,
        start_block: 0, // TODO: Make start_block configurable
    };
    let starknet_monitor = StarknetMonitorActor::new(
        starknet_monitor_config,
        starknet_client.clone(),
        psbt_tx.clone(),
    );
    let starknet_monitor_handle = tokio::spawn(async move {
        starknet_monitor.run(starknet_monitor_rx).await;
    });
    info!("Starknet Monitor spawned");

    // Spawn PSBT Signer actor
    let psbt_signer_config = PsbtSignerConfig::default();
    let psbt_signer = PsbtSignerActor::new(
        psbt_signer_config,
        bitcoin_client,
        starknet_client.clone(),
    );
    let psbt_signer_handle = tokio::spawn(async move {
        psbt_signer.run(psbt_rx).await;
    });
    info!("PSBT Signer spawned");

    info!("All actors running - press Ctrl+C to shutdown");

    // Wait for shutdown signal
    tokio::signal::ctrl_c().await.map_err(anyhow::Error::from)?;
    info!("Shutdown signal received");

    // Send Stop messages to all actors
    // Bitcoin Monitor and Starknet Monitor get Stop on their control channels
    let _ = bitcoin_monitor_tx.send(BitcoinMonitorMsg::Stop).await;
    let _ = starknet_monitor_tx.send(StarknetMonitorMsg::Stop).await;

    // Deposit Processor and PSBT Signer get Stop on their data+control channels
    let _ = deposit_tx.send(DepositProcessorMsg::Stop).await;
    let _ = psbt_tx.send(PsbtSignerMsg::Stop).await;

    info!("Stop signals sent to all actors");

    // Give actors time to finish current operations
    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

    // Drop handles to ensure actors complete
    drop(bitcoin_monitor_handle);
    drop(deposit_processor_handle);
    drop(starknet_monitor_handle);
    drop(psbt_signer_handle);

    info!("Watcher-signer service stopped");

    Ok(())
}
