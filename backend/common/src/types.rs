use crate::error::{BridgeError, Result};
use serde::{Deserialize, Serialize};

const DUST_LIMIT: u64 = 546;
const MAX_SATS: u64 = 2_100_000_000_000_000; // 21M BTC

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Deposit {
    pub txid: String,
    pub starknet_address: String,
    pub amount: u64, // satoshis
    pub confirmations: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Withdrawal {
    pub request_id: String,
    pub btc_address: String,
    pub amount: u64, // satoshis
}

impl Withdrawal {
    pub fn validate_amount(&self) -> Result<()> {
        if self.amount < DUST_LIMIT {
            return Err(BridgeError::Other(anyhow::anyhow!(
                "Amount {} is below dust limit {}",
                self.amount,
                DUST_LIMIT
            )));
        }
        if self.amount > MAX_SATS {
            return Err(BridgeError::Other(anyhow::anyhow!(
                "Amount {} exceeds maximum {}",
                self.amount,
                MAX_SATS
            )));
        }
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct ConfirmedDeposit {
    pub txid: String,
    pub starknet_address: String,
    pub amount: u64,
}

#[derive(Debug, Clone)]
pub struct FinalizedWithdrawal {
    pub request_id: String,
    pub btc_address: String,
    pub amount: u64,
}

impl FinalizedWithdrawal {
    pub fn validate_amount(&self) -> Result<()> {
        if self.amount < DUST_LIMIT {
            return Err(BridgeError::Other(anyhow::anyhow!(
                "Amount {} is below dust limit {}",
                self.amount,
                DUST_LIMIT
            )));
        }
        if self.amount > MAX_SATS {
            return Err(BridgeError::Other(anyhow::anyhow!(
                "Amount {} exceeds maximum {}",
                self.amount,
                MAX_SATS
            )));
        }
        Ok(())
    }
}
