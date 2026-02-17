//! Deposit Processor Actor
//!
//! This actor receives confirmed Bitcoin deposits from the Bitcoin Monitor
//! and submits them to the Starknet bridge contract for minting.

use crate::actors::messages::DepositProcessorMsg;
use common::starknet::StarknetProvider;
use common::ConfirmedDeposit;
use tokio::sync::mpsc;
use tracing::{error, info};

/// Configuration for the Deposit Processor actor
#[derive(Debug, Clone)]
pub struct DepositProcessorConfig {
    /// Channel buffer size for incoming messages
    pub channel_buffer_size: usize,
}

impl Default for DepositProcessorConfig {
    fn default() -> Self {
        Self {
            channel_buffer_size: 100,
        }
    }
}

/// Actor that processes confirmed Bitcoin deposits and submits them to Starknet
pub struct DepositProcessorActor<P: StarknetProvider> {
    config: DepositProcessorConfig,
    starknet_client: P,
}

impl<P: StarknetProvider> DepositProcessorActor<P> {
    /// Create a new Deposit Processor actor
    pub fn new(config: DepositProcessorConfig, starknet_client: P) -> Self {
        Self {
            config,
            starknet_client,
        }
    }

    /// Run the actor's main loop
    ///
    /// This method receives messages from the provided channel and processes them.
    /// It returns when a `Stop` message is received.
    pub async fn run(&self, mut rx: mpsc::Receiver<DepositProcessorMsg>) {
        info!("Deposit Processor actor started");

        while let Some(msg) = rx.recv().await {
            match msg {
                DepositProcessorMsg::ProcessDeposit(deposit) => {
                    self.process_deposit(deposit).await;
                }
                DepositProcessorMsg::Stop => {
                    info!("Deposit Processor actor stopping");
                    break;
                }
            }
        }

        info!("Deposit Processor actor stopped");
    }

