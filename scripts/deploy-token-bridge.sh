#!/usr/bin/env bash

set -e

# Kaia Token Bridge Deployment Script
# This script deploys the token bridge contracts and automatically updates the
# corresponding Helm chart values files.

# --- Prerequisites ---
# 1. Docker
# 2. gcloud CLI (for docker auth)
# 3. yq (for updating YAML files)
# 4. jq (for JSON parsing)

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "❌ 'yq' command not found."
    echo "Please install it to proceed."
    echo "  - macOS: brew install yq"
    echo "  - Linux: sudo snap install yq or download from https://github.com/mikefarah/yq/"
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
if [[ ! "$ENV" =~ ^(dev|qa|perf)$ ]]; then
    echo "Usage: $0 [dev|qa|perf]"
    echo "Environment '$ENV' is not valid. Only 'dev', 'qa', or 'perf' are supported."
    exit 1
fi

echo "=== Kaia Token Bridge Deployment for '$ENV' environment ==="

# Configuration based on environment
case $ENV in
    dev)
        L1_RPC_URL="https://archive-en-kairos.node.kaia.io"
        L2_RPC_URL="https://l2-rpc-dev.dexor.trade"
        DEPLOYER_KEY="${TOKEN_BRIDGE_DEPLOYER_KEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        ;;
    qa)
        L1_RPC_URL="https://archive-en-kairos.node.kaia.io"
        L2_RPC_URL="https://l2-rpc-qa.dexor.trade"
        DEPLOYER_KEY="${TOKEN_BRIDGE_DEPLOYER_KEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        ;;
    perf)
        L1_RPC_URL="https://archive-en-kairos.node.kaia.io"
        L2_RPC_URL="https://l2-rpc-perf.dexor.trade"
        DEPLOYER_KEY="${TOKEN_BRIDGE_DEPLOYER_KEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        ;;
esac

# Read rollup address from existing deployment
DEPLOYMENT_INFO_FILE="config/$ENV/deployed_chain_info.json"
if [ ! -f "$DEPLOYMENT_INFO_FILE" ]; then
    echo "❌ ERROR: $DEPLOYMENT_INFO_FILE not found. Please deploy L2 first using deploy-to-kairos.sh"
    exit 1
fi

ROLLUP_ADDRESS=$(jq -r '.[0].rollup.rollup' $DEPLOYMENT_INFO_FILE)
INBOX_ADDRESS=$(jq -r '.[0].rollup.inbox' $DEPLOYMENT_INFO_FILE)

if [ -z "$ROLLUP_ADDRESS" ] || [ "$ROLLUP_ADDRESS" = "null" ]; then
    echo "❌ ERROR: Could not find rollup address in $DEPLOYMENT_INFO_FILE"
    exit 1
fi

if [ -z "$INBOX_ADDRESS" ] || [ "$INBOX_ADDRESS" = "null" ]; then
    echo "❌ ERROR: Could not find inbox address in $DEPLOYMENT_INFO_FILE"
    exit 1
fi

# Docker image for token bridge
TOKEN_BRIDGE_IMAGE="asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core-testnode/token-bridge-contracts:1.0.0"

echo "Configuration:"
echo "- L1 RPC URL: $L1_RPC_URL"
echo "- L2 RPC URL: $L2_RPC_URL"
echo "- Rollup Address: $ROLLUP_ADDRESS"
echo "- Inbox Address: $INBOX_ADDRESS"
echo "- Token Bridge Image: $TOKEN_BRIDGE_IMAGE"
echo ""

# Create output directory for deployment results
mkdir -p config/$ENV/token-bridge

