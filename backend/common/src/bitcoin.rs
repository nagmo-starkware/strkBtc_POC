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

#[derive(Clone)]
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
            let parsed_address = Address::from_str(&address)
                .map_err(|e| BridgeError::Other(anyhow::anyhow!("Invalid address: {}", e)))?
                .assume_checked();

            // List unspent outputs for the address
            let unspent = client
                .list_unspent(Some(0), None, Some(&[&parsed_address]), None, None)
                .map_err(|e| BridgeError::Other(anyhow::anyhow!("list_unspent failed: {}", e)))?;

            // For each UTXO, get confirmation count
            let mut result = Vec::new();
            for utxo in unspent {
                let tx_info = client
                    .get_raw_transaction_info(&utxo.txid, None)
                    .map_err(|e| BridgeError::Other(anyhow::anyhow!("get_raw_transaction_info failed: {}", e)))?;
                let confirmations = tx_info.confirmations.unwrap_or(0);
                result.push((utxo.txid, confirmations));
            }

            Ok(result)
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

    // Count OP_RETURN outputs and collect data
    let mut op_return_count = 0;
    let mut op_return_data: Option<Vec<u8>> = None;

    for output in &tx.output {
        if output.script_pubkey.is_op_return() {
            op_return_count += 1;
            if op_return_data.is_none() {
                let mut instructions = output.script_pubkey.instructions();
                // Skip OP_RETURN opcode
                instructions.next();
                // Get the data push
                if let Some(Ok(Instruction::PushBytes(data))) = instructions.next() {
                    op_return_data = Some(data.as_bytes().to_vec());
                }
            }
        }
    }

    // Reject multiple OP_RETURN outputs
    if op_return_count > 1 {
        return Err(BridgeError::Other(anyhow::anyhow!("Multiple OP_RETURN outputs not allowed")));
    }

    Ok(op_return_data)
}
