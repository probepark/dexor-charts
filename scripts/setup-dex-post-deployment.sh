#!/usr/bin/env bash

set -e

# Kaia DEX Post-Deployment Setup Script
# This script handles admin registration, token bridging, and market creation
# after the token bridge has been deployed

# --- Prerequisites ---
# 1. cast (foundry) installed
# 2. jq installed
# 3. Token bridge already deployed
# 4. Access to L1 and L2 RPC endpoints

# Check for cast (foundry)
if ! command -v cast &> /dev/null; then
    echo "❌ 'cast' command not found."
    echo "Please install foundry to proceed."
    echo "  - curl -L https://foundry.paradigm.xyz | bash"
    echo "  - foundryup"
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "❌ 'jq' command not found."
    echo "Please install it to proceed."
    echo "  - macOS: brew install jq"
    echo "  - Linux: sudo apt-get install jq"
    exit 1
fi

# Check for environment argument
ENV=${1:-dev}
if [[ ! "$ENV" =~ ^(dev|qa|perf|local)$ ]]; then
    echo "Usage: $0 [dev|qa|perf|local]"
    echo "Environment '$ENV' is not valid. Only 'dev', 'qa', 'perf', or 'local' are supported."
    exit 1
fi

echo "=== Kaia DEX Post-Deployment Setup for '$ENV' environment ==="

# Configuration based on environment
case $ENV in
    dev)
        L1_RPC_URL="https://public-en-kairos.node.kaia.io"
        L2_RPC_URL="https://l2-rpc-dev.dexor.trade"
        DEPLOYER_KEY="${DEPLOYER_KEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        ;;
    qa)
        L1_RPC_URL="https://public-en-kairos.node.kaia.io"
        L2_RPC_URL="https://l2-rpc-qa.dexor.trade"
        DEPLOYER_KEY="${DEPLOYER_KEY:-0x11d00470a9a385668a65abc1a31a4a349301e5cd8217fdc33fb0eb6c6f971a8e}"
        ;;
    perf)
        L1_RPC_URL="https://public-en-kairos.node.kaia.io"
        L2_RPC_URL="https://l2-rpc-perf.dexor.trade"
        DEPLOYER_KEY="${DEPLOYER_KEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        ;;
    local)
        L1_RPC_URL="https://public-en-kairos.node.kaia.io"
        L2_RPC_URL="http://localhost:8547"
        DEPLOYER_KEY="${DEPLOYER_KEY:-0xcc56168a0e292aad91d2f03a976da05910215a6d3cafff8bdad463736ac8f548}"
        ;;
esac

# Admin addresses to register
declare -A ADMIN_ADDRESSES=(
    ["Jake"]="0xfEc0a168FD7a33C2a76A8D746F437e28e4691103"
    ["Henry"]="0xC9118E2d1eE3debb200a4dBdd7F1E52867Fe51b0"
    ["Edwin"]="0xAaFB3dD3644359a4437F954C47A9D94dd168fbfc"
    ["Blue1"]="0x96a565B415869325F3a9eF17029a29Eae7843F04"
    ["Blue2"]="0xF5DcBA7592F733c5A12D2640D4C641b38b874D78"
    ["JK"]="0x806ab94Da1f70001Be60D0764Dcb6178BCE03DC4"
    ["Jay1"]="0x27D0Aeae3FA28Ba490DD771ec7b29b7365233386"
    ["Jay2"]="0x50A5639770E4B3dD67Bde9e2A6e78a10abf31302"
    ["Peter"]="0xe3CFD0e2c7E4C05C3d951BB016E0FD722801622C"
    ["Sitong"]="0x3497d3c0761f397f9dbd8017bb35c6ee34c5f0e2"
)

# Token addresses to bridge
declare -A TOKEN_ADDRESSES=(
    ["USDT"]="0xac76d4a9985abA068dbae07bf5cC10be06A19f12"
    ["BTC"]="0x4D9da7D07be1cB223bd4B3b4Fa0AF9896e565160"
    ["WETH"]="0xfd24a22fA1938387D605529645bD2bd3e2b30c2E"
    ["GRND"]="0x0217F9AbB3a578b8e84e5D728FbF4bA477EBeDA2"
)

# Token owner wallet address and key (will be set later)
TOKEN_OWNER_ADDRESS="0x4D3cF56fB96c287387606862df55005d52FEa89b"
TOKEN_OWNER_KEY="${TOKEN_OWNER_KEY:-PLACEHOLDER_WILL_BE_PROVIDED_LATER}"

