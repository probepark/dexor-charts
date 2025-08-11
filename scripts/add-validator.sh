#!/usr/bin/env bash

set -e

# Kaia Orderbook DEX - Validator Management Script
# This script adds or removes validators from the rollup contract

# --- Prerequisites ---
# 1. Foundry (cast) - Install: curl -L https://foundry.paradigm.xyz | bash
# 2. Access to deployer private key with UpgradeExecutor permissions

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check for required tools
check_requirements() {
    if ! command -v cast &> /dev/null; then
        print_color "$RED" "❌ 'cast' command not found."
        echo "Please install Foundry to proceed:"
        echo "  curl -L https://foundry.paradigm.xyz | bash"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_color "$RED" "❌ 'jq' command not found."
        echo "Please install jq to proceed:"
        echo "  - macOS: brew install jq"
        echo "  - Linux: sudo apt-get install jq"
        exit 1
    fi
}

# Show usage
usage() {
    echo "Usage: $0 [ENVIRONMENT] [ACTION] [VALIDATOR_ADDRESS]"
    echo ""
    echo "ENVIRONMENT:"
    echo "  dev    - Development environment"
    echo "  qa     - QA environment"
    echo "  perf   - Performance environment"
    echo "  local  - Local environment"
    echo ""
    echo "ACTION:"
    echo "  add    - Add validator"
    echo "  remove - Remove validator"
    echo "  check  - Check validator status"
    echo "  list   - List all known validators"
    echo ""
    echo "VALIDATOR_ADDRESS: (optional)"
    echo "  Ethereum address of the validator"
    echo "  If not provided, uses default validator for the environment"
    echo ""
    echo "Examples:"
    echo "  $0 dev add                    # Add default dev validator"
    echo "  $0 perf check                  # Check perf validator status"
    echo "  $0 qa add 0x1234...5678        # Add custom validator to QA"
    echo "  $0 dev remove                  # Remove dev validator"
    exit 1
}

# Check arguments
if [ $# -lt 2 ]; then
    usage
fi

ENV=$1
ACTION=$2
CUSTOM_VALIDATOR=$3

# Validate environment
if [[ ! "$ENV" =~ ^(dev|qa|perf|local)$ ]]; then
    print_color "$RED" "❌ Invalid environment: $ENV"
    usage
fi

# Validate action
if [[ ! "$ACTION" =~ ^(add|remove|check|list)$ ]]; then
    print_color "$RED" "❌ Invalid action: $ACTION"
    usage
fi

# Check requirements
check_requirements

# Configuration
KAIROS_RPC_URL="https://public-en-kairos.node.kaia.io"

# Load environment-specific configuration
case $ENV in
    dev)
        DEPLOYER_PRIVKEY="${DEPLOYER_PRIVKEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        DEFAULT_VALIDATOR="0x03C6FcED478cBbC9a4FAB34eF9f40767739D1Ff7"
        CONFIG_FILE="config/dev/deployed_chain_info.json"
        ;;
    qa)
        DEPLOYER_PRIVKEY="${DEPLOYER_PRIVKEY:-0x11d00470a9a385668a65abc1a31a4a349301e5cd8217fdc33fb0eb6c6f971a8e}"
        DEFAULT_VALIDATOR="0xfDA64D91f24107Ba1747510D062cBf0fB87238C3"
        CONFIG_FILE="config/qa/deployed_chain_info.json"
        ;;
    perf)
        DEPLOYER_PRIVKEY="${DEPLOYER_PRIVKEY:-0x25c4b8e9afe2ff43f27e370087ad842443259734d758b9021ae368415b92a723}"
        DEFAULT_VALIDATOR="0x1EeFeB1fE3050E0555C1a73aF913AAA7A5E65187"
        CONFIG_FILE="config/perf/deployed_chain_info.json"
        ;;
    local)
        DEPLOYER_PRIVKEY="${DEPLOYER_PRIVKEY:-0xcc56168a0e292aad91d2f03a976da05910215a6d3cafff8bdad463736ac8f548}"
        DEFAULT_VALIDATOR="0x1b4cc087207149A84A9B062D2EB90a1a5cc5B308"
        CONFIG_FILE="config/local/deployed_chain_info.json"
        ;;
