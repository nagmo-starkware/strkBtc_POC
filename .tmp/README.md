# Incremental Test Files for Git Rebase

This directory contains 8 versions of test files, each matching the contract state at a specific commit.

## File Mapping

### Commit 4: `4a488b7` - Token contract (basic mint/burn, NO allowance check)
- `04-test_token.cairo` - Token tests without approval requirement
- `04-tests.cairo` - Module file (test_token only)

**Key characteristics:**
- `burn()` does NOT check allowance
- NO `approve()` function in interface
- NO `get_bridge()` function
- NO zero-address check in constructor

### Commit 5: `d83822b` - Token with allowance-based burn
- `05-test_token.cairo` - Updated token tests with approval flow

**Changes from commit 4:**
- `burn()` now requires holder to approve bridge first
- Adds `approve()` to interface
- Adds `get_bridge()` to interface
- Constructor validates bridge != zero address
- New tests: `test_burn_without_approval_fails`, `test_burn_with_insufficient_approval_fails`, `test_constructor_zero_bridge_fails`, `test_get_bridge`

### Commit 6: `069666c` - BridgeCore constructor only
- `06-test_bridge_core.cairo` - Constructor validation tests
- `06-tests.cairo` - Module file (test_token + test_bridge_core)

**Key characteristics:**
- NO `IBridgeCore` interface yet
- Only constructor tests (deployment panics)
- Tests use raw `declare().deploy()` pattern

### Commit 7: `9d6299b` - BridgeCore admin functions
- `07-test_bridge_core.cairo` - Admin function tests

**Adds `IBridgeCore` interface with:**
- `add_committee_member`, `remove_committee_member`
- `update_threshold`
- `add_btc_whitelist`, `remove_btc_whitelist`
- `add_starknet_whitelist`, `remove_starknet_whitelist`
- `update_minimum_withdrawal`

**Tests cover:**
- Committee management (add, remove, duplicates, threshold validation)
- Whitelist management (BTC and Starknet addresses)
- Minimum withdrawal updates
- Access control (only owner)

### Commit 8: `dde9712` - MinimumWithdrawalUpdated event
- `08-test_bridge_core.cairo` - Same as commit 7

**No test changes** - event emission is not testable without spy utilities.

### Commit 9: `3b2042f` - Deposit request with signature collection
- `09-test_bridge_core.cairo` - Adds deposit_request tests

**Adds to `IBridgeCore`:**
- `deposit_request(btc_tx_hash, starknet_address, amount)`

**New tests:**
- `test_deposit_request_single_signature` (below threshold)
- `test_deposit_request_already_processed_fails`
- `test_deposit_request_already_signed_fails`
- `test_deposit_request_non_committee_fails`
- `test_deposit_request_data_mismatch_fails`

**Note:** Integration test for threshold-reached minting would require deploying both token and bridge contracts.

### Commit 10: `65f722b` - Withdrawal flow and view functions
- `10-test_bridge_core.cairo` - Adds withdraw and view function tests

**Adds to `IBridgeCore`:**
- `withdraw(btc_address, amount)`
- View functions: `is_btc_whitelisted`, `is_starknet_whitelisted`, `is_committee_member`, `get_signature_threshold`, `get_committee_count`, `get_minimum_withdrawal`, `is_deposit_processed`, `get_deposit_signature_count`

**New tests:**
- `test_initial_state` (uses view functions)
- `test_view_committee_member`
- `test_view_btc_whitelist`
- `test_view_starknet_whitelist`
- `test_view_deposit_state`
- `test_withdraw_not_whitelisted_fails`
- `test_withdraw_below_minimum_fails`

### Commit 11: `0e33ef1` - Bridge registry for PSBT tracking
- `11-test_bridge_registry.cairo` - Registry tests
- `11-tests.cairo` - Module file (test_token + test_bridge_core + test_bridge_registry)

**New contract:** `BridgeRegistry`

**`IBridgeRegistry` interface:**
- `submit_psbt(tx_hash, psbt_data)`
- `get_signature_count(tx_hash)`
- `get_psbt(tx_hash)`
- `has_signed(tx_hash, signer)`
- `psbt_exists(tx_hash)`

**Tests:**
- `test_registry_deploys`
- View function tests (default state)
- Integration tests marked with `#[ignore]` (require BridgeCore deployment)

**Note:** Most registry tests require integration with BridgeCore because `submit_psbt` calls `bridge_core.is_committee_member()`. The standalone unit tests only cover view functions on empty state.

## Usage During Rebase

During `git rebase -i`, for each commit:

1. Edit the commit to stop for testing
2. Copy the appropriate test files:
   ```bash
   cp .tmp/XX-test_*.cairo contracts/tests/
   cp .tmp/XX-tests.cairo contracts/tests.cairo
   ```
3. Run tests: `scarb test`
4. If tests pass, continue rebase
5. If tests fail, fix the contract code to match the test expectations

## Notes

- All tests use `snforge_std` for test utilities
- Tests use short felt252 literals for addresses: `'owner'.try_into().unwrap()`
- Burn tests in commit 5+ require approval step before burning
- Some integration tests are marked `#[ignore]` where cross-contract setup is too complex for unit tests
- Event testing is not included (would require spy utilities)
