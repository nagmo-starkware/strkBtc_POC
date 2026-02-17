# BTC Bridge Backend Services

Rust backend services for the BTC ↔ Starknet bridge.

## Services

### watcher-signer
Committee member service that:
- Monitors Bitcoin for deposits
- Monitors Starknet for withdrawal requests
- Submits deposit requests to Starknet
- Signs PSBTs and submits to registry

### broadcaster
PSBT combiner service that:
- Monitors registry for PSBT submissions
- Combines PSBTs when threshold met
- Broadcasts final transaction to Bitcoin

## Development

### Prerequisites
```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install Docker
# (platform-specific)
```

### Build
```bash
cd backend
cargo build
```

### Run Locally
```bash
# Copy environment template
cp .env.example .env
# Edit .env with your configuration

# Run watcher-signer
cargo run -p watcher-signer

# Run broadcaster (in another terminal)
cargo run -p broadcaster
```

### Docker
```bash
docker-compose up --build
```

## Configuration

See `.env.example` for all configuration options.

### Required Environment Variables

**watcher-signer:**
- `BITCOIN_RPC_URL` - Bitcoin node RPC endpoint
- `BITCOIN_RPC_USER` - RPC username
- `BITCOIN_RPC_PASSWORD` - RPC password
- `BITCOIN_MULTISIG_ADDRESS` - Bridge multisig address
- `BITCOIN_PRIVATE_KEY` - Committee member's Bitcoin key
- `STARKNET_RPC_URL` - Starknet RPC endpoint
- `SIGNER_PRIVATE_KEY` - Committee member's Starknet key
- `BRIDGE_CONTRACT_ADDRESS` - Bridge contract address
- `REGISTRY_CONTRACT_ADDRESS` - Registry contract address

**broadcaster:**
- `BITCOIN_RPC_URL` - Bitcoin node RPC endpoint
- `BITCOIN_RPC_USER` - RPC username
- `BITCOIN_RPC_PASSWORD` - RPC password
- `BITCOIN_PRIVATE_KEY` - Bitcoin key for fee input
- `STARKNET_RPC_URL` - Starknet RPC endpoint
- `REGISTRY_CONTRACT_ADDRESS` - Registry contract address
- `SIGNATURE_THRESHOLD` - M-of-N threshold

## Architecture

See `../docs/plans/2026-02-17-phase-2-rust-backend.md` for detailed design.

## Testing

```bash
cargo test
```

## Logging

Set `RUST_LOG` environment variable:
- `RUST_LOG=debug` - Verbose logging
- `RUST_LOG=info` - Standard logging (default)
- `RUST_LOG=warn` - Warnings only
