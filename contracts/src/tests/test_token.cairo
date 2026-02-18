#[cfg(test)]
mod tests {
    use core::num::traits::Zero;
    use starknet::ContractAddress;
    use starknet::SyscallResultTrait;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};

    // Updated interface for commit 5 - adds approve and get_bridge
    #[starknet::interface]
    trait IStrkBTC<TContractState> {
        fn name(self: @TContractState) -> ByteArray;
        fn symbol(self: @TContractState) -> ByteArray;
        fn total_supply(self: @TContractState) -> u256;
        fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
        fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
        fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
        fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
        fn get_bridge(self: @TContractState) -> ContractAddress;
    }

    fn deploy_token(owner: ContractAddress, bridge: ContractAddress) -> ContractAddress {
        let token_contract = declare("StrkBTC").unwrap().contract_class();
        let mut args: Array<felt252> = array![];
        args.append(owner.into());
        args.append(bridge.into());
        let (address, _) = token_contract.deploy(@args).unwrap();
        address
    }

    #[test]
    fn test_initialization() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        assert(token.name() == "Starknet BTC", 'Wrong name');
        assert(token.symbol() == "strkBTC", 'Wrong symbol');
        assert(token.total_supply() == 0, 'Initial supply not zero');
    }

    #[test]
    fn test_mint_as_bridge() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let recipient: ContractAddress = 'recipient'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        start_cheat_caller_address(token_address, bridge);
        token.mint(recipient, 1000);
        stop_cheat_caller_address(token_address);

        assert(token.balance_of(recipient) == 1000, 'Wrong balance');
        assert(token.total_supply() == 1000, 'Wrong total supply');
    }

    #[test]
    #[should_panic(expected: ('Caller is not the bridge',))]
    fn test_mint_not_bridge_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let recipient: ContractAddress = 'recipient'.try_into().unwrap();
        let attacker: ContractAddress = 'attacker'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        start_cheat_caller_address(token_address, attacker);
        token.mint(recipient, 1000);
    }

    #[test]
    fn test_burn_as_bridge() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let holder: ContractAddress = 'holder'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        // Mint first
        start_cheat_caller_address(token_address, bridge);
        token.mint(holder, 1000);
        stop_cheat_caller_address(token_address);

        // Holder approves bridge to burn
        start_cheat_caller_address(token_address, holder);
        token.approve(bridge, 500);
        stop_cheat_caller_address(token_address);

        // Bridge burns from holder's balance
        start_cheat_caller_address(token_address, bridge);
        token.burn(holder, 500);
        stop_cheat_caller_address(token_address);

        assert(token.balance_of(holder) == 500, 'Wrong balance after burn');
        assert(token.total_supply() == 500, 'Wrong supply after burn');
    }

    #[test]
    #[should_panic(expected: ('Caller is not the bridge',))]
    fn test_burn_not_bridge_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let holder: ContractAddress = 'holder'.try_into().unwrap();
        let attacker: ContractAddress = 'attacker'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        // Mint first
        start_cheat_caller_address(token_address, bridge);
        token.mint(holder, 1000);
        stop_cheat_caller_address(token_address);

        // Try to burn as attacker
        start_cheat_caller_address(token_address, attacker);
        token.burn(holder, 500);
    }

    #[test]
    fn test_mint_multiple_recipients() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let recipient1: ContractAddress = 'recipient1'.try_into().unwrap();
        let recipient2: ContractAddress = 'recipient2'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        start_cheat_caller_address(token_address, bridge);
        token.mint(recipient1, 1000);
        token.mint(recipient2, 2000);
        stop_cheat_caller_address(token_address);

        assert(token.balance_of(recipient1) == 1000, 'Wrong balance 1');
        assert(token.balance_of(recipient2) == 2000, 'Wrong balance 2');
        assert(token.total_supply() == 3000, 'Wrong total supply');
    }

    #[test]
    fn test_burn_entire_balance() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let holder: ContractAddress = 'holder'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        start_cheat_caller_address(token_address, bridge);
        token.mint(holder, 1000);
        stop_cheat_caller_address(token_address);

        // Holder approves bridge to burn entire balance
        start_cheat_caller_address(token_address, holder);
        token.approve(bridge, 1000);
        stop_cheat_caller_address(token_address);

        // Bridge burns entire balance
        start_cheat_caller_address(token_address, bridge);
        token.burn(holder, 1000);
        stop_cheat_caller_address(token_address);

        assert(token.balance_of(holder) == 0, 'Balance should be zero');
        assert(token.total_supply() == 0, 'Supply should be zero');
    }

    #[test]
    fn test_mint_zero_amount() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let recipient: ContractAddress = 'recipient'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        start_cheat_caller_address(token_address, bridge);
        token.mint(recipient, 0);
        stop_cheat_caller_address(token_address);

        assert(token.balance_of(recipient) == 0, 'Balance should be zero');
        assert(token.total_supply() == 0, 'Supply should be zero');
    }

    #[test]
    fn test_burn_zero_amount() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let holder: ContractAddress = 'holder'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        start_cheat_caller_address(token_address, bridge);
        token.mint(holder, 1000);
        stop_cheat_caller_address(token_address);

        // Approve and burn zero
        start_cheat_caller_address(token_address, holder);
        token.approve(bridge, 0);
        stop_cheat_caller_address(token_address);

        start_cheat_caller_address(token_address, bridge);
        token.burn(holder, 0);
        stop_cheat_caller_address(token_address);

        assert(token.balance_of(holder) == 1000, 'Balance should be unchanged');
        assert(token.total_supply() == 1000, 'Supply should be unchanged');
    }

    #[test]
    fn test_get_bridge() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        assert(token.get_bridge() == bridge, 'Wrong bridge address');
    }

    #[test]
    #[should_panic(expected: ('Bridge cannot be zero address',))]
    fn test_constructor_zero_bridge_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let zero_address: ContractAddress = Zero::zero();

        let token_contract = declare("StrkBTC").unwrap().contract_class();
        let mut args: Array<felt252> = array![];
        args.append(owner.into());
        args.append(zero_address.into());
        let deploy_address: ContractAddress = 0x999.try_into().unwrap();
        token_contract.deploy_at(@args, deploy_address).unwrap_syscall();
    }

    #[test]
    #[should_panic(expected: ('ERC20: insufficient allowance',))]
    fn test_burn_without_approval_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let holder: ContractAddress = 'holder'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        // Mint first
        start_cheat_caller_address(token_address, bridge);
        token.mint(holder, 1000);

        // Try to burn without approval
        token.burn(holder, 500);
    }

    #[test]
    #[should_panic(expected: ('ERC20: insufficient allowance',))]
    fn test_burn_with_insufficient_approval_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let bridge: ContractAddress = 'bridge'.try_into().unwrap();
        let holder: ContractAddress = 'holder'.try_into().unwrap();

        let token_address = deploy_token(owner, bridge);
        let token = IStrkBTCDispatcher { contract_address: token_address };

        // Mint first
        start_cheat_caller_address(token_address, bridge);
        token.mint(holder, 1000);
        stop_cheat_caller_address(token_address);

        // Approve insufficient amount
        start_cheat_caller_address(token_address, holder);
        token.approve(bridge, 300);
        stop_cheat_caller_address(token_address);

        // Try to burn more than approved
        start_cheat_caller_address(token_address, bridge);
        token.burn(holder, 500);
    }
}