esac

# Use custom validator if provided, otherwise use default
VALIDATOR_ADDRESS=${CUSTOM_VALIDATOR:-$DEFAULT_VALIDATOR}

# Load deployment info
if [ ! -f "$CONFIG_FILE" ]; then
    print_color "$RED" "❌ Deployment info not found: $CONFIG_FILE"
    echo "Please run the deployment script first: ./scripts/deploy-to-kairos.sh $ENV"
    exit 1
fi

# Extract contract addresses
ROLLUP_ADDRESS=$(jq -r '.[0]."rollup"."rollup"' "$CONFIG_FILE")
UPGRADE_EXECUTOR_ADDRESS=$(jq -r '.[0]."rollup"."upgrade-executor"' "$CONFIG_FILE")

if [ -z "$ROLLUP_ADDRESS" ] || [ "$ROLLUP_ADDRESS" = "null" ]; then
    print_color "$RED" "❌ Failed to extract rollup address from deployment info"
    exit 1
fi

if [ -z "$UPGRADE_EXECUTOR_ADDRESS" ] || [ "$UPGRADE_EXECUTOR_ADDRESS" = "null" ]; then
    print_color "$RED" "❌ Failed to extract UpgradeExecutor address from deployment info"
    exit 1
fi

# Print configuration
echo "=== Validator Management for $ENV Environment ==="
echo "RPC URL: $KAIROS_RPC_URL"
echo "Rollup: $ROLLUP_ADDRESS"
echo "UpgradeExecutor: $UPGRADE_EXECUTOR_ADDRESS"
echo "Validator: $VALIDATOR_ADDRESS"
echo ""

# Function to check validator status
check_validator() {
    local address=$1
    local status=$(cast call "$ROLLUP_ADDRESS" \
        "isValidator(address)(bool)" \
        "$address" \
        --rpc-url "$KAIROS_RPC_URL" 2>/dev/null || echo "error")
    
    if [ "$status" = "true" ]; then
        print_color "$GREEN" "✅ $address is a validator"
        return 0
    elif [ "$status" = "false" ]; then
        print_color "$YELLOW" "⚠️  $address is NOT a validator"
        return 1
    else
        print_color "$RED" "❌ Failed to check validator status"
        return 2
    fi
}

