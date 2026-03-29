#[cfg(test)]
mod tests {
    use core::num::traits::Zero;
    use starknet::ContractAddress;
    use starknet::SyscallResultTrait;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};

    // Interface for commit 7 - admin functions only
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
}