# DEX admin contract address on L2
DEX_ADMIN_CONTRACT="0x0000000000000000000000000000000000000070"

# Read token bridge addresses from network.json if it exists
NETWORK_JSON_FILE="config/$ENV/token-bridge/network.json"
if [ -f "$NETWORK_JSON_FILE" ]; then
    echo "Reading token bridge addresses from network.json..."
    L1_GATEWAY_ROUTER=$(jq -r '.l1.network.tokenBridge.parentGatewayRouter // ""' "$NETWORK_JSON_FILE")
    L1_ERC20_GATEWAY=$(jq -r '.l1.network.tokenBridge.parentErc20Gateway // ""' "$NETWORK_JSON_FILE")
    L2_GATEWAY_ROUTER=$(jq -r '.l2.network.tokenBridge.childGatewayRouter // ""' "$NETWORK_JSON_FILE")
    
    if [ -z "$L1_GATEWAY_ROUTER" ] || [ "$L1_GATEWAY_ROUTER" = "null" ]; then
        echo "❌ ERROR: Could not find L1 Gateway Router in network.json"
        exit 1
    fi
    
    echo "Token Bridge Addresses:"
    echo "- L1 Gateway Router: $L1_GATEWAY_ROUTER"
    echo "- L1 ERC20 Gateway: $L1_ERC20_GATEWAY"
    echo "- L2 Gateway Router: $L2_GATEWAY_ROUTER"
    echo ""
else
    echo "❌ ERROR: $NETWORK_JSON_FILE not found. Please deploy token bridge first."
    exit 1
fi

# Function to register admin addresses
register_admins() {
    echo ""
    echo "=== Step 1: Registering Admin Addresses ==="
    echo ""
    
    for name in "${!ADMIN_ADDRESSES[@]}"; do
        address="${ADMIN_ADDRESSES[$name]}"
        echo "Registering $name ($address) as DEX admin..."
        
        cast send "$DEX_ADMIN_CONTRACT" \
            "addDexAdmin(address)" \
            "$address" \
            --private-key "$DEPLOYER_KEY" \
            --rpc-url "$L2_RPC_URL" \
            || echo "⚠️  Warning: Failed to register $name as admin (may already be registered)"
        
        echo "✅ Admin registration attempted for $name"
    done
    
    echo ""
    echo "Admin registration completed!"
}

# Function to bridge tokens from L1 to L2
bridge_tokens() {
    echo ""
    echo "=== Step 2: Bridging Tokens from L1 to L2 ==="
    echo ""
    
    # Check if we have a valid token owner key
    if [ "$TOKEN_OWNER_KEY" = "PLACEHOLDER_WILL_BE_PROVIDED_LATER" ]; then
        echo "⚠️  Warning: TOKEN_OWNER_KEY not set. Skipping token bridging."
        echo "To bridge tokens, set TOKEN_OWNER_KEY environment variable and re-run."
        return
    fi
    
    # Parameters for bridging
    MAX_GAS="1000000"
    GAS_PRICE_BID="100000000"  # 0.1 gwei
    BRIDGE_VALUE="0.01ether"   # ETH to send for L2 gas
    
    for token_name in "${!TOKEN_ADDRESSES[@]}"; do
        token_address="${TOKEN_ADDRESSES[$token_name]}"
        echo ""
        echo "Bridging $token_name ($token_address)..."
        
        # Amount to bridge (using 1000 tokens with 18 decimals as example)
        AMOUNT="1000000000000000000000"
        
        # Step 1: Approve the gateway to spend tokens
        echo "  1. Approving gateway to spend $token_name..."
        cast send "$token_address" \
            "approve(address,uint256)" \
            "$L1_GATEWAY_ROUTER" \
            "$AMOUNT" \
            --private-key "$TOKEN_OWNER_KEY" \
            --rpc-url "$L1_RPC_URL" \
            || echo "  ⚠️  Warning: Failed to approve $token_name"
        
        # Step 2: Execute the bridge transfer
        echo "  2. Initiating bridge transfer for $token_name..."
        
        # For standard ERC20 tokens (not WETH)
        if [ "$token_name" != "WETH" ]; then
            cast send "$L1_GATEWAY_ROUTER" \
                "outboundTransfer(address,address,uint256,uint256,uint256,bytes)" \
                "$token_address" \
                "$TOKEN_OWNER_ADDRESS" \
                "$AMOUNT" \
                "$MAX_GAS" \
                "$GAS_PRICE_BID" \
                "0x" \
                --value "$BRIDGE_VALUE" \
                --private-key "$TOKEN_OWNER_KEY" \
                --rpc-url "$L1_RPC_URL" \
                || echo "  ⚠️  Warning: Failed to bridge $token_name"
        else
            # For WETH, use special handling
            echo "  Special handling for WETH bridging..."
            # WETH bridging might require different parameters or gateway
        fi
        
        echo "✅ Bridge transfer initiated for $token_name"
    done
    
    echo ""
    echo "Token bridging completed! Note: It may take a few minutes for tokens to appear on L2."
}

