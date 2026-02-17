use super::messages::{BitcoinMonitorMsg, DepositProcessorMsg};
use common::{parse_op_return, BitcoinProvider, ConfirmedDeposit, Result};
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};
use tracing::{error, info, warn};

pub struct BitcoinMonitorActor {
    multisig_address: String,
    bitcoin_client: Arc<dyn BitcoinProvider>,
    deposit_tx: mpsc::Sender<DepositProcessorMsg>,
    seen_txids: HashSet<String>,
}

impl BitcoinMonitorActor {
    pub fn new(
        multisig_address: String,
        bitcoin_client: Arc<dyn BitcoinProvider>,
        deposit_tx: mpsc::Sender<DepositProcessorMsg>,
    ) -> Self {
        Self {
            multisig_address,
            bitcoin_client,
            deposit_tx,
            seen_txids: HashSet::new(),
        }
    }

    pub async fn run(mut self, mut stop_rx: mpsc::Receiver<BitcoinMonitorMsg>) {
        let mut tick = interval(Duration::from_secs(600)); // 10 minutes

        loop {
            tokio::select! {
                _ = tick.tick() => {
                    if let Err(e) = self.check_deposits().await {
                        error!("Failed to check deposits: {}", e);
                    }
                }
                msg = stop_rx.recv() => {
                    match msg {
                        Some(BitcoinMonitorMsg::Stop) => {
                            info!("BitcoinMonitorActor stopping");
                            break;
                        }
                        None => {
                            info!("BitcoinMonitorActor stop channel closed");
                            break;
                        }
                    }
                }
            }
        }
    }

    async fn check_deposits(&mut self) -> Result<()> {
        info!("Checking Bitcoin deposits to {}", self.multisig_address);

        let txs = self
            .bitcoin_client
            .list_transactions_to_address(&self.multisig_address, 100)
            .await?;

        for (txid, confirmations) in txs {
            let txid_str = txid.to_string();

            // Skip if already seen
            if self.seen_txids.contains(&txid_str) {
                continue;
            }

            // Check confirmations
            if confirmations < 6 {
                warn!(
                    "Transaction {} has {} confirmations, waiting for 6",
                    txid_str, confirmations
                );
                continue;
            }

            // Get full transaction
            let tx = self.bitcoin_client.get_transaction(&txid).await?;

            // Parse OP_RETURN for Starknet address
            let starknet_address = match parse_op_return(&tx)? {
                Some(data) => {
                    if data.len() == 32 {
                        hex::encode(&data)
                    } else {
                        warn!("Invalid OP_RETURN data length: {}", data.len());
                        continue;
                    }
                }
                None => {
                    warn!("No OP_RETURN found in transaction {}", txid_str);
                    continue;
                }
            };

            // Calculate deposit amount (placeholder for now)
            let amount_sats = calculate_deposit_amount(&tx);

            info!(
                "Detected confirmed deposit: {} BTC from {} to {}",
                amount_sats, txid_str, starknet_address
            );

            // Send to deposit processor
            let deposit = ConfirmedDeposit {
                txid: txid_str.clone(),
                amount: amount_sats,
                starknet_address: starknet_address.clone(),
            };

            let msg = DepositProcessorMsg::ProcessDeposit(deposit);

            if let Err(e) = self.deposit_tx.send(msg).await {
                error!("Failed to send deposit message: {}", e);
                continue;
            }

            // Mark as seen
            self.seen_txids.insert(txid_str);
        }

        Ok(())
    }
}

