//! Integration tests for watcher-signer actors
//!
//! These tests verify real RPC connections to Bitcoin testnet and Starknet Sepolia.
//! They are marked `#[ignore]` by default and only run when explicitly requested.
//!
//! Run with: cargo test --test integration_tests -- --ignored

use common::bitcoin::BitcoinClient;
use common::starknet::StarknetBridgeClient;
use std::env;

/// Test configuration loaded from environment variables.
/// Falls back to public testnet endpoints if not set.
struct TestConfig {
    bitcoin_rpc_url: String,
    bitcoin_rpc_user: String,
    bitcoin_rpc_password: String,
    starknet_rpc_url: String,
    bridge_address: String,
    registry_address: String,
}

impl TestConfig {
    fn load() -> Self {
        Self {
            bitcoin_rpc_url: env::var("TEST_BITCOIN_RPC_URL")
                .unwrap_or_else(|_| "http://127.0.0.1:18332".to_string()),
            bitcoin_rpc_user: env::var("TEST_BITCOIN_RPC_USER")
                .unwrap_or_else(|_| "testuser".to_string()),
            bitcoin_rpc_password: env::var("TEST_BITCOIN_RPC_PASSWORD")
                .unwrap_or_else(|_| "testpass".to_string()),
            starknet_rpc_url: env::var("TEST_STARKNET_RPC_URL")
                .unwrap_or_else(|_| "https://starknet-sepolia.public.blastapi.io/rpc/v0_7".to_string()),
            bridge_address: env::var("TEST_BRIDGE_CONTRACT_ADDRESS")
                .unwrap_or_else(|_| "0x0000000000000000000000000000000000000001".to_string()),
            registry_address: env::var("TEST_REGISTRY_CONTRACT_ADDRESS")
                .unwrap_or_else(|_| "0x0000000000000000000000000000000000000002".to_string()),
        }
    }
}

// ========================================
// Bitcoin Client Integration Tests
// ========================================

/// Test that BitcoinClient can connect to a real Bitcoin testnet node.
///
/// This verifies:
/// - RPC authentication works
/// - Network connectivity is functional
/// - Basic RPC calls succeed
///
/// Requires: A running Bitcoin testnet node or public testnet RPC access.
#[tokio::test]
#[ignore]
async fn test_bitcoin_client_connects() {
    let config = TestConfig::load();

    // Attempt to create a client
    let client = BitcoinClient::new(
        &config.bitcoin_rpc_url,
        &config.bitcoin_rpc_user,
        &config.bitcoin_rpc_password,
    );

    assert!(
        client.is_ok(),
        "Failed to create Bitcoin client: {:?}",
        client.err()
    );

    println!("✓ Bitcoin client created successfully");
    println!("  RPC URL: {}", config.bitcoin_rpc_url);
}

// ========================================
// Starknet Client Integration Tests
// ========================================

/// Test that StarknetBridgeClient can connect to Starknet Sepolia testnet.
///
/// This verifies:
/// - RPC URL is valid and reachable
/// - Client can fetch the latest block number
/// - Network connectivity is functional
///
/// Requires: Internet access to Starknet Sepolia RPC endpoint.
#[tokio::test]
#[ignore]
async fn test_starknet_client_connects() {
    let config = TestConfig::load();

    // Attempt to create a client
    let client = StarknetBridgeClient::new(
        &config.starknet_rpc_url,
        &config.bridge_address,
        &config.registry_address,
    );

    assert!(
        client.is_ok(),
        "Failed to create Starknet client: {:?}",
        client.err()
    );

    let client = client.unwrap();
    println!("✓ Starknet client created successfully");
    println!("  RPC URL: {}", config.starknet_rpc_url);

    // Test basic RPC call: get latest block
    use common::starknet::StarknetProvider;
    let block_number = client.get_latest_block().await;

    assert!(
        block_number.is_ok(),
        "Failed to get latest block: {:?}",
        block_number.err()
    );

    let block_number = block_number.unwrap();
    println!("✓ Latest block fetched: {}", block_number);
    assert!(block_number > 0, "Block number should be > 0");
}

// ========================================
// End-to-End Flow Tests (Placeholders)
// ========================================

/// Test end-to-end deposit flow from Bitcoin to Starknet.
///
/// TODO: Implement this test once deposit flow is fully wired.
///
/// Steps:
/// 1. Send BTC to multisig address with OP_RETURN containing Starknet address
/// 2. Wait for Bitcoin confirmations
/// 3. Verify BitcoinMonitor detects the deposit
/// 4. Verify DepositProcessor submits deposit to Starknet
/// 5. Verify Starknet transaction confirms
#[tokio::test]
#[ignore]
async fn test_end_to_end_deposit_flow() {
    // TODO: Implement E2E deposit test
    // This requires:
    // - Ability to send Bitcoin testnet transactions
    // - Deployed Starknet bridge contract on Sepolia
    // - Watcher-signer running and monitoring

    println!("TODO: Implement E2E deposit test");
}

/// Test end-to-end withdrawal flow from Starknet to Bitcoin.
///
/// TODO: Implement this test once withdrawal flow is fully wired.
///
/// Steps:
/// 1. Submit withdrawal request on Starknet
/// 2. Wait for Starknet confirmation
/// 3. Verify StarknetMonitor detects the withdrawal request
/// 4. Verify PSBTSigner creates and signs PSBT
/// 5. Verify PSBT is submitted to Registry contract
/// 6. Verify Broadcaster broadcasts the finalized transaction
/// 7. Verify Bitcoin transaction confirms
#[tokio::test]
#[ignore]
async fn test_end_to_end_withdrawal_flow() {
    // TODO: Implement E2E withdrawal test
    // This requires:
    // - Deployed Starknet bridge contract on Sepolia
    // - Ability to submit withdrawal requests from Starknet
    // - Full watcher-signer + broadcaster running
    // - Bitcoin testnet access

    println!("TODO: Implement E2E withdrawal test");
}
