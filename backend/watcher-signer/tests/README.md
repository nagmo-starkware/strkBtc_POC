# Integration Tests

This directory contains integration tests for the watcher-signer service that verify real RPC connections to Bitcoin testnet and Starknet Sepolia.

## Running Integration Tests

All integration tests are marked with `#[ignore]` and must be explicitly run:

```bash
# Run all integration tests
cargo test --test integration_tests -- --ignored

# Run a specific integration test
cargo test --test integration_tests test_bitcoin_client_connects -- --ignored

# Run with verbose output
cargo test --test integration_tests -- --ignored --nocapture
```

Regular `cargo test` will **not** run these tests by default.

## Prerequisites

### Bitcoin Testnet Access

You need access to a Bitcoin testnet RPC node. Options:

1. **Local testnet node** (recommended for CI/development):
   ```bash
   docker run -d --name bitcoin-testnet \
     -p 18332:18332 \
     kylemanna/bitcoind \
     -testnet -rpcuser=testuser -rpcpassword=testpass \
     -rpcallowip=0.0.0.0/0 -rpcbind=0.0.0.0
   ```

2. **Public testnet RPC** (may have rate limits):
   - Use a service like Blockstream's testnet API
   - Or run your own node and expose it

### Starknet Sepolia Access

You need access to a Starknet Sepolia RPC endpoint. Options:

1. **Public RPC** (default, no setup required):
   - The tests use `https://starknet-sepolia.public.blastapi.io/rpc/v0_7` by default
   - Free, but may have rate limits

2. **Alchemy/Infura** (recommended for CI):
   - Sign up for an account
   - Get your Sepolia RPC URL
   - Set `TEST_STARKNET_RPC_URL` env var

## Environment Variables

Configure test endpoints and credentials via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `TEST_BITCOIN_RPC_URL` | Bitcoin testnet RPC endpoint | `http://127.0.0.1:18332` |
| `TEST_BITCOIN_RPC_USER` | Bitcoin RPC username | `testuser` |
| `TEST_BITCOIN_RPC_PASSWORD` | Bitcoin RPC password | `testpass` |
| `TEST_STARKNET_RPC_URL` | Starknet Sepolia RPC endpoint | `https://starknet-sepolia.public.blastapi.io/rpc/v0_7` |
| `TEST_BRIDGE_CONTRACT_ADDRESS` | Bridge contract address (hex) | `0x0000000000000000000000000000000000000001` |
| `TEST_REGISTRY_CONTRACT_ADDRESS` | Registry contract address (hex) | `0x0000000000000000000000000000000000000002` |

Example `.env` file for integration tests:

```bash
# Bitcoin testnet (local node)
TEST_BITCOIN_RPC_URL=http://127.0.0.1:18332
TEST_BITCOIN_RPC_USER=testuser
TEST_BITCOIN_RPC_PASSWORD=testpass

# Starknet Sepolia (public RPC)
TEST_STARKNET_RPC_URL=https://starknet-sepolia.public.blastapi.io/rpc/v0_7
TEST_BRIDGE_CONTRACT_ADDRESS=0x0000000000000000000000000000000000000001
TEST_REGISTRY_CONTRACT_ADDRESS=0x0000000000000000000000000000000000000002
```

Load it with:

```bash
source .env && cargo test --test integration_tests -- --ignored
```

## Test Coverage

### ✅ Implemented

| Test | Verifies |
|------|----------|
| `test_bitcoin_client_connects` | Bitcoin RPC authentication and connectivity |
| `test_starknet_client_connects` | Starknet RPC connectivity and `get_latest_block()` |

### 📋 TODO (Placeholders)

| Test | Verifies |
|------|----------|
| `test_end_to_end_deposit_flow` | Full deposit flow: BTC → Bridge → Starknet |
| `test_end_to_end_withdrawal_flow` | Full withdrawal flow: Starknet → PSBT → BTC |

The E2E tests are placeholders until:
- Bridge contracts are deployed on Sepolia
- Actor system can be instantiated in test mode
- Test helpers can submit real transactions

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Setup Bitcoin Testnet
  run: |
    docker run -d --name bitcoin-testnet \
      -p 18332:18332 \
      kylemanna/bitcoind \
      -testnet -rpcuser=ci -rpcpassword=${{ secrets.BTC_RPC_PASS }} \
      -rpcallowip=0.0.0.0/0 -rpcbind=0.0.0.0

- name: Run Integration Tests
  env:
    TEST_BITCOIN_RPC_URL: http://127.0.0.1:18332
    TEST_BITCOIN_RPC_USER: ci
    TEST_BITCOIN_RPC_PASSWORD: ${{ secrets.BTC_RPC_PASS }}
    TEST_STARKNET_RPC_URL: ${{ secrets.STARKNET_RPC_URL }}
  run: |
    cargo test --test integration_tests -- --ignored
```

## Development Workflow

1. **Start local Bitcoin testnet** (if needed):
   ```bash
   docker run -d --name bitcoin-testnet -p 18332:18332 \
     kylemanna/bitcoind -testnet -rpcuser=testuser -rpcpassword=testpass \
     -rpcallowip=0.0.0.0/0 -rpcbind=0.0.0.0
   ```

2. **Configure environment variables** (optional if using defaults)

3. **Run integration tests**:
   ```bash
   cargo test --test integration_tests -- --ignored --nocapture
   ```

4. **Check results**:
   - All tests should PASS if infrastructure is reachable
   - FAILED tests indicate RPC issues or network problems

## Notes

- Integration tests are **not run** by default `cargo test` to avoid CI failures
- Use `--ignored` flag to explicitly run them
- Bitcoin testnet may take time to sync (use a pre-synced node for CI)
- Starknet Sepolia public RPCs may have rate limits
- E2E tests require deployed contracts and running actors (future work)