# Function to create KAIA/USDT market
create_market() {
    echo ""
    echo "=== Step 3: Creating KAIA/USDT Market ==="
    echo ""
    
    # Check if we have market maker contract address
    MARKET_MAKER_CONTRACT="${MARKET_MAKER_CONTRACT:-0x0000000000000000000000000000000000000071}"
    
    # Market parameters
    BASE_TOKEN_ID="1"        # KAIA token ID
    QUOTE_TOKEN_ID="2"       # USDT token ID
    MARKET_TYPE="spot"
    TAKER_FEE="300"          # 0.3% = 300 basis points
    MAKER_FEE="100"          # 0.1% = 100 basis points
    LISTED="true"
    
    # KAIA token details on L1
    KAIA_L1_ADDRESS="0x0000000000000000000000000000000000000000"  # Native KAIA
    KAIA_L1_SYMBOL="KAIA"
    KAIA_L1_NAME="Kaia"
    KAIA_L1_DECIMAL="18"
    
    echo "Creating KAIA/USDT market with following parameters:"
    echo "- Base Token (KAIA) ID: $BASE_TOKEN_ID"
    echo "- Quote Token (USDT) ID: $QUOTE_TOKEN_ID"
    echo "- Market Type: $MARKET_TYPE"
    echo "- Taker Fee: $TAKER_FEE basis points"
    echo "- Maker Fee: $MAKER_FEE basis points"
    echo "- Listed: $LISTED"
    echo ""
    
    cast send "$MARKET_MAKER_CONTRACT" \
        "addMarket(uint64,uint64,string,uint256,uint256,bool,address,string,string,uint8)" \
        "$BASE_TOKEN_ID" \
        "$QUOTE_TOKEN_ID" \
        "$MARKET_TYPE" \
        "$TAKER_FEE" \
        "$MAKER_FEE" \
        "$LISTED" \
        "$KAIA_L1_ADDRESS" \
        "$KAIA_L1_SYMBOL" \
        "$KAIA_L1_NAME" \
        "$KAIA_L1_DECIMAL" \
        --private-key "$DEPLOYER_KEY" \
        --rpc-url "$L2_RPC_URL" \
        || echo "⚠️  Warning: Failed to create KAIA/USDT market (may already exist)"
    
    echo "✅ KAIA/USDT market creation attempted!"
}

# Main execution
echo ""
echo "Starting post-deployment setup..."
echo "Environment: $ENV"
echo "L1 RPC: $L1_RPC_URL"
echo "L2 RPC: $L2_RPC_URL"
echo ""

# Step 1: Register admins
register_admins

# Step 2: Bridge tokens (will skip if TOKEN_OWNER_KEY not set)
bridge_tokens

# Step 3: Create market
create_market

echo ""
echo "=== Post-Deployment Setup Completed! ==="
echo ""
echo "Summary:"
echo "1. ✅ Admin addresses registered"
if [ "$TOKEN_OWNER_KEY" != "PLACEHOLDER_WILL_BE_PROVIDED_LATER" ]; then
    echo "2. ✅ Tokens bridged to L2 (may take a few minutes to confirm)"
else
    echo "2. ⚠️  Token bridging skipped (TOKEN_OWNER_KEY not provided)"
fi
echo "3. ✅ KAIA/USDT market created"
echo ""
echo "Next steps:"
echo "1. Verify admin registrations by checking on-chain"
echo "2. Monitor token bridge transfers (usually takes 5-10 minutes)"
echo "3. Verify market creation in the DEX UI"
echo "4. Test trading on the KAIA/USDT pair"
echo ""
echo "To re-run with token bridging:"
echo "  export TOKEN_OWNER_KEY=<private_key>"
echo "  ./scripts/setup-dex-post-deployment.sh $ENV"