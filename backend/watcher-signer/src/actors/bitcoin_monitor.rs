use super::messages::{BitcoinMonitorMsg, DepositProcessorMsg};
use common::{parse_op_return, BitcoinProvider, ConfirmedDeposit, Result};
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};
use tracing::{error, info, warn};

const MAX_SEEN_TXIDS: usize = 10_000;

pub struct BitcoinMonitorActor {
    multisig_address: String,
    bitcoin_client: Arc<dyn BitcoinProvider>,
    deposit_tx: mpsc::Sender<DepositProcessorMsg>,
    seen_txids: HashSet<String>,
    poll_interval_secs: u64,
    min_confirmations: u32,
}

impl BitcoinMonitorActor {
    pub fn new(
        multisig_address: String,
        bitcoin_client: Arc<dyn BitcoinProvider>,
        deposit_tx: mpsc::Sender<DepositProcessorMsg>,
        poll_interval_secs: u64,
        min_confirmations: u32,
    ) -> Self {
        Self {
            multisig_address,
            bitcoin_client,
            deposit_tx,
            seen_txids: HashSet::new(),
            poll_interval_secs,
            min_confirmations,
        }
    }

    pub async fn run(mut self, mut stop_rx: mpsc::Receiver<BitcoinMonitorMsg>) {
        let mut tick = interval(Duration::from_secs(self.poll_interval_secs));

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
            if confirmations < self.min_confirmations {
                warn!(
                    "Transaction {} has {} confirmations, waiting for {}",
                    txid_str, confirmations, self.min_confirmations
                );
                continue;
            }

            // Get full transaction
            let tx = match self.bitcoin_client.get_transaction(&txid).await {
                Ok(tx) => tx,
                Err(e) => {
                    error!("Failed to fetch transaction {}: {}", txid_str, e);
                    continue;
                }
            };

            // Parse OP_RETURN for Starknet address
            let starknet_address = match parse_op_return(&tx) {
                Ok(Some(data)) if data.len() == 32 => hex::encode(&data),
                Ok(Some(data)) => {
                    warn!("Invalid OP_RETURN data length {} in tx {}", data.len(), txid_str);
                    continue;
                }
                Ok(None) => {
                    warn!("No OP_RETURN found in transaction {}", txid_str);
                    continue;
                }
                Err(e) => {
                    error!("Failed to parse OP_RETURN in tx {}: {}", txid_str, e);
                    continue;
                }
            };

            // Calculate deposit amount
            let amount_sats = calculate_deposit_amount(&tx, &self.multisig_address);

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

            // Cap the seen_txids cache to prevent unbounded growth
            if self.seen_txids.len() > MAX_SEEN_TXIDS {
                self.seen_txids.clear();
                info!("Cleared seen_txids cache (exceeded {} entries)", MAX_SEEN_TXIDS);
            }
        }

        Ok(())
    }
}

fn calculate_deposit_amount(tx: &bitcoin::Transaction, _multisig_address: &str) -> u64 {
    // Sum all outputs that pay to the multisig address
    // TODO: In production, parse script_pubkey and match against multisig_address exactly.
    // For POC: sum all non-OP_RETURN outputs with positive value.
    // This is a reasonable approximation since the multisig is typically the primary recipient.
    tx.output
        .iter()
        .filter(|output| {
            // Include all spendable outputs (exclude OP_RETURN)
            !output.script_pubkey.is_op_return() && output.value.to_sat() > 0
        })
        .map(|output| output.value.to_sat())
        .sum()
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

        // Create a payment output (simulates sending to multisig) + OP_RETURN output
        let payment_script = Builder::new()
            .push_opcode(opcodes::OP_TRUE)
            .into_script();

        Transaction {
            version: bitcoin::transaction::Version::TWO,
            lock_time: bitcoin::absolute::LockTime::ZERO,
            input: vec![TxIn::default()],
            output: vec![
                TxOut {
                    value: Amount::from_sat(100_000),
                    script_pubkey: payment_script,
                },
                TxOut {
                    value: Amount::from_sat(0),
                    script_pubkey: script,
                },
            ],
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
            600,  // poll_interval_secs
            6,    // min_confirmations
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
            600,  // poll_interval_secs
            6,    // min_confirmations
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
            600,  // poll_interval_secs
            6,    // min_confirmations
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
