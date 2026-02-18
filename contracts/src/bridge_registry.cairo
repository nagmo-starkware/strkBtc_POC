use starknet::ContractAddress;

#[starknet::interface]
trait IBridgeRegistry<TContractState> {
    fn submit_psbt(
        ref self: TContractState,
        tx_hash: felt252,
        psbt_data: Span<felt252>
    );
    fn get_signature_count(self: @TContractState, tx_hash: felt252) -> u32;
    fn get_psbt(self: @TContractState, tx_hash: felt252) -> Span<felt252>;
    fn has_signed(self: @TContractState, tx_hash: felt252, signer: ContractAddress) -> bool;
    fn psbt_exists(self: @TContractState, tx_hash: felt252) -> bool;
}

#[starknet::contract]
mod BridgeRegistry {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry,
        Vec, VecTrait, MutableVecTrait
    };
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;

    // Interface for querying the bridge core contract
    #[starknet::interface]
    trait IBridgeCoreQuery<TContractState> {
        fn is_committee_member(self: @TContractState, address: ContractAddress) -> bool;
    }

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
        // Bridge core contract address for committee verification
        bridge_core: ContractAddress,

        // PSBT data storage: tx_hash -> Vec<felt252>
        psbt_data: Map<felt252, Vec<felt252>>,

        // Signature tracking: (tx_hash, signer) -> bool
        psbt_signatures: Map<(felt252, ContractAddress), bool>,

        // Signature count per tx_hash
        signature_count: Map<felt252, u32>,

        // Track if a PSBT exists
        psbt_exists_map: Map<felt252, bool>,

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
        PSBTSubmitted: PSBTSubmitted,
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
    struct PSBTSubmitted {
        #[key]
        tx_hash: felt252,
        signer: ContractAddress,
        signature_count: u32,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        bridge_core_address: ContractAddress,
    ) {
        assert(bridge_core_address != Zero::zero(), 'Bridge core cannot be zero');
        self.ownable.initializer(owner);
        self.replaceability.initialize(upgrade_delay: Zero::zero());
        self.bridge_core.write(bridge_core_address);
    }

    #[abi(embed_v0)]
    impl BridgeRegistryImpl of super::IBridgeRegistry<ContractState> {
        /// Submit a PSBT for a withdrawal transaction
        /// Only committee members can submit
        /// Each committee member can submit once per tx_hash
        fn submit_psbt(
            ref self: ContractState,
            tx_hash: felt252,
            psbt_data: Span<felt252>
        ) {
            // Verify caller is committee member
            self._assert_committee_member();

            let caller = starknet::get_caller_address();

            // Check if this signer has already submitted for this tx_hash
            let already_signed = self.psbt_signatures.entry((tx_hash, caller)).read();
            assert(!already_signed, 'Already submitted PSBT');

            // Check PSBT data is not empty
            assert(psbt_data.len() > 0, 'PSBT data cannot be empty');

            // If this is the first PSBT submission for this tx_hash, store the data
            let exists = self.psbt_exists_map.entry(tx_hash).read();
            if !exists {
                // Store PSBT data
                let mut psbt_vec = self.psbt_data.entry(tx_hash);
                let mut i: u32 = 0;
                loop {
                    if i >= psbt_data.len() {
                        break;
                    }
                    psbt_vec.push(*psbt_data.at(i));
                    i += 1;
                };

                self.psbt_exists_map.entry(tx_hash).write(true);
            }

            // Record this signature
            self.psbt_signatures.entry((tx_hash, caller)).write(true);

            // Increment signature count
            let current_count = self.signature_count.entry(tx_hash).read();
            let new_count = current_count + 1;
            self.signature_count.entry(tx_hash).write(new_count);

            // Emit event
            self.emit(PSBTSubmitted { tx_hash, signer: caller, signature_count: new_count });
        }

        /// Get the number of signatures for a PSBT
        fn get_signature_count(self: @ContractState, tx_hash: felt252) -> u32 {
            self.signature_count.entry(tx_hash).read()
        }

        /// Get the PSBT data for a transaction hash
        fn get_psbt(self: @ContractState, tx_hash: felt252) -> Span<felt252> {
            let psbt_vec = self.psbt_data.entry(tx_hash);
            let mut result: Array<felt252> = ArrayTrait::new();

            let len = psbt_vec.len();
            let mut i: u64 = 0;
            loop {
                if i >= len {
                    break;
                }
                result.append(psbt_vec.at(i).read());
                i += 1;
            };

            result.span()
        }

        /// Check if a signer has submitted a PSBT for this tx_hash
        fn has_signed(self: @ContractState, tx_hash: felt252, signer: ContractAddress) -> bool {
            self.psbt_signatures.entry((tx_hash, signer)).read()
        }

        /// Check if a PSBT exists for this tx_hash
        fn psbt_exists(self: @ContractState, tx_hash: felt252) -> bool {
            self.psbt_exists_map.entry(tx_hash).read()
        }
    }

    // ============================================
    // Internal Functions
    // ============================================

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Assert that caller is a committee member by querying bridge_core
        fn _assert_committee_member(ref self: ContractState) {
            let caller = starknet::get_caller_address();
            let bridge_core_address = self.bridge_core.read();

            let bridge_core_dispatcher = IBridgeCoreQueryDispatcher {
                contract_address: bridge_core_address
            };

            let is_member = bridge_core_dispatcher.is_committee_member(caller);
            assert(is_member, 'Not a committee member');
        }
    }
}
