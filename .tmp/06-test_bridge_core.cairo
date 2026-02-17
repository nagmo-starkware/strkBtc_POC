#[cfg(test)]
mod tests {
    use starknet::ContractAddress;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

    // No IBridgeCore interface yet - only constructor tests

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

        // Just verify it deployed (non-zero address)
        assert(bridge_address.into() != 0, 'Deployment failed');
    }

    #[test]
    #[should_panic(expected: ('Token cannot be zero address',))]
    fn test_constructor_zero_token_fails() {
        let owner: ContractAddress = 'owner'.try_into().unwrap();
        let zero_address: ContractAddress = 0.try_into().unwrap();
        let registry: ContractAddress = 'registry'.try_into().unwrap();

        deploy_bridge(
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
        let zero_address: ContractAddress = 0.try_into().unwrap();

        deploy_bridge(
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

        deploy_bridge(
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

        deploy_bridge(
            owner,
            token,
            registry,
            2,
            0
        );
    }
}
