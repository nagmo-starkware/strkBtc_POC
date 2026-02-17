//! Starknet Monitor Actor
//!
//! This actor polls the Starknet bridge contract for withdrawal requests
//! and forwards them to the PSBT Signer for Bitcoin transaction creation.

use crate::actors::messages::{PsbtSignerMsg, StarknetMonitorMsg};
use common::starknet::StarknetProvider;
use common::FinalizedWithdrawal;
use std::collections::HashSet;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};
use tracing::{error, info};

/// Configuration for the Starknet Monitor actor
#[derive(Debug, Clone)]
pub struct StarknetMonitorConfig {
    /// Polling interval in seconds (default: 10)
    pub poll_interval_secs: u64,
    /// Block number to start scanning from
    pub start_block: u64,
}

impl Default for StarknetMonitorConfig {
    fn default() -> Self {
        Self {
            poll_interval_secs: 10,
            start_block: 0,
        }
    }
}

/// Actor that monitors Starknet for withdrawal requests
///
/// Polls the Starknet bridge contract every 10 seconds for WithdrawalRequested events,
/// tracks the last checked block, deduplicates requests, and sends FinalizedWithdrawal
/// messages to the PSBT Signer.
pub struct StarknetMonitorActor<P: StarknetProvider> {
    config: StarknetMonitorConfig,
    starknet_client: P,
    psbt_tx: mpsc::Sender<PsbtSignerMsg>,
    seen_request_ids: HashSet<String>,
    last_checked_block: u64,
}

impl<P: StarknetProvider> StarknetMonitorActor<P> {
    /// Create a new Starknet Monitor actor
    ///
    /// # Arguments
    /// * `config` - Configuration including polling interval and start block
    /// * `starknet_client` - Client for interacting with Starknet
    /// * `psbt_tx` - Channel to send withdrawal requests to PSBT Signer
    pub fn new(
        config: StarknetMonitorConfig,
        starknet_client: P,
        psbt_tx: mpsc::Sender<PsbtSignerMsg>,
    ) -> Self {
        let start_block = config.start_block;
        Self {
            config,
            starknet_client,
            psbt_tx,
            seen_request_ids: HashSet::new(),
            last_checked_block: start_block,
        }
    }

    /// Run the actor's main loop
    ///
    /// Polls Starknet every `poll_interval_secs` for withdrawal requests.
    /// Returns when a `Stop` message is received.
    pub async fn run(mut self, mut stop_rx: mpsc::Receiver<StarknetMonitorMsg>) {
        info!(
            "Starknet Monitor actor started (polling every {}s from block {})",
            self.config.poll_interval_secs, self.last_checked_block
        );

        let mut tick = interval(Duration::from_secs(self.config.poll_interval_secs));

        loop {
            tokio::select! {
                _ = tick.tick() => {
                    if let Err(e) = self.check_withdrawals().await {
                        error!("Failed to check withdrawals: {}", e);
                    }
                }
                msg = stop_rx.recv() => {
                    match msg {
                        Some(StarknetMonitorMsg::Stop) => {
                            info!("Starknet Monitor actor stopping");
                            break;
                        }
                        None => {
                            info!("Starknet Monitor actor stop channel closed");
                            break;
                        }
                    }
                }
            }
        }

        info!("Starknet Monitor actor stopped");
    }

