# Phase 2: Rust Backend - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build two Rust services (watcher-signer and broadcaster) that enable committee members to coordinate BTC deposits and withdrawals between Bitcoin and Starknet.

**Architecture:** Cargo workspace with 3 crates (common library, watcher-signer binary, broadcaster binary). Actor-based watcher-signer for concurrent Bitcoin/Starknet monitoring. Simple event loop broadcaster for PSBT combination. Stateless design with in-memory tracking.

**Tech Stack:** Rust, Tokio, bitcoincore-rpc, rust-bitcoin, starknet-rs, Docker

---

## Prerequisites

- Rust installed (stable channel): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- Docker installed
- Bitcoin Core node access (testnet recommended for initial development)
- Starknet RPC access (testnet)

---

## Task 1: Workspace Setup

**Files:**
- Create: `backend/Cargo.toml`
- Create: `backend/.gitignore`
- Create: `backend/.env.example`

**Step 1: Initialize Cargo workspace**

```bash
cd /home/lt-nevoa/btc-bridge-poc
mkdir -p backend
cd backend
```

Create `backend/Cargo.toml`:

```toml
[workspace]
members = ["common", "watcher-signer", "broadcaster"]
resolver = "2"

[workspace.dependencies]
tokio = { version = "1.35", features = ["full"] }
anyhow = "1.0"
thiserror = "1.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
```

**Step 2: Create .gitignore**

Create `backend/.gitignore`:

```
target/
**/*.rs.bk
*.pdb
.env
.env.*
!.env.example
```

**Step 3: Create environment template**

Create `backend/.env.example`:

```env
# Bitcoin Configuration
BITCOIN_RPC_URL=http://localhost:18332
BITCOIN_RPC_USER=rpcuser
BITCOIN_RPC_PASSWORD=rpcpassword
BITCOIN_MULTISIG_ADDRESS=
BITCOIN_PRIVATE_KEY=
MIN_CONFIRMATIONS=6

# Starknet Configuration
STARKNET_RPC_URL=https://starknet-sepolia.infura.io/v3/YOUR_KEY
SIGNER_PRIVATE_KEY=
BRIDGE_CONTRACT_ADDRESS=
REGISTRY_CONTRACT_ADDRESS=

# Polling Intervals (seconds)
BITCOIN_POLL_INTERVAL_SECS=600
STARKNET_POLL_INTERVAL_SECS=10
REGISTRY_POLL_INTERVAL_SECS=30
BROADCAST_CHECK_INTERVAL_SECS=60

# Signature Threshold
SIGNATURE_THRESHOLD=3
```

**Step 4: Verify workspace structure**

```bash
cargo new --lib common
cargo new --bin watcher-signer
cargo new --bin broadcaster
```

Expected: Creates 3 crates with basic structure

**Step 5: Commit**

```bash
git add backend/
git commit -m "feat(backend): initialize Cargo workspace

- Set up workspace with common, watcher-signer, broadcaster
- Add workspace dependencies (tokio, anyhow, tracing)
- Create .gitignore and .env.example"
```

---

## Task 2: Common Crate - Error Types

**Files:**
- Create: `backend/common/src/error.rs`
- Modify: `backend/common/src/lib.rs`

**Step 1: Create error types**

