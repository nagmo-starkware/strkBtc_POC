# BTC Bridge Architecture Design

**Date:** 2026-02-16
**Status:** Approved
**Version:** 1.0

## Overview

This document describes the architecture for a permissioned Bitcoin ↔ Starknet bridge enabling whitelisted users to bridge BTC to strkBTC and back.

### System Components

The bridge consists of three parallel implementation streams:

1. **Bridge Core** (Cairo contracts + Rust backend) - Handles BTC ↔ strkBTC bridging with committee-based signing
2. **Post-Bridge Hook Flow** - Deferred to future design phase
3. **Bridge Web UI** (React frontend) - User interface for deposits, withdrawals, and status tracking

### Trust Model

- **Committee of signers:** Multiple independent operators run identical Rust backend services
- **Bitcoin side:** M-of-N multisig P2SH/P2WSH address
- **Starknet side:** Individual committee accounts submit transactions to bridge contract
- **Permissioned deposits:** Only whitelisted BTC addresses can bridge in
  - Non-whitelisted deposits locked in multisig, owner can manually return funds
- **Permissioned withdrawals:** Whitelist checked before burning strkBTC

---

## Architecture Approach

**Selected: Minimal On-Chain State**

The registry tracks only withdrawal PSBTs. The bridge contract handles whitelist + mint/burn logic. Bitcoin multisig address is static with no on-chain deposit tracking.

**Rationale:**
- Lowest gas costs (minimal state storage)
- Simple contract logic
- Clean separation: on-chain for withdrawals, off-chain for deposits
- Best fit for POC phase where simplicity and gas efficiency matter most

**Trade-offs:**
- No on-chain audit trail for deposits
- Cannot query "pending deposits" from contract
- Backends must maintain Bitcoin event history
- Can add indexer service later if full history tracking is needed

---

## Smart Contracts Architecture

### 1. strkBTC Token (ERC20)

**Implementation:**
- OpenZeppelin ERC20 implementation (battle-tested standard)
- Upgradeable via owner-controlled proxy
- Bridge contract has exclusive minting and burning rights

**Interface:**
```cairo
// Standard ERC20: transfer, approve, transferFrom, balanceOf, totalSupply
// Minting/burning only callable by bridge contract
```

### 2. Bridge Core Contract

**Upgradeable:** Owner-controlled upgrades

**State:**
- Committee members (addresses)
- Signature threshold (M-of-N)
- BTC address whitelist
- Starknet address whitelist
- Processed deposit hashes (prevent double-mint)
- Minimum withdrawal amount

**Deposit Flow:**
- Committee members call `deposit_request(btc_tx_hash, starknet_address, amount)`
- Contract collects signatures internally
- Auto-executes mint when threshold met
- Checks BTC whitelist before minting
- Transfers minted strkBTC to user's Starknet address

**Withdrawal Flow:**
- User calls `withdraw(btc_address, amount)`
- Checks Starknet address is whitelisted
- Checks amount ≥ minimum
- Burns strkBTC immediately
- Emits `WithdrawalRequested` event

**Admin Functions:**
- Add/remove committee members
- Update signature threshold
- Add/remove whitelisted addresses (both BTC and Starknet)
- Update minimum withdrawal amount
- Upgrade contract

### 3. Bridge Registry Contract

**Upgradeable:** Owner-controlled upgrades

**Purpose:** Track withdrawal PSBT signatures

**State:**
- `tx_hash → tx_body` (stores PSBT data)
- `(tx_hash, signer) → bool` (tracks which signers submitted)

**Functions:**
- `submit_psbt(tx_hash, psbt_data)` - Signer submits PSBT
- `get_signature_count(tx_hash) → u32` - Query how many signers submitted
- `get_psbt(tx_hash) → bytes` - Retrieve PSBT data

**Events:**
- `PSBTSubmitted(tx_hash, signer, psbt_data)` - Emitted on each submission