# Test L2 RPC connectivity
echo "Testing L2 RPC connectivity..."
if ! curl -s -X POST "$L2_RPC_URL" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' > /dev/null 2>&1; then
    echo "⚠️  Warning: Cannot reach L2 RPC at $L2_RPC_URL from host"
    echo "Trying alternative approach..."
    
    # Use port forwarding as fallback for dev/qa/perf environments
    if [ "$ENV" = "dev" ]; then
        echo "Setting up port forwarding to L2 RPC..."
        kubectl port-forward -n kaia-dex svc/dev-kaia-orderbook-dex-core-nitro 8547:8547 > /tmp/port-forward.log 2>&1 &
        PF_PID=$!
        sleep 3
        L2_RPC_URL="http://localhost:8547"
        echo "Using local port forward: $L2_RPC_URL"
    elif [ "$ENV" = "qa" ]; then
        echo "Setting up port forwarding to L2 RPC..."
        kubectl port-forward -n kaia-dex-qa svc/qa-kaia-orderbook-dex-core-nitro 8547:8547 > /tmp/port-forward.log 2>&1 &
        PF_PID=$!
        sleep 3
        L2_RPC_URL="http://localhost:8547"
        echo "Using local port forward: $L2_RPC_URL"
    elif [ "$ENV" = "perf" ]; then
        echo "Setting up port forwarding to L2 RPC..."
        kubectl port-forward -n kaia-dex-perf svc/perf-kaia-orderbook-dex-core-nitro 8547:8547 > /tmp/port-forward.log 2>&1 &
        PF_PID=$!
        sleep 3
        L2_RPC_URL="http://localhost:8547"
        echo "Using local port forward: $L2_RPC_URL"
    fi
fi

# Deploy token bridge
echo "Deploying token bridge contracts..."
DEPLOYMENT_OUTPUT=$(mktemp)

# Add host networking for Docker to access external URLs
docker run --rm \
    --network host \
    -e L1_RPC_URL="$L1_RPC_URL" \
    -e L2_RPC_URL="$L2_RPC_URL" \
    -e DEPLOYER_KEY="$DEPLOYER_KEY" \
    -e ROLLUP_ADDRESS="$ROLLUP_ADDRESS" \
    -e INBOX_ADDRESS="$INBOX_ADDRESS" \
    $TOKEN_BRIDGE_IMAGE \
    run create:token-bridge 2>&1 | tee $DEPLOYMENT_OUTPUT

# Clean up port forwarding if used
if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
fi

# Check if deployment was successful
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ ERROR: Token bridge deployment failed"
    cat $DEPLOYMENT_OUTPUT
    rm -f $DEPLOYMENT_OUTPUT
    exit 1
fi

# Parse deployment output to extract contract addresses
# Assuming the output contains JSON or specific format with addresses
# This part needs to be adjusted based on actual output format
echo ""
echo "Parsing deployment results..."

# Example parsing (adjust based on actual output format)
# Looking for patterns like "L1_GATEWAY_ROUTER: 0x..."
L1_GATEWAY_ROUTER=$(grep -o "L1_GATEWAY_ROUTER:.*0x[a-fA-F0-9]\{40\}" $DEPLOYMENT_OUTPUT | grep -o "0x[a-fA-F0-9]\{40\}" || echo "")
L1_ERC20_GATEWAY=$(grep -o "L1_ERC20_GATEWAY:.*0x[a-fA-F0-9]\{40\}" $DEPLOYMENT_OUTPUT | grep -o "0x[a-fA-F0-9]\{40\}" || echo "")
L1_WETH_GATEWAY=$(grep -o "L1_WETH_GATEWAY:.*0x[a-fA-F0-9]\{40\}" $DEPLOYMENT_OUTPUT | grep -o "0x[a-fA-F0-9]\{40\}" || echo "")
L2_GATEWAY_ROUTER=$(grep -o "L2_GATEWAY_ROUTER:.*0x[a-fA-F0-9]\{40\}" $DEPLOYMENT_OUTPUT | grep -o "0x[a-fA-F0-9]\{40\}" || echo "")
L2_ERC20_GATEWAY=$(grep -o "L2_ERC20_GATEWAY:.*0x[a-fA-F0-9]\{40\}" $DEPLOYMENT_OUTPUT | grep -o "0x[a-fA-F0-9]\{40\}" || echo "")
L2_WETH_GATEWAY=$(grep -o "L2_WETH_GATEWAY:.*0x[a-fA-F0-9]\{40\}" $DEPLOYMENT_OUTPUT | grep -o "0x[a-fA-F0-9]\{40\}" || echo "")

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
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo ""
echo "=== Token Bridge Deployment Completed! ==="
echo ""
echo "Deployed contracts:"
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

