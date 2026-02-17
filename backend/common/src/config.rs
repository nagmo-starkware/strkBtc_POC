use crate::error::{BridgeError, Result};
use std::env;

/// Read a required environment variable, returning a config error if missing.
fn required_env(name: &str) -> Result<String> {
    env::var(name).map_err(|_| BridgeError::Config(format!("{name} not set")))
}

/// Read an optional environment variable with a default, parse it as the target type.
fn parse_env_or<T: std::str::FromStr>(name: &str, default: &str) -> Result<T> {
    let raw = env::var(name).unwrap_or_else(|_| default.to_string());
    raw.parse()
        .map_err(|_| BridgeError::Config(format!("Invalid {name}")))
}

/// Read an optional env var with a default and validate it's > 0.
fn parse_positive_env<T: std::str::FromStr + PartialOrd + Default>(
    name: &str,
    default: &str,
) -> Result<T> {
    let val = parse_env_or::<T>(name, default)?;
    if val <= T::default() {
        return Err(BridgeError::Config(format!("{name} must be > 0")));
    }
    Ok(val)
}

#[derive(Debug, Clone)]
pub struct Config {
    // Bitcoin
    pub bitcoin_rpc_url: String,
    pub bitcoin_rpc_user: String,
    pub bitcoin_rpc_password: String,
    pub bitcoin_multisig_address: String,
    // SECURITY TODO: Private keys should not be stored in environment variables in production.
    // Migrate to Google Secret Manager, HashiCorp Vault, or HSM-backed key storage.
    pub bitcoin_private_key: String,
    pub min_confirmations: u32,

    // Starknet
    pub starknet_rpc_url: String,
    // SECURITY TODO: Private keys should not be stored in environment variables in production.
    // Migrate to Google Secret Manager, HashiCorp Vault, or HSM-backed key storage.
    pub signer_private_key: String,
    pub bridge_contract_address: String,
    pub registry_contract_address: String,

    // Polling
    pub bitcoin_poll_interval_secs: u64,
    pub starknet_poll_interval_secs: u64,
}

#[derive(Debug, Clone)]
pub struct BroadcasterConfig {
    // Bitcoin
    pub bitcoin_rpc_url: String,
    pub bitcoin_rpc_user: String,
    pub bitcoin_rpc_password: String,
    // SECURITY TODO: Private keys should not be stored in environment variables in production.
    // Migrate to Google Secret Manager, HashiCorp Vault, or HSM-backed key storage.
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
        let config = Self {
            bitcoin_rpc_url: required_env("BITCOIN_RPC_URL")?,
            bitcoin_rpc_user: required_env("BITCOIN_RPC_USER")?,
            bitcoin_rpc_password: required_env("BITCOIN_RPC_PASSWORD")?,
            bitcoin_multisig_address: required_env("BITCOIN_MULTISIG_ADDRESS")?,
            bitcoin_private_key: required_env("BITCOIN_PRIVATE_KEY")?,
            min_confirmations: parse_positive_env("MIN_CONFIRMATIONS", "6")?,
            starknet_rpc_url: required_env("STARKNET_RPC_URL")?,
            signer_private_key: required_env("SIGNER_PRIVATE_KEY")?,
            bridge_contract_address: required_env("BRIDGE_CONTRACT_ADDRESS")?,
            registry_contract_address: required_env("REGISTRY_CONTRACT_ADDRESS")?,
            bitcoin_poll_interval_secs: parse_positive_env("BITCOIN_POLL_INTERVAL_SECS", "600")?,
            starknet_poll_interval_secs: parse_positive_env("STARKNET_POLL_INTERVAL_SECS", "10")?,
        };

        // Validate URLs
        if !config.bitcoin_rpc_url.starts_with("http://") && !config.bitcoin_rpc_url.starts_with("https://") {
            return Err(BridgeError::Config("BITCOIN_RPC_URL must start with http:// or https://".to_string()));
        }
        if !config.starknet_rpc_url.starts_with("http://") && !config.starknet_rpc_url.starts_with("https://") {
            return Err(BridgeError::Config("STARKNET_RPC_URL must start with http:// or https://".to_string()));
        }

        // Validate contract addresses
        if !config.bridge_contract_address.starts_with("0x") {
            return Err(BridgeError::Config("BRIDGE_CONTRACT_ADDRESS must start with 0x".to_string()));
        }
        if !config.registry_contract_address.starts_with("0x") {
            return Err(BridgeError::Config("REGISTRY_CONTRACT_ADDRESS must start with 0x".to_string()));
        }

        tracing::info!("Config validation passed");
        tracing::info!("Bitcoin RPC: {}", config.bitcoin_rpc_url);
        tracing::info!("Starknet RPC: {}", config.starknet_rpc_url);
        tracing::info!("Bridge contract: {}", config.bridge_contract_address);
        tracing::info!("Registry contract: {}", config.registry_contract_address);

        Ok(config)
    }
}

impl BroadcasterConfig {
    pub fn from_env() -> Result<Self> {
        let config = Self {
            bitcoin_rpc_url: required_env("BITCOIN_RPC_URL")?,
            bitcoin_rpc_user: required_env("BITCOIN_RPC_USER")?,
            bitcoin_rpc_password: required_env("BITCOIN_RPC_PASSWORD")?,
            bitcoin_private_key: required_env("BITCOIN_PRIVATE_KEY")?,
            starknet_rpc_url: required_env("STARKNET_RPC_URL")?,
            registry_contract_address: required_env("REGISTRY_CONTRACT_ADDRESS")?,
            signature_threshold: parse_positive_env("SIGNATURE_THRESHOLD", "3")?,
            registry_poll_interval_secs: parse_positive_env("REGISTRY_POLL_INTERVAL_SECS", "30")?,
            broadcast_check_interval_secs: parse_positive_env("BROADCAST_CHECK_INTERVAL_SECS", "60")?,
        };

        // Validate URLs
        if !config.bitcoin_rpc_url.starts_with("http://") && !config.bitcoin_rpc_url.starts_with("https://") {
            return Err(BridgeError::Config("BITCOIN_RPC_URL must start with http:// or https://".to_string()));
        }
        if !config.starknet_rpc_url.starts_with("http://") && !config.starknet_rpc_url.starts_with("https://") {
            return Err(BridgeError::Config("STARKNET_RPC_URL must start with http:// or https://".to_string()));
        }

        // Validate contract address
        if !config.registry_contract_address.starts_with("0x") {
            return Err(BridgeError::Config("REGISTRY_CONTRACT_ADDRESS must start with 0x".to_string()));
        }

        tracing::info!("BroadcasterConfig validation passed");
        tracing::info!("Bitcoin RPC: {}", config.bitcoin_rpc_url);
        tracing::info!("Starknet RPC: {}", config.starknet_rpc_url);
        tracing::info!("Registry contract: {}", config.registry_contract_address);

        Ok(config)
    }
}
