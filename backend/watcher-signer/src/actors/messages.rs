//! Message types for inter-actor communication
//!
//! Each actor has its own message enum defining the commands it can process.
//! All message enums have a `Stop` variant for graceful shutdown.

use common::{ConfirmedDeposit, FinalizedWithdrawal};

/// Messages for the Bitcoin Monitor actor
///
/// The Bitcoin Monitor scans the Bitcoin blockchain for deposits to the bridge address.
#[derive(Debug, Clone)]
pub enum BitcoinMonitorMsg {
    /// Stop the actor gracefully
    Stop,
}

/// Messages for the Deposit Processor actor
///
/// The Deposit Processor handles confirmed Bitcoin deposits and creates Starknet mints.
#[derive(Debug, Clone)]
pub enum DepositProcessorMsg {
    /// Process a confirmed Bitcoin deposit
    ProcessDeposit(ConfirmedDeposit),
    /// Stop the actor gracefully
    Stop,
}

/// Messages for the Starknet Monitor actor
///
/// The Starknet Monitor watches for withdrawal requests on the Starknet contract.
#[derive(Debug, Clone)]
pub enum StarknetMonitorMsg {
    /// Stop the actor gracefully
    Stop,
}

/// Messages for the PSBT Signer actor
///
/// The PSBT Signer creates and signs Bitcoin PSBTs for approved withdrawals.
#[derive(Debug, Clone)]
pub enum PsbtSignerMsg {
    /// Sign and broadcast a withdrawal
    SignWithdrawal(FinalizedWithdrawal),
    /// Stop the actor gracefully
    Stop,
}
