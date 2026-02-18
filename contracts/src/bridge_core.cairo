use starknet::ContractAddress;

// Token interface for minting
#[starknet::interface]
trait IStrkBTC<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
}

#[starknet::interface]
trait IBridgeCore<TContractState> {
    fn add_committee_member(ref self: TContractState, member: ContractAddress);
    fn remove_committee_member(ref self: TContractState, member: ContractAddress);
    fn update_threshold(ref self: TContractState, new_threshold: u32);
    fn add_btc_whitelist(ref self: TContractState, btc_address: felt252);
    fn remove_btc_whitelist(ref self: TContractState, btc_address: felt252);
    fn add_starknet_whitelist(ref self: TContractState, starknet_address: ContractAddress);
    fn remove_starknet_whitelist(ref self: TContractState, starknet_address: ContractAddress);
    fn update_minimum_withdrawal(ref self: TContractState, new_minimum: u256);
    fn deposit_request(
        ref self: TContractState,
        btc_tx_hash: felt252,
        starknet_address: ContractAddress,
        amount: u256
    );
}

#[starknet::contract]
mod BridgeCore {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry
    };
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use super::{IStrkBTCDispatcher, IStrkBTCDispatcherTrait};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

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
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        DepositProcessed: DepositProcessed,
        WithdrawalRequested: WithdrawalRequested,
        CommitteeMemberAdded: CommitteeMemberAdded,
        CommitteeMemberRemoved: CommitteeMemberRemoved,
        ThresholdUpdated: ThresholdUpdated,
        BtcAddressWhitelisted: BtcAddressWhitelisted,
        BtcAddressRemovedFromWhitelist: BtcAddressRemovedFromWhitelist,
        StarknetAddressWhitelisted: StarknetAddressWhitelisted,
        StarknetAddressRemovedFromWhitelist: StarknetAddressRemovedFromWhitelist,
        MinimumWithdrawalUpdated: MinimumWithdrawalUpdated,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
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
    struct BtcAddressWhitelisted {
        btc_address: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct BtcAddressRemovedFromWhitelist {
        btc_address: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct StarknetAddressWhitelisted {
        starknet_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct StarknetAddressRemovedFromWhitelist {
        starknet_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct MinimumWithdrawalUpdated {
        old_minimum: u256,
        new_minimum: u256,
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
        assert(token_address != Zero::zero(), 'Token cannot be zero address');
        assert(registry_address != Zero::zero(), 'Registry cannot be zero address');
        assert(initial_threshold > 0, 'Threshold must be positive');
        assert(minimum_withdrawal > 0, 'Minimum must be positive');

        self.ownable.initializer(owner);
        self.replaceability.initialize(upgrade_delay: Zero::zero());
        self.token_address.write(token_address);
        self.registry_address.write(registry_address);
        self.signature_threshold.write(initial_threshold);
        self.minimum_withdrawal_amount.write(minimum_withdrawal);
    }

    // ============================================
    // Admin Functions
    // ============================================

    #[abi(embed_v0)]
    impl BridgeCoreImpl of super::IBridgeCore<ContractState> {
        fn add_committee_member(ref self: ContractState, member: ContractAddress) {
            self.ownable.assert_only_owner();

            let is_member = self.committee_members.entry(member).read();
            assert(!is_member, 'Member already exists');

            self.committee_members.entry(member).write(true);
            let new_count = self.committee_count.read() + 1;
            self.committee_count.write(new_count);

            self.emit(CommitteeMemberAdded { member });
        }

        fn remove_committee_member(ref self: ContractState, member: ContractAddress) {
            self.ownable.assert_only_owner();

            let is_member = self.committee_members.entry(member).read();
            assert(is_member, 'Member does not exist');

            let current_count = self.committee_count.read();
            let threshold = self.signature_threshold.read();

            // Ensure threshold is still achievable
            assert(current_count - 1 >= threshold, 'Would break threshold');

            self.committee_members.entry(member).write(false);
            self.committee_count.write(current_count - 1);

            self.emit(CommitteeMemberRemoved { member });
        }

        fn update_threshold(ref self: ContractState, new_threshold: u32) {
            self.ownable.assert_only_owner();

            assert(new_threshold > 0, 'Threshold must be positive');

            let committee_count = self.committee_count.read();
            assert(new_threshold <= committee_count, 'Threshold exceeds members');

            let old_threshold = self.signature_threshold.read();
            self.signature_threshold.write(new_threshold);

            self.emit(ThresholdUpdated { old_threshold, new_threshold });
        }

        fn add_btc_whitelist(ref self: ContractState, btc_address: felt252) {
            self.ownable.assert_only_owner();

            let is_whitelisted = self.btc_whitelist.entry(btc_address).read();
            assert(!is_whitelisted, 'BTC address already whitelisted');

            self.btc_whitelist.entry(btc_address).write(true);

            self.emit(BtcAddressWhitelisted { btc_address });
        }

        fn remove_btc_whitelist(ref self: ContractState, btc_address: felt252) {
            self.ownable.assert_only_owner();

            let is_whitelisted = self.btc_whitelist.entry(btc_address).read();
            assert(is_whitelisted, 'BTC address not whitelisted');

            self.btc_whitelist.entry(btc_address).write(false);

            self.emit(BtcAddressRemovedFromWhitelist { btc_address });
        }

        fn add_starknet_whitelist(ref self: ContractState, starknet_address: ContractAddress) {
            self.ownable.assert_only_owner();

            let is_whitelisted = self.starknet_whitelist.entry(starknet_address).read();
            assert(!is_whitelisted, 'Address already whitelisted');

            self.starknet_whitelist.entry(starknet_address).write(true);

            self.emit(StarknetAddressWhitelisted { starknet_address });
        }

        fn remove_starknet_whitelist(ref self: ContractState, starknet_address: ContractAddress) {
            self.ownable.assert_only_owner();

            let is_whitelisted = self.starknet_whitelist.entry(starknet_address).read();
            assert(is_whitelisted, 'Address not whitelisted');

            self.starknet_whitelist.entry(starknet_address).write(false);

            self.emit(StarknetAddressRemovedFromWhitelist { starknet_address });
        }

        fn update_minimum_withdrawal(ref self: ContractState, new_minimum: u256) {
            self.ownable.assert_only_owner();

            assert(new_minimum > 0, 'Minimum must be positive');

            let old_minimum = self.minimum_withdrawal_amount.read();
            self.minimum_withdrawal_amount.write(new_minimum);

            self.emit(MinimumWithdrawalUpdated { old_minimum, new_minimum });
        }

        // ============================================
        // Deposit Functions
        // ============================================

        /// Committee member submits a deposit request
        /// Multiple committee members must sign the same deposit
        /// Automatically mints when threshold is reached
        fn deposit_request(
            ref self: ContractState,
            btc_tx_hash: felt252,
            starknet_address: ContractAddress,
            amount: u256
        ) {
            // Only committee members can submit
            self._assert_committee_member();

            // Check if already processed
            let is_processed = self.processed_deposits.entry(btc_tx_hash).read();
            assert(!is_processed, 'Deposit already processed');

            // Check if caller already signed
            let caller = starknet::get_caller_address();
            let already_signed = self.deposit_signatures.entry((btc_tx_hash, caller)).read();
            assert(!already_signed, 'Already signed this deposit');

            // Get current signature count
            let current_count = self.deposit_signature_count.entry(btc_tx_hash).read();

            if current_count == 0 {
                // First signature - store the deposit data
                self._set_pending_deposit(btc_tx_hash, starknet_address, amount);
            } else {
                // Subsequent signatures - validate data matches
                let stored_address = self.pending_deposit_starknet_address.entry(btc_tx_hash).read();
                let stored_amount = self.pending_deposit_amount.entry(btc_tx_hash).read();

                assert(stored_address == starknet_address, 'Address mismatch');
                assert(stored_amount == amount, 'Amount mismatch');
            }

            // Record this signature
            self.deposit_signatures.entry((btc_tx_hash, caller)).write(true);
            let new_count = current_count + 1;
            self.deposit_signature_count.entry(btc_tx_hash).write(new_count);

            // Check if threshold reached
            let threshold = self.signature_threshold.read();
            if new_count >= threshold {
                self._execute_mint(btc_tx_hash, starknet_address, amount);
            }
        }
    }

    // ============================================
    // Internal Functions
    // ============================================

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Assert that caller is a committee member
        fn _assert_committee_member(ref self: ContractState) {
            let caller = starknet::get_caller_address();
            let is_member = self.committee_members.entry(caller).read();
            assert(is_member, 'Not a committee member');
        }

        fn _set_pending_deposit(
            ref self: ContractState,
            btc_tx_hash: felt252,
            starknet_address: ContractAddress,
            amount: u256
        ) {
            self.pending_deposit_starknet_address.entry(btc_tx_hash).write(starknet_address);
            self.pending_deposit_amount.entry(btc_tx_hash).write(amount);
        }

        /// Execute the mint after threshold is reached
        fn _execute_mint(
            ref self: ContractState,
            btc_tx_hash: felt252,
            starknet_address: ContractAddress,
            amount: u256
        ) {
            // Mark as processed
            self.processed_deposits.entry(btc_tx_hash).write(true);

            // Call token contract to mint
            let token_address = self.token_address.read();
            let token_dispatcher = IStrkBTCDispatcher { contract_address: token_address };
            token_dispatcher.mint(starknet_address, amount);

            // Emit event
            self.emit(DepositProcessed { btc_tx_hash, starknet_address, amount });
        }
    }
}
