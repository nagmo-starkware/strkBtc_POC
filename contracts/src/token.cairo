#[starknet::contract]
mod StrkBTC {
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::access::ownable::OwnableComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use core::num::traits::Zero;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[storage]
    struct Storage {
        bridge_address: ContractAddress,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        bridge: ContractAddress
    ) {
        self.erc20.initializer("Starknet BTC", "strkBTC");
        self.ownable.initializer(owner);
        self.replaceability.initialize(upgrade_delay: Zero::zero());
        self.bridge_address.write(bridge);
    }

    #[external(v0)]
    fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
        self._assert_only_bridge();
        self.erc20.mint(to, amount);
    }

    #[external(v0)]
    fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
        self._assert_only_bridge();
        self.erc20.burn(from, amount);
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
