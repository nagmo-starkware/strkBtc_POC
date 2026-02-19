# Post-Bridge Privacy Hook Design

**Date:** 2026-02-18
**Status:** Approved
**Version:** 1.0

## Overview

This document describes the design for integrating a privacy pool post-bridge hook into the BTC ↔ Starknet bridge. Users bridge BTC through the Atomiq operator, and bridged strkBTC is automatically deposited into a general-purpose privacy pool.

### System Components

**New Components:**
1. **Backend Service** (Rust) - Handles privacy pool setup (registration, open note creation)
2. **Hook Contract** (Cairo) - Receives minted tokens from Atomiq, deposits to privacy pool

**External Dependencies:**
1. **Atomiq API** (operator) - Extended to support hook contracts and metadata storage
2. **Starknet Wallet API** - Extended to send PSBT + private key to backend
3. **Privacy Pool Contracts** (external team) - General-purpose privacy pool for Starknet

### Trust Model

**POC Phase:**
- User trusts backend with Starknet private key temporarily
- Backend is stateless (contracts are source of truth)
- Atomiq is trusted bridge operator (whitelisted in bridge core)

**Future Migration:**
- Move to account abstraction / session keys
- Eliminate private key transmission to backend

---

## Architecture Approach

**Selected: Backend Pre-Setup with Simple Hook Contract**

The backend prepares everything BEFORE the user signs the Bitcoin PSBT. The hook contract only deposits to a pre-existing open note.

**Flow:**
```
Backend → Privacy Pool (register + create open note)
Backend → Atomiq (submit PSBT + note_id)
[Bitcoin tx confirms]
Atomiq Bridge → Hook Contract (mint tokens with note_id)
Hook Contract → Privacy Pool (deposit to note)
```

**Rationale:**
- User registration and open note creation happen before Bitcoin transaction
- Hook contract is extremely simple (just deposit to existing note)
- Backend can verify setup succeeded before PSBT submission
- Atomiq stores note_id and injects it when calling hook contract

**Trade-offs:**
- Open notes created before BTC is sent (timing mismatch)
- If user abandons flow, unused open notes remain in privacy pool
- Privacy pool must support creating notes without immediate funding

---

## Detailed Flow Sequence

### Happy Flow (Step-by-Step)

**Step 1: User Initiates Bridge**
- User connects BTC wallet to dapp
- User connects Starknet wallet to dapp
- User enters amount to bridge (e.g., 0.001 BTC)

**Step 2: Dapp Prepares Request**
- Dapp extracts BTC address, Starknet address, amount
- Dapp knows hook contract address (configured)

**Step 3: Dapp Calls Atomiq API**
```
POST /psbt/create-with-hook
{
  "btc_address": "bc1q...",
  "amount_sats": 100000,
  "starknet_recipient": "0x...",
  "hook_contract": "0x123..."
}
```
Atomiq returns unsigned PSBT

