use crate::error::{BridgeError, Result};
use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    // Bitcoin
    pub bitcoin_rpc_url: String,
    pub bitcoin_rpc_user: String,
    pub bitcoin_rpc_password: String,
    pub bitcoin_multisig_address: String,
    pub bitcoin_private_key: String,
    pub min_confirmations: u32,

    // Starknet
    pub starknet_rpc_url: String,
    pub signer_private_key: String,
    pub bridge_contract_address: String,
    pub registry_contract_address: String,

    // Polling
    pub bitcoin_poll_interval_secs: u64,
    pub starknet_poll_interval_secs: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct BroadcasterConfig {
    // Bitcoin
    pub bitcoin_rpc_url: String,
    pub bitcoin_rpc_user: String,
    pub bitcoin_rpc_password: String,
    pub bitcoin_private_key: String,

    // Starknet
    pub starknet_rpc_url: String,
    pub registry_contract_address: String,
    pub signature_threshold: u32,

    // Polling
    pub registry_poll_interval_secs: u64,
    pub broadcast_check_interval_secs: u64,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        let min_confirmations: u32 = env::var("MIN_CONFIRMATIONS")
            .unwrap_or_else(|_| "6".to_string())
            .parse()
            .map_err(|_| BridgeError::Config("Invalid MIN_CONFIRMATIONS".into()))?;

        if min_confirmations == 0 {
            return Err(BridgeError::Config("MIN_CONFIRMATIONS must be > 0".into()));
        }

        let bitcoin_poll_interval_secs: u64 = env::var("BITCOIN_POLL_INTERVAL_SECS")
            .unwrap_or_else(|_| "600".to_string())
            .parse()
            .map_err(|_| BridgeError::Config("Invalid BITCOIN_POLL_INTERVAL_SECS".into()))?;

        if bitcoin_poll_interval_secs == 0 {
            return Err(BridgeError::Config("BITCOIN_POLL_INTERVAL_SECS must be > 0".into()));
        }

        let starknet_poll_interval_secs: u64 = env::var("STARKNET_POLL_INTERVAL_SECS")
            .unwrap_or_else(|_| "10".to_string())
            .parse()
            .map_err(|_| BridgeError::Config("Invalid STARKNET_POLL_INTERVAL_SECS".into()))?;

        if starknet_poll_interval_secs == 0 {
            return Err(BridgeError::Config("STARKNET_POLL_INTERVAL_SECS must be > 0".into()));
        }

        Ok(Self {
            bitcoin_rpc_url: env::var("BITCOIN_RPC_URL")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_URL not set".into()))?,
            bitcoin_rpc_user: env::var("BITCOIN_RPC_USER")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_USER not set".into()))?,
            bitcoin_rpc_password: env::var("BITCOIN_RPC_PASSWORD")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_PASSWORD not set".into()))?,
            bitcoin_multisig_address: env::var("BITCOIN_MULTISIG_ADDRESS")
                .map_err(|_| BridgeError::Config("BITCOIN_MULTISIG_ADDRESS not set".into()))?,
            bitcoin_private_key: env::var("BITCOIN_PRIVATE_KEY")
                .map_err(|_| BridgeError::Config("BITCOIN_PRIVATE_KEY not set".into()))?,
            min_confirmations,
            starknet_rpc_url: env::var("STARKNET_RPC_URL")
                .map_err(|_| BridgeError::Config("STARKNET_RPC_URL not set".into()))?,
            signer_private_key: env::var("SIGNER_PRIVATE_KEY")
                .map_err(|_| BridgeError::Config("SIGNER_PRIVATE_KEY not set".into()))?,
            bridge_contract_address: env::var("BRIDGE_CONTRACT_ADDRESS")
                .map_err(|_| BridgeError::Config("BRIDGE_CONTRACT_ADDRESS not set".into()))?,
            registry_contract_address: env::var("REGISTRY_CONTRACT_ADDRESS")
                .map_err(|_| BridgeError::Config("REGISTRY_CONTRACT_ADDRESS not set".into()))?,
            bitcoin_poll_interval_secs,
            starknet_poll_interval_secs,
        })
    }
}

impl BroadcasterConfig {
    pub fn from_env() -> Result<Self> {
        let signature_threshold: u32 = env::var("SIGNATURE_THRESHOLD")
            .unwrap_or_else(|_| "3".to_string())
            .parse()
            .map_err(|_| BridgeError::Config("Invalid SIGNATURE_THRESHOLD".into()))?;

        if signature_threshold == 0 {
            return Err(BridgeError::Config("SIGNATURE_THRESHOLD must be > 0".into()));
        }

        let registry_poll_interval_secs: u64 = env::var("REGISTRY_POLL_INTERVAL_SECS")
            .unwrap_or_else(|_| "30".to_string())
            .parse()
            .map_err(|_| BridgeError::Config("Invalid REGISTRY_POLL_INTERVAL_SECS".into()))?;

        if registry_poll_interval_secs == 0 {
            return Err(BridgeError::Config("REGISTRY_POLL_INTERVAL_SECS must be > 0".into()));
        }

        let broadcast_check_interval_secs: u64 = env::var("BROADCAST_CHECK_INTERVAL_SECS")
            .unwrap_or_else(|_| "60".to_string())
            .parse()
            .map_err(|_| BridgeError::Config("Invalid BROADCAST_CHECK_INTERVAL_SECS".into()))?;

        if broadcast_check_interval_secs == 0 {
            return Err(BridgeError::Config("BROADCAST_CHECK_INTERVAL_SECS must be > 0".into()));
        }

        Ok(Self {
            bitcoin_rpc_url: env::var("BITCOIN_RPC_URL")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_URL not set".into()))?,
            bitcoin_rpc_user: env::var("BITCOIN_RPC_USER")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_USER not set".into()))?,
            bitcoin_rpc_password: env::var("BITCOIN_RPC_PASSWORD")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_PASSWORD not set".into()))?,
            bitcoin_private_key: env::var("BITCOIN_PRIVATE_KEY")
                .map_err(|_| BridgeError::Config("BITCOIN_PRIVATE_KEY not set".into()))?,
            starknet_rpc_url: env::var("STARKNET_RPC_URL")
                .map_err(|_| BridgeError::Config("STARKNET_RPC_URL not set".into()))?,
            registry_contract_address: env::var("REGISTRY_CONTRACT_ADDRESS")
                .map_err(|_| BridgeError::Config("REGISTRY_CONTRACT_ADDRESS not set".into()))?,
            signature_threshold,
            registry_poll_interval_secs,
            broadcast_check_interval_secs,
        })
    }
}