# Function to add validator
add_validator() {
    local address=$1
    
    print_color "$GREEN" "Adding validator: $address"
    
    # Check deployer balance first
    DEPLOYER_ADDRESS=$(cast wallet address --private-key "$DEPLOYER_PRIVKEY" 2>/dev/null)
    BALANCE=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$KAIROS_RPC_URL" 2>/dev/null || echo "0")
    BALANCE_ETH=$(cast to-unit "$BALANCE" ether 2>/dev/null || echo "0")
    
    print_color "$YELLOW" "Deployer: $DEPLOYER_ADDRESS"
    print_color "$YELLOW" "Balance: $BALANCE_ETH KAIA"
    
    # Check if balance is sufficient (need at least 0.1 KAIA for gas)
    MIN_BALANCE="100000000000000000" # 0.1 KAIA in wei
    if [ "$(echo "$BALANCE < $MIN_BALANCE" | bc)" = "1" ]; then
        print_color "$RED" "❌ Insufficient balance for gas fees"
        echo "Please fund the deployer account with at least 0.1 KAIA:"
        echo "  Address: $DEPLOYER_ADDRESS"
        echo "  Current balance: $BALANCE_ETH KAIA"
        echo "  Required: At least 0.1 KAIA"
        echo ""
        echo "You can get test KAIA from:"
        echo "  https://faucet.kaia.io/"
        exit 1
    fi
    
    # Check if already validator
    if check_validator "$address"; then
        print_color "$YELLOW" "Already a validator, no action needed"
        return 0
    fi
    
    # Encode the setValidator function call with function selector
    print_color "$YELLOW" "Encoding setValidator call..."
    CALLDATA=$(cast calldata "setValidator(address[],bool[])" \
        "[$address]" \
        "[true]")
    
    # Debug: Print the calldata
    echo "Calldata: $CALLDATA"
    
    # Create the execute call for UpgradeExecutor
    print_color "$YELLOW" "Preparing UpgradeExecutor transaction..."
    
    # Send transaction through UpgradeExecutor
    print_color "$YELLOW" "Sending transaction..."
    
    # Use proper execute function
    echo "Executing through UpgradeExecutor at $UPGRADE_EXECUTOR_ADDRESS"
    echo "Target contract: $ROLLUP_ADDRESS"
    
    TX_OUTPUT=$(cast send "$UPGRADE_EXECUTOR_ADDRESS" \
        "executeCall(address,bytes)" \
        "$ROLLUP_ADDRESS" \
        "$CALLDATA" \
        --private-key "$DEPLOYER_PRIVKEY" \
        --rpc-url "$KAIROS_RPC_URL" \
        --gas-price 250000000000 \
        --gas-limit 500000 \
        --legacy \
        2>&1)
    
    # Check for errors in output
    if echo "$TX_OUTPUT" | grep -q "Error\|error\|revert\|failed"; then
        print_color "$RED" "❌ Transaction failed"
        echo "Error details:"
        echo "$TX_OUTPUT"
        
        # Try to extract specific error
        if echo "$TX_OUTPUT" | grep -q "insufficient funds"; then
            echo "Insufficient funds for transaction. Check account balance."
        elif echo "$TX_OUTPUT" | grep -q "gas too low"; then
            echo "Gas limit too low. Try increasing gas limit."
        elif echo "$TX_OUTPUT" | grep -q "execution reverted"; then
            echo "Contract execution reverted. Check permissions and parameters."
        fi
        exit 1
    fi
    
    # Extract transaction hash
    TX_HASH=$(echo "$TX_OUTPUT" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
    
    if [ -n "$TX_HASH" ]; then
        print_color "$GREEN" "Transaction sent: $TX_HASH"
        echo "Waiting for confirmation..."
        sleep 10
        
        # Verify validator was added
        if check_validator "$address"; then
            print_color "$GREEN" "🎉 Successfully added validator!"
        else
            print_color "$YELLOW" "⚠️  Validator addition may still be pending. Check transaction:"
            echo "https://kairos.kaiascan.io/tx/$TX_HASH"
        fi
    else
        print_color "$RED" "❌ Failed to extract transaction hash"
        echo "Full output:"
        echo "$TX_OUTPUT"
        exit 1
    fi
}

# Function to remove validator
remove_validator() {
    local address=$1
    
    print_color "$YELLOW" "Removing validator: $address"
    
    # Check deployer balance first
    DEPLOYER_ADDRESS=$(cast wallet address --private-key "$DEPLOYER_PRIVKEY" 2>/dev/null)
    BALANCE=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$KAIROS_RPC_URL" 2>/dev/null || echo "0")
    BALANCE_ETH=$(cast to-unit "$BALANCE" ether 2>/dev/null || echo "0")
    
    print_color "$YELLOW" "Deployer: $DEPLOYER_ADDRESS"
    print_color "$YELLOW" "Balance: $BALANCE_ETH KAIA"
    
    # Check if balance is sufficient (need at least 0.1 KAIA for gas)
    MIN_BALANCE="100000000000000000" # 0.1 KAIA in wei
    if [ "$(echo "$BALANCE < $MIN_BALANCE" | bc)" = "1" ]; then
        print_color "$RED" "❌ Insufficient balance for gas fees"
        echo "Please fund the deployer account with at least 0.1 KAIA:"
        echo "  Address: $DEPLOYER_ADDRESS"
        echo "  Current balance: $BALANCE_ETH KAIA"
        echo "  Required: At least 0.1 KAIA"
        echo ""
        echo "You can get test KAIA from:"
        echo "  https://faucet.kaia.io/"
        exit 1
    fi
    
    # Check if currently a validator
    if ! check_validator "$address"; then
        print_color "$YELLOW" "Not a validator, no action needed"
        return 0
    fi
    
    # Encode the setValidator function call with function selector (with false to remove)
    print_color "$YELLOW" "Encoding setValidator call..."
    CALLDATA=$(cast calldata "setValidator(address[],bool[])" \
        "[$address]" \
        "[false]")
    
    # Debug: Print the calldata
    echo "Calldata: $CALLDATA"
    
    # Send transaction through UpgradeExecutor
    print_color "$YELLOW" "Sending transaction..."
    
    # Use proper execute function
    echo "Executing through UpgradeExecutor at $UPGRADE_EXECUTOR_ADDRESS"
    echo "Target contract: $ROLLUP_ADDRESS"
    
    TX_OUTPUT=$(cast send "$UPGRADE_EXECUTOR_ADDRESS" \
        "executeCall(address,bytes)" \
        "$ROLLUP_ADDRESS" \
        "$CALLDATA" \
        --private-key "$DEPLOYER_PRIVKEY" \
        --rpc-url "$KAIROS_RPC_URL" \
        --gas-price 250000000000 \
        --gas-limit 500000 \
        --legacy \
        2>&1)
    
    # Extract transaction hash
    TX_HASH=$(echo "$TX_OUTPUT" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
    
    if [ -n "$TX_HASH" ]; then
        print_color "$GREEN" "Transaction sent: $TX_HASH"
        echo "Waiting for confirmation..."
        sleep 10
        
        # Verify validator was removed
        if ! check_validator "$address"; then
            print_color "$GREEN" "✅ Successfully removed validator!"
        else
            print_color "$RED" "❌ Validator removal may have failed. Please check transaction."
        fi
    else
        print_color "$RED" "❌ Failed to send transaction"
        echo "Error output:"
        echo "$TX_OUTPUT"
        exit 1
    fi
}

# Function to list all validators
list_validators() {
    echo "=== Known Validators for All Environments ==="
    echo ""
    echo "Dev Environment:"
    echo "  Deployer: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
    echo "  Validator: 0x03C6FcED478cBbC9a4FAB34eF9f40767739D1Ff7"
    echo ""
    echo "QA Environment:"
    echo "  Deployer: 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f"
    echo "  Validator: 0xfDA64D91f24107Ba1747510D062cBf0fB87238C3"
    echo ""
    echo "Perf Environment:"
    echo "  Deployer: 0x34844E6c6C60b590eE54AC5A9183526Eaf376fa6"
    echo "  Validator: 0x1EeFeB1fE3050E0555C1a73aF913AAA7A5E65187"
    echo ""
    echo "Local Environment:"
    echo "  Deployer: 0xEe5FB80d84D389E35867092ed7A2d0aa5A7A207a"
    echo "  Validator: 0x1b4cc087207149A84A9B062D2EB90a1a5cc5B308"
    echo ""
    
    # Check current environment validators
    if [ -n "$ROLLUP_ADDRESS" ] && [ "$ROLLUP_ADDRESS" != "null" ]; then
        echo "=== Current Status for $ENV Environment ==="
        check_validator "$VALIDATOR_ADDRESS"
    fi
}

# Execute action
case $ACTION in
    add)
        add_validator "$VALIDATOR_ADDRESS"
        ;;
    remove)
        remove_validator "$VALIDATOR_ADDRESS"
        ;;
    check)
        check_validator "$VALIDATOR_ADDRESS"
        ;;
    list)
        list_validators
        ;;
esac

echo ""
print_color "$GREEN" "=== Operation Complete ==="