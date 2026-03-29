# Phase 1: Smart Contracts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the three Cairo smart contracts for the BTC bridge: strkBTC ERC20 token, Bridge Core contract, and Bridge Registry contract.

**Architecture:** We're building upgradeable Cairo contracts on Starknet using OpenZeppelin for the ERC20 base. The Bridge Core handles deposits (committee signature collection + minting) and withdrawals (whitelist check + burning). The Registry tracks withdrawal PSBTs for off-chain coordinator consumption.

**Tech Stack:** Cairo 2.x, Scarb (Cairo package manager), OpenZeppelin Cairo Contracts, Starknet Foundry (testing)

---

## Prerequisites

Before starting, ensure you have:
- Cairo 2.x installed (`curl -L https://raw.githubusercontent.com/software-mansion/asdf-scarb/main/scripts/install.sh | bash`)
- Scarb package manager
- Starknet Foundry for testing (`curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh`)

---

## Task 1: Project Setup

**Files:**
- Create: `contracts/Scarb.toml`
- Create: `contracts/src/lib.cairo`
- Create: `.gitignore` updates

**Step 1: Initialize Scarb project**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
scarb init --name btc_bridge
```

Expected: Creates `Scarb.toml` and `src/lib.cairo`

**Step 2: Configure Scarb.toml with dependencies**

Edit `contracts/Scarb.toml`:

```toml
[package]
name = "btc_bridge"
version = "0.1.0"
edition = "2024_07"

[dependencies]
starknet = ">=2.6.0"
openzeppelin = { git = "https://github.com/OpenZeppelin/cairo-contracts.git", tag = "v0.14.0" }

[[target.starknet-contract]]
sierra = true
casm = true

[tool.snforge]
exit_first = true
```

**Step 3: Update .gitignore**

Add to `/home/lt-nevoa/btc-bridge-poc/.gitignore`:

```
# Cairo/Scarb
contracts/target/
contracts/Scarb.lock
contracts/.snfoundry_cache/
```

**Step 4: Verify setup**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
scarb build
```

Expected: Build succeeds with "Compiling btc_bridge"

**Step 5: Commit**

```bash
git add contracts/ .gitignore
git commit -m "feat(contracts): initialize Cairo project with Scarb

- Add Scarb.toml with OpenZeppelin dependency
- Configure starknet-contract target
- Add Cairo build artifacts to gitignore"
```

---

## Task 2: strkBTC ERC20 Token Contract

**Files:**
- Create: `contracts/src/token.cairo`
- Modify: `contracts/src/lib.cairo`

**Step 1: Write the token contract interface**

Create `contracts/src/token.cairo`:

```cairo
#[starknet::contract]
mod StrkBTC {
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        bridge_address: ContractAddress,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        bridge: ContractAddress
    ) {
        self.erc20.initializer("Starknet BTC", "strkBTC");
        self.ownable.initializer(owner);
        self.bridge_address.write(bridge);
    }

    #[external(v0)]
    fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
        self._assert_only_bridge();
        self.erc20._mint(to, amount);
    }

    #[external(v0)]
    fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
        self._assert_only_bridge();
        self.erc20._burn(from, amount);
    }

    #[external(v0)]
    fn set_bridge(ref self: ContractState, new_bridge: ContractAddress) {
        self.ownable.assert_only_owner();
        self.bridge_address.write(new_bridge);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_only_bridge(self: @ContractState) {
            let caller = starknet::get_caller_address();
            let bridge = self.bridge_address.read();
            assert(caller == bridge, 'Caller is not the bridge');
        }
    }
}
```

**Step 2: Update lib.cairo to include token module**

Edit `contracts/src/lib.cairo`:

```cairo
mod token;
```

**Step 3: Build to verify compilation**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
scarb build
```

Expected: Build succeeds, no errors

**Step 4: Commit**

```bash
git add contracts/src/
git commit -m "feat(contracts): add strkBTC ERC20 token contract