Create `backend/common/src/error.rs`:

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum BridgeError {
    #[error("Bitcoin RPC error: {0}")]
    BitcoinRpc(#[from] bitcoincore_rpc::Error),

    #[error("Starknet provider error: {0}")]
    StarknetProvider(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Invalid OP_RETURN data: {0}")]
    InvalidOpReturn(String),

    #[error("PSBT error: {0}")]
    Psbt(String),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Other error: {0}")]
    Other(#[from] anyhow::Error),
}

pub type Result<T> = std::result::Result<T, BridgeError>;
```

**Step 2: Update lib.rs**

Edit `backend/common/src/lib.rs`:

```rust
pub mod error;

pub use error::{BridgeError, Result};
```

**Step 3: Add dependencies to common/Cargo.toml**

Edit `backend/common/Cargo.toml`:

```toml
[package]
name = "common"
version = "0.1.0"
edition = "2021"

[dependencies]
anyhow = { workspace = true }
thiserror = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
tokio = { workspace = true }
tracing = { workspace = true }
bitcoincore-rpc = "0.18"
```

**Step 4: Build to verify**

```bash
cd /home/lt-nevoa/btc-bridge-poc/backend
cargo build -p common
```

Expected: Build succeeds

**Step 5: Commit**

```bash
git add backend/common/
git commit -m "feat(backend): add common error types

- Define BridgeError enum with thiserror
- Add Result type alias
- Set up common crate dependencies"
```

---

## Task 3: Common Crate - Configuration

**Files:**
- Create: `backend/common/src/config.rs`
- Modify: `backend/common/src/lib.rs`

**Step 1: Create config module**

Create `backend/common/src/config.rs`:

```rust
use crate::error::{BridgeError, Result};
use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    // Bitcoin
    pub bitcoin_rpc_url: String,
    pub bitcoin_rpc_user: String,
    pub bitcoin_rpc_password: String,
    pub bitcoin_multisig_address: String,
    pub bitcoin_private_key: String,
    pub min_confirmations: u32,

    // Starknet
    pub starknet_rpc_url: String,
    pub signer_private_key: String,
    pub bridge_contract_address: String,
    pub registry_contract_address: String,

    // Polling
    pub bitcoin_poll_interval_secs: u64,
    pub starknet_poll_interval_secs: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct BroadcasterConfig {
    // Bitcoin
    pub bitcoin_rpc_url: String,
    pub bitcoin_rpc_user: String,
    pub bitcoin_rpc_password: String,
    pub bitcoin_private_key: String,

    // Starknet
    pub starknet_rpc_url: String,
    pub registry_contract_address: String,
    pub signature_threshold: u32,

    // Polling
    pub registry_poll_interval_secs: u64,
    pub broadcast_check_interval_secs: u64,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        Ok(Self {
            bitcoin_rpc_url: env::var("BITCOIN_RPC_URL")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_URL not set".into()))?,
            bitcoin_rpc_user: env::var("BITCOIN_RPC_USER")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_USER not set".into()))?,
            bitcoin_rpc_password: env::var("BITCOIN_RPC_PASSWORD")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_PASSWORD not set".into()))?,
            bitcoin_multisig_address: env::var("BITCOIN_MULTISIG_ADDRESS")
                .map_err(|_| BridgeError::Config("BITCOIN_MULTISIG_ADDRESS not set".into()))?,
            bitcoin_private_key: env::var("BITCOIN_PRIVATE_KEY")
                .map_err(|_| BridgeError::Config("BITCOIN_PRIVATE_KEY not set".into()))?,
            min_confirmations: env::var("MIN_CONFIRMATIONS")
                .unwrap_or_else(|_| "6".to_string())
                .parse()
                .map_err(|_| BridgeError::Config("Invalid MIN_CONFIRMATIONS".into()))?,
            starknet_rpc_url: env::var("STARKNET_RPC_URL")
                .map_err(|_| BridgeError::Config("STARKNET_RPC_URL not set".into()))?,
            signer_private_key: env::var("SIGNER_PRIVATE_KEY")
                .map_err(|_| BridgeError::Config("SIGNER_PRIVATE_KEY not set".into()))?,
            bridge_contract_address: env::var("BRIDGE_CONTRACT_ADDRESS")
                .map_err(|_| BridgeError::Config("BRIDGE_CONTRACT_ADDRESS not set".into()))?,
            registry_contract_address: env::var("REGISTRY_CONTRACT_ADDRESS")
                .map_err(|_| BridgeError::Config("REGISTRY_CONTRACT_ADDRESS not set".into()))?,
            bitcoin_poll_interval_secs: env::var("BITCOIN_POLL_INTERVAL_SECS")
                .unwrap_or_else(|_| "600".to_string())
                .parse()
                .map_err(|_| BridgeError::Config("Invalid BITCOIN_POLL_INTERVAL_SECS".into()))?,
            starknet_poll_interval_secs: env::var("STARKNET_POLL_INTERVAL_SECS")
                .unwrap_or_else(|_| "10".to_string())
                .parse()
                .map_err(|_| BridgeError::Config("Invalid STARKNET_POLL_INTERVAL_SECS".into()))?,
        })
    }
}

impl BroadcasterConfig {
    pub fn from_env() -> Result<Self> {
        Ok(Self {
            bitcoin_rpc_url: env::var("BITCOIN_RPC_URL")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_URL not set".into()))?,
            bitcoin_rpc_user: env::var("BITCOIN_RPC_USER")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_USER not set".into()))?,
            bitcoin_rpc_password: env::var("BITCOIN_RPC_PASSWORD")
                .map_err(|_| BridgeError::Config("BITCOIN_RPC_PASSWORD not set".into()))?,
            bitcoin_private_key: env::var("BITCOIN_PRIVATE_KEY")
                .map_err(|_| BridgeError::Config("BITCOIN_PRIVATE_KEY not set".into()))?,
            starknet_rpc_url: env::var("STARKNET_RPC_URL")
                .map_err(|_| BridgeError::Config("STARKNET_RPC_URL not set".into()))?,
            registry_contract_address: env::var("REGISTRY_CONTRACT_ADDRESS")
                .map_err(|_| BridgeError::Config("REGISTRY_CONTRACT_ADDRESS not set".into()))?,
            signature_threshold: env::var("SIGNATURE_THRESHOLD")
                .unwrap_or_else(|_| "3".to_string())
                .parse()
                .map_err(|_| BridgeError::Config("Invalid SIGNATURE_THRESHOLD".into()))?,
            registry_poll_interval_secs: env::var("REGISTRY_POLL_INTERVAL_SECS")
                .unwrap_or_else(|_| "30".to_string())
                .parse()
                .map_err(|_| BridgeError::Config("Invalid REGISTRY_POLL_INTERVAL_SECS".into()))?,
            broadcast_check_interval_secs: env::var("BROADCAST_CHECK_INTERVAL_SECS")
                .unwrap_or_else(|_| "60".to_string())
                .parse()
                .map_err(|_| BridgeError::Config("Invalid BROADCAST_CHECK_INTERVAL_SECS".into()))?,
        })
    }
}
```

**Step 2: Update lib.rs**

Edit `backend/common/src/lib.rs`:

```rust
pub mod config;
pub mod error;

pub use config::{BroadcasterConfig, Config};
pub use error::{BridgeError, Result};
```

**Step 3: Build to verify**

```bash
cargo build -p common
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add backend/common/
git commit -m "feat(backend): add configuration loading from env

- Config struct for watcher-signer
- BroadcasterConfig struct for broadcaster
- Load from environment variables with defaults"
```

---

## Task 4: Common Crate - Shared Types

**Files:**
- Create: `backend/common/src/types.rs`
- Modify: `backend/common/src/lib.rs`

**Step 1: Create shared types**

Create `backend/common/src/types.rs`:

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Deposit {
    pub txid: String,
    pub starknet_address: String,
    pub amount: u64, // satoshis
    pub confirmations: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Withdrawal {
    pub request_id: String,
    pub btc_address: String,
    pub amount: u64, // satoshis
}

#[derive(Debug, Clone)]
pub struct ConfirmedDeposit {
    pub txid: String,
    pub starknet_address: String,
    pub amount: u64,
}

#[derive(Debug, Clone)]
pub struct FinalizedWithdrawal {
    pub request_id: String,
    pub btc_address: String,
    pub amount: u64,
}
```

**Step 2: Update lib.rs**

Edit `backend/common/src/lib.rs`:

```rust
pub mod config;
pub mod error;
pub mod types;

pub use config::{BroadcasterConfig, Config};
pub use error::{BridgeError, Result};
pub use types::{ConfirmedDeposit, Deposit, FinalizedWithdrawal, Withdrawal};
```

**Step 3: Build to verify**

```bash
cargo build -p common
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add backend/common/
git commit -m "feat(backend): add shared data types

- Deposit and Withdrawal structs
- ConfirmedDeposit and FinalizedWithdrawal messages
- Serialization support with serde"
```

---

## Task 5: Common Crate - Bitcoin Client Wrapper

**Files:**
- Create: `backend/common/src/bitcoin.rs`
- Modify: `backend/common/src/lib.rs`
- Modify: `backend/common/Cargo.toml`

**Step 1: Add bitcoin dependencies**

Edit `backend/common/Cargo.toml` and add:

```toml
bitcoin = "0.31"
bitcoincore-rpc = "0.18"
```

**Step 2: Create Bitcoin client wrapper**

Create `backend/common/src/bitcoin.rs`:

```rust
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
        Ok(tx_info.transaction()?)
    }

    pub fn get_confirmations(&self, txid: &Txid) -> Result<u32> {
        let tx_info = self.client.get_raw_transaction_info(txid, None)?;
        Ok(tx_info.confirmations.unwrap_or(0))
    }

    pub fn list_transactions_to_address(
        &self,
        address: &str,
        count: usize,
    ) -> Result<Vec<(Txid, u32)>> {
        // This is a simplified implementation
        // In production, you'd use listsinceblock or similar
        let address = Address::from_str(address)
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
    for output in &tx.output {
        if output.script_pubkey.is_op_return() {
            let script = output.script_pubkey.as_bytes();
            if script.len() > 2 {
                // Skip OP_RETURN opcode (0x6a) and push length
                return Ok(Some(script[2..].to_vec()));
            }
        }
    }
    Ok(None)
}
```

**Step 3: Update lib.rs**

Edit `backend/common/src/lib.rs`:

```rust
pub mod bitcoin;
pub mod config;
pub mod error;
pub mod types;

pub use bitcoin::BitcoinClient;
pub use config::{BroadcasterConfig, Config};
pub use error::{BridgeError, Result};
pub use types::{ConfirmedDeposit, Deposit, FinalizedWithdrawal, Withdrawal};
```

**Step 4: Build to verify**

```bash
cargo build -p common
```

Expected: Build succeeds

**Step 5: Commit**

```bash
git add backend/common/
git commit -m "feat(backend): add Bitcoin RPC client wrapper

- BitcoinClient with transaction queries
- Confirmation count checking
- OP_RETURN parsing helper
- Transaction broadcasting"
```

---

## Task 6: Watcher-Signer - Main Entry Point

**Files:**
- Modify: `backend/watcher-signer/Cargo.toml`
- Modify: `backend/watcher-signer/src/main.rs`

**Step 1: Add dependencies**

Edit `backend/watcher-signer/Cargo.toml`:

```toml
[package]
name = "watcher-signer"
version = "0.1.0"
edition = "2021"

[dependencies]
common = { path = "../common" }
tokio = { workspace = true }
anyhow = { workspace = true }
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
```

**Step 2: Create main.rs skeleton**

Edit `backend/watcher-signer/src/main.rs`:

```rust
use common::{Config, Result};
use tracing::{info, error};
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    info!("Starting watcher-signer service");

    // Load configuration
    let config = Config::from_env()?;
    info!("Configuration loaded");

    // TODO: Start actors

    info!("Watcher-signer service started");

    // Keep running
    tokio::signal::ctrl_c().await?;
    info!("Shutting down");

    Ok(())
}
```

**Step 3: Build to verify**

```bash
cargo build -p watcher-signer
```

Expected: Build succeeds

**Step 4: Test run (will exit immediately on Ctrl+C)**

```bash
cd backend
cargo run -p watcher-signer
```

Expected: Prints log messages, waits for Ctrl+C

**Step 5: Commit**

```bash
git add backend/watcher-signer/
git commit -m "feat(backend): add watcher-signer entry point

- Basic main.rs with tracing setup
- Configuration loading
- Graceful shutdown on Ctrl+C"
```

---

## Task 7: Broadcaster - Main Entry Point

**Files:**
- Modify: `backend/broadcaster/Cargo.toml`
- Modify: `backend/broadcaster/src/main.rs`

**Step 1: Add dependencies**

Edit `backend/broadcaster/Cargo.toml`:

```toml
[package]
name = "broadcaster"
version = "0.1.0"
edition = "2021"

[dependencies]
common = { path = "../common" }
tokio = { workspace = true }
anyhow = { workspace = true }
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
```

**Step 2: Create main.rs skeleton**

Edit `backend/broadcaster/src/main.rs`:

```rust
use common::{BroadcasterConfig, Result};
use tracing::{info, error};
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    info!("Starting broadcaster service");

    // Load configuration
    let config = BroadcasterConfig::from_env()?;
    info!("Configuration loaded");

    // TODO: Start event loop

    info!("Broadcaster service started");

    // Keep running
    tokio::signal::ctrl_c().await?;
    info!("Shutting down");

    Ok(())
}
```

**Step 3: Build to verify**

```bash
cargo build -p broadcaster
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add backend/broadcaster/
git commit -m "feat(backend): add broadcaster entry point

- Basic main.rs with tracing setup
- Configuration loading
- Graceful shutdown on Ctrl+C"
```

---

## Task 8: Docker Setup

**Files:**
- Create: `backend/watcher-signer/Dockerfile`
- Create: `backend/broadcaster/Dockerfile`
- Create: `backend/docker-compose.yml`

**Step 1: Create watcher-signer Dockerfile**

Create `backend/watcher-signer/Dockerfile`:

```dockerfile
FROM rust:1.75 as builder

WORKDIR /app
COPY . .
RUN cargo build --release -p watcher-signer

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/watcher-signer /usr/local/bin/watcher-signer

CMD ["watcher-signer"]
```

**Step 2: Create broadcaster Dockerfile**

Create `backend/broadcaster/Dockerfile`:

```dockerfile
FROM rust:1.75 as builder

WORKDIR /app
COPY . .
RUN cargo build --release -p broadcaster

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/broadcaster /usr/local/bin/broadcaster

CMD ["broadcaster"]
```

**Step 3: Create docker-compose.yml**

Create `backend/docker-compose.yml`:

```yaml
version: '3.8'

services:
  watcher-signer:
    build:
      context: .
      dockerfile: watcher-signer/Dockerfile
    env_file: .env
    restart: unless-stopped
    volumes:
      - ./logs/watcher-signer:/app/logs
    environment:
      - RUST_LOG=info

  broadcaster:
    build:
      context: .
      dockerfile: broadcaster/Dockerfile
    env_file: .env
    restart: unless-stopped
    volumes:
      - ./logs/broadcaster:/app/logs
    environment:
      - RUST_LOG=info
```

**Step 4: Commit**

```bash
git add backend/
git commit -m "feat(backend): add Docker configuration

- Dockerfiles for both services
- Docker Compose setup
- Multi-stage builds for smaller images"
```

---

## Task 9: Documentation

**Files:**
- Create: `backend/README.md`

**Step 1: Create README**

Create `backend/README.md`:

```markdown
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
```

**Step 2: Commit**

```bash
git add backend/README.md
git commit -m "docs(backend): add comprehensive README

- Service descriptions
- Development setup
- Configuration guide
- Docker instructions"
```

---

## Success Criteria

After completing all tasks:

✅ Cargo workspace builds successfully
✅ Both services have entry points with configuration
✅ Common crate provides Bitcoin client wrapper
✅ Error types and shared types defined
✅ Docker setup complete
✅ Documentation complete

---

## Next Steps

After Phase 2 foundation complete:
1. **Implement Bitcoin monitoring** - Scan for deposits
2. **Implement Starknet monitoring** - Watch for withdrawals
3. **Implement deposit processing** - Submit to Starknet
4. **Implement PSBT signing** - Create and sign PSBTs
5. **Implement broadcaster logic** - Combine and broadcast
6. **Integration testing** - End-to-end tests on testnet

---

## Notes for Implementation

- **Starknet integration:** The starknet-rs API is still evolving. May need to adjust imports/usage
- **Bitcoin key format:** Use WIF (Wallet Import Format) for BITCOIN_PRIVATE_KEY
- **Testnet:** Use Bitcoin testnet and Starknet Sepolia for initial development
- **OP_RETURN parsing:** Current implementation is basic, may need refinement
- **Error handling:** Add retry logic with exponential backoff in future tasks
- **Actor implementation:** Will use Tokio channels for actor communication (next phase)
