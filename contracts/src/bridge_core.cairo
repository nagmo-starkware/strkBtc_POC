#[starknet::contract]
mod BridgeCore {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StoragePointerWriteAccess};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;

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
        // component inherited storage
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
        // custom storage
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
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        // component events
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
        // custom events
        DepositProcessed: DepositProcessed,
        WithdrawalRequested: WithdrawalRequested,
        CommitteeMemberAdded: CommitteeMemberAdded,
        CommitteeMemberRemoved: CommitteeMemberRemoved,
        ThresholdUpdated: ThresholdUpdated,
        BtcAddressWhitelisted: BtcAddressWhitelisted,
        BtcAddressRemovedFromWhitelist: BtcAddressRemovedFromWhitelist,
        StarknetAddressWhitelisted: StarknetAddressWhitelisted,
        StarknetAddressRemovedFromWhitelist: StarknetAddressRemovedFromWhitelist,
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
}
