#!/bin/bash

# BTC Bridge Deployment Script — TEMPLATE
#
# ⚠ WARNING: This is a deployment template. All starkli commands are commented out.
# Uncomment and configure before use.
#
# Usage:
#   ./scripts/deploy.sh [testnet|mainnet]
#
# Prerequisites:
#   - starkli CLI installed
#   - Scarb installed and contracts built
#   - Account deployed and funded on target network
#
# Environment variables:
#   STARKNET_RPC       - RPC endpoint URL
#   STARKNET_ACCOUNT   - Account address
#   STARKNET_KEYSTORE  - Path to keystore file
#   OWNER_ADDRESS      - Address that will own the contracts

set -eu  # Exit on error or undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored message
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if network argument is provided
if [ -z "$1" ]; then
    print_error "Network argument required: testnet or mainnet"
    echo "Usage: $0 [testnet|mainnet]"
    exit 1
fi

NETWORK=$1

# Validate network
if [ "$NETWORK" != "testnet" ] && [ "$NETWORK" != "mainnet" ]; then
    print_error "Invalid network: $NETWORK. Must be 'testnet' or 'mainnet'"
    exit 1
fi

print_info "Deploying to: $NETWORK"

# Check required environment variables
if [ -z "$STARKNET_RPC" ]; then
    print_error "STARKNET_RPC environment variable not set"
    exit 1
fi

if [ -z "$STARKNET_ACCOUNT" ]; then
    print_error "STARKNET_ACCOUNT environment variable not set"
    exit 1
fi

if [ -z "$STARKNET_KEYSTORE" ]; then
    print_error "STARKNET_KEYSTORE environment variable not set"
    exit 1
fi

if [ -z "$OWNER_ADDRESS" ]; then
    print_warn "OWNER_ADDRESS not set, using STARKNET_ACCOUNT as owner"
    OWNER_ADDRESS=$STARKNET_ACCOUNT
fi

print_info "Configuration:"
echo "  RPC: $STARKNET_RPC"
echo "  Account: $STARKNET_ACCOUNT"
echo "  Owner: $OWNER_ADDRESS"
echo ""

# Confirm before proceeding
read -p "Continue with deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Deployment cancelled"
    exit 0
fi

# Build contracts
print_info "Building contracts..."
cd "$(dirname "$0")/.."
scarb build

if [ $? -ne 0 ]; then
    print_error "Build failed"
    exit 1
fi

print_info "Build successful"
echo ""

# Check for build artifacts
TOKEN_ARTIFACT="target/dev/btc_bridge_StrkBTC.contract_class.json"
BRIDGE_ARTIFACT="target/dev/btc_bridge_BridgeCore.contract_class.json"
REGISTRY_ARTIFACT="target/dev/btc_bridge_BridgeRegistry.contract_class.json"

if [ ! -f "$TOKEN_ARTIFACT" ]; then
    print_error "Token artifact not found: $TOKEN_ARTIFACT"
    exit 1
fi

if [ ! -f "$BRIDGE_ARTIFACT" ]; then
    print_error "Bridge artifact not found: $BRIDGE_ARTIFACT"
    exit 1
fi

if [ ! -f "$REGISTRY_ARTIFACT" ]; then
    print_error "Registry artifact not found: $REGISTRY_ARTIFACT"
    exit 1
fi

print_info "All artifacts found"
echo ""

# Deployment output file
OUTPUT_FILE="deployments/${NETWORK}_$(date +%Y%m%d_%H%M%S).json"
mkdir -p deployments

echo "{" > $OUTPUT_FILE
echo "  \"network\": \"$NETWORK\"," >> $OUTPUT_FILE
echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> $OUTPUT_FILE
echo "  \"deployer\": \"$STARKNET_ACCOUNT\"," >> $OUTPUT_FILE
echo "  \"owner\": \"$OWNER_ADDRESS\"," >> $OUTPUT_FILE

#
# Step 1: Declare StrkBTC Token
#
print_info "Step 1: Declaring StrkBTC Token contract..."

# TODO: Uncomment and run actual declaration
# TOKEN_CLASS_HASH=$(starkli declare $TOKEN_ARTIFACT \
#     --account $STARKNET_ACCOUNT \
#     --keystore $STARKNET_KEYSTORE \
#     --rpc $STARKNET_RPC \
#     | grep -oP '(?<=Class hash declared: )0x[0-9a-fA-F]+')

# Placeholder - replace with actual class hash after declaration
TOKEN_CLASS_HASH="0x0000000000000000000000000000000000000000000000000000000000000000"

print_info "Token class hash: $TOKEN_CLASS_HASH"
echo "  \"token_class_hash\": \"$TOKEN_CLASS_HASH\"," >> $OUTPUT_FILE

#
# Step 2: Deploy StrkBTC Token
#
print_info "Step 2: Deploying StrkBTC Token..."
print_info "Constructor args: owner=$OWNER_ADDRESS, bridge=0x0 (will be set later)"

# TODO: Uncomment and run actual deployment
# TOKEN_ADDRESS=$(starkli deploy $TOKEN_CLASS_HASH \
#     $OWNER_ADDRESS \
#     0x0 \
#     --account $STARKNET_ACCOUNT \
#     --keystore $STARKNET_KEYSTORE \
#     --rpc $STARKNET_RPC \
#     | grep -oP '(?<=Contract deployed: )0x[0-9a-fA-F]+')

# Placeholder - replace with actual address after deployment
TOKEN_ADDRESS="0x0000000000000000000000000000000000000000000000000000000000000000"

