use crate::error::{BridgeError, Result};
use async_trait::async_trait;
use bitcoin::{Address, Transaction, Txid};
use bitcoincore_rpc::{Auth, Client, RpcApi};
use std::str::FromStr;
use std::sync::Arc;

#[async_trait]
pub trait BitcoinProvider: Send + Sync {
    async fn get_transaction(&self, txid: &Txid) -> Result<Transaction>;
    async fn get_confirmations(&self, txid: &Txid) -> Result<u32>;
    async fn list_transactions_to_address(&self, address: &str, count: usize) -> Result<Vec<(Txid, u32)>>;
    async fn broadcast_transaction(&self, tx: &Transaction) -> Result<Txid>;
}

pub struct BitcoinClient {
    client: Arc<Client>,
}

impl BitcoinClient {
    pub fn new(url: &str, user: &str, password: &str) -> Result<Self> {
        let client = Client::new(url, Auth::UserPass(user.to_string(), password.to_string()))?;
        Ok(Self { client: Arc::new(client) })
    }
}

#[async_trait]
impl BitcoinProvider for BitcoinClient {
    async fn get_transaction(&self, txid: &Txid) -> Result<Transaction> {
        let client = self.client.clone();
        let txid = *txid;
        tokio::task::spawn_blocking(move || {
            let tx_info = client.get_raw_transaction_info(&txid, None)?;
            let tx = tx_info.transaction()
                .map_err(|e| BridgeError::Other(anyhow::anyhow!("Transaction decode error: {}", e)))?;
            Ok(tx)
        })
        .await
        .map_err(|e| BridgeError::Other(anyhow::anyhow!("Task join error: {}", e)))?
    }

    async fn get_confirmations(&self, txid: &Txid) -> Result<u32> {
        let client = self.client.clone();
        let txid = *txid;
        tokio::task::spawn_blocking(move || {
            let tx_info = client.get_raw_transaction_info(&txid, None)?;
            Ok(tx_info.confirmations.unwrap_or(0))
        })
        .await
        .map_err(|e| BridgeError::Other(anyhow::anyhow!("Task join error: {}", e)))?
    }

    async fn list_transactions_to_address(
        &self,
        address: &str,
        _count: usize,
    ) -> Result<Vec<(Txid, u32)>> {
        let client = self.client.clone();
        let address = address.to_string();
        tokio::task::spawn_blocking(move || {
            let _address = Address::from_str(&address)
                .map_err(|e| BridgeError::Other(anyhow::anyhow!("Invalid address: {}", e)))?;

            // TODO: CRITICAL - Implement proper blockchain scanning
            // This stub means the Bitcoin monitor will never detect deposits
            // Must implement before any testing
            tracing::warn!("list_transactions_to_address is stubbed - no deposits will be detected");
            Ok(Vec::new())
        })
        .await
        .map_err(|e| BridgeError::Other(anyhow::anyhow!("Task join error: {}", e)))?
    }

    async fn broadcast_transaction(&self, tx: &Transaction) -> Result<Txid> {
        let client = self.client.clone();
        let tx = tx.clone();
        tokio::task::spawn_blocking(move || {
            let txid = client.send_raw_transaction(&tx)?;
            Ok(txid)
        })
        .await
        .map_err(|e| BridgeError::Other(anyhow::anyhow!("Task join error: {}", e)))?
    }
}

pub fn parse_op_return(tx: &Transaction) -> Result<Option<Vec<u8>>> {
    use bitcoin::script::Instruction;

    for output in &tx.output {
        if output.script_pubkey.is_op_return() {
            let mut instructions = output.script_pubkey.instructions();
            // Skip OP_RETURN opcode
            instructions.next();
            // Get the data push
            if let Some(Ok(Instruction::PushBytes(data))) = instructions.next() {
                return Ok(Some(data.as_bytes().to_vec()));
            }
        }
    }
    Ok(None)
}