**Step 4: User Signs PSBT with Bitcoin Wallet**
- Dapp passes unsigned PSBT to BTC wallet
- User approves and signs
- BTC wallet returns partially signed PSBT (missing Atomiq's signature)

**Step 5: Dapp Sends PSBT to Starknet Wallet**
```typescript
wallet.sendPSBTToBackend({
  psbt: "base64_psbt",
  backendEndpoint: "https://backend.example.com/execute-bridge-hook",
  btcAmount: 100000
})
```

**Step 6: Starknet Wallet → Backend**
Wallet POSTs to backend:
```json
{
  "psbt": "base64...",
  "starknet_private_key": "0x...",
  "btc_amount_sats": 100000,
  "starknet_address": "0x..."
}
```
Backend responds immediately: `{status: "accepted", request_id: "uuid"}`

**Step 7: Backend Processing (Async)**
1. Query `privacy_pool.is_registered(starknet_address)`
2. If false: Call `privacy_pool.register_user(starknet_address)`
3. Call `privacy_pool.create_open_note(amount, ...TBD params)`
4. Receive `open_note_id` from contract
5. POST to Atomiq `/psbt/submit-with-hook` with PSBT + note_id
6. Atomiq stores mapping: `psbt_hash → open_note_id`

**Step 8: Atomiq Signs & Broadcasts Bitcoin TX**
- Atomiq adds their signature to PSBT
- Atomiq broadcasts to Bitcoin network
- Bitcoin tx confirms (~1 hour with 6 confirmations)

**Step 9: Atomiq Bridge Detects Deposit**
- Atomiq's watcher detects confirmed Bitcoin deposit
- Atomiq retrieves `open_note_id` from storage
- Atomiq's bridge calls hook contract:
```cairo
hook_contract.receive_bridge_tokens(
    recipient: user_starknet_address,
    amount: 100000_u256,
    open_note_id: note_id_from_storage
)
```

**Step 10: Hook Contract Deposits to Privacy Pool**
1. Verify caller is Atomiq bridge (whitelisted)
2. Receive strkBTC tokens
3. Approve privacy_pool to spend tokens
4. Call `privacy_pool.deposit_to_note(open_note_id, amount)`
5. Emit `TokensDepositedToPrivacyPool` event

**Result:** User's BTC is now in privacy pool as strkBTC

---

## Component Interfaces

### Backend Service API

**Endpoint:** `POST /execute-bridge-hook`

**Request:**
```json
{
  "psbt": "base64_encoded_psbt_string",
  "starknet_private_key": "0x...",
  "btc_amount_sats": 100000,
  "starknet_address": "0x..."
}
```

**Response (Immediate - Async Processing):**
```json
{
  "status": "accepted",
  "request_id": "uuid-...",
  "message": "PSBT accepted for processing"
}
```

**Processing Logic:**
```rust
async fn handle_bridge_hook_request(req: ExecuteBridgeHookRequest) -> Result<()> {
    // 1. Validate inputs
    validate_psbt(&req.psbt)?;
    validate_private_key(&req.starknet_private_key)?;
    validate_address(&req.starknet_address)?;

    // 2. Initialize Starknet account from private key
    let account = create_starknet_account(&req.starknet_private_key).await?;

    // 3. Query privacy pool: is user registered?
    let is_registered = privacy_pool_contract
        .call("is_registered")
        .args(&[req.starknet_address])
        .call()
        .await?;

    // 4. Register if needed
    if !is_registered {
        let tx = privacy_pool_contract
            .method("register_user")
            .args(&[req.starknet_address])
            .send_with_account(&account)
            .await?;

        wait_for_tx_confirmation(tx.transaction_hash).await?;
    }

    // 5. Create open note
    let open_note_tx = privacy_pool_contract
        .method("create_open_note")
        .args(&[req.btc_amount_sats, /* ...TBD params */])
        .send_with_account(&account)
        .await?;

    wait_for_tx_confirmation(open_note_tx.transaction_hash).await?;

    // 6. Extract open_note_id from transaction receipt/events
    let open_note_id = extract_note_id_from_receipt(&open_note_tx).await?;

    // 7. Submit PSBT + note_id to Atomiq
    let atomiq_response = atomiq_client
        .submit_psbt_with_hook(SubmitPSBTRequest {
            psbt: req.psbt,
            hook_data: HookData {
                open_note_id,
            },
        })
        .await?;

    log::info!("PSBT submitted to Atomiq: {:?}", atomiq_response);

    Ok(())
}
```

**Configuration:**
```bash
STARKNET_RPC_URL=https://starknet-mainnet.infura.io/v3/...
PRIVACY_POOL_CONTRACT=0x...
HOOK_CONTRACT=0x...
ATOMIQ_API_URL=https://api.atomiq.exchange
ATOMIQ_API_KEY=...
```

**Dependencies:**
- `starknet-rs` - Starknet account and contract interaction
- `tokio` - Async runtime
- `axum` - HTTP server
- `serde` / `serde_json` - Serialization
- `reqwest` - HTTP client for Atomiq API
- `base64` - PSBT decoding/encoding
- `anyhow` - Error handling

### Hook Contract (Cairo)

**Contract Name:** `BridgePrivacyHook`

**Storage:**
```cairo
#[storage]
struct Storage {
    atomiq_bridge: ContractAddress,    // Whitelisted caller
    privacy_pool: ContractAddress,      // Target privacy pool
    strk_btc_token: ContractAddress,    // Token contract
}
```

**Main Function:**
```cairo
#[external(v0)]
fn receive_bridge_tokens(
    ref self: ContractState,
    recipient: ContractAddress,
    amount: u256,
    open_note_id: felt252
) {
    // 1. Verify caller is Atomiq bridge
    let caller = get_caller_address();
    assert(caller == self.atomiq_bridge.read(), 'Unauthorized caller');

    // 2. Receive strkBTC tokens (already transferred by bridge)
    // Tokens are already in this contract's balance

    // 3. Approve privacy pool to spend tokens
    let token = IERC20Dispatcher { contract_address: self.strk_btc_token.read() };
    token.approve(self.privacy_pool.read(), amount);

    // 4. Deposit to open note in privacy pool
    let pool = IPrivacyPoolDispatcher { contract_address: self.privacy_pool.read() };
    pool.deposit_to_note(open_note_id, amount);

    // 5. Emit event
    self.emit(TokensDepositedToPrivacyPool {
        recipient,
        amount,
        open_note_id,
        timestamp: get_block_timestamp()
    });
}
```

**Events:**
```cairo
#[derive(Drop, starknet::Event)]
struct TokensDepositedToPrivacyPool {
    recipient: ContractAddress,
    amount: u256,
    open_note_id: felt252,
    timestamp: u64
}
```

**Admin Functions:**
```cairo
#[external(v0)]
fn update_atomiq_bridge(ref self: ContractState, new_bridge: ContractAddress) {
    self.ownable.assert_only_owner();
    self.atomiq_bridge.write(new_bridge);
}

#[external(v0)]
fn update_privacy_pool(ref self: ContractState, new_pool: ContractAddress) {
    self.ownable.assert_only_owner();
    self.privacy_pool.write(new_pool);
}
```

### Starknet Wallet API (To Be Implemented by Wallet Team)

**Function:** `sendPSBTToBackend`

**Interface:**
```typescript
interface SendPSBTToBackendParams {
  psbt: string;              // base64 encoded
  backendEndpoint: string;   // URL
  btcAmount: number;         // satoshis
}

wallet.sendPSBTToBackend(params): Promise<{status: 'accepted', request_id: string}>
```

**Wallet Behavior:**
1. Extract user's private key from wallet storage
2. POST to backend endpoint with PSBT + private key + metadata
3. Return immediate acknowledgment to dapp

### Atomiq API (To Be Extended by Atomiq Team)

**New Endpoint:** `POST /psbt/create-with-hook`

**Request:**
```json
{
  "btc_address": "bc1q...",
  "amount_sats": 100000,
  "starknet_recipient": "0x...",
  "hook_contract": "0x..."
}
```

**Response:** Unsigned PSBT (base64 encoded)

**New Endpoint:** `POST /psbt/submit-with-hook`

**Request:**
```json
{
  "psbt": "base64_partially_signed",
  "hook_data": {
    "open_note_id": "0x..."
  }
}
```

**Atomiq's Backend Behavior:**
1. Store mapping: `sha256(psbt) → open_note_id`
2. Sign and broadcast Bitcoin transaction
3. When deposit confirms, retrieve `open_note_id` from storage
4. Call hook contract with stored `note_id`

### Privacy Pool Interface (Expected)

**Note:** Interface defined by privacy pool team. Expected methods:

```cairo
#[starknet::interface]
trait IPrivacyPool<TContractState> {
    fn is_registered(self: @TContractState, user: ContractAddress) -> bool;
    fn register_user(ref self: TContractState, user: ContractAddress);
    fn create_open_note(ref self: TContractState, amount: u256 /* ...TBD params */) -> felt252;
    fn deposit_to_note(ref self: TContractState, note_id: felt252, amount: u256);
}
```

---

## Data Flow & Timing

### Critical Insight

**PSBT doesn't contain open_note_id.** Atomiq's backend stores the association and injects it when calling the hook contract.

### Timing Sequence
```
T0: User initiates bridge in dapp
T1: Dapp requests PSBT from Atomiq (without note_id)
T2: Atomiq returns unsigned PSBT
T3: User signs PSBT with BTC wallet
T4: Dapp sends signed PSBT to Starknet wallet
T5: Wallet sends PSBT + private key to backend
T6: Backend creates open note → receives note_id
T7: Backend submits PSBT + note_id to Atomiq
T8: Atomiq stores mapping: psbt_hash → note_id
T9: Atomiq signs and broadcasts Bitcoin tx
T10: Bitcoin tx confirms (~1 hour)
T11: Atomiq retrieves note_id from storage
T12: Atomiq mints and calls hook_contract.receive_bridge_tokens(recipient, amount, note_id)
T13: Hook deposits to privacy pool using note_id
```

---

## Integration Points & Open Items

### What We're Building (In Scope)

**Components to Implement:**
1. **Backend Service** (Rust)
   - Single endpoint: `/execute-bridge-hook`
   - Stateless, queries privacy pool contracts
   - Handles registration + open note creation
   - Submits PSBT to Atomiq

2. **Hook Contract** (Cairo)
   - Receives tokens from Atomiq bridge
   - Deposits to privacy pool using note_id
   - Simple, focused responsibility

### External Dependencies (Not In Scope)

**Atomiq API Extensions:**
- `POST /psbt/create-with-hook` - Generate PSBT with hook contract address
- `POST /psbt/submit-with-hook` - Accept PSBT + hook_data (open_note_id)
- Backend storage for `psbt_hash → open_note_id` mapping
- Inject note_id when calling hook contract

**Starknet Wallet API:**
- `wallet.sendPSBTToBackend(params)` - New function in wallet connection API
- Extract user's private key and POST to backend
- Return immediate acknowledgment

**Privacy Pool Contracts:**
- Interface implementation (by privacy pool team)
- Contract addresses (testnet/mainnet)

### Open Items / TBD

**From Privacy Pool Team:**
1. `create_open_note()` full parameter list (beyond amount)
2. Note commitment/nullifier generation (backend or contract?)
3. Privacy pool contract addresses (testnet/mainnet)
4. Event schema for extracting note_id from transaction receipt

**From Atomiq Team:**
1. Hook contract address encoding mechanism
2. API authentication for backend (API keys? OAuth?)
3. Storage mechanism for note_id mapping
4. Hook contract calling convention (parameters, gas limits)

**From Wallet Team:**
1. `sendPSBTToBackend` API signature finalization
2. Security review of private key transmission
3. User consent flow for sending key to backend

### Dapp Flow (Deferred to Separate Phase)

**Not detailed in this design:**
- Web UI design
- Wallet connection UX
- Status tracking / progress indicators
- Error handling UI
- User notifications

**High-level dapp responsibilities:**
1. Connect BTC + Starknet wallets
2. Call Atomiq API to get PSBT
3. Get BTC wallet signature
4. Trigger Starknet wallet's `sendPSBTToBackend` function

---

## Security Considerations

### Private Key Handling

**POC Phase Approach:**
- User's Starknet private key transmitted to backend via HTTPS
- Backend uses key to sign transactions, then discards it
- Backend does not persist private keys

**Risks:**
- Backend compromise = user funds at risk
- Network interception possible (HTTPS mitigates)
- Insider threat from backend operator

**Mitigation (POC Phase):**
- HTTPS only (TLS 1.3)
- Backend runs in secure environment (cloud VM with disk encryption)
- Audit logging of all private key usage
- Clear user warnings in UI

**Future Migration Path:**
- Account abstraction with session keys
- User pre-authorizes specific operations (register, create note)
- Backend never sees private key

### Hook Contract Security

**Risks:**
- Unauthorized caller mints tokens to hook but doesn't deposit
- Privacy pool contract has vulnerability
- Note_id collision or manipulation

**Mitigations:**
- Whitelist check: only Atomiq bridge can call
- Atomic execution: approve + deposit in single transaction
- Privacy pool assumed secure (external audit responsibility)
- Open note IDs generated by privacy pool (trusted source)

---

## Future Enhancements

### Account Abstraction Migration

**Goal:** Eliminate private key transmission to backend

**Approach:**
- User account supports session keys with limited permissions
- Backend receives session key (not full private key)
- Session key can only call: `register_user`, `create_open_note`
- Session key expires after use or time limit

**Benefits:**
- User's main private key never leaves wallet
- Backend compromise doesn't expose full account control
- Better security model for production

### Status Tracking & Notifications

**User Visibility:**
- Backend webhook to notify dapp when processing complete
- Dapp polls backend endpoint for status updates
- On-chain events tracked by dapp for final confirmation

**Status States:**
1. PSBT accepted by backend
2. User registered in privacy pool
3. Open note created
4. PSBT submitted to Atomiq
5. Bitcoin tx broadcast
6. Bitcoin tx confirmed
7. Tokens minted and deposited

### Failure Handling (Future Design)

**Deferred to separate design phase:**
- Backend retries registration/note creation on failure
- Fallback mechanism if privacy pool unavailable
- Refund mechanism if Bitcoin tx confirms but hook fails
- User-initiated recovery flows

---

## Success Criteria

### POC Milestone

✅ User can bridge BTC through Atomiq with privacy pool integration
✅ Backend successfully registers users and creates open notes
✅ Hook contract receives tokens and deposits to privacy pool
✅ End-to-end flow completes without manual intervention
✅ Integration with external dependencies clearly defined

### Production Readiness (Future)

- Account abstraction implemented (no private key transmission)
- Comprehensive error handling and recovery flows
- Status tracking and user notifications
- Security audit of backend and hook contract
- Monitoring and alerting infrastructure
- User documentation and support

---

## Implementation Phases

**Phase 1: Hook Contract**
1. Implement `BridgePrivacyHook` contract
2. Add admin functions and events
3. Deploy to testnet
4. Integration testing with mock privacy pool

**Phase 2: Backend Service**
1. Set up Rust project structure
2. Implement `/execute-bridge-hook` endpoint
3. Add Starknet account management
4. Implement privacy pool interactions
5. Add Atomiq API client
6. Deploy to staging environment

**Phase 3: Integration Testing**
1. Test with real privacy pool contracts (testnet)
2. Coordinate with Atomiq team for API testing
3. Test with wallet team for API integration
4. End-to-end flow testing

**Phase 4: Dapp Integration**
1. Design dapp flow (separate phase)
2. Implement wallet connections
3. Integrate with backend endpoint
4. User testing and feedback

---

## Appendix: Assumptions

These assumptions underpin the design and must be validated:

1. **Privacy pool supports creating unfunded open notes** - notes can exist before tokens deposited
2. **Atomiq can store arbitrary metadata per PSBT** - needed for note_id mapping
3. **Starknet wallet willing to expose private key transmission API** - critical for POC approach
4. **Privacy pool interface is stable** - changes require hook contract updates
5. **Backend can extract note_id from transaction receipts** - event schema must support this
6. **Atomiq bridge contract allows hook contracts** - architecture supports this pattern
7. **Privacy pool accepts deposits from hook contracts** - no caller restrictions beyond token approval
