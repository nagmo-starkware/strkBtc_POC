# BTC Bridge - Cairo Smart Contracts

This directory contains the Starknet smart contracts for the Bitcoin bridge POC.

## Architecture

The bridge consists of three main contracts:

### 1. StrkBTC Token (`src/token.cairo`)
- **Purpose**: ERC-20 token representing bridged Bitcoin on Starknet
- **Features**:
  - Standard ERC-20 functionality (OpenZeppelin implementation)
  - Mint/burn capabilities restricted to bridge contract
  - Ownable for administrative control
  - 8 decimals to match Bitcoin
- **Key Functions**:
  - `mint(recipient, amount)`: Mint new tokens (bridge only)
  - `burn(from, amount)`: Burn tokens (bridge only)
  - `set_bridge_address(new_bridge)`: Update bridge contract (owner only)

### 2. Bridge Core (`src/bridge_core.cairo`)
- **Purpose**: Main bridge logic for deposits and withdrawals
- **Features**:
  - Committee-based multi-sig verification
  - Configurable signature threshold
  - Whitelisted BTC and Starknet addresses
  - Minimum withdrawal limits
  - Replay protection for deposit transactions
- **Key Functions**:
  - `deposit_request(btc_tx_hash, starknet_address, amount)`: Process BTC deposits
  - `withdraw(btc_address, amount)`: Initiate BTC withdrawal
  - `add_committee_member(member)`: Add committee signer
  - `update_threshold(new_threshold)`: Update signature requirement
  - `add_btc_whitelist(btc_address)`: Whitelist BTC address
  - `add_starknet_whitelist(starknet_address)`: Whitelist Starknet address

### 3. Bridge Registry (`src/bridge_registry.cairo`)
- **Purpose**: Store and track Partially Signed Bitcoin Transactions (PSBTs)
- **Features**:
  - Committee member signature collection
  - PSBT data storage and retrieval
  - Signature count tracking
  - Duplicate signature prevention
- **Key Functions**:
  - `submit_psbt(tx_hash, psbt_data)`: Submit PSBT with signature
  - `get_psbt(tx_hash)`: Retrieve PSBT data
  - `get_signature_count(tx_hash)`: Check signature count
  - `has_signed(tx_hash, signer)`: Check if address has signed

## Development Setup

### Prerequisites