// Placeholder - will implement proper calculation later
fn calculate_deposit_amount(_tx: &bitcoin::Transaction) -> u64 {
    100_000 // 100k sats
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use bitcoin::{Transaction, Txid};
    use std::str::FromStr;

    struct MockBitcoinProvider {
        txs: Vec<(Txid, u32)>,
        tx_data: std::collections::HashMap<Txid, Transaction>,
    }

    #[async_trait]
    impl BitcoinProvider for MockBitcoinProvider {
        async fn get_transaction(&self, txid: &Txid) -> Result<Transaction> {
            self.tx_data
                .get(txid)
                .cloned()
                .ok_or_else(|| common::BridgeError::Other(anyhow::anyhow!("tx not found")))
        }

        async fn get_confirmations(&self, txid: &Txid) -> Result<u32> {
            self.txs
                .iter()
                .find(|(t, _)| t == txid)
                .map(|(_, c)| *c)
                .ok_or_else(|| common::BridgeError::Other(anyhow::anyhow!("tx not found")))
        }

        async fn list_transactions_to_address(
            &self,
            _address: &str,
            _count: usize,
        ) -> Result<Vec<(Txid, u32)>> {
            Ok(self.txs.clone())
        }

        async fn broadcast_transaction(&self, _tx: &Transaction) -> Result<Txid> {
            unimplemented!()
        }
    }

    fn create_mock_tx_with_op_return(op_return_data: Vec<u8>) -> Transaction {
        use bitcoin::blockdata::script::Builder;
        use bitcoin::blockdata::transaction::{Transaction, TxIn, TxOut};
        use bitcoin::opcodes;
        use bitcoin::Amount;
        use bitcoin::script::PushBytesBuf;

        let push_bytes = PushBytesBuf::try_from(op_return_data).unwrap();
        let script = Builder::new()
            .push_opcode(opcodes::all::OP_RETURN)
            .push_slice(push_bytes)
            .into_script();

        Transaction {
            version: bitcoin::transaction::Version::TWO,
            lock_time: bitcoin::absolute::LockTime::ZERO,
            input: vec![TxIn::default()],
            output: vec![TxOut {
                value: Amount::from_sat(100_000),
                script_pubkey: script,
            }],
        }
    }

    #[tokio::test]
    async fn test_bitcoin_monitor_skips_unconfirmed() {
        let txid = Txid::from_str(
            "0000000000000000000000000000000000000000000000000000000000000001",
        )
        .unwrap();

        let mock_provider = Arc::new(MockBitcoinProvider {
            txs: vec![(txid, 3)], // Only 3 confirmations
            tx_data: std::collections::HashMap::new(),
        });

        let (deposit_tx, mut deposit_rx) = mpsc::channel::<DepositProcessorMsg>(10);
        let (_stop_tx, stop_rx) = mpsc::channel::<BitcoinMonitorMsg>(1);

        let actor = BitcoinMonitorActor::new(
            "bc1qtest".to_string(),
            mock_provider,
            deposit_tx,
        );

        tokio::spawn(async move {
            actor.run(stop_rx).await;
        });

        // Wait briefly
        tokio::time::sleep(Duration::from_millis(100)).await;

        // Should not receive any deposits (channel still open, but no messages)
        let result = tokio::time::timeout(Duration::from_millis(100), deposit_rx.recv()).await;
        assert!(result.is_err(), "Should timeout - no deposits expected");

        // Stop the actor
        _stop_tx.send(BitcoinMonitorMsg::Stop).await.unwrap();
    }

    #[tokio::test]
    async fn test_bitcoin_monitor_processes_confirmed() {
        let txid = Txid::from_str(
            "0000000000000000000000000000000000000000000000000000000000000002",
        )
        .unwrap();

        let starknet_addr = vec![0u8; 32]; // Valid 32-byte address
        let tx = create_mock_tx_with_op_return(starknet_addr.clone());

        let mut tx_data = std::collections::HashMap::new();
        tx_data.insert(txid, tx);

        let mock_provider = Arc::new(MockBitcoinProvider {
            txs: vec![(txid, 6)], // 6 confirmations
            tx_data,
        });

        let (deposit_tx, mut deposit_rx) = mpsc::channel::<DepositProcessorMsg>(10);
        let (_stop_tx, _stop_rx) = mpsc::channel::<BitcoinMonitorMsg>(1);

        let mut actor = BitcoinMonitorActor::new(
            "bc1qtest".to_string(),
            mock_provider,
            deposit_tx,
        );

        // Run check_deposits directly
        actor.check_deposits().await.unwrap();

        // Should receive the deposit
        let msg = tokio::time::timeout(Duration::from_millis(100), deposit_rx.recv())
            .await
            .expect("Should receive deposit")
            .expect("Channel should not be closed");

        match msg {
            DepositProcessorMsg::ProcessDeposit(deposit) => {
                assert_eq!(deposit.txid, txid.to_string());
                assert_eq!(deposit.amount, 100_000);
                assert_eq!(deposit.starknet_address, hex::encode(starknet_addr));
            }
            _ => panic!("Expected ProcessDeposit message"),
        }
    }

    #[tokio::test]
    async fn test_bitcoin_monitor_deduplicates() {
        let txid = Txid::from_str(
            "0000000000000000000000000000000000000000000000000000000000000003",
        )
        .unwrap();

        let starknet_addr = vec![1u8; 32];
        let tx = create_mock_tx_with_op_return(starknet_addr.clone());

        let mut tx_data = std::collections::HashMap::new();
        tx_data.insert(txid, tx);

        let mock_provider = Arc::new(MockBitcoinProvider {
            txs: vec![(txid, 6)],
            tx_data,
        });

        let (deposit_tx, mut deposit_rx) = mpsc::channel::<DepositProcessorMsg>(10);
        let (_stop_tx, _stop_rx) = mpsc::channel::<BitcoinMonitorMsg>(1);

        let mut actor = BitcoinMonitorActor::new(
            "bc1qtest".to_string(),
            mock_provider,
            deposit_tx,
        );

        // First check
        actor.check_deposits().await.unwrap();
        let msg1 = deposit_rx.recv().await.expect("Should receive first deposit");

        // Verify first message
        match msg1 {
            DepositProcessorMsg::ProcessDeposit(deposit) => {
                assert_eq!(deposit.txid, txid.to_string());
            }
            _ => panic!("Expected ProcessDeposit message"),
        }

        // Second check - should deduplicate
        actor.check_deposits().await.unwrap();
        tokio::time::timeout(Duration::from_millis(100), deposit_rx.recv())
            .await
            .expect_err("Should timeout - duplicate should be skipped");
    }
}
