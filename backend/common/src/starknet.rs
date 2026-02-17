use crate::error::{BridgeError, Result};
use crate::types::{ConfirmedDeposit, Withdrawal};
use async_trait::async_trait;
use starknet::core::types::FieldElement;
use starknet::providers::jsonrpc::HttpTransport;
use starknet::providers::{JsonRpcClient, Provider};
use std::sync::Arc;

/// Helper to convert any Display error into BridgeError::Other.
fn other(msg: &str, e: impl std::fmt::Display) -> BridgeError {
    BridgeError::Other(anyhow::anyhow!("{msg}: {e}"))
}

#[async_trait]
pub trait StarknetProvider: Send + Sync {
    async fn get_withdrawal_requests(&self, from_block: u64) -> Result<Vec<Withdrawal>>;
    async fn submit_deposit(&self, deposit: &ConfirmedDeposit) -> Result<FieldElement>;
    async fn submit_psbt(&self, withdrawal_id: &str, psbt: Vec<u8>) -> Result<FieldElement>;
    async fn get_latest_block(&self) -> Result<u64>;
}

pub struct StarknetBridgeClient {
    provider: Arc<JsonRpcClient<HttpTransport>>,
    #[allow(dead_code)] // Used once contract calls are implemented
    bridge_address: FieldElement,
    #[allow(dead_code)] // Used once contract calls are implemented
    registry_address: FieldElement,
}

impl StarknetBridgeClient {
    pub fn new(
        rpc_url: &str,
        bridge_address: &str,
        registry_address: &str,
    ) -> Result<Self> {
        let provider = JsonRpcClient::new(HttpTransport::new(
            reqwest::Url::parse(rpc_url).map_err(|e| other("Invalid RPC URL", e))?,
        ));

        Ok(Self {
            provider: Arc::new(provider),
            bridge_address: FieldElement::from_hex_be(bridge_address)
                .map_err(|e| other("Invalid bridge address", e))?,
            registry_address: FieldElement::from_hex_be(registry_address)
                .map_err(|e| other("Invalid registry address", e))?,
        })
    }
}

#[async_trait]
impl StarknetProvider for StarknetBridgeClient {
    async fn get_withdrawal_requests(&self, _from_block: u64) -> Result<Vec<Withdrawal>> {
        unimplemented!("event filtering and parsing not yet implemented")
    }

    async fn submit_deposit(&self, _deposit: &ConfirmedDeposit) -> Result<FieldElement> {
        unimplemented!("deposit contract call not yet implemented")
    }

    async fn submit_psbt(&self, _withdrawal_id: &str, _psbt: Vec<u8>) -> Result<FieldElement> {
        unimplemented!("PSBT contract call not yet implemented")
    }

    async fn get_latest_block(&self) -> Result<u64> {
        let block_number = self.provider.block_number().await
            .map_err(|e| other("Failed to get block number", e))?;
        Ok(block_number)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Clone)]
    struct MockStarknetProvider {
        withdrawals: Vec<Withdrawal>,
        latest_block: u64,
    }

    #[async_trait]
    impl StarknetProvider for MockStarknetProvider {
        async fn get_withdrawal_requests(&self, _from_block: u64) -> Result<Vec<Withdrawal>> {
            Ok(self.withdrawals.clone())
        }

        async fn submit_deposit(&self, _deposit: &ConfirmedDeposit) -> Result<FieldElement> {
            Ok(FieldElement::from_hex_be("0x1234").unwrap())
        }

        async fn submit_psbt(&self, _withdrawal_id: &str, _psbt: Vec<u8>) -> Result<FieldElement> {
            Ok(FieldElement::from_hex_be("0x5678").unwrap())
        }

        async fn get_latest_block(&self) -> Result<u64> {
            Ok(self.latest_block)
        }
    }

    #[tokio::test]
    async fn test_mock_provider_returns_withdrawals() {
        let withdrawal = Withdrawal {
            request_id: "req1".to_string(),
            btc_address: "bc1q...".to_string(),
            amount: 100_000,
        };
        let provider = MockStarknetProvider {
            withdrawals: vec![withdrawal.clone()],
            latest_block: 1000,
        };

        let result = provider.get_withdrawal_requests(900).await.unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].request_id, "req1");
    }

    #[tokio::test]
    async fn test_mock_provider_submit_deposit() {
        let provider = MockStarknetProvider {
            withdrawals: vec![],
            latest_block: 1000,
        };
        let deposit = ConfirmedDeposit {
            txid: "abc123".to_string(),
            starknet_address: "0x456".to_string(),
            amount: 50_000,
        };

        let tx_hash = provider.submit_deposit(&deposit).await.unwrap();
        assert_eq!(tx_hash, FieldElement::from_hex_be("0x1234").unwrap());
    }

    #[tokio::test]
    async fn test_mock_provider_get_latest_block() {
        let provider = MockStarknetProvider {
            withdrawals: vec![],
            latest_block: 1000,
        };

        let block = provider.get_latest_block().await.unwrap();
        assert_eq!(block, 1000);
    }
}