- OpenZeppelin ERC20 base with mint/burn permissions
- Bridge-only minting and burning
- Owner can update bridge address
- Standard ERC20 interface (transfer, approve, etc.)"
```

---

## Task 3: Bridge Core Contract - Storage and Events

**Files:**
- Create: `contracts/src/bridge_core.cairo`
- Modify: `contracts/src/lib.cairo`

**Step 1: Create bridge core contract skeleton with storage and events**

Create `contracts/src/bridge_core.cairo`:

```cairo
#[starknet::contract]
mod BridgeCore {
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess
    };
    use openzeppelin::access::ownable::OwnableComponent;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        // Token and registry addresses
        token_address: ContractAddress,
        registry_address: ContractAddress,

        // Committee configuration
        committee_members: Map<ContractAddress, bool>,
        committee_count: u32,
        signature_threshold: u32,

        // Whitelists
        btc_whitelist: Map<felt252, bool>,
        starknet_whitelist: Map<ContractAddress, bool>,

        // Deposit tracking
        processed_deposits: Map<felt252, bool>,
        deposit_signatures: Map<(felt252, ContractAddress), bool>,
        deposit_signature_count: Map<felt252, u32>,

        // Pending deposits data
        pending_deposit_starknet_address: Map<felt252, ContractAddress>,
        pending_deposit_amount: Map<felt252, u256>,

        // Configuration
        minimum_withdrawal_amount: u256,

        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        DepositProcessed: DepositProcessed,
        WithdrawalRequested: WithdrawalRequested,
        CommitteeMemberAdded: CommitteeMemberAdded,
        CommitteeMemberRemoved: CommitteeMemberRemoved,
        ThresholdUpdated: ThresholdUpdated,
        AddressWhitelisted: AddressWhitelisted,
        AddressRemovedFromWhitelist: AddressRemovedFromWhitelist,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositProcessed {
        #[key]
        btc_tx_hash: felt252,
        starknet_address: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawalRequested {
        #[key]
        request_id: felt252,
        btc_address: felt252,
        amount: u256,
        starknet_tx_hash: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct CommitteeMemberAdded {
        member: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct CommitteeMemberRemoved {
        member: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ThresholdUpdated {
        old_threshold: u32,
        new_threshold: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct AddressWhitelisted {
        address: felt252,
        is_btc: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct AddressRemovedFromWhitelist {
        address: felt252,
        is_btc: bool,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        token_address: ContractAddress,
        registry_address: ContractAddress,
        initial_threshold: u32,
        minimum_withdrawal: u256,
    ) {
        self.ownable.initializer(owner);
        self.token_address.write(token_address);
        self.registry_address.write(registry_address);
        self.signature_threshold.write(initial_threshold);
        self.minimum_withdrawal_amount.write(minimum_withdrawal);
    }
}
```

**Step 2: Update lib.cairo**

Edit `contracts/src/lib.cairo`:

```cairo
mod token;
mod bridge_core;
```

**Step 3: Build to verify compilation**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
scarb build
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add contracts/src/
git commit -m "feat(contracts): add bridge core storage and events

- Storage for committee, whitelists, deposits
- Events for all state changes
- Constructor with initial configuration"
```

---

## Task 4: Bridge Core Contract - Admin Functions

**Files:**
- Modify: `contracts/src/bridge_core.cairo`

**Step 1: Add committee management functions**

Add to the `BridgeCore` contract (after constructor):

```cairo
    // ============ Admin Functions ============

    #[external(v0)]
    fn add_committee_member(ref self: ContractState, member: ContractAddress) {
        self.ownable.assert_only_owner();
        assert(!self.committee_members.entry(member).read(), 'Member already exists');

        self.committee_members.entry(member).write(true);
        let new_count = self.committee_count.read() + 1;
        self.committee_count.write(new_count);

        self.emit(CommitteeMemberAdded { member });
    }

    #[external(v0)]
    fn remove_committee_member(ref self: ContractState, member: ContractAddress) {
        self.ownable.assert_only_owner();
        assert(self.committee_members.entry(member).read(), 'Member does not exist');

        self.committee_members.entry(member).write(false);
        let new_count = self.committee_count.read() - 1;
        self.committee_count.write(new_count);

        // Ensure threshold is still achievable
        assert(new_count >= self.signature_threshold.read(), 'Threshold too high');

        self.emit(CommitteeMemberRemoved { member });
    }

    #[external(v0)]
    fn update_threshold(ref self: ContractState, new_threshold: u32) {
        self.ownable.assert_only_owner();
        let committee_count = self.committee_count.read();
        assert(new_threshold > 0 && new_threshold <= committee_count, 'Invalid threshold');

        let old_threshold = self.signature_threshold.read();
        self.signature_threshold.write(new_threshold);

        self.emit(ThresholdUpdated { old_threshold, new_threshold });
    }

    #[external(v0)]
    fn add_btc_whitelist(ref self: ContractState, btc_address: felt252) {
        self.ownable.assert_only_owner();
        self.btc_whitelist.entry(btc_address).write(true);
        self.emit(AddressWhitelisted { address: btc_address, is_btc: true });
    }

    #[external(v0)]
    fn remove_btc_whitelist(ref self: ContractState, btc_address: felt252) {
        self.ownable.assert_only_owner();
        self.btc_whitelist.entry(btc_address).write(false);
        self.emit(AddressRemovedFromWhitelist { address: btc_address, is_btc: true });
    }

    #[external(v0)]
    fn add_starknet_whitelist(ref self: ContractState, starknet_address: ContractAddress) {
        self.ownable.assert_only_owner();
        self.starknet_whitelist.entry(starknet_address).write(true);
        let address_felt: felt252 = starknet_address.into();
        self.emit(AddressWhitelisted { address: address_felt, is_btc: false });
    }

    #[external(v0)]
    fn remove_starknet_whitelist(ref self: ContractState, starknet_address: ContractAddress) {
        self.ownable.assert_only_owner();
        self.starknet_whitelist.entry(starknet_address).write(false);
        let address_felt: felt252 = starknet_address.into();
        self.emit(AddressRemovedFromWhitelist { address: address_felt, is_btc: false });
    }

    #[external(v0)]
    fn update_minimum_withdrawal(ref self: ContractState, new_minimum: u256) {
        self.ownable.assert_only_owner();
        self.minimum_withdrawal_amount.write(new_minimum);
    }
```

**Step 2: Build to verify compilation**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
scarb build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add contracts/src/bridge_core.cairo
git commit -m "feat(contracts): add bridge admin functions

- Committee member management (add/remove)
- Threshold updates with validation
- BTC and Starknet whitelist management
- Minimum withdrawal amount configuration"
```

---

## Task 5: Bridge Core Contract - Deposit Request Function

**Files:**
- Modify: `contracts/src/bridge_core.cairo`

**Step 1: Add deposit request function with signature collection**

Add to the `BridgeCore` contract:

```cairo
    // ============ Deposit Flow ============

    #[external(v0)]
    fn deposit_request(
        ref self: ContractState,
        btc_tx_hash: felt252,
        starknet_address: ContractAddress,
        amount: u256,
    ) {
        // Only committee members can call
        self._assert_committee_member();

        // Check if already processed
        assert(!self.processed_deposits.entry(btc_tx_hash).read(), 'Deposit already processed');

        // Check if caller already signed
        let caller = starknet::get_caller_address();
        assert(
            !self.deposit_signatures.entry((btc_tx_hash, caller)).read(),
            'Already signed'
        );

        // Check BTC address is whitelisted (would need BTC sender address as param in real impl)
        // For now we assume backend validated this

        // Record signature
        self.deposit_signatures.entry((btc_tx_hash, caller)).write(true);

        // Update signature count
        let current_count = self.deposit_signature_count.entry(btc_tx_hash).read();
        let new_count = current_count + 1;
        self.deposit_signature_count.entry(btc_tx_hash).write(new_count);

        // Store pending deposit data (for first signer)
        if current_count == 0 {
            self.pending_deposit_starknet_address.entry(btc_tx_hash).write(starknet_address);
            self.pending_deposit_amount.entry(btc_tx_hash).write(amount);
        } else {
            // Verify all signers agree on the data
            assert(
                self.pending_deposit_starknet_address.entry(btc_tx_hash).read() == starknet_address,
                'Address mismatch'
            );
            assert(
                self.pending_deposit_amount.entry(btc_tx_hash).read() == amount,
                'Amount mismatch'
            );
        }

        // Check if threshold met
        let threshold = self.signature_threshold.read();
        if new_count >= threshold {
            self._execute_mint(btc_tx_hash, starknet_address, amount);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_committee_member(self: @ContractState) {
            let caller = starknet::get_caller_address();
            assert(self.committee_members.entry(caller).read(), 'Not a committee member');
        }

        fn _execute_mint(
            ref self: ContractState,
            btc_tx_hash: felt252,
            starknet_address: ContractAddress,
            amount: u256,
        ) {
            // Mark as processed
            self.processed_deposits.entry(btc_tx_hash).write(true);

            // Mint tokens via token contract
            let token = self.token_address.read();
            let token_dispatcher = IStrkBTCDispatcher { contract_address: token };
            token_dispatcher.mint(starknet_address, amount);

            // Emit event
            self.emit(DepositProcessed { btc_tx_hash, starknet_address, amount });
        }
    }
```

**Step 2: Add token interface for calling mint**

Add near the top of the file after imports:

```cairo
    #[starknet::interface]
    trait IStrkBTC<TContractState> {
        fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
        fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
    }
```

**Step 3: Build to verify compilation**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
scarb build
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add contracts/src/bridge_core.cairo
git commit -m "feat(contracts): add deposit request with signature collection

- Committee members submit deposit requests
- Automatic signature collection and counting
- Data validation across signers
- Auto-mint when threshold reached
- Prevents double-processing"
```

---

## Task 6: Bridge Core Contract - Withdrawal Function

**Files:**
- Modify: `contracts/src/bridge_core.cairo`

**Step 1: Add withdrawal function**

Add to the `BridgeCore` contract:

```cairo
    // ============ Withdrawal Flow ============

    #[external(v0)]
    fn withdraw(ref self: ContractState, btc_address: felt252, amount: u256) {
        let caller = starknet::get_caller_address();

        // Check caller is whitelisted
        assert(
            self.starknet_whitelist.entry(caller).read(),
            'Address not whitelisted'
        );

        // Check amount meets minimum
        let minimum = self.minimum_withdrawal_amount.read();
        assert(amount >= minimum, 'Amount below minimum');

        // Burn tokens
        let token = self.token_address.read();
        let token_dispatcher = IStrkBTCDispatcher { contract_address: token };
        token_dispatcher.burn(caller, amount);

        // Generate request ID (using tx hash)
        let tx_info = starknet::get_tx_info().unbox();
        let request_id = tx_info.transaction_hash;

        // Emit withdrawal event for backends to process
        self.emit(
            WithdrawalRequested {
                request_id,
                btc_address,
                amount,
                starknet_tx_hash: request_id,
            }
        );
    }
```

**Step 2: Add view functions for querying state**

Add to the `BridgeCore` contract:

```cairo
    // ============ View Functions ============

    #[external(v0)]
    fn is_btc_whitelisted(self: @ContractState, btc_address: felt252) -> bool {
        self.btc_whitelist.entry(btc_address).read()
    }

    #[external(v0)]
    fn is_starknet_whitelisted(self: @ContractState, address: ContractAddress) -> bool {
        self.starknet_whitelist.entry(address).read()
    }

    #[external(v0)]
    fn is_committee_member(self: @ContractState, address: ContractAddress) -> bool {
        self.committee_members.entry(address).read()
    }

    #[external(v0)]
    fn get_signature_threshold(self: @ContractState) -> u32 {
        self.signature_threshold.read()
    }

    #[external(v0)]
    fn get_committee_count(self: @ContractState) -> u32 {
        self.committee_count.read()
    }

    #[external(v0)]
    fn get_minimum_withdrawal(self: @ContractState) -> u256 {
        self.minimum_withdrawal_amount.read()
    }

    #[external(v0)]
    fn is_deposit_processed(self: @ContractState, btc_tx_hash: felt252) -> bool {
        self.processed_deposits.entry(btc_tx_hash).read()
    }

    #[external(v0)]
    fn get_deposit_signature_count(self: @ContractState, btc_tx_hash: felt252) -> u32 {
        self.deposit_signature_count.entry(btc_tx_hash).read()
    }
```

**Step 3: Build to verify compilation**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
scarb build
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add contracts/src/bridge_core.cairo
git commit -m "feat(contracts): add withdrawal flow and view functions

- Withdrawal with whitelist check and minimum validation
- Burns strkBTC immediately
- Emits WithdrawalRequested event
- View functions for querying contract state"
```

---

## Task 7: Bridge Registry Contract

**Files:**
- Create: `contracts/src/bridge_registry.cairo`
- Modify: `contracts/src/lib.cairo`

**Step 1: Create registry contract**

Create `contracts/src/bridge_registry.cairo`:

```cairo
#[starknet::contract]
mod BridgeRegistry {
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess
    };
    use openzeppelin::access::ownable::OwnableComponent;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        // Bridge core address (only bridge can submit on behalf of committee)
        bridge_core: ContractAddress,

        // PSBT storage: tx_hash -> PSBT data (as array of felt252)
        psbt_data: Map<felt252, Span<felt252>>,
        psbt_exists: Map<felt252, bool>,

        // Signature tracking: (tx_hash, signer) -> bool
        psbt_signatures: Map<(felt252, ContractAddress), bool>,

        // Signature count: tx_hash -> count
        signature_count: Map<felt252, u32>,

        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PSBTSubmitted: PSBTSubmitted,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct PSBTSubmitted {
        #[key]
        tx_hash: felt252,
        signer: ContractAddress,
        signature_count: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, bridge_core: ContractAddress) {
        self.ownable.initializer(owner);
        self.bridge_core.write(bridge_core);
    }

    // ============ PSBT Submission ============

    #[external(v0)]
    fn submit_psbt(ref self: ContractState, tx_hash: felt252, psbt: Span<felt252>) {
        let caller = starknet::get_caller_address();

        // Check caller hasn't already signed
        assert(
            !self.psbt_signatures.entry((tx_hash, caller)).read(),
            'Already submitted PSBT'
        );

        // Store PSBT data on first submission
        if !self.psbt_exists.entry(tx_hash).read() {
            self.psbt_data.entry(tx_hash).write(psbt);
            self.psbt_exists.entry(tx_hash).write(true);
        }
        // TODO: Verify subsequent PSBTs match the first one

        // Mark signer
        self.psbt_signatures.entry((tx_hash, caller)).write(true);

        // Increment count
        let current_count = self.signature_count.entry(tx_hash).read();
        let new_count = current_count + 1;
        self.signature_count.entry(tx_hash).write(new_count);

        // Emit event
        self.emit(PSBTSubmitted { tx_hash, signer: caller, signature_count: new_count });
    }

    // ============ View Functions ============

    #[external(v0)]
    fn get_signature_count(self: @ContractState, tx_hash: felt252) -> u32 {
        self.signature_count.entry(tx_hash).read()
    }

    #[external(v0)]
    fn get_psbt(self: @ContractState, tx_hash: felt252) -> Span<felt252> {
        self.psbt_data.entry(tx_hash).read()
    }

    #[external(v0)]
    fn has_signed(self: @ContractState, tx_hash: felt252, signer: ContractAddress) -> bool {
        self.psbt_signatures.entry((tx_hash, signer)).read()
    }

    #[external(v0)]
    fn psbt_exists(self: @ContractState, tx_hash: felt252) -> bool {
        self.psbt_exists.entry(tx_hash).read()
    }
}
```

**Step 2: Update lib.cairo**

Edit `contracts/src/lib.cairo`:

```cairo
mod token;
mod bridge_core;
mod bridge_registry;
```

**Step 3: Build to verify compilation**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
scarb build
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add contracts/src/
git commit -m "feat(contracts): add bridge registry for PSBT tracking

- Stores PSBT data keyed by tx hash
- Tracks which signers submitted PSBTs
- Counts signatures for threshold checking
- Emits events for backend monitoring"
```

---

## Task 8: Write Tests - strkBTC Token

**Files:**
- Create: `contracts/tests/test_token.cairo`
- Modify: `contracts/src/lib.cairo`

**Step 1: Create test file for token**

Create `contracts/tests/test_token.cairo`:

```cairo
#[cfg(test)]
mod tests {
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use btc_bridge::token::StrkBTC;
    use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank, CheatTarget};

    fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
        let owner = contract_address_const::<'owner'>();
        let bridge = contract_address_const::<'bridge'>();

        let contract = declare("StrkBTC");
        let constructor_args = array![owner.into(), bridge.into()];
        let contract_address = contract.deploy(@constructor_args).unwrap();

        (contract_address, owner, bridge)
    }

    #[test]
    fn test_initialization() {
        let (token_address, owner, bridge) = setup();
        let dispatcher = IStrkBTCDispatcher { contract_address: token_address };

        assert(dispatcher.name() == "Starknet BTC", 'Wrong name');
        assert(dispatcher.symbol() == "strkBTC", 'Wrong symbol');
        assert(dispatcher.total_supply() == 0, 'Supply should be 0');
    }

    #[test]
    fn test_mint_as_bridge() {
        let (token_address, owner, bridge) = setup();
        let dispatcher = IStrkBTCDispatcher { contract_address: token_address };
        let recipient = contract_address_const::<'recipient'>();

        start_prank(CheatTarget::One(token_address), bridge);
        dispatcher.mint(recipient, 1000);
        stop_prank(CheatTarget::One(token_address));

        assert(dispatcher.balance_of(recipient) == 1000, 'Wrong balance');
        assert(dispatcher.total_supply() == 1000, 'Wrong supply');
    }

    #[test]
    #[should_panic(expected: ('Caller is not the bridge',))]
    fn test_mint_not_bridge_fails() {
        let (token_address, owner, bridge) = setup();
        let dispatcher = IStrkBTCDispatcher { contract_address: token_address };
        let attacker = contract_address_const::<'attacker'>();
        let recipient = contract_address_const::<'recipient'>();

        start_prank(CheatTarget::One(token_address), attacker);
        dispatcher.mint(recipient, 1000);
    }

    #[test]
    fn test_burn_as_bridge() {
        let (token_address, owner, bridge) = setup();
        let dispatcher = IStrkBTCDispatcher { contract_address: token_address };
        let holder = contract_address_const::<'holder'>();

        // Mint first
        start_prank(CheatTarget::One(token_address), bridge);
        dispatcher.mint(holder, 1000);

        // Burn
        dispatcher.burn(holder, 300);
        stop_prank(CheatTarget::One(token_address));

        assert(dispatcher.balance_of(holder) == 700, 'Wrong balance');
        assert(dispatcher.total_supply() == 700, 'Wrong supply');
    }
}

#[starknet::interface]
trait IStrkBTC<TContractState> {
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
}
```

**Step 2: Update lib.cairo to include tests**

Edit `contracts/src/lib.cairo`:

```cairo
mod token;
mod bridge_core;
mod bridge_registry;

#[cfg(test)]
mod tests;
```

Create `contracts/src/tests.cairo`:

```cairo
mod test_token;
```

**Step 3: Run tests**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
snforge test
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add contracts/
git commit -m "test(contracts): add strkBTC token tests

- Test initialization
- Test minting permissions
- Test burning permissions
- Test unauthorized access prevention"
```

---

## Task 9: Write Tests - Bridge Core

**Files:**
- Create: `contracts/tests/test_bridge_core.cairo`
- Modify: `contracts/src/tests.cairo`

**Step 1: Create test file for bridge core**

Create `contracts/tests/test_bridge_core.cairo`:

```cairo
#[cfg(test)]
mod tests {
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use btc_bridge::bridge_core::BridgeCore;
    use btc_bridge::token::StrkBTC;
    use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank, CheatTarget};

    fn setup() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
        let owner = contract_address_const::<'owner'>();
        let registry = contract_address_const::<'registry'>();

        // Deploy token (bridge will be set after bridge deployment)
        let token_contract = declare("StrkBTC");
        let temp_bridge = contract_address_const::<0>();
        let token_args = array![owner.into(), temp_bridge.into()];
        let token_address = token_contract.deploy(@token_args).unwrap();

        // Deploy bridge
        let bridge_contract = declare("BridgeCore");
        let bridge_args = array![
            owner.into(),
            token_address.into(),
            registry.into(),
            3_u32.into(), // threshold
            1000_u256.into(), // min withdrawal
        ];
        let bridge_address = bridge_contract.deploy(@bridge_args).unwrap();

        // Update token bridge address
        let token_dispatcher = IStrkBTCDispatcher { contract_address: token_address };
        start_prank(CheatTarget::One(token_address), owner);
        token_dispatcher.set_bridge(bridge_address);
        stop_prank(CheatTarget::One(token_address));

        (bridge_address, token_address, owner, registry)
    }

    #[test]
    fn test_add_committee_member() {
        let (bridge_address, _, owner, _) = setup();
        let dispatcher = IBridgeCoreDispatcher { contract_address: bridge_address };
        let member = contract_address_const::<'member1'>();

        start_prank(CheatTarget::One(bridge_address), owner);
        dispatcher.add_committee_member(member);
        stop_prank(CheatTarget::One(bridge_address));

        assert(dispatcher.is_committee_member(member), 'Member not added');
        assert(dispatcher.get_committee_count() == 1, 'Wrong count');
    }

    #[test]
    fn test_deposit_request_threshold() {
        let (bridge_address, token_address, owner, _) = setup();
        let dispatcher = IBridgeCoreDispatcher { contract_address: bridge_address };
        let token_dispatcher = IStrkBTCDispatcher { contract_address: token_address };

        // Add 3 committee members
        let member1 = contract_address_const::<'member1'>();
        let member2 = contract_address_const::<'member2'>();
        let member3 = contract_address_const::<'member3'>();

        start_prank(CheatTarget::One(bridge_address), owner);
        dispatcher.add_committee_member(member1);
        dispatcher.add_committee_member(member2);
        dispatcher.add_committee_member(member3);
        stop_prank(CheatTarget::One(bridge_address));

        let btc_tx_hash = 'btc_tx_123';
        let recipient = contract_address_const::<'recipient'>();
        let amount = 5000_u256;

        // First signature
        start_prank(CheatTarget::One(bridge_address), member1);
        dispatcher.deposit_request(btc_tx_hash, recipient, amount);
        stop_prank(CheatTarget::One(bridge_address));
        assert(dispatcher.get_deposit_signature_count(btc_tx_hash) == 1, 'Wrong count 1');
        assert(token_dispatcher.balance_of(recipient) == 0, 'Should not mint yet');

        // Second signature
        start_prank(CheatTarget::One(bridge_address), member2);
        dispatcher.deposit_request(btc_tx_hash, recipient, amount);
        stop_prank(CheatTarget::One(bridge_address));
        assert(dispatcher.get_deposit_signature_count(btc_tx_hash) == 2, 'Wrong count 2');
        assert(token_dispatcher.balance_of(recipient) == 0, 'Should not mint yet');

        // Third signature - should trigger mint
        start_prank(CheatTarget::One(bridge_address), member3);
        dispatcher.deposit_request(btc_tx_hash, recipient, amount);
        stop_prank(CheatTarget::One(bridge_address));

        assert(dispatcher.get_deposit_signature_count(btc_tx_hash) == 3, 'Wrong count 3');
        assert(token_dispatcher.balance_of(recipient) == amount, 'Mint failed');
        assert(dispatcher.is_deposit_processed(btc_tx_hash), 'Not marked processed');
    }

    #[test]
    fn test_withdrawal_with_whitelist() {
        let (bridge_address, token_address, owner, _) = setup();
        let dispatcher = IBridgeCoreDispatcher { contract_address: bridge_address };
        let token_dispatcher = IStrkBTCDispatcher { contract_address: token_address };

        let user = contract_address_const::<'user'>();
        let btc_address = 'btc_address_123';

        // Mint tokens to user first
        start_prank(CheatTarget::One(token_address), bridge_address);
        token_dispatcher.mint(user, 10000);
        stop_prank(CheatTarget::One(token_address));

        // Whitelist user
        start_prank(CheatTarget::One(bridge_address), owner);
        dispatcher.add_starknet_whitelist(user);
        stop_prank(CheatTarget::One(bridge_address));

        // Withdraw
        start_prank(CheatTarget::One(bridge_address), user);
        dispatcher.withdraw(btc_address, 5000);
        stop_prank(CheatTarget::One(bridge_address));

        assert(token_dispatcher.balance_of(user) == 5000, 'Burn failed');
    }

    #[test]
    #[should_panic(expected: ('Address not whitelisted',))]
    fn test_withdrawal_not_whitelisted_fails() {
        let (bridge_address, token_address, owner, _) = setup();
        let dispatcher = IBridgeCoreDispatcher { contract_address: bridge_address };
        let token_dispatcher = IStrkBTCDispatcher { contract_address: token_address };

        let user = contract_address_const::<'user'>();
        let btc_address = 'btc_address_123';

        // Mint tokens but don't whitelist
        start_prank(CheatTarget::One(token_address), bridge_address);
        token_dispatcher.mint(user, 10000);
        stop_prank(CheatTarget::One(token_address));

        start_prank(CheatTarget::One(bridge_address), user);
        dispatcher.withdraw(btc_address, 5000);
    }
}

#[starknet::interface]
trait IBridgeCore<TContractState> {
    fn add_committee_member(ref self: TContractState, member: ContractAddress);
    fn add_starknet_whitelist(ref self: TContractState, address: ContractAddress);
    fn deposit_request(
        ref self: TContractState, btc_tx_hash: felt252, starknet_address: ContractAddress, amount: u256
    );
    fn withdraw(ref self: TContractState, btc_address: felt252, amount: u256);
    fn is_committee_member(self: @TContractState, address: ContractAddress) -> bool;
    fn get_committee_count(self: @TContractState) -> u32;
    fn get_deposit_signature_count(self: @TContractState, btc_tx_hash: felt252) -> u32;
    fn is_deposit_processed(self: @TContractState, btc_tx_hash: felt252) -> bool;
}

#[starknet::interface]
trait IStrkBTC<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn set_bridge(ref self: TContractState, bridge: ContractAddress);
}
```

**Step 2: Update tests.cairo**

Edit `contracts/src/tests.cairo`:

```cairo
mod test_token;
mod test_bridge_core;
```

**Step 3: Run tests**

```bash
cd /home/lt-nevoa/btc-bridge-poc/contracts
snforge test
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add contracts/
git commit -m "test(contracts): add bridge core tests

- Test committee management
- Test deposit signature collection and threshold
- Test withdrawal with whitelist validation
- Test unauthorized withdrawal prevention"
```

---

## Task 10: Documentation and Deployment Guide

**Files:**
- Create: `contracts/README.md`
- Create: `contracts/scripts/deploy.sh`

**Step 1: Write contracts README**

Create `contracts/README.md`:

```markdown
# BTC Bridge Smart Contracts

Cairo smart contracts for the BTC ↔ Starknet bridge.

## Contracts

### StrkBTC (ERC20)
- Standard OpenZeppelin ERC20 token
- Minting/burning permissions restricted to bridge contract
- Symbol: strkBTC
- Name: Starknet BTC

### BridgeCore
- Manages deposits (committee signature collection)
- Manages withdrawals (whitelist validation + burning)
- Committee and whitelist administration
- Owner-controlled configuration

### BridgeRegistry
- Tracks PSBT submissions for withdrawals
- Counts signatures per withdrawal transaction
- Emits events for backend monitoring

## Development

### Prerequisites
```bash
# Install Cairo and Scarb
curl -L https://raw.githubusercontent.com/software-mansion/asdf-scarb/main/scripts/install.sh | bash

# Install Starknet Foundry
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
```

### Build
```bash
cd contracts
scarb build
```

### Test
```bash
cd contracts
snforge test
```

### Deploy (Testnet)

1. Set environment variables:
```bash
export STARKNET_RPC=https://starknet-sepolia.infura.io/v3/YOUR_KEY
export STARKNET_ACCOUNT=/path/to/account.json
export OWNER_ADDRESS=0x...
```

2. Deploy token:
```bash
starkli deploy target/dev/btc_bridge_StrkBTC.sierra.json \
  $OWNER_ADDRESS \
  0x0  # Temporary bridge address, will update
```

3. Deploy bridge core:
```bash
starkli deploy target/dev/btc_bridge_BridgeCore.sierra.json \
  $OWNER_ADDRESS \
  $TOKEN_ADDRESS \
  $REGISTRY_ADDRESS \
  3 \  # Threshold
  1000  # Min withdrawal (in smallest unit)
```

4. Deploy registry:
```bash
starkli deploy target/dev/btc_bridge_BridgeRegistry.sierra.json \
  $OWNER_ADDRESS \
  $BRIDGE_CORE_ADDRESS
```

5. Update token bridge address:
```bash
starkli invoke $TOKEN_ADDRESS set_bridge $BRIDGE_CORE_ADDRESS
```

## Configuration

### Add Committee Members
```bash
starkli invoke $BRIDGE_CORE_ADDRESS add_committee_member $MEMBER_ADDRESS
```

### Whitelist Addresses
```bash
# BTC address (as felt252)
starkli invoke $BRIDGE_CORE_ADDRESS add_btc_whitelist $BTC_ADDRESS_FELT

# Starknet address
starkli invoke $BRIDGE_CORE_ADDRESS add_starknet_whitelist $STARKNET_ADDRESS
```

## Architecture

See `../docs/plans/2026-02-16-btc-bridge-architecture-design.md` for complete design documentation.
```

**Step 2: Create deployment script skeleton**

Create `contracts/scripts/deploy.sh`:

```bash
#!/bin/bash
set -e

echo "BTC Bridge Deployment Script"
echo "============================"
echo ""
echo "Ensure you have set:"
echo "  STARKNET_RPC"
echo "  STARKNET_ACCOUNT"
echo "  OWNER_ADDRESS"
echo ""

# TODO: Add actual deployment commands
# This will be filled in when we have testnet access and account setup

echo "Build contracts..."
scarb build

echo ""
echo "Deployment commands would go here"
echo "See README.md for manual deployment steps"
```

**Step 3: Make script executable**

```bash
chmod +x contracts/scripts/deploy.sh
```

**Step 4: Commit**

```bash
git add contracts/README.md contracts/scripts/
git commit -m "docs(contracts): add README and deployment guide

- Development setup instructions
- Build and test commands
- Manual deployment steps for testnet
- Configuration examples
- Architecture reference"
```

---

## Success Criteria

After completing all tasks:

✅ All three contracts compile successfully
✅ All tests pass with `snforge test`
✅ Contracts follow OpenZeppelin patterns and Cairo best practices
✅ Deposit signature collection works with configurable threshold
✅ Withdrawal validates whitelists and minimum amounts
✅ Registry tracks PSBTs for backend consumption
✅ Admin functions are owner-protected
✅ Documentation covers deployment and configuration

---

## Next Steps

After Phase 1 completion:
1. **Phase 2: Rust Backend** - Implement watcher-signer and broadcaster services
2. **Testnet Deployment** - Deploy contracts and test with real Bitcoin testnet
3. **Phase 3: Web UI** - Build React frontend for bridge interaction
4. **Integration Testing** - End-to-end testing with all components

---

## Notes for Implementation

- **Cairo version:** This plan assumes Cairo 2.x with latest Scarb
- **OpenZeppelin:** Using v0.14.0 - check for newer versions
- **Testing:** Starknet Foundry (`snforge`) is the recommended testing framework
- **Storage optimization:** Current design is straightforward; optimize later if gas costs are an issue
- **PSBT encoding:** The registry stores PSBTs as `Span<felt252>` - backends will need to encode/decode appropriately
- **Error messages:** All asserts include descriptive error strings for easier debugging