print_info "Token deployed at: $TOKEN_ADDRESS"
echo "  \"token_address\": \"$TOKEN_ADDRESS\"," >> $OUTPUT_FILE
echo ""

#
# Step 3: Declare Bridge Core
#
print_info "Step 3: Declaring Bridge Core contract..."

# TODO: Uncomment and run actual declaration
# BRIDGE_CLASS_HASH=$(starkli declare $BRIDGE_ARTIFACT \
#     --account $STARKNET_ACCOUNT \
#     --keystore $STARKNET_KEYSTORE \
#     --rpc $STARKNET_RPC \
#     | grep -oP '(?<=Class hash declared: )0x[0-9a-fA-F]+')

# Placeholder
BRIDGE_CLASS_HASH="0x0000000000000000000000000000000000000000000000000000000000000000"

print_info "Bridge class hash: $BRIDGE_CLASS_HASH"
echo "  \"bridge_class_hash\": \"$BRIDGE_CLASS_HASH\"," >> $OUTPUT_FILE

#
# Step 4: Deploy Bridge Core
#
print_info "Step 4: Deploying Bridge Core..."
print_info "Constructor args: owner=$OWNER_ADDRESS, token=$TOKEN_ADDRESS, threshold=2"

# TODO: Uncomment and run actual deployment
# BRIDGE_ADDRESS=$(starkli deploy $BRIDGE_CLASS_HASH \
#     $OWNER_ADDRESS \
#     $TOKEN_ADDRESS \
#     2 \
#     --account $STARKNET_ACCOUNT \
#     --keystore $STARKNET_KEYSTORE \
#     --rpc $STARKNET_RPC \
#     | grep -oP '(?<=Contract deployed: )0x[0-9a-fA-F]+')

# Placeholder
BRIDGE_ADDRESS="0x0000000000000000000000000000000000000000000000000000000000000000"

print_info "Bridge Core deployed at: $BRIDGE_ADDRESS"
echo "  \"bridge_address\": \"$BRIDGE_ADDRESS\"," >> $OUTPUT_FILE
echo ""

#
# Step 5: Declare Bridge Registry
#
print_info "Step 5: Declaring Bridge Registry contract..."

# TODO: Uncomment and run actual declaration
# REGISTRY_CLASS_HASH=$(starkli declare $REGISTRY_ARTIFACT \
#     --account $STARKNET_ACCOUNT \
#     --keystore $STARKNET_KEYSTORE \
#     --rpc $STARKNET_RPC \
#     | grep -oP '(?<=Class hash declared: )0x[0-9a-fA-F]+')

# Placeholder
REGISTRY_CLASS_HASH="0x0000000000000000000000000000000000000000000000000000000000000000"

print_info "Registry class hash: $REGISTRY_CLASS_HASH"
echo "  \"registry_class_hash\": \"$REGISTRY_CLASS_HASH\"," >> $OUTPUT_FILE

#
# Step 6: Deploy Bridge Registry
#
print_info "Step 6: Deploying Bridge Registry..."
print_info "Constructor args: bridge_core=$BRIDGE_ADDRESS"

# TODO: Uncomment and run actual deployment
# REGISTRY_ADDRESS=$(starkli deploy $REGISTRY_CLASS_HASH \
#     $BRIDGE_ADDRESS \
#     --account $STARKNET_ACCOUNT \
#     --keystore $STARKNET_KEYSTORE \
#     --rpc $STARKNET_RPC \
#     | grep -oP '(?<=Contract deployed: )0x[0-9a-fA-F]+')

# Placeholder
REGISTRY_ADDRESS="0x0000000000000000000000000000000000000000000000000000000000000000"

print_info "Bridge Registry deployed at: $REGISTRY_ADDRESS"
echo "  \"registry_address\": \"$REGISTRY_ADDRESS\"" >> $OUTPUT_FILE
echo "}" >> $OUTPUT_FILE
echo ""

#
# Step 7: Link Token to Bridge
#
print_info "Step 7: Linking token to bridge..."

# TODO: Uncomment and run actual invocation
# starkli invoke $TOKEN_ADDRESS set_bridge_address $BRIDGE_ADDRESS \
#     --account $STARKNET_ACCOUNT \
#     --keystore $STARKNET_KEYSTORE \
#     --rpc $STARKNET_RPC

print_info "Token linked to bridge"
echo ""

#
# Deployment Complete
#
print_info "================================================"
print_info "Deployment complete!"
print_info "================================================"
echo ""
echo "Contract Addresses:"
echo "  Token (StrkBTC):   $TOKEN_ADDRESS"
echo "  Bridge Core:       $BRIDGE_ADDRESS"
echo "  Bridge Registry:   $REGISTRY_ADDRESS"
echo ""
echo "Deployment details saved to: $OUTPUT_FILE"
echo ""
print_warn "Next steps:"
echo "  1. Add committee members: starkli invoke $BRIDGE_ADDRESS add_committee_member <member>"
echo "  2. Whitelist BTC addresses: starkli invoke $BRIDGE_ADDRESS add_btc_whitelist <address>"
echo "  3. Whitelist Starknet addresses: starkli invoke $BRIDGE_ADDRESS add_starknet_whitelist <address>"
echo "  4. Set minimum withdrawal (optional): starkli invoke $BRIDGE_ADDRESS update_minimum_withdrawal <amount>"
echo ""
print_info "See README.md for detailed configuration instructions"
