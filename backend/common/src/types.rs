use serde::{Deserialize, Serialize};

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
