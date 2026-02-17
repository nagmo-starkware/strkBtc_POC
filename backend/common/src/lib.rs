pub mod bitcoin;
pub mod config;
pub mod error;
pub mod types;

pub use bitcoin::{parse_op_return, BitcoinClient};
pub use config::{BroadcasterConfig, Config};
pub use error::{BridgeError, Result};
pub use types::{ConfirmedDeposit, Deposit, FinalizedWithdrawal, Withdrawal};