1. **Install Scarb** (Cairo package manager):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh
   ```
   Version: 2.8.5 or later

2. **Install Starknet Foundry** (testing framework):
   ```bash
   curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
   snfoundryup
   ```
   Version: 0.56.0 or later

3. **Verify installations**:
   ```bash
   scarb --version
   snforge --version
   ```

### Project Structure

```
contracts/
├── Scarb.toml              # Package manifest and dependencies
├── Scarb.lock              # Dependency lockfile
├── src/
│   ├── lib.cairo           # Main library entry point
│   ├── token.cairo         # StrkBTC ERC-20 token
│   ├── bridge_core.cairo   # Core bridge logic
│   ├── bridge_registry.cairo  # PSBT registry
│   └── tests/
│       ├── test_token.cairo       # Token contract tests
│       └── test_bridge_core.cairo # Bridge core tests
├── target/                 # Build artifacts (generated)
└── README.md              # This file
```

## Building

Compile all contracts:

```bash
cd contracts
scarb build
```

This generates:
- Sierra code: `target/dev/*.contract_class.json`
- CASM code: `target/dev/*.compiled_contract_class.json`

## Testing

Run all tests:

```bash
cd contracts
snforge test
```

Run specific test:

```bash
snforge test test_deposit_request
```

Run tests with detailed output:

```bash
snforge test --trace-verbosity detailed
```

Run tests and show gas usage:

```bash
snforge test --gas-usage
```

### Test Coverage

Current test files:
- `test_token.cairo`: Token mint/burn, access control, ERC-20 compliance
- `test_bridge_core.cairo`: Deposits, withdrawals, committee management, whitelisting

## Deployment

### Manual Deployment (Testnet)

1. **Set up Starknet CLI** (if not already installed):
   ```bash
   pip install starknet-py
   ```

2. **Configure environment variables**:
   ```bash
   export STARKNET_RPC=<your-rpc-url>
   export STARKNET_ACCOUNT=<your-account-address>
   export STARKNET_KEYSTORE=<path-to-keystore>
   ```

3. **Build contracts**:
   ```bash
   cd contracts
   scarb build
   ```

4. **Deploy StrkBTC Token**:
   ```bash
   starkli declare target/dev/btc_bridge_StrkBTC.contract_class.json \
     --account $STARKNET_ACCOUNT \
     --keystore $STARKNET_KEYSTORE

   # Deploy with constructor args: owner, bridge (use zero for now)
   starkli deploy <class-hash> \
     <owner-address> \
     0x0 \
     --account $STARKNET_ACCOUNT \
     --keystore $STARKNET_KEYSTORE
   ```

5. **Deploy Bridge Core**:
   ```bash
   starkli declare target/dev/btc_bridge_BridgeCore.contract_class.json \
     --account $STARKNET_ACCOUNT \
     --keystore $STARKNET_KEYSTORE

   # Deploy with constructor args: owner, token_address, initial_threshold
   starkli deploy <class-hash> \
     <owner-address> \
     <token-address> \
     2 \
     --account $STARKNET_ACCOUNT \
     --keystore $STARKNET_KEYSTORE
   ```

6. **Deploy Bridge Registry**:
   ```bash
   starkli declare target/dev/btc_bridge_BridgeRegistry.contract_class.json \
     --account $STARKNET_ACCOUNT \
     --keystore $STARKNET_KEYSTORE

   # Deploy with constructor arg: bridge_core_address
   starkli deploy <class-hash> \
     <bridge-core-address> \
     --account $STARKNET_ACCOUNT \
     --keystore $STARKNET_KEYSTORE
   ```

7. **Link Token to Bridge**:
   ```bash
   starkli invoke <token-address> set_bridge_address <bridge-core-address> \
     --account $STARKNET_ACCOUNT \
     --keystore $STARKNET_KEYSTORE
   ```

### Automated Deployment Script

See `scripts/deploy.sh` for a deployment script template.

## Configuration

### Initial Setup After Deployment

1. **Add Committee Members** (minimum 2 for threshold of 2):
   ```bash
   starkli invoke <bridge-core-address> add_committee_member <member1-address>
   starkli invoke <bridge-core-address> add_committee_member <member2-address>
   ```

2. **Whitelist BTC Addresses**:
   ```bash
   # BTC addresses are stored as felt252 (hash of address)
   starkli invoke <bridge-core-address> add_btc_whitelist <btc-address-felt>
   ```

3. **Whitelist Starknet Addresses**:
   ```bash
   starkli invoke <bridge-core-address> add_starknet_whitelist <starknet-address>
   ```

4. **Set Minimum Withdrawal** (optional, default is 0):
   ```bash
   # Amount in smallest unit (satoshis), as u256
   starkli invoke <bridge-core-address> update_minimum_withdrawal 100000
   ```

### Example Configuration

For a testnet deployment with 3 committee members and 2-of-3 threshold:

```bash
# Committee
MEMBER_1=0x1234...
MEMBER_2=0x5678...
MEMBER_3=0x9abc...

starkli invoke $BRIDGE_CORE add_committee_member $MEMBER_1
starkli invoke $BRIDGE_CORE add_committee_member $MEMBER_2
starkli invoke $BRIDGE_CORE add_committee_member $MEMBER_3
starkli invoke $BRIDGE_CORE update_threshold 2

# Whitelisting
BTC_ADDR=0xdef0...  # Hash of Bitcoin address
STARK_USER=0x4567...

starkli invoke $BRIDGE_CORE add_btc_whitelist $BTC_ADDR
starkli invoke $BRIDGE_CORE add_starknet_whitelist $STARK_USER

# Set minimum withdrawal to 0.001 BTC (100,000 satoshis)
starkli invoke $BRIDGE_CORE update_minimum_withdrawal 100000
```

## Usage Flows

### Deposit Flow (BTC → Starknet)

1. User sends BTC to bridge wallet
2. Committee members monitor Bitcoin blockchain
3. Once confirmed, committee member calls `deposit_request`:
   ```cairo
   bridge_core.deposit_request(
       btc_tx_hash: felt252,          // Bitcoin transaction hash
       starknet_address: ContractAddress,  // Recipient on Starknet
       amount: u256                    // Amount in satoshis
   )
   ```
4. Each committee member calls `deposit_request` with same params
5. When threshold is reached, tokens are minted to recipient

### Withdrawal Flow (Starknet → BTC)

1. User calls `withdraw` on bridge core:
   ```cairo
   bridge_core.withdraw(
       btc_address: felt252,  // Destination Bitcoin address
       amount: u256           // Amount in satoshis
   )
   ```
2. Bridge burns user's strkBTC tokens
3. Off-chain service creates PSBT for withdrawal
4. Committee members review and call `submit_psbt`:
   ```cairo
   bridge_registry.submit_psbt(
       tx_hash: felt252,
       psbt_data: Span<felt252>
   )
   ```
5. When threshold is reached, PSBT is fully signed
6. Off-chain service broadcasts final Bitcoin transaction

## Security Considerations

1. **Committee Security**:
   - Committee members must securely manage their Starknet private keys
   - Recommend hardware wallet or secure key management solution
   - Use different keys for testnet and mainnet

2. **Whitelisting**:
   - Initially enabled for controlled testing
   - Can be disabled by removing whitelist checks (future upgrade)
   - Whitelist BTC addresses carefully (verify ownership)

3. **Minimum Withdrawal**:
   - Prevents dust attacks and uneconomical withdrawals
   - Should cover Bitcoin network fees + margin

4. **Replay Protection**:
   - Each Bitcoin transaction can only be deposited once
   - Tracked via `btc_tx_hash` mapping

5. **Access Control**:
   - Owner can update committee and thresholds
   - Bridge contract can mint/burn tokens
   - Use multi-sig wallet for owner in production

## Troubleshooting

### Build Issues

**Error: `scarb: command not found`**
- Install Scarb following setup instructions above
- Ensure Scarb is in your PATH

**Error: `unknown edition '2024_07'`**
- Update Scarb to version 2.8.5 or later

### Test Issues

**Error: `snforge: command not found`**
- Install Starknet Foundry following setup instructions
- Run `snfoundryup` to update to latest version

**Test failures**:
- Check that all dependencies are installed: `scarb fetch`
- Rebuild: `scarb build`
- Run with detailed output: `snforge test --trace-verbosity detailed`

### Deployment Issues

**Error: `Account not found`**
- Verify `STARKNET_ACCOUNT` and `STARKNET_KEYSTORE` are set correctly
- Ensure account is deployed and funded on target network

**Error: `Class hash already declared`**
- Use the existing class hash for deployment
- Or modify contract code if you need a new declaration

## Resources

- [Cairo Documentation](https://book.cairo-lang.org/)
- [Starknet Book](https://book.starknet.io/)
- [Scarb Documentation](https://docs.swmansion.com/scarb/)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/)
- [OpenZeppelin Cairo Contracts](https://github.com/OpenZeppelin/cairo-contracts)

## License

[License information to be added]

## Contact

[Contact information to be added]
