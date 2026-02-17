#[cfg(test)]
mod tests {
    use starknet::ContractAddress;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};

    // Minimal interface for commit 4 - NO approve, NO get_bridge
    #[starknet::interface]
    trait IStrkBTC<TContractState> {
        fn name(self: @TContractState) -> ByteArray;
        fn symbol(self: @TContractState) -> ByteArray;
        fn total_supply(self: @TContractState) -> u256;
        fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
        fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
        fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
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

        // Burn directly (NO approve needed at this commit)
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

        // Burn entire balance (NO approve needed)
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

        // Burn zero (NO approve needed)
        token.burn(holder, 0);
        stop_cheat_caller_address(token_address);

        assert(token.balance_of(holder) == 1000, 'Balance should be unchanged');
        assert(token.total_supply() == 1000, 'Supply should be unchanged');
    }
}