### Contract Events

**DepositProcessed**
```cairo
struct DepositProcessed {
    btc_tx_hash: felt252,
    starknet_address: ContractAddress,
    amount: u256
}
```

**WithdrawalRequested**
```cairo
struct WithdrawalRequested {
    request_id: felt252,
    btc_address: felt252,  // Bitcoin address as felt
    amount: u256
}
```

**PSBTSubmitted**
```cairo
struct PSBTSubmitted {
    tx_hash: felt252,
    signer: ContractAddress,
    psbt_data: Array<felt252>
}
```

---

## Rust Backend Architecture

### Two-Service Design

**Service 1: Event Watcher + Deposit Processor (`watcher-signer`)**

**Bitcoin Monitoring:**
- Watches multisig address for incoming transactions
- Waits for 6 confirmations (standard Bitcoin finality)
- Parses OP_RETURN for Starknet address (version byte + 32 bytes)
- Queries bridge contract to check if sender is whitelisted

**Deposit Processing:**
- If whitelisted: calls `deposit_request()` on bridge contract
- Contract collects signatures and auto-mints at threshold
- If NOT whitelisted: logs deposit, funds remain locked

**Starknet Event Monitoring:**
- Watches for `WithdrawalRequested` events
- Creates deterministic PSBT using SIGHASH_ANYONECANPAY
- Submits PSBT to registry contract

**Service 2: Registry Monitor + Bitcoin Broadcaster (`broadcaster`)**

**Registry Monitoring:**
- Watches `PSBTSubmitted` events
- Tracks signature count per withdrawal

**Transaction Broadcasting:**
- When threshold met, collects all PSBTs for that withdrawal
- Adds own input to cover Bitcoin network fees (ANYONECANPAY allows this)
- Combines partial signatures
- Broadcasts final Bitcoin transaction

### Configuration (Environment Variables)

```env
BITCOIN_RPC_URL=http://bitcoin-node:8332
STARKNET_RPC_URL=https://starknet-mainnet.infura.io/v3/...
SIGNER_PRIVATE_KEY=0x...
BITCOIN_MULTISIG_ADDRESS=3...
BRIDGE_CONTRACT_ADDRESS=0x...
REGISTRY_CONTRACT_ADDRESS=0x...
MIN_CONFIRMATIONS=6
```

### Restart & Recovery

**Design:** Stateless services with registry as source of truth

**On Startup:**
1. Query registry contract to see recent activity
2. Resync logic (details to be fine-tuned later)
3. Scan recent blocks to catch up on missed events
4. Idempotency: skip already-processed operations (check contract state)

### Docker Deployment

**Containers:**
- `watcher-signer` - Service 1
- `broadcaster` - Service 2

**Orchestration:**
- Docker Compose for local development
- Health checks and automatic restarts
- Shared network if inter-service communication needed
- Volume mounts for logs

---

## Bitcoin Integration Details

### Deposit Flow (BTC → Starknet)

**1. User Sends BTC**
- Destination: Bridge multisig address
- OP_RETURN data:
  - Version byte (1 byte) - enables future protocol upgrades
  - Starknet address (32 bytes / felt252)

**2. Backend Detects Deposit**
- Waits for 6 confirmations (~1 hour)
- Parses OP_RETURN data
- Validates format
- Queries bridge contract: is sender BTC address whitelisted?

**3. If Whitelisted**
- Backend calls `deposit_request(btc_tx_hash, starknet_address, amount)`
- Bridge contract collects signatures from committee members
- Auto-mints strkBTC when threshold met
- Transfers minted strkBTC to user's Starknet address
- Emits `DepositProcessed` event

**4. If NOT Whitelisted**
- Backend logs the deposit for owner visibility
- Funds remain locked in multisig
- No mint occurs on Starknet
- Owner can manually coordinate return via off-chain committee action

### Withdrawal Flow (Starknet → BTC)

