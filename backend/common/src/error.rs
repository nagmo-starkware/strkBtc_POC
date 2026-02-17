use thiserror::Error;

#[derive(Error, Debug)]
pub enum BridgeError {
    #[error("Bitcoin RPC error: {0}")]
    BitcoinRpc(#[from] bitcoincore_rpc::Error),

    #[error("Starknet provider error: {0}")]
    StarknetProvider(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Invalid OP_RETURN data: {0}")]
    InvalidOpReturn(String),

    #[error("PSBT error: {0}")]
    Psbt(String),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Other error: {0}")]
    Other(#[from] anyhow::Error),
}

pub type Result<T> = std::result::Result<T, BridgeError>;
