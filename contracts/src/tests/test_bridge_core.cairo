#[cfg(test)]
mod tests {
    use core::num::traits::Zero;
    use starknet::ContractAddress;
    use starknet::SyscallResultTrait;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};

    // Interface for commit 10 - adds withdraw and view functions
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
        fn withdraw(ref self: TContractState, btc_address: felt252, amount: u256);
        fn is_btc_whitelisted(self: @TContractState, btc_address: felt252) -> bool;
        fn is_starknet_whitelisted(self: @TContractState, address: ContractAddress) -> bool;
        fn is_committee_member(self: @TContractState, address: ContractAddress) -> bool;
        fn get_signature_threshold(self: @TContractState) -> u32;
        fn get_committee_count(self: @TContractState) -> u32;
        fn get_minimum_withdrawal(self: @TContractState) -> u256;
        fn is_deposit_processed(self: @TContractState, btc_tx_hash: felt252) -> bool;
        fn get_deposit_signature_count(self: @TContractState, btc_tx_hash: felt252) -> u32;
    }

    fn deploy_bridge(
        owner: ContractAddress,
        token: ContractAddress,
        registry: ContractAddress,
        threshold: u32,
        minimum: u256
    ) -> ContractAddress {
        let bridge_contract = declare("BridgeCore").unwrap().contract_class();
        let mut args: Array<felt252> = array![];
        args.append(owner.into());
        args.append(token.into());
        args.append(registry.into());
        args.append(threshold.into());
        args.append(minimum.low.into());
        args.append(minimum.high.into());
        let (address, _) = bridge_contract.deploy(@args).unwrap();
        address
    }

    fn deploy_bridge_raw(
        owner: ContractAddress,
        token: ContractAddress,
        registry: ContractAddress,
        threshold: u32,
        minimum: u256
    ) {
        let bridge_contract = declare("BridgeCore").unwrap().contract_class();
        let mut args: Array<felt252> = array![];
        args.append(owner.into());
        args.append(token.into());
        args.append(registry.into());
        args.append(threshold.into());
        args.append(minimum.low.into());
        args.append(minimum.high.into());
        let deploy_address: ContractAddress = 0x999.try_into().unwrap();
        bridge_contract.deploy_at(@args, deploy_address).unwrap_syscall();
    }

    // ========== ALL TESTS FROM COMMIT 7 (baseline) ==========

    #[test]
    fn test_bridge_core_deploys() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();

        let bridge_address = deploy_bridge(
            owner,
            token,
            registry,
            2,
            100000
        );

        assert(bridge_address.into() != 0, 'Deployment failed');
    }

    #[test]
    #[should_panic(expected: ('Token cannot be zero address',))]
    fn test_constructor_zero_token_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let zero_address: ContractAddress = Zero::zero();
        let registry: ContractAddress = 'registry'.try_into().unwrap();

        deploy_bridge_raw(
            owner,
            zero_address,
            registry,
            2,
            100000
        );
    }

    #[test]
    #[should_panic(expected: ('Registry cannot be zero address',))]
    fn test_constructor_zero_registry_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let zero_address: ContractAddress = Zero::zero();

        deploy_bridge_raw(
            owner,
            token,
            zero_address,
            2,
            100000
        );
    }

    #[test]
    #[should_panic(expected: ('Threshold must be positive',))]
    fn test_constructor_zero_threshold_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();

        deploy_bridge_raw(
            owner,
            token,
            registry,
            0,
            100000
        );
    }

    #[test]
    #[should_panic(expected: ('Minimum must be positive',))]
    fn test_constructor_zero_minimum_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();

        deploy_bridge_raw(
            owner,
            token,
            registry,
            2,
            0
        );
    }

    #[test]
    fn test_add_committee_member() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member: ContractAddress = 'member'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member);
        stop_cheat_caller_address(bridge_address);

        // Now we can verify with view function
        assert(bridge.is_committee_member(member), 'Should be member');
        assert(bridge.get_committee_count() == 1, 'Wrong count');
    }

    #[test]
    #[should_panic(expected: ('Member already exists',))]
    fn test_add_duplicate_committee_member_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member: ContractAddress = 'member'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member);
        bridge.add_committee_member(member);
    }

    #[test]
    fn test_remove_committee_member() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member1: ContractAddress = 'member1'.try_into().unwrap();
        let member2: ContractAddress = 'member2'.try_into().unwrap();
        let member3: ContractAddress = 'member3'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member1);
        bridge.add_committee_member(member2);
        bridge.add_committee_member(member3);

        // Remove one member (3 members, threshold 2, so safe)
        bridge.remove_committee_member(member3);
        stop_cheat_caller_address(bridge_address);

        // Verify with view functions
        assert(bridge.is_committee_member(member1), 'member1 should exist');
        assert(bridge.is_committee_member(member2), 'member2 should exist');
        assert(!bridge.is_committee_member(member3), 'member3 should be removed');
        assert(bridge.get_committee_count() == 2, 'Wrong count after removal');
    }

    #[test]
    #[should_panic(expected: ('Member does not exist',))]
    fn test_remove_nonexistent_member_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member: ContractAddress = 'member'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.remove_committee_member(member);
    }

    #[test]
    #[should_panic(expected: ('Would break threshold',))]
    fn test_remove_member_breaking_threshold_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member1: ContractAddress = 'member1'.try_into().unwrap();
        let member2: ContractAddress = 'member2'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member1);
        bridge.add_committee_member(member2);

        // Try to remove one (would leave 1 member, but threshold is 2)
        bridge.remove_committee_member(member2);
    }

    #[test]
    fn test_update_threshold() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member1: ContractAddress = 'member1'.try_into().unwrap();
        let member2: ContractAddress = 'member2'.try_into().unwrap();
        let member3: ContractAddress = 'member3'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member1);
        bridge.add_committee_member(member2);
        bridge.add_committee_member(member3);

        // Update threshold to 3 (3 members present)
        bridge.update_threshold(3);
        stop_cheat_caller_address(bridge_address);

        // Verify with view function
        assert(bridge.get_signature_threshold() == 3, 'Wrong threshold');
    }

    #[test]
    #[should_panic(expected: ('Threshold must be positive',))]
    fn test_update_threshold_zero_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.update_threshold(0);
    }

    #[test]
    #[should_panic(expected: ('Threshold exceeds members',))]
    fn test_update_threshold_exceeds_members_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member1: ContractAddress = 'member1'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 1, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member1);

        // Try to set threshold to 5 when only 1 member exists
        bridge.update_threshold(5);
    }

    #[test]
    fn test_btc_whitelist() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let btc_address: felt252 = 'bc1qxy2kgdygjrsqtzq2n0yrf24';

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_btc_whitelist(btc_address);
        stop_cheat_caller_address(bridge_address);

        // Verify with view function
        assert(bridge.is_btc_whitelisted(btc_address), 'Should be whitelisted');
    }

    #[test]
    #[should_panic(expected: ('BTC address already whitelisted',))]
    fn test_add_duplicate_btc_whitelist_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let btc_address: felt252 = 'bc1qxy2kgdygjrsqtzq2n0yrf24';

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_btc_whitelist(btc_address);
        bridge.add_btc_whitelist(btc_address);
    }

    #[test]
    fn test_remove_btc_whitelist() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let btc_address: felt252 = 'bc1qxy2kgdygjrsqtzq2n0yrf24';

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_btc_whitelist(btc_address);
        bridge.remove_btc_whitelist(btc_address);
        stop_cheat_caller_address(bridge_address);

        // Verify with view function
        assert(!bridge.is_btc_whitelisted(btc_address), 'Should not be whitelisted');
    }

    #[test]
    #[should_panic(expected: ('BTC address not whitelisted',))]
    fn test_remove_nonexistent_btc_whitelist_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let btc_address: felt252 = 'bc1qxy2kgdygjrsqtzq2n0yrf24';

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.remove_btc_whitelist(btc_address);
    }

    #[test]
    fn test_starknet_whitelist() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let starknet_address: ContractAddress = 'user'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_starknet_whitelist(starknet_address);
        stop_cheat_caller_address(bridge_address);

        // Verify with view function
        assert(bridge.is_starknet_whitelisted(starknet_address), 'Should be whitelisted');
    }

    #[test]
    #[should_panic(expected: ('Address already whitelisted',))]
    fn test_add_duplicate_starknet_whitelist_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let starknet_address: ContractAddress = 'user'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_starknet_whitelist(starknet_address);
        bridge.add_starknet_whitelist(starknet_address);
    }

    #[test]
    fn test_remove_starknet_whitelist() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let starknet_address: ContractAddress = 'user'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_starknet_whitelist(starknet_address);
        bridge.remove_starknet_whitelist(starknet_address);
        stop_cheat_caller_address(bridge_address);

        // Verify with view function
        assert(!bridge.is_starknet_whitelisted(starknet_address), 'Should not be whitelisted');
    }

    #[test]
    #[should_panic(expected: ('Address not whitelisted',))]
    fn test_remove_nonexistent_starknet_whitelist_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let starknet_address: ContractAddress = 'user'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.remove_starknet_whitelist(starknet_address);
    }

    #[test]
    fn test_update_minimum_withdrawal() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.update_minimum_withdrawal(200000);
        stop_cheat_caller_address(bridge_address);

        // Verify with view function
        assert(bridge.get_minimum_withdrawal() == 200000, 'Wrong minimum');
    }

    #[test]
    #[should_panic(expected: ('Minimum must be positive',))]
    fn test_update_minimum_withdrawal_zero_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.update_minimum_withdrawal(0);
    }

    #[test]
    #[should_panic(expected: ('Caller is not the owner',))]
    fn test_non_owner_cannot_add_committee_member() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let attacker: ContractAddress = 'attacker'.try_into().unwrap();
        let member: ContractAddress = 'member'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, attacker);
        bridge.add_committee_member(member);
    }

    // ========== TESTS FROM COMMIT 9 (deposit_request) ==========

    #[test]
    fn test_deposit_request_single_signature() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member1: ContractAddress = 'member1'.try_into().unwrap();
        let member2: ContractAddress = 'member2'.try_into().unwrap();
        let recipient: ContractAddress = 'recipient'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        // Setup: add 2 committee members, threshold 2
        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member1);
        bridge.add_committee_member(member2);
        stop_cheat_caller_address(bridge_address);

        let btc_tx_hash: felt252 = 'btc_tx_123';

        // First signature (doesn't reach threshold, no mint should happen)
        start_cheat_caller_address(bridge_address, member1);
        bridge.deposit_request(btc_tx_hash, recipient, 1000);
        stop_cheat_caller_address(bridge_address);

        // Verify state with view functions
        assert(bridge.get_deposit_signature_count(btc_tx_hash) == 1, 'Wrong sig count');
        assert(!bridge.is_deposit_processed(btc_tx_hash), 'Should not be processed');
    }

    #[test]
    #[should_panic(expected: ('Already signed this deposit',))]
    fn test_deposit_request_already_signed_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member1: ContractAddress = 'member1'.try_into().unwrap();
        let member2: ContractAddress = 'member2'.try_into().unwrap();
        let recipient: ContractAddress = 'recipient'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member1);
        bridge.add_committee_member(member2);
        stop_cheat_caller_address(bridge_address);

        let btc_tx_hash: felt252 = 'btc_tx_123';

        // First signature
        start_cheat_caller_address(bridge_address, member1);
        bridge.deposit_request(btc_tx_hash, recipient, 1000);

        // Try to sign again (same member, same tx_hash)
        bridge.deposit_request(btc_tx_hash, recipient, 1000);
    }

    #[test]
    #[should_panic(expected: ('Not a committee member',))]
    fn test_deposit_request_non_committee_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let attacker: ContractAddress = 'attacker'.try_into().unwrap();
        let recipient: ContractAddress = 'recipient'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        let btc_tx_hash: felt252 = 'btc_tx_123';

        // Try to sign as non-member
        start_cheat_caller_address(bridge_address, attacker);
        bridge.deposit_request(btc_tx_hash, recipient, 1000);
    }

    #[test]
    #[should_panic(expected: ('Amount mismatch',))]
    fn test_deposit_request_data_mismatch_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member1: ContractAddress = 'member1'.try_into().unwrap();
        let member2: ContractAddress = 'member2'.try_into().unwrap();
        let recipient: ContractAddress = 'recipient'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member1);
        bridge.add_committee_member(member2);
        stop_cheat_caller_address(bridge_address);

        let btc_tx_hash: felt252 = 'btc_tx_123';

        // First signature with amount 1000
        start_cheat_caller_address(bridge_address, member1);
        bridge.deposit_request(btc_tx_hash, recipient, 1000);
        stop_cheat_caller_address(bridge_address);

        // Second signature with DIFFERENT amount (2000)
        start_cheat_caller_address(bridge_address, member2);
        bridge.deposit_request(btc_tx_hash, recipient, 2000);
    }

    // ========== NEW TESTS FOR COMMIT 10 (view functions and withdraw) ==========

    #[test]
    fn test_initial_state() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        assert(bridge.get_signature_threshold() == 2, 'Wrong threshold');
        assert(bridge.get_committee_count() == 0, 'Wrong initial count');
        assert(bridge.get_minimum_withdrawal() == 100000, 'Wrong minimum');
    }

    #[test]
    fn test_view_committee_member() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member: ContractAddress = 'member'.try_into().unwrap();
        let non_member: ContractAddress = 'non_member'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        assert(!bridge.is_committee_member(member), 'Should not be member');

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member);
        stop_cheat_caller_address(bridge_address);

        assert(bridge.is_committee_member(member), 'Should be member');
        assert(!bridge.is_committee_member(non_member), 'Should not be member');
        assert(bridge.get_committee_count() == 1, 'Wrong count');
    }

    #[test]
    fn test_view_btc_whitelist() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let btc_address: felt252 = 'bc1qxy2kgdygjrsqtzq2n0yrf24';

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        assert(!bridge.is_btc_whitelisted(btc_address), 'Should not be whitelisted');

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_btc_whitelist(btc_address);
        stop_cheat_caller_address(bridge_address);

        assert(bridge.is_btc_whitelisted(btc_address), 'Should be whitelisted');
    }

    #[test]
    fn test_view_starknet_whitelist() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let user: ContractAddress = 'user'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        assert(!bridge.is_starknet_whitelisted(user), 'Should not be whitelisted');

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_starknet_whitelist(user);
        stop_cheat_caller_address(bridge_address);

        assert(bridge.is_starknet_whitelisted(user), 'Should be whitelisted');
    }

    #[test]
    fn test_view_deposit_state() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let member1: ContractAddress = 'member1'.try_into().unwrap();
        let recipient: ContractAddress = 'recipient'.try_into().unwrap();

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        start_cheat_caller_address(bridge_address, owner);
        bridge.add_committee_member(member1);
        stop_cheat_caller_address(bridge_address);

        let btc_tx_hash: felt252 = 'btc_tx_123';

        assert(!bridge.is_deposit_processed(btc_tx_hash), 'Should not be processed');
        assert(bridge.get_deposit_signature_count(btc_tx_hash) == 0, 'Wrong sig count');

        start_cheat_caller_address(bridge_address, member1);
        bridge.deposit_request(btc_tx_hash, recipient, 1000);
        stop_cheat_caller_address(bridge_address);

        assert(bridge.get_deposit_signature_count(btc_tx_hash) == 1, 'Wrong sig count');
    }

    #[test]
    #[should_panic(expected: ('Address not whitelisted',))]
    fn test_withdraw_not_whitelisted_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let user: ContractAddress = 'user'.try_into().unwrap();
        let btc_address: felt252 = 'bc1qxy2kgdygjrsqtzq2n0yrf24';

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        // Try to withdraw without being whitelisted
        start_cheat_caller_address(bridge_address, user);
        bridge.withdraw(btc_address, 150000);
    }

    #[test]
    #[should_panic(expected: ('Amount below minimum',))]
    fn test_withdraw_below_minimum_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let token: ContractAddress = 'token'.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();
        let user: ContractAddress = 'user'.try_into().unwrap();
        let btc_address: felt252 = 'bc1qxy2kgdygjrsqtzq2n0yrf24';

        let bridge_address = deploy_bridge(owner, token, registry, 2, 100000);
        let bridge = IBridgeCoreDispatcher { contract_address: bridge_address };

        // Whitelist user first
        start_cheat_caller_address(bridge_address, owner);
        bridge.add_starknet_whitelist(user);
        bridge.add_btc_whitelist(btc_address);
        stop_cheat_caller_address(bridge_address);

        // Try to withdraw below minimum (100000)
        start_cheat_caller_address(bridge_address, user);
        bridge.withdraw(btc_address, 50000);
    }
}