    /// Process a single confirmed deposit
    ///
    /// Submits the deposit to Starknet. Errors are logged but do not crash the actor.
    async fn process_deposit(&self, deposit: ConfirmedDeposit) {
        info!(
            "Processing deposit: txid={}, amount={}, starknet_address={}",
            deposit.txid, deposit.amount, deposit.starknet_address
        );

        match self.starknet_client.submit_deposit(&deposit).await {
            Ok(tx_hash) => {
                // TODO: Poll get_transaction_receipt() to confirm the tx was included in a block.
                // Currently we trust the submission succeeded but don't verify on-chain confirmation.
                // A rejected/reverted tx means the deposit is lost (BTC locked, no strkBTC minted).
                info!(
                    "Successfully submitted deposit to Starknet: txid={}, starknet_tx={:?}",
                    deposit.txid, tx_hash
                );
            }
            Err(e) => {
                // TODO: Implement retry with exponential backoff for transient failures.
                // Failed deposits are currently lost — user's BTC is locked but strkBTC never minted.
                // Must add dead-letter queue or persistent retry store before production.
                error!(
                    "Failed to submit deposit to Starknet: txid={}, error={}",
                    deposit.txid, e
                );
                // Log the error but continue processing other deposits
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use common::types::ConfirmedDeposit;
    use starknet::core::types::FieldElement;
    use std::sync::{Arc, Mutex};

    /// Mock provider that tracks calls and can be configured to fail
    #[derive(Clone)]
    struct TestMockStarknetProvider {
        should_fail: bool,
        submitted_deposits: Arc<Mutex<Vec<ConfirmedDeposit>>>,
    }

    impl TestMockStarknetProvider {
        fn new(should_fail: bool) -> Self {
            Self {
                should_fail,
                submitted_deposits: Arc::new(Mutex::new(Vec::new())),
            }
        }

        fn get_submitted_deposits(&self) -> Vec<ConfirmedDeposit> {
            self.submitted_deposits.lock().unwrap().clone()
        }
    }

    #[async_trait::async_trait]
    impl StarknetProvider for TestMockStarknetProvider {
        async fn get_withdrawal_requests(
            &self,
            _from_block: u64,
        ) -> common::error::Result<Vec<common::types::Withdrawal>> {
            Ok(vec![])
        }

        async fn submit_deposit(
            &self,
            deposit: &ConfirmedDeposit,
        ) -> common::error::Result<FieldElement> {
            if self.should_fail {
                return Err(common::error::BridgeError::Other(anyhow::anyhow!(
                    "Mock submission failure"
                )));
            }

            self.submitted_deposits.lock().unwrap().push(deposit.clone());
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
            Ok(1000)
        }
    }

    #[tokio::test]
    async fn test_deposit_processor_submits_successfully() {
        let mock = TestMockStarknetProvider::new(false);
        let config = DepositProcessorConfig::default();
        let actor = DepositProcessorActor::new(config, mock.clone());

        let (tx, rx) = mpsc::channel(10);

        // Spawn the actor in the background
        let actor_handle = tokio::spawn(async move {
            actor.run(rx).await;
        });

        // Send a deposit
        let deposit = ConfirmedDeposit {
            txid: "abc123".to_string(),
            starknet_address: "0x456".to_string(),
            amount: 50_000,
        };
        tx.send(DepositProcessorMsg::ProcessDeposit(deposit.clone()))
            .await
            .unwrap();

        // Give it time to process
        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

        // Stop the actor
        tx.send(DepositProcessorMsg::Stop).await.unwrap();
        actor_handle.await.unwrap();

        // Verify the deposit was submitted
        let submitted = mock.get_submitted_deposits();
        assert_eq!(submitted.len(), 1);
        assert_eq!(submitted[0].txid, "abc123");
        assert_eq!(submitted[0].amount, 50_000);
    }

    #[tokio::test]
    async fn test_deposit_processor_handles_errors() {
        let mock = TestMockStarknetProvider::new(true); // Configure to fail
        let config = DepositProcessorConfig::default();
        let actor = DepositProcessorActor::new(config, mock.clone());

        let (tx, rx) = mpsc::channel(10);

        // Spawn the actor in the background
        let actor_handle = tokio::spawn(async move {
            actor.run(rx).await;
        });

        // Send a deposit
        let deposit = ConfirmedDeposit {
            txid: "failing_tx".to_string(),
            starknet_address: "0x789".to_string(),
            amount: 100_000,
        };
        tx.send(DepositProcessorMsg::ProcessDeposit(deposit.clone()))
            .await
            .unwrap();

        // Give it time to process
        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

        // Stop the actor - should not crash despite the error
        tx.send(DepositProcessorMsg::Stop).await.unwrap();
        actor_handle.await.unwrap();

        // Verify no deposits were submitted (due to failure)
        let submitted = mock.get_submitted_deposits();
        assert_eq!(submitted.len(), 0);
    }

    #[tokio::test]
    async fn test_deposit_processor_receives_messages() {
        let mock = TestMockStarknetProvider::new(false);
        let config = DepositProcessorConfig::default();
        let actor = DepositProcessorActor::new(config, mock.clone());

        let (tx, rx) = mpsc::channel(10);

        // Spawn the actor in the background
        let actor_handle = tokio::spawn(async move {
            actor.run(rx).await;
        });

        // Send multiple deposits
        for i in 0..3 {
            let deposit = ConfirmedDeposit {
                txid: format!("tx{}", i),
                starknet_address: "0xabc".to_string(),
                amount: 10_000 * (i + 1),
            };
            tx.send(DepositProcessorMsg::ProcessDeposit(deposit))
                .await
                .unwrap();
        }

        // Give it time to process
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        // Stop the actor
        tx.send(DepositProcessorMsg::Stop).await.unwrap();
        actor_handle.await.unwrap();

        // Verify all deposits were received and submitted
        let submitted = mock.get_submitted_deposits();
        assert_eq!(submitted.len(), 3);
        assert_eq!(submitted[0].txid, "tx0");
        assert_eq!(submitted[1].txid, "tx1");
        assert_eq!(submitted[2].txid, "tx2");
    }
}