    /// Check for new withdrawal requests
    ///
    /// Queries Starknet for WithdrawalRequested events since the last checked block,
    /// deduplicates them, and sends them to the PSBT Signer.
    async fn check_withdrawals(&mut self) -> common::error::Result<()> {
        info!(
            "Checking Starknet withdrawals from block {}",
            self.last_checked_block
        );

        // Get withdrawal requests from Starknet
        let withdrawals = self
            .starknet_client
            .get_withdrawal_requests(self.last_checked_block)
            .await?;

        info!("Found {} withdrawal requests", withdrawals.len());

        // Process each withdrawal
        for withdrawal in withdrawals {
            // Skip if already seen (deduplication)
            if self.seen_request_ids.contains(&withdrawal.request_id) {
                info!(
                    "Skipping duplicate withdrawal request: {}",
                    withdrawal.request_id
                );
                continue;
            }

            info!(
                "Processing withdrawal request: id={}, btc_address={}, amount={}",
                withdrawal.request_id, withdrawal.btc_address, withdrawal.amount
            );

            // Convert to FinalizedWithdrawal and send to PSBT Signer
            let finalized = FinalizedWithdrawal {
                request_id: withdrawal.request_id.clone(),
                btc_address: withdrawal.btc_address.clone(),
                amount: withdrawal.amount,
            };

            if let Err(e) = self.psbt_tx.send(PsbtSignerMsg::SignWithdrawal(finalized)).await {
                error!(
                    "Failed to send withdrawal to PSBT Signer: id={}, error={}",
                    withdrawal.request_id, e
                );
                continue;
            }

            // Mark as seen
            self.seen_request_ids.insert(withdrawal.request_id.clone());
            info!("Withdrawal request sent to PSBT Signer: {}", withdrawal.request_id);
        }

        // Update last checked block
        let latest_block = self.starknet_client.get_latest_block().await?;
        info!(
            "Updating last checked block: {} -> {}",
            self.last_checked_block, latest_block
        );
        self.last_checked_block = latest_block;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use common::types::Withdrawal;
    use starknet::core::types::FieldElement;
    use std::sync::{Arc, Mutex};

    /// Mock provider that returns configurable withdrawals for testing
    #[derive(Clone)]
    struct TestMockStarknetProvider {
        withdrawals: Vec<Withdrawal>,
        latest_block: u64,
    }

    impl TestMockStarknetProvider {
        fn new(withdrawals: Vec<Withdrawal>, latest_block: u64) -> Self {
            Self {
                withdrawals,
                latest_block,
            }
        }
    }

    #[async_trait::async_trait]
    impl StarknetProvider for TestMockStarknetProvider {
        async fn get_withdrawal_requests(
            &self,
            _from_block: u64,
        ) -> common::error::Result<Vec<Withdrawal>> {
            Ok(self.withdrawals.clone())
        }

        async fn submit_deposit(
            &self,
            _deposit: &common::types::ConfirmedDeposit,
        ) -> common::error::Result<FieldElement> {
            Ok(FieldElement::from_hex_be("0x1234").unwrap())
        }

        async fn submit_psbt(
            &self,
            _withdrawal_id: &str,
            _psbt: Vec<u8>,
        ) -> common::error::Result<FieldElement> {
            Ok(FieldElement::from_hex_be("0x5678").unwrap())
        }

        async fn get_latest_block(&self) -> common::error::Result<u64> {
            Ok(self.latest_block)
        }
    }

    #[tokio::test]
    async fn test_starknet_monitor_detects_withdrawals() {
        let withdrawal = Withdrawal {
            request_id: "req1".to_string(),
            btc_address: "bc1qtest123".to_string(),
            amount: 50_000,
        };

        let mock = TestMockStarknetProvider::new(vec![withdrawal.clone()], 1000);
        let config = StarknetMonitorConfig {
            poll_interval_secs: 10,
            start_block: 900,
        };

        let (psbt_tx, mut psbt_rx) = mpsc::channel::<PsbtSignerMsg>(10);
        let (_stop_tx, _stop_rx) = mpsc::channel::<StarknetMonitorMsg>(1);

        let mut actor = StarknetMonitorActor::new(config, mock, psbt_tx);

        // Run check_withdrawals directly
        actor.check_withdrawals().await.unwrap();

        // Should receive the withdrawal
        let msg = tokio::time::timeout(Duration::from_millis(100), psbt_rx.recv())
            .await
            .expect("Should receive withdrawal")
            .expect("Channel should not be closed");

        match msg {
            PsbtSignerMsg::SignWithdrawal(finalized) => {
                assert_eq!(finalized.request_id, "req1");
                assert_eq!(finalized.btc_address, "bc1qtest123");
                assert_eq!(finalized.amount, 50_000);
            }
            _ => panic!("Expected SignWithdrawal message"),
        }

        // Verify block number was updated
        assert_eq!(actor.last_checked_block, 1000);
    }

    #[tokio::test]
    async fn test_starknet_monitor_deduplicates() {
        let withdrawal = Withdrawal {
            request_id: "req2".to_string(),
            btc_address: "bc1qtest456".to_string(),
            amount: 100_000,
        };

        let mock = TestMockStarknetProvider::new(vec![withdrawal.clone()], 1001);
        let config = StarknetMonitorConfig::default();

        let (psbt_tx, mut psbt_rx) = mpsc::channel::<PsbtSignerMsg>(10);
        let (_stop_tx, _stop_rx) = mpsc::channel::<StarknetMonitorMsg>(1);

        let mut actor = StarknetMonitorActor::new(config, mock, psbt_tx);

        // First check
        actor.check_withdrawals().await.unwrap();
        let msg1 = psbt_rx.recv().await.expect("Should receive first withdrawal");

        // Verify first message
        match msg1 {
            PsbtSignerMsg::SignWithdrawal(finalized) => {
                assert_eq!(finalized.request_id, "req2");
            }
            _ => panic!("Expected SignWithdrawal message"),
        }

        // Second check - should deduplicate
        actor.check_withdrawals().await.unwrap();
        tokio::time::timeout(Duration::from_millis(100), psbt_rx.recv())
            .await
            .expect_err("Should timeout - duplicate should be skipped");
    }

    #[tokio::test]
    async fn test_starknet_monitor_updates_block_number() {
        let mock = TestMockStarknetProvider::new(vec![], 2000);
        let config = StarknetMonitorConfig {
            poll_interval_secs: 10,
            start_block: 1500,
        };

        let (psbt_tx, _psbt_rx) = mpsc::channel::<PsbtSignerMsg>(10);
        let (_stop_tx, _stop_rx) = mpsc::channel::<StarknetMonitorMsg>(1);

        let mut actor = StarknetMonitorActor::new(config, mock, psbt_tx);

        // Verify starting block
        assert_eq!(actor.last_checked_block, 1500);

        // Run check
        actor.check_withdrawals().await.unwrap();

        // Verify block was updated to latest
        assert_eq!(actor.last_checked_block, 2000);
    }
}
