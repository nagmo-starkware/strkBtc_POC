use crate::error::{BridgeError, Result};
use bitcoin::{Address, Transaction, Txid};
use bitcoincore_rpc::{Auth, Client, RpcApi};
use std::str::FromStr;

pub struct BitcoinClient {
    client: Client,
}

impl BitcoinClient {
    pub fn new(url: &str, user: &str, password: &str) -> Result<Self> {
        let client = Client::new(url, Auth::UserPass(user.to_string(), password.to_string()))?;
        Ok(Self { client })
    }

    pub fn get_transaction(&self, txid: &Txid) -> Result<Transaction> {
        let tx_info = self.client.get_raw_transaction_info(txid, None)?;
        let tx = tx_info.transaction()
            .map_err(|e| BridgeError::Other(anyhow::anyhow!("Transaction decode error: {}", e)))?;
        Ok(tx)
    }

    pub fn get_confirmations(&self, txid: &Txid) -> Result<u32> {
        let tx_info = self.client.get_raw_transaction_info(txid, None)?;
        Ok(tx_info.confirmations.unwrap_or(0))
    }

    pub fn list_transactions_to_address(
        &self,
        address: &str,
        _count: usize,
    ) -> Result<Vec<(Txid, u32)>> {
        // This is a simplified implementation
        // In production, you'd use listsinceblock or similar
        let _address = Address::from_str(address)
            .map_err(|e| BridgeError::Other(anyhow::anyhow!("Invalid address: {}", e)))?;

        // For now, return empty vec - will implement proper scanning later
        Ok(Vec::new())
    }

    pub fn broadcast_transaction(&self, tx: &Transaction) -> Result<Txid> {
        let txid = self.client.send_raw_transaction(tx)?;
        Ok(txid)
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