## Update Helm values files
#echo "Updating Helm values files..."
#
#CORE_VALUES_FILE="charts/kaia-orderbook-dex-core/values-$ENV.yaml"
#BACKEND_VALUES_FILE="charts/kaia-orderbook-dex-backend/values-$ENV.yaml"
#FRONTEND_VALUES_FILE="charts/kaia-orderbook-dex-frontend/values-$ENV.yaml"
#
## Update Core values with token bridge addresses
#if [ -f "$CORE_VALUES_FILE" ]; then
#    # Add token bridge section if it doesn't exist
#    yq e -i '.tokenBridge = {}' "$CORE_VALUES_FILE"
#    yq e -i ".tokenBridge.l1GatewayRouter = \"$L1_GATEWAY_ROUTER\"" "$CORE_VALUES_FILE"
#    yq e -i ".tokenBridge.l1Erc20Gateway = \"$L1_ERC20_GATEWAY\"" "$CORE_VALUES_FILE"
#    yq e -i ".tokenBridge.l1WethGateway = \"$L1_WETH_GATEWAY\"" "$CORE_VALUES_FILE"
#    yq e -i ".tokenBridge.l2GatewayRouter = \"$L2_GATEWAY_ROUTER\"" "$CORE_VALUES_FILE"
#    yq e -i ".tokenBridge.l2Erc20Gateway = \"$L2_ERC20_GATEWAY\"" "$CORE_VALUES_FILE"
#    yq e -i ".tokenBridge.l2WethGateway = \"$L2_WETH_GATEWAY\"" "$CORE_VALUES_FILE"
#    echo "✅ Updated $CORE_VALUES_FILE"
#fi
#
## Update Backend values with token bridge addresses
#if [ -f "$BACKEND_VALUES_FILE" ]; then
#    # Add token bridge section if it doesn't exist
#    yq e -i '.tokenBridge = {}' "$BACKEND_VALUES_FILE"
#    yq e -i ".tokenBridge.l1GatewayRouter = \"$L1_GATEWAY_ROUTER\"" "$BACKEND_VALUES_FILE"
#    yq e -i ".tokenBridge.l2GatewayRouter = \"$L2_GATEWAY_ROUTER\"" "$BACKEND_VALUES_FILE"
#    echo "✅ Updated $BACKEND_VALUES_FILE"
#fi
#
## Update Frontend values with token bridge addresses
#if [ -f "$FRONTEND_VALUES_FILE" ]; then
#    # Add token bridge configuration to frontend env
#    yq e -i ".env.VITE_L1_GATEWAY_ROUTER = \"$L1_GATEWAY_ROUTER\"" "$FRONTEND_VALUES_FILE"
#    yq e -i ".env.VITE_L2_GATEWAY_ROUTER = \"$L2_GATEWAY_ROUTER\"" "$FRONTEND_VALUES_FILE"
#    echo "✅ Updated $FRONTEND_VALUES_FILE"
#fi
#
## Clean up
#rm -f $DEPLOYMENT_OUTPUT
#
#echo ""
#echo "Next steps:"
#echo "1. Review and commit the updated values-$ENV.yaml files"
#echo "2. ArgoCD will automatically sync the changes"
#echo "3. Monitor the token bridge deployment logs"
#echo ""
#echo "To test the token bridge:"
#echo "- Use the gateway router addresses to deposit/withdraw tokens"
#echo "- Monitor bridge events in the backend event service"
