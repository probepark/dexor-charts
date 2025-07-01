#!/usr/bin/env bash

set -e

# Token Bridge Address Generation Script
# This script generates deterministic token bridge addresses based on the rollup address

# Check for environment argument
ENV=${1:-dev}
if [[ ! "$ENV" =~ ^(dev|qa)$ ]]; then
    echo "Usage: $0 [dev|qa]"
    echo "Environment '$ENV' is not valid. Only 'dev' or 'qa' are supported."
    exit 1
fi

echo "=== Token Bridge Address Generation for '$ENV' environment ==="

# Read rollup address from existing deployment
DEPLOYMENT_INFO_FILE="config/$ENV/deployed_chain_info.json"
if [ ! -f "$DEPLOYMENT_INFO_FILE" ]; then
    echo "❌ ERROR: $DEPLOYMENT_INFO_FILE not found. Please deploy L2 first using deploy-to-kairos.sh"
    exit 1
fi

ROLLUP_ADDRESS=$(jq -r '.[0].rollup.rollup' $DEPLOYMENT_INFO_FILE)
if [ -z "$ROLLUP_ADDRESS" ] || [ "$ROLLUP_ADDRESS" = "null" ]; then
    echo "❌ ERROR: Could not find rollup address in $DEPLOYMENT_INFO_FILE"
    exit 1
fi

# Generate deterministic addresses based on rollup address
# In a real deployment, these would be calculated from CREATE2 or deployment nonces
# For now, we'll generate mock addresses
generate_address() {
    local prefix=$1
    local base=$2
    # Simple deterministic generation - in production this would use proper CREATE2 calculation
    echo "0x${prefix}${base:2:38}" | tr '[:upper:]' '[:lower:]'
}

# Generate addresses with different prefixes to ensure uniqueness
L1_GATEWAY_ROUTER=$(generate_address "A1" "$ROLLUP_ADDRESS")
L1_ERC20_GATEWAY=$(generate_address "A2" "$ROLLUP_ADDRESS")
L1_WETH_GATEWAY=$(generate_address "A3" "$ROLLUP_ADDRESS")
L2_GATEWAY_ROUTER=$(generate_address "B1" "$ROLLUP_ADDRESS")
L2_ERC20_GATEWAY=$(generate_address "B2" "$ROLLUP_ADDRESS")
L2_WETH_GATEWAY=$(generate_address "B3" "$ROLLUP_ADDRESS")

# Create output directory
mkdir -p config/$ENV/token-bridge

# Save deployment info to JSON file
cat > config/$ENV/token-bridge/deployment.json <<EOF
{
  "l1": {
    "gatewayRouter": "$L1_GATEWAY_ROUTER",
    "erc20Gateway": "$L1_ERC20_GATEWAY",
    "wethGateway": "$L1_WETH_GATEWAY"
  },
  "l2": {
    "gatewayRouter": "$L2_GATEWAY_ROUTER",
    "erc20Gateway": "$L2_ERC20_GATEWAY",
    "wethGateway": "$L2_WETH_GATEWAY"
  },
  "rollupAddress": "$ROLLUP_ADDRESS",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "note": "These are mock addresses for development. Deploy actual contracts before production use."
}
EOF

echo ""
echo "=== Token Bridge Address Generation Completed! ==="
echo ""
echo "Generated addresses saved to: config/$ENV/token-bridge/deployment.json"
echo ""
echo "L1 Contracts:"
echo "- Gateway Router: $L1_GATEWAY_ROUTER"
echo "- ERC20 Gateway:  $L1_ERC20_GATEWAY"
echo "- WETH Gateway:   $L1_WETH_GATEWAY"
echo ""
echo "L2 Contracts:"
echo "- Gateway Router: $L2_GATEWAY_ROUTER"
echo "- ERC20 Gateway:  $L2_ERC20_GATEWAY"
echo "- WETH Gateway:   $L2_WETH_GATEWAY"
echo ""
echo "⚠️  Note: These are mock addresses for development purposes."
echo "   Deploy actual token bridge contracts before production use."