**1. User Burns strkBTC**
- User calls `withdraw(btc_address, amount)` on bridge contract
- Contract checks:
  - Is Starknet address whitelisted?
  - Is amount ≥ minimum withdrawal?
- Burns strkBTC immediately
- Emits `WithdrawalRequested(request_id, btc_address, amount)`

**2. Each Signer Creates PSBT**
- Backend detects `WithdrawalRequested` event
- Creates deterministic PSBT:
  - Same algorithm used by all signers = identical PSBTs
  - Uses **SIGHASH_ANYONECANPAY** flag
  - No fee inputs (broadcaster adds those later)
- Submits PSBT to registry contract
- Registry emits `PSBTSubmitted` event

**3. Broadcaster Combines and Sends**
- Monitors registry for threshold
- When enough PSBTs collected:
  - Retrieves all PSBTs for that withdrawal
  - Adds own input to pay Bitcoin network fees
  - Combines partial signatures into final transaction
  - Broadcasts to Bitcoin network

### Bitcoin Multisig Configuration

**Address Type:** P2SH or P2WSH (not P2TR for simplicity)

**Threshold:** M-of-N (e.g., 3-of-5 signers required)

**UTXO Management:**
- No optimization strategy
- Simple management: use available UTXOs
- Manual cleanup when needed
- Prevents complexity in UTXO selection logic

---

## Web UI Overview

**Note:** Detailed design to be refined in future phase.

### Core Features

**Deposit Instructions:**
- Show bridge multisig BTC address
- Generate OP_RETURN data with user's Starknet address
- Display formatted instructions for wallet usage

**Withdrawal Interface:**
- Connect Starknet wallet
- Input BTC destination address
- Input amount to withdraw
- Burn strkBTC to initiate withdrawal

**Status Tracking:**
- Bridge status and health
- Transaction history
- Pending operations

### Technical Stack

- React-based frontend
- Starknet wallet integration (wallet connect)
- Starknet RPC integration to query contract state
- Optional: indexer service for richer history (future enhancement)

---

## Error Handling & Edge Cases

### Deposit Edge Cases

**Duplicate Deposits:**
- Bridge contract tracks processed `btc_tx_hash`
- Subsequent `deposit_request()` calls with same hash rejected
- Prevents double-minting attack

**Malformed OP_RETURN:**
- Backend validates format (version byte + 32-byte address)
- Invalid format = not processed, funds locked in multisig
- Owner can manually return after investigation

**Race Conditions (Multiple Signers):**
- Bridge contract handles concurrent `deposit_request()` calls
- First N signers to reach threshold trigger mint
- Additional calls after mint are no-ops (already processed check)

### Withdrawal Edge Cases

**Below Minimum Amount:**
- Contract reverts transaction
- User keeps their strkBTC, no burn occurs
- User must retry with amount ≥ minimum

**User Not Whitelisted:**
- Contract reverts transaction
- User keeps their strkBTC, no burn occurs
- Must get whitelisted before withdrawing

**strkBTC Burned but BTC Transaction Fails:**
- **No automatic recovery mechanism**
- Committee manually investigates off-chain
- Manual resolution options:
  - Re-broadcast transaction if issue was temporary
  - Manually construct and send BTC to user
- Rare scenario (deterministic PSBT construction minimizes risk)

**PSBT Signature Threshold Not Met:**
- Withdrawal remains in registry indefinitely
- Backends continue attempting to sign/broadcast
- Manual committee intervention if needed
- Could add timeout mechanism in future version

### Non-Whitelisted Deposit Handling

**When non-whitelisted address deposits BTC:**

1. Funds locked in multisig (backends ignore the deposit)
2. Backend logs transaction for owner visibility
3. Owner can manually construct and sign transaction to return funds
4. Requires off-chain committee coordination

**Recovery Process:**
1. Owner identifies locked deposit via backend logs
2. Owner coordinates with committee signers
3. Committee manually signs Bitcoin transaction to return funds
4. Funds sent back to original sender address

---

## Security Considerations

### Threat Model

**Committee Compromise:**
- Threshold design prevents single signer compromise
- Owner can remove compromised signers
- Monitor for unusual signing patterns

**Smart Contract Bugs:**
- Use OpenZeppelin audited contracts
- Upgrade mechanism allows fixes
- Start with conservative limits (minimum withdrawal amounts)

**Bitcoin Reorg Risk:**
- 6 confirmations mitigates deep reorg risk
- In rare reorg case: manual committee intervention required

**Whitelist Bypass:**
- Dual whitelist (BTC + Starknet) enforced on-chain
- Only owner can modify whitelists
- Monitor whitelist changes

### Operational Security

**Private Key Management:**
- Committee signers must secure their private keys
- Recommend hardware wallets or secure enclaves
- Key rotation mechanism via owner admin functions

**Backend Infrastructure:**
- Each signer runs independent infrastructure
- No shared secrets between signers
- Docker isolation and security best practices

---

## Future Enhancements

**Post-Bridge Hook Flow:**
- Design and implementation deferred to separate phase
- Integration points identified but not specified

**Indexer Service:**
- Optional enhancement for richer transaction history
- Would enable better web UI status tracking
- Not required for core bridge functionality

**Resync Logic Refinement:**
- Current design: stateless with registry as source of truth
- Fine-tuning needed for optimal catch-up behavior
- Consider block range limits, pagination, event filtering

**Fee Optimization:**
- Current: no UTXO optimization
- Future: could add consolidation during low-fee periods
- Future: could implement coin selection algorithms

**Time-Based Expiry:**
- Registry entries could expire after N blocks
- Prevents unbounded state growth
- Would require cleanup mechanism

---

## Success Criteria

### MVP Milestone

✅ Whitelisted user can deposit BTC and receive strkBTC
✅ Whitelisted user can burn strkBTC and receive BTC
✅ Non-whitelisted deposits are blocked
✅ Committee threshold enforced on both deposits and withdrawals
✅ Owner can manage whitelists and committee membership
✅ Backends are stateless and recoverable

### Production Readiness (Future)

- Security audit of smart contracts
- Backend high-availability setup
- Monitoring and alerting infrastructure
- User documentation and support
- Post-bridge hook flow implemented
- Web UI with rich status tracking

---

## Implementation Phases

**Phase 1: Smart Contracts**
1. strkBTC ERC20 token (OpenZeppelin)
2. Bridge Core contract (deposits, withdrawals, whitelists)
3. Bridge Registry contract (PSBT tracking)
4. Deploy to testnet

**Phase 2: Rust Backend**
1. Service 1: Event watcher + deposit processor
2. Service 2: Registry monitor + broadcaster
3. Docker setup and configuration
4. Integration testing with testnet contracts

**Phase 3: Web UI**
1. Design UI flows (separate design phase)
2. Implement deposit instructions generator
3. Implement withdrawal interface
4. Implement status tracking
5. Deploy frontend

**Phase 4: Testing & Refinement**
1. End-to-end integration testing
2. Committee coordination testing
3. Edge case validation
4. Performance optimization
5. Security hardening

**Phase 5: Post-Bridge Hook Flow**
1. Design phase (requirements TBD)
2. Implementation (details TBD)
3. Integration with core bridge

---

## Appendix: Open Questions

These items require future refinement:

1. **Resync logic details** - exact block range, pagination strategy
2. **Post-bridge hook flow** - complete requirements and design
3. **Web UI detailed flows** - specific components and UX
4. **Fee rate strategy** - broadcaster input amount calculation
5. **Registry cleanup** - time-based expiry mechanism
6. **Monitoring strategy** - metrics, alerts, dashboards
7. **Testnet deployment details** - which networks, faucet requirements
