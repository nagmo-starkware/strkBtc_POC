# Phase 2: Rust Backend Implementation Design

**Date:** 2026-02-17
**Status:** Approved
**Version:** 1.0

## Overview

This document describes the Rust backend implementation for the BTC bridge. The backend consists of two services that enable committee members to coordinate deposits and withdrawals between Bitcoin and Starknet.

### System Components

1. **watcher-signer** - Committee member service that monitors both chains and submits transactions
2. **broadcaster** - PSBT combiner service that finalizes and broadcasts Bitcoin withdrawals

### Design Principles

- **Stateless:** Services use in-memory tracking only, no persistent storage
- **Idempotent:** All operations can be safely retried
- **Resilient:** Graceful error handling, automatic recovery on restart
- **Simple:** Actor-based for watcher-signer, simple async loop for broadcaster

---

## Architecture Overview

### Two-Service Design

**Service 1: watcher-signer** (runs on each committee member's infrastructure)
- Monitors Bitcoin blockchain for deposits to multisig address
- Monitors Starknet for withdrawal requests
- Submits deposit requests to Starknet bridge contract
- Creates and signs PSBTs for withdrawals, submits to registry

**Service 2: broadcaster** (runs independently, can be any committee member)
- Monitors Starknet registry for PSBT submissions
- Combines PSBTs when threshold is met
- Adds fee input and broadcasts final transaction to Bitcoin

### Technology Stack

- **Language:** Rust (stable)
- **Async Runtime:** Tokio
- **Bitcoin:** bitcoincore-rpc + rust-bitcoin
- **Starknet:** starknet-rs (providers + accounts)
- **Containerization:** Docker + Docker Compose

### Stateless Design Philosophy

Both services maintain **no persistent state**:
- In-memory `HashSet<TxHash>` for tracking seen transactions
- On restart: re-scan recent blocks to rebuild state
- Source of truth: blockchain state (Bitcoin, Starknet, Registry contract)
- Idempotency ensures safe re-processing

---

## Service 1: watcher-signer Architecture

### Actor-Based Design

Uses Tokio actors for concurrent, independent tasks:

**1. Bitcoin Monitor Actor**
- **Polls:** Every 10 minutes (matches Bitcoin block time)
- **Tracks:** `HashSet<Txid>` of seen deposits
- **Logic:**
  - Query multisig address for new transactions
  - Parse OP_RETURN (version byte + 32-byte Starknet address)
  - Check confirmation count
  - When 6 confirmations reached → send to Deposit Processor

**2. Starknet Monitor Actor**
- **Polls:** Every 10 seconds
- **Tracks:** `HashSet<felt252>` of seen withdrawal request IDs
- **Logic:**
  - Query bridge contract for `WithdrawalRequested` events
  - Wait for L1 finalization (Ethereum finality)
  - When finalized → send to PSBT Signer

**3. Deposit Processor**
- **Triggered by:** Bitcoin Monitor when deposit has 6 confirmations
- **Logic:**
  - Query bridge contract: is sender BTC address whitelisted?
  - If whitelisted: submit `deposit_request(btc_tx_hash, starknet_address, amount)` transaction
  - If not whitelisted: log and skip (funds locked in multisig)
  - Contract handles duplicate rejection (idempotent)

**4. PSBT Signer**
- **Triggered by:** Starknet Monitor when withdrawal is L1-finalized
- **Logic:**
  - Create PSBT for withdrawal (output to user's BTC address)
  - Add SIGHASH_ANYONECANPAY flag (allows broadcaster to add fee input)
  - Partially sign PSBT with committee member's Bitcoin private key
  - Submit signed PSBT to registry contract via `submit_psbt()` transaction
  - Contract tracks signatures and emits events

### Communication Flow

```
Bitcoin Monitor → (confirmed deposit) → Deposit Processor → Starknet Bridge Contract
Starknet Monitor → (L1 finalized withdrawal) → PSBT Signer → Registry Contract
```

### Actor Communication

- **Tokio channels (mpsc):** Actors send messages via async channels
- **Message types:**
  - `ConfirmedDeposit { txid, starknet_addr, amount }`
  - `FinalizedWithdrawal { request_id, btc_addr, amount }`

---

## Service 2: broadcaster Architecture

### Simple Event Loop (tokio::select!)

No actors needed - single async loop handles all logic:

```rust
loop {
    tokio::select! {
        _ = registry_poll_interval.tick() => {
            // Poll registry for new PSBT submissions
            check_registry_events().await;
        }

        _ = broadcast_check_interval.tick() => {
            // Check if any withdrawals ready to broadcast
            check_and_broadcast().await;
        }
    }
}
```

### State Management

**In-memory tracking:**
- `HashMap<TxHash, SignatureCount>` - tracks PSBT count per withdrawal
- Simple counter only (pull actual PSBTs from contract when needed)

### Logic Flow

**1. Registry Monitoring**
- **Poll interval:** Every 30 seconds
- **Query:** `PSBTSubmitted` events from registry contract
- **Update:** Increment signature count for each withdrawal
- **Track:** Which withdrawals have reached threshold

**2. PSBT Combination & Broadcasting**
- **Check interval:** Every 60 seconds
- **For each withdrawal at threshold:**
  1. Query registry contract for all PSBTs
  2. Combine PSBTs (merge partial signatures)
  3. Add own Bitcoin input to cover network fees (ANYONECANPAY allows this)
  4. Finalize transaction
  5. Broadcast to Bitcoin network via RPC
  6. Mark as processed (in-memory, to avoid re-broadcast)

**Note:** Bitcoin node automatically rejects duplicate broadcasts (idempotent)

---

## Configuration & Environment

### Environment Variables

**watcher-signer:**
```env
# Bitcoin Configuration
BITCOIN_RPC_URL=http://bitcoin-node:8332
BITCOIN_RPC_USER=rpcuser
BITCOIN_RPC_PASSWORD=rpcpassword
BITCOIN_MULTISIG_ADDRESS=3...              # The bridge's multisig address
BITCOIN_PRIVATE_KEY=L...                   # Committee member's BTC key (WIF format)
MIN_CONFIRMATIONS=6

# Starknet Configuration
STARKNET_RPC_URL=https://starknet-sepolia.infura.io/v3/YOUR_KEY
SIGNER_PRIVATE_KEY=0x...                   # Committee member's Starknet private key
BRIDGE_CONTRACT_ADDRESS=0x...
REGISTRY_CONTRACT_ADDRESS=0x...

# Polling Intervals
BITCOIN_POLL_INTERVAL_SECS=600             # 10 minutes
STARKNET_POLL_INTERVAL_SECS=10
```

**broadcaster:**
```env
# Bitcoin Configuration
BITCOIN_RPC_URL=http://bitcoin-node:8332
BITCOIN_RPC_USER=rpcuser
BITCOIN_RPC_PASSWORD=rpcpassword
BITCOIN_PRIVATE_KEY=L...                   # For adding fee input

# Starknet Configuration
STARKNET_RPC_URL=https://starknet-sepolia.infura.io/v3/YOUR_KEY
REGISTRY_CONTRACT_ADDRESS=0x...
SIGNATURE_THRESHOLD=3                      # M-of-N threshold

# Polling Intervals
REGISTRY_POLL_INTERVAL_SECS=30
BROADCAST_CHECK_INTERVAL_SECS=60
```

### Docker Compose Setup

```yaml
version: '3.8'

services:
  watcher-signer:
    build:
      context: ./watcher-signer
      dockerfile: Dockerfile
    env_file: .env.watcher-signer
    restart: unless-stopped
    volumes:
      - ./logs/watcher-signer:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  broadcaster:
    build:
      context: ./broadcaster
      dockerfile: Dockerfile
    env_file: .env.broadcaster
    restart: unless-stopped
    volumes:
      - ./logs/broadcaster:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

---

## Error Handling & Recovery

### Restart & Resync Strategy

**watcher-signer on startup:**

1. **Bitcoin resync:**
   - Scan last 144 blocks (~24 hours at 10 min/block)
   - Check each transaction against multisig address
   - Process any deposits with 6+ confirmations
   - Add all seen transaction IDs to in-memory HashSet

2. **Starknet resync:**
   - Query last 1000 blocks for `WithdrawalRequested` events
   - Check L1 finalization status for each
   - Process any that are finalized
   - Add all seen request IDs to in-memory HashSet

**broadcaster on startup:**

1. **Registry resync:**
   - Query last 1000 `PSBTSubmitted` events from registry
   - Rebuild `HashMap<TxHash, SignatureCount>`
   - Check for any withdrawals at threshold
   - Broadcast immediately if ready
   - Continue normal monitoring

### Error Handling Patterns

**RPC Connection Failures:**
- Retry with exponential backoff (base: 1s, max: 60s, attempts: 3)
- Log error details (not crash)
- Continue monitoring after recovery
- Future: emit metrics/alerts after N consecutive failures

**Transaction Submission Failures:**

| Failure Type | Action |
|--------------|--------|
| Starknet tx rejected (duplicate) | Log and skip (idempotent, already processed) |
| Starknet tx rejected (revert) | Log revert reason, mark as processed |
| Bitcoin broadcast rejected (duplicate) | Log and skip (idempotent) |
| Bitcoin broadcast rejected (other) | Retry up to 3 times, then log and skip |
| Contract call timeout | Retry with backoff |

**Invalid Data Handling:**
- Malformed OP_RETURN: Log warning, skip deposit
- Invalid PSBT from registry: Log error, skip withdrawal
- Never crash service due to bad data
- Validate all parsed data before processing

### Idempotency Guarantees

All operations are designed to be safely retried:

| Operation | Idempotency Mechanism |
|-----------|----------------------|
| `deposit_request()` | Contract rejects duplicate `btc_tx_hash` |
| `submit_psbt()` | Contract rejects duplicate signature from same signer |
| Bitcoin broadcast | Bitcoin node rejects duplicate transactions (same inputs) |
| PSBT combination | Combining same PSBTs multiple times produces identical result |

**Result:** Services can be restarted at any time, will re-process recent transactions safely.

---

## Cargo Workspace Structure

### Directory Layout

```
backend/
├── Cargo.toml                          # Workspace root
├── docker-compose.yml                  # Container orchestration
├── .env.example                        # Environment template
├── .gitignore
│
├── common/                             # Shared library crate
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs                      # Re-exports
│       ├── bitcoin.rs                  # Bitcoin RPC client wrapper
│       ├── starknet.rs                 # Starknet provider/account wrapper
│       ├── types.rs                    # Shared types (Deposit, Withdrawal, etc.)
│       ├── config.rs                   # Config loading from env
│       └── error.rs                    # Common error types
│
├── watcher-signer/                     # Service 1 binary crate
│   ├── Cargo.toml
│   ├── Dockerfile
│   └── src/
│       ├── main.rs                     # Entry point, actor setup
│       ├── actors/
│       │   ├── mod.rs
│       │   ├── bitcoin_monitor.rs      # Bitcoin blockchain polling actor
│       │   └── starknet_monitor.rs     # Starknet event polling actor
│       ├── processors/
│       │   ├── mod.rs
│       │   ├── deposit_processor.rs    # Deposit submission logic
│       │   └── psbt_signer.rs          # PSBT creation & signing
│       └── messages.rs                 # Actor message types
│
└── broadcaster/                        # Service 2 binary crate
    ├── Cargo.toml
    ├── Dockerfile
    └── src/
        ├── main.rs                     # Entry point, select! loop
        ├── registry_monitor.rs         # Registry event polling
        └── psbt_combiner.rs            # PSBT combination & broadcast logic
```

### Key Dependencies

**Workspace (`backend/Cargo.toml`):**
```toml
[workspace]
members = ["common", "watcher-signer", "broadcaster"]
resolver = "2"

[workspace.dependencies]
tokio = { version = "1.35", features = ["full"] }
anyhow = "1.0"
thiserror = "1.0"
serde = { version = "1.0", features = ["derive"] }
tracing = "0.1"
tracing-subscriber = "0.3"
```

**common crate:**
- `bitcoincore-rpc` - Bitcoin RPC client
- `bitcoin` - Bitcoin primitives (PSBT, transactions, keys)
- `starknet` - Starknet providers and accounts
- `starknet-crypto` - Cryptographic primitives
- `tokio` - Async runtime
- `serde` / `serde_json` - Serialization
- `anyhow` / `thiserror` - Error handling
- `tracing` - Structured logging

**watcher-signer:**
- `common` (workspace)
- `tokio` (workspace, with sync feature for channels)

**broadcaster:**
- `common` (workspace)
- `tokio` (workspace)

---

## Data Flow Diagrams

### Deposit Flow (BTC → Starknet)

```
User
  ↓ (sends BTC to multisig with OP_RETURN)
Bitcoin Network
  ↓ (6 confirmations)
Bitcoin Monitor Actor (watcher-signer)
  ↓ (ConfirmedDeposit message)
Deposit Processor
  ↓ (queries whitelist)
Bridge Contract (Starknet)
  ↓ (if whitelisted)
Deposit Processor
  ↓ (submits deposit_request tx)
Bridge Contract (Starknet)
  ↓ (collects signatures, auto-mints at threshold)
strkBTC Token Contract
  ↓ (mints tokens)
User's Starknet Address
```

### Withdrawal Flow (Starknet → BTC)

```
User
  ↓ (calls withdraw() on bridge)
Bridge Contract (Starknet)
  ↓ (burns strkBTC, emits WithdrawalRequested)
Ethereum L1
  ↓ (finalized)
Starknet Monitor Actor (watcher-signer)
  ↓ (FinalizedWithdrawal message)
PSBT Signer
  ↓ (creates PSBT with ANYONECANPAY)
PSBT Signer
  ↓ (signs with BTC key)
Registry Contract (Starknet)
  ↓ (stores PSBT, emits PSBTSubmitted)
Broadcaster
  ↓ (monitors events, counts signatures)
Broadcaster
  ↓ (threshold met, retrieves PSBTs)
Broadcaster
  ↓ (combines PSBTs, adds fee input)
Bitcoin Network
  ↓ (broadcast)
User's Bitcoin Address
```

---

## Testing Strategy

### Unit Tests

**common crate:**
- Bitcoin RPC client wrapper (mock RPC responses)
- Starknet provider wrapper (mock contract calls)
- OP_RETURN parsing (valid/invalid formats)
- PSBT creation and signing
- Configuration loading

**watcher-signer:**
- Actor message passing
- Deposit detection logic
- Withdrawal detection logic
- Whitelist checking

**broadcaster:**
- PSBT combination logic
- Signature counting
- Threshold detection

### Integration Tests

**End-to-end flow:**
1. Deploy contracts to Starknet testnet
2. Start watcher-signer and broadcaster with testnet config
3. Send test BTC transaction (testnet)
4. Verify deposit processed on Starknet
5. Initiate withdrawal on Starknet
6. Verify PSBT signed and submitted
7. Verify Bitcoin transaction broadcast

### Manual Testing Checklist

- [ ] Service startup and resync logic
- [ ] Bitcoin deposit with valid OP_RETURN
- [ ] Bitcoin deposit with malformed OP_RETURN
- [ ] Bitcoin deposit from non-whitelisted address
- [ ] Starknet withdrawal from whitelisted address
- [ ] Starknet withdrawal from non-whitelisted address
- [ ] Service restart mid-process
- [ ] RPC connection failures and recovery
- [ ] Multiple committee members signing
- [ ] Threshold reached and broadcast

---

## Security Considerations

### Private Key Management

**Committee members must:**
- Store Bitcoin private keys securely (hardware wallet or HSM recommended)
- Store Starknet private keys securely
- Use environment variables (never hardcode)
- Rotate keys via owner admin functions if compromised

**Key permissions:**
- Bitcoin key: Only needs signing permission (not spending permission on its own)
- Starknet key: Needs transaction submission permission

### Network Security

**RPC endpoints:**
- Use authenticated Bitcoin RPC (username + password)
- Use HTTPS for Starknet RPC
- Consider running own nodes (don't rely on third-party RPCs for production)

**Docker:**
- Run containers with minimal privileges
- Use read-only filesystem where possible
- Network isolation between services (if running multiple committees)

### Attack Vectors

| Attack | Mitigation |
|--------|-----------|
| Compromised committee member | Threshold design (requires M signatures) |
| RPC MITM | HTTPS for Starknet, authenticated RPC for Bitcoin |
| Malformed transactions | Validation before processing |
| Replay attacks | Contract idempotency checks |
| DoS via invalid deposits | Whitelist enforcement, skip invalid data |

---

## Operational Monitoring

### Logging

**Structured logging with tracing:**
- INFO: Normal operations (deposit detected, PSBT signed, tx broadcast)
- WARN: Recoverable errors (RPC retry, invalid data skipped)
- ERROR: Critical failures (contract call reverted, broadcast failed after retries)

**Log format:**
```json
{
  "timestamp": "2026-02-17T10:30:00Z",
  "level": "INFO",
  "service": "watcher-signer",
  "component": "bitcoin_monitor",
  "message": "Deposit detected",
  "txid": "abc123...",
  "confirmations": 6,
  "amount": 0.5
}
```

### Health Checks

**HTTP endpoint (future enhancement):**
- `GET /health` - returns 200 if service is running
- `GET /metrics` - Prometheus-style metrics

**Metrics to track (future):**
- Deposits processed (count)
- Withdrawals signed (count)
- Transactions broadcast (count)
- RPC failures (count)
- Average confirmation time
- Current in-memory state size

---

## Future Enhancements

**Not in scope for Phase 2, but identified for later:**

1. **Metrics & Alerting:**
   - Prometheus metrics export
   - Grafana dashboards
   - Alert on excessive RPC failures
   - Alert on stuck transactions

2. **Advanced Resync:**
   - Configurable resync depth
   - Incremental state checkpointing (optional persistence)
   - Faster catchup via batched RPC calls

3. **Fee Optimization:**
   - Dynamic Bitcoin fee estimation
   - Fee market tracking
   - RBF (Replace-By-Fee) for stuck withdrawals

4. **High Availability:**
   - Multiple broadcaster instances (leader election)
   - Distributed tracing across services
   - Health check integration with orchestration

5. **Performance:**
   - Parallel RPC requests
   - Connection pooling
   - Caching of frequently-queried contract data

---

## Implementation Phases

**Phase 2A: Foundation**
1. Set up Cargo workspace
2. Implement common crate (Bitcoin, Starknet wrappers, config)
3. Write unit tests for common

**Phase 2B: watcher-signer**
1. Implement Bitcoin monitor actor
2. Implement Starknet monitor actor
3. Implement deposit processor
4. Implement PSBT signer
5. Wire up actors with channels
6. Integration test with testnet

**Phase 2C: broadcaster**
1. Implement registry monitor
2. Implement PSBT combiner
3. Integration test with testnet

**Phase 2D: Docker & Deployment**
1. Create Dockerfiles
2. Create docker-compose.yml
3. Write deployment documentation
4. End-to-end testing

---

## Success Criteria

### Phase 2 Complete When:

✅ watcher-signer service runs and monitors both chains
✅ Deposits detected and processed correctly
✅ Withdrawals detected and PSBTs signed
✅ broadcaster combines PSBTs and broadcasts to Bitcoin
✅ Services restart gracefully with resync
✅ Error handling works (RPC failures, invalid data)
✅ Docker setup works for local development
✅ Unit tests pass
✅ Integration tests pass on testnet
✅ Documentation complete (README, deployment guide)

### Production Readiness (Future):

- Metrics and monitoring
- High availability setup
- Security audit
- Performance optimization
- Operational runbooks

---

## Appendix: Open Questions

These will be refined during implementation:

1. **Exact resync block depth** - 144 blocks for Bitcoin, 1000 for Starknet (to be validated)
2. **RPC connection pooling** - Use single connection or pool?
3. **Bitcoin fee input selection** - Broadcaster's UTXO management strategy
4. **L1 finalization check** - Exact API for checking Ethereum finality from Starknet event
5. **Actor restart policy** - Should actors restart on panic or crash entire service?
