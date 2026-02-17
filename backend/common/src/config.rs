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

#[derive(Debug, Clone)]
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
        Ok(Self {
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
        })
    }
}

impl BroadcasterConfig {
    pub fn from_env() -> Result<Self> {
        Ok(Self {
            bitcoin_rpc_url: required_env("BITCOIN_RPC_URL")?,
            bitcoin_rpc_user: required_env("BITCOIN_RPC_USER")?,
            bitcoin_rpc_password: required_env("BITCOIN_RPC_PASSWORD")?,
            bitcoin_private_key: required_env("BITCOIN_PRIVATE_KEY")?,
            starknet_rpc_url: required_env("STARKNET_RPC_URL")?,
            registry_contract_address: required_env("REGISTRY_CONTRACT_ADDRESS")?,
            signature_threshold: parse_positive_env("SIGNATURE_THRESHOLD", "3")?,
            registry_poll_interval_secs: parse_positive_env("REGISTRY_POLL_INTERVAL_SECS", "30")?,
            broadcast_check_interval_secs: parse_positive_env("BROADCAST_CHECK_INTERVAL_SECS", "60")?,
        })
    }
}
