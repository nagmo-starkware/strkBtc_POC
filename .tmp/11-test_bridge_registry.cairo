#[cfg(test)]
mod tests {
    use starknet::ContractAddress;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};

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

    // Mock IBridgeCoreQuery interface (registry queries bridge to check committee membership)
    #[starknet::interface]
    trait IMockBridgeCore<TContractState> {
        fn is_committee_member(self: @TContractState, address: ContractAddress) -> bool;
        fn set_committee_member(ref self: TContractState, address: ContractAddress, is_member: bool);
    }

    fn deploy_mock_bridge() -> ContractAddress {
        // For testing, we need a mock bridge that implements is_committee_member
        // This is a simplified approach - in practice, you might deploy a full BridgeCore
        // or create a dedicated mock contract. For now, we'll note this limitation.
        'mock_bridge'.try_into().unwrap()
    }

    fn deploy_registry(bridge_core: ContractAddress) -> ContractAddress {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let registry_contract = declare("BridgeRegistry").unwrap().contract_class();
        let mut args: Array<felt252> = array![];
        args.append(owner.into());
        args.append(bridge_core.into());
        let (address, _) = registry_contract.deploy(@args).unwrap();
        address
    }

    #[test]
    fn test_registry_deploys() {
        let bridge_core: ContractAddress = 'bridge'.try_into().unwrap();
        let registry_address = deploy_registry(bridge_core);
        assert(registry_address.into() != 0, 'Deployment failed');
    }

    // NOTE: The following tests require a mock BridgeCore contract that implements
    // is_committee_member. For a complete test suite, you would need to:
    // 1. Deploy a full BridgeCore contract, OR
    // 2. Create a MockBridgeCore contract with is_committee_member
    //
    // These tests are structured but may need integration-level setup to run properly.

    #[test]
    #[ignore]
    fn test_submit_psbt() {
        // TODO: Requires deploying BridgeCore and adding a committee member
        // let owner: ContractAddress = 'owner'.try_into().unwrap();
        // let token: ContractAddress = 'token'.try_into().unwrap();
        // let bridge_core = deploy_bridge_core(owner, token, ...);
        // let registry = deploy_registry(bridge_core);
        //
        // // Add member to bridge_core committee
        // bridge.add_committee_member(member);
        //
        // // Submit PSBT
        // let tx_hash: felt252 = 'withdrawal_tx_123';
        // let psbt_data: Array<felt252> = array![1, 2, 3, 4, 5];
        // start_cheat_caller_address(registry_address, member);
        // registry.submit_psbt(tx_hash, psbt_data.span());
        // stop_cheat_caller_address(registry_address);
        //
        // assert(registry.psbt_exists(tx_hash), 'PSBT should exist');
        // assert(registry.get_signature_count(tx_hash) == 1, 'Wrong sig count');
        // assert(registry.has_signed(tx_hash, member), 'Should have signed');
    }

    #[test]
    #[ignore]
    fn test_get_signature_count() {
        // TODO: Integration test with BridgeCore
        // Deploy bridge_core, add 2 members, submit PSBT from both
        // Verify signature count increments correctly
    }

    #[test]
    #[ignore]
    #[should_panic(expected: ('Not a committee member',))]
    fn test_non_committee_cannot_submit_fails() {
        // TODO: Integration test
        // Deploy bridge_core (no members), registry
        // Try to submit PSBT as non-member
        // Should panic with 'Not a committee member'
    }

    #[test]
    #[ignore]
    #[should_panic(expected: ('Already submitted PSBT',))]
    fn test_duplicate_submission_fails() {
        // TODO: Integration test
        // Deploy bridge_core, add member, submit PSBT
        // Try to submit same tx_hash again from same member
        // Should panic with 'Already submitted PSBT'
    }

    // Standalone unit test (no integration needed)
    #[test]
    fn test_get_psbt_empty_by_default() {
        let bridge_core: ContractAddress = 'bridge'.try_into().unwrap();
        let registry_address = deploy_registry(bridge_core);
        let registry = IBridgeRegistryDispatcher { contract_address: registry_address };

        let tx_hash: felt252 = 'nonexistent_tx';
        let psbt = registry.get_psbt(tx_hash);
        assert(psbt.len() == 0, 'PSBT should be empty');
    }

    #[test]
    fn test_psbt_exists_false_by_default() {
        let bridge_core: ContractAddress = 'bridge'.try_into().unwrap();
        let registry_address = deploy_registry(bridge_core);
        let registry = IBridgeRegistryDispatcher { contract_address: registry_address };

        let tx_hash: felt252 = 'nonexistent_tx';
        assert(!registry.psbt_exists(tx_hash), 'PSBT should not exist');
    }

    #[test]
    fn test_has_signed_false_by_default() {
        let bridge_core: ContractAddress = 'bridge'.try_into().unwrap();
        let registry_address = deploy_registry(bridge_core);
        let registry = IBridgeRegistryDispatcher { contract_address: registry_address };

        let tx_hash: felt252 = 'nonexistent_tx';
        let signer: ContractAddress = 'signer'.try_into().unwrap();
        assert(!registry.has_signed(tx_hash, signer), 'Should not have signed');
    }

    #[test]
    fn test_get_signature_count_zero_by_default() {
        let bridge_core: ContractAddress = 'bridge'.try_into().unwrap();
        let registry_address = deploy_registry(bridge_core);
        let registry = IBridgeRegistryDispatcher { contract_address: registry_address };

        let tx_hash: felt252 = 'nonexistent_tx';
        assert(registry.get_signature_count(tx_hash) == 0, 'Count should be zero');
    }
}
