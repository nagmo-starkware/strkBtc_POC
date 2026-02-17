//! PSBT Signer Actor
//!
//! This actor receives finalized withdrawals from the Starknet Monitor,
//! creates deterministic PSBTs for Bitcoin transactions, and submits them
//! to the Starknet registry contract.

use crate::actors::messages::PsbtSignerMsg;
use common::bitcoin::BitcoinProvider;
use common::starknet::StarknetProvider;
use common::FinalizedWithdrawal;
use tokio::sync::mpsc;
use tracing::{error, info};

/// Configuration for the PSBT Signer actor
#[derive(Debug, Clone)]
pub struct PsbtSignerConfig {
    // Configuration will be expanded when we implement real PSBT creation
    // For now, this is a placeholder for future settings like:
    // - signing keys
    // - fee rate
    // - UTXO selection strategy
}

impl Default for PsbtSignerConfig {
    fn default() -> Self {
        Self {}
    }
}

/// Actor that creates and signs Bitcoin PSBTs for withdrawals
///
/// Receives FinalizedWithdrawal messages from the Starknet Monitor,
/// creates deterministic PSBTs using SIGHASH_ANYONECANPAY (stub for now),
/// and submits them to the Starknet registry contract.
pub struct PsbtSignerActor<B: BitcoinProvider, S: StarknetProvider> {
    #[allow(dead_code)] // Will be used when implementing real PSBT creation
    config: PsbtSignerConfig,
    #[allow(dead_code)] // Will be used when implementing real PSBT creation
    bitcoin_client: B,
    starknet_client: S,
}

impl<B: BitcoinProvider, S: StarknetProvider> PsbtSignerActor<B, S> {
    /// Create a new PSBT Signer actor
    ///
    /// # Arguments
    /// * `config` - Configuration for PSBT creation
    /// * `bitcoin_client` - Client for Bitcoin operations (UTXO selection, broadcasting)
    /// * `starknet_client` - Client for submitting PSBTs to registry
    pub fn new(config: PsbtSignerConfig, bitcoin_client: B, starknet_client: S) -> Self {
        Self {
            config,
            bitcoin_client,
            starknet_client,
        }
    }

    /// Run the actor's main loop
    ///
    /// Processes PsbtSignerMsg::SignWithdrawal messages until a Stop message is received.
    pub async fn run(self, mut msg_rx: mpsc::Receiver<PsbtSignerMsg>) {
        info!("PSBT Signer actor started");

        loop {
            match msg_rx.recv().await {
                Some(PsbtSignerMsg::SignWithdrawal(withdrawal)) => {
                    info!(
                        "Received withdrawal to sign: id={}, btc_address={}, amount={}",
                        withdrawal.request_id, withdrawal.btc_address, withdrawal.amount
                    );

                    if let Err(e) = self.sign_withdrawal(&withdrawal).await {
                        error!(
                            "Failed to sign withdrawal {}: {}",
                            withdrawal.request_id, e
                        );
                    }
                }
                Some(PsbtSignerMsg::Stop) => {
                    info!("PSBT Signer actor stopping");
                    break;
                }
                None => {
                    info!("PSBT Signer actor message channel closed");
                    break;
                }
            }
        }

        info!("PSBT Signer actor stopped");
    }

    /// Sign a withdrawal by creating a PSBT and submitting it to Starknet
    ///
    /// # Arguments
    /// * `withdrawal` - The finalized withdrawal to process
    ///
    /// # Returns
    /// Result indicating success or failure
    async fn sign_withdrawal(&self, withdrawal: &FinalizedWithdrawal) -> common::error::Result<()> {
        info!(
            "Creating PSBT for withdrawal: id={}",
            withdrawal.request_id
        );

        // Create the PSBT (currently a stub)
        let psbt = self.create_psbt(withdrawal).await?;

        info!(
            "Created PSBT for withdrawal {} ({} bytes)",
            withdrawal.request_id,
            psbt.len()
        );

        // Submit PSBT to Starknet registry
        let tx_hash = self
            .starknet_client
            .submit_psbt(&withdrawal.request_id, psbt)
            .await?;

        info!(
            "Successfully submitted PSBT for withdrawal {}: tx_hash={:#x}",
            withdrawal.request_id, tx_hash
        );

        Ok(())
    }

    /// Create a deterministic PSBT for a withdrawal
    ///
    /// # Arguments
    /// * `withdrawal` - The withdrawal to create a PSBT for
    ///
    /// # Returns
    /// PSBT bytes
    ///
    /// # Note
    /// This is currently a stub that returns the PSBT magic bytes.
    /// Real implementation will use SIGHASH_ANYONECANPAY to allow
    /// multiple signers to add inputs for fee funding.
    async fn create_psbt(&self, _withdrawal: &FinalizedWithdrawal) -> common::error::Result<Vec<u8>> {
        // TODO: Implement real PSBT creation with:
        // 1. Select UTXOs for the withdrawal amount
        // 2. Create output to withdrawal.btc_address for withdrawal.amount
        // 3. Add fee funding input placeholder
        // 4. Sign with SIGHASH_ANYONECANPAY to allow additional inputs
        // 5. Serialize to PSBT format

        // For now, return PSBT magic bytes as a stub
        Ok(vec![0x70, 0x73, 0x62, 0x74]) // "psbt" in hex
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use bitcoin::{Transaction, Txid};
    use common::bitcoin::BitcoinProvider;
    use common::starknet::StarknetProvider;
    use common::types::{ConfirmedDeposit, Withdrawal};
    use starknet::core::types::FieldElement;
    use std::sync::{Arc, Mutex};
    use tokio::time::Duration;

    // Mock Bitcoin Provider for testing
    #[derive(Clone)]
    struct MockBitcoinProvider;

    #[async_trait]
    impl BitcoinProvider for MockBitcoinProvider {
        async fn get_transaction(&self, _txid: &Txid) -> common::error::Result<Transaction> {
            unimplemented!("Not needed for PSBT signer tests")
        }

        async fn get_confirmations(&self, _txid: &Txid) -> common::error::Result<u32> {
            unimplemented!("Not needed for PSBT signer tests")
        }

        async fn list_transactions_to_address(
            &self,
            _address: &str,
            _count: usize,
        ) -> common::error::Result<Vec<(Txid, u32)>> {
            unimplemented!("Not needed for PSBT signer tests")
        }

        async fn broadcast_transaction(&self, _tx: &Transaction) -> common::error::Result<Txid> {
            unimplemented!("Not needed for PSBT signer tests")
        }
    }

    // Mock Starknet Provider that tracks PSBT submissions
    #[derive(Clone)]
    struct MockStarknetProvider {
        submitted_psbts: Arc<Mutex<Vec<(String, Vec<u8>)>>>,
        should_fail: bool,
    }

    impl MockStarknetProvider {
        fn new() -> Self {
            Self {
                submitted_psbts: Arc::new(Mutex::new(Vec::new())),
                should_fail: false,
            }
        }

        fn with_failure() -> Self {
            Self {
                submitted_psbts: Arc::new(Mutex::new(Vec::new())),
                should_fail: true,
            }
        }

        fn get_submitted_psbts(&self) -> Vec<(String, Vec<u8>)> {
            self.submitted_psbts.lock().unwrap().clone()
        }
    }

    #[async_trait]
    impl StarknetProvider for MockStarknetProvider {
        async fn get_withdrawal_requests(
            &self,
            _from_block: u64,
        ) -> common::error::Result<Vec<Withdrawal>> {
            unimplemented!("Not needed for PSBT signer tests")
        }

        async fn submit_deposit(
            &self,
            _deposit: &ConfirmedDeposit,
        ) -> common::error::Result<FieldElement> {
            unimplemented!("Not needed for PSBT signer tests")
        }

        async fn submit_psbt(
            &self,
            withdrawal_id: &str,
            psbt: Vec<u8>,
        ) -> common::error::Result<FieldElement> {
            if self.should_fail {
                return Err(common::BridgeError::Other(anyhow::anyhow!(
                    "Mock submission failure"
                )));
            }

            self.submitted_psbts
                .lock()
                .unwrap()
                .push((withdrawal_id.to_string(), psbt));
            Ok(FieldElement::from_hex_be("0xabcd").unwrap())
        }

        async fn get_latest_block(&self) -> common::error::Result<u64> {
            unimplemented!("Not needed for PSBT signer tests")
        }
    }

    #[tokio::test]
    async fn test_psbt_signer_creates_psbt() {
        let bitcoin_client = MockBitcoinProvider;
        let starknet_client = MockStarknetProvider::new();
        let config = PsbtSignerConfig::default();

        let actor = PsbtSignerActor::new(config, bitcoin_client, starknet_client);

        let withdrawal = FinalizedWithdrawal {
            request_id: "req1".to_string(),
            btc_address: "bc1qtest123".to_string(),
            amount: 50_000,
        };

        let psbt = actor.create_psbt(&withdrawal).await.unwrap();

        // Verify PSBT magic bytes
        assert_eq!(psbt, vec![0x70, 0x73, 0x62, 0x74]);
    }

    #[tokio::test]
    async fn test_psbt_signer_submits_successfully() {
        let bitcoin_client = MockBitcoinProvider;
        let starknet_client = MockStarknetProvider::new();
        let config = PsbtSignerConfig::default();

        let actor = PsbtSignerActor::new(config, bitcoin_client, starknet_client.clone());

        let withdrawal = FinalizedWithdrawal {
            request_id: "req2".to_string(),
            btc_address: "bc1qtest456".to_string(),
            amount: 100_000,
        };

        actor.sign_withdrawal(&withdrawal).await.unwrap();

        // Verify PSBT was submitted
        let submitted = starknet_client.get_submitted_psbts();
        assert_eq!(submitted.len(), 1);
        assert_eq!(submitted[0].0, "req2");
        assert_eq!(submitted[0].1, vec![0x70, 0x73, 0x62, 0x74]);
    }

    #[tokio::test]
    async fn test_psbt_signer_handles_errors() {
        let bitcoin_client = MockBitcoinProvider;
        let starknet_client = MockStarknetProvider::with_failure();
        let config = PsbtSignerConfig::default();

        let actor = PsbtSignerActor::new(config, bitcoin_client, starknet_client);

        let withdrawal = FinalizedWithdrawal {
            request_id: "req3".to_string(),
            btc_address: "bc1qtest789".to_string(),
            amount: 75_000,
        };

        let result = actor.sign_withdrawal(&withdrawal).await;

        // Should return an error
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_psbt_signer_receives_messages() {
        let bitcoin_client = MockBitcoinProvider;
        let starknet_client = MockStarknetProvider::new();
        let config = PsbtSignerConfig::default();

        let (msg_tx, msg_rx) = mpsc::channel::<PsbtSignerMsg>(10);

        let actor = PsbtSignerActor::new(config, bitcoin_client, starknet_client.clone());

        // Spawn actor in background
        let actor_handle = tokio::spawn(async move {
            actor.run(msg_rx).await;
        });

        // Send a withdrawal
        let withdrawal = FinalizedWithdrawal {
            request_id: "req4".to_string(),
            btc_address: "bc1qtest000".to_string(),
            amount: 25_000,
        };

        msg_tx
            .send(PsbtSignerMsg::SignWithdrawal(withdrawal))
            .await
            .unwrap();

        // Give actor time to process
        tokio::time::sleep(Duration::from_millis(50)).await;

        // Send stop
        msg_tx.send(PsbtSignerMsg::Stop).await.unwrap();

        // Wait for actor to finish
        actor_handle.await.unwrap();

        // Verify PSBT was submitted
        let submitted = starknet_client.get_submitted_psbts();
        assert_eq!(submitted.len(), 1);
        assert_eq!(submitted[0].0, "req4");
    }
}
