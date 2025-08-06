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

# Check for cast (foundry)
if ! command -v cast &> /dev/null; then
    echo "❌ 'cast' command not found."
    echo "Please install foundry to proceed."
    echo "  - curl -L https://foundry.paradigm.xyz | bash"
    echo "  - foundryup"
    exit 1
fi

# Check for environment argument
ENV=${1:-dev}
if [[ ! "$ENV" =~ ^(dev|qa|perf|local)$ ]]; then
    echo "Usage: $0 [dev|qa|perf|local]"
    echo "Environment '$ENV' is not valid. Only 'dev', 'qa', 'perf', or 'local' are supported."
    exit 1
fi

echo "=== Kaia Token Bridge Deployment for '$ENV' environment ==="

# Configuration based on environment
case $ENV in
    dev)
        L1_RPC_URL="https://public-en-kairos.node.kaia.io"
        L2_RPC_URL="https://l2-rpc-dev.dexor.trade"
        DEPLOYER_KEY="${TOKEN_BRIDGE_DEPLOYER_KEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        ;;
    qa)
        L1_RPC_URL="https://public-en-kairos.node.kaia.io"
        L2_RPC_URL="https://l2-rpc-qa.dexor.trade"
        DEPLOYER_KEY="${TOKEN_BRIDGE_DEPLOYER_KEY:-0x11d00470a9a385668a65abc1a31a4a349301e5cd8217fdc33fb0eb6c6f971a8e}"
        ;;
    perf)
        L1_RPC_URL="https://public-en-kairos.node.kaia.io"
        L2_RPC_URL="https://l2-rpc-perf.dexor.trade"
        DEPLOYER_KEY="${TOKEN_BRIDGE_DEPLOYER_KEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        ;;
    local)
        # Local environment with same key as deploy-to-kairos.sh local
        L1_RPC_URL="https://public-en-kairos.node.kaia.io"
        L2_RPC_URL="http://localhost:8547"  # Assume local L2 node
        DEPLOYER_KEY="${TOKEN_BRIDGE_DEPLOYER_KEY:-0xcc56168a0e292aad91d2f03a976da05910215a6d3cafff8bdad463736ac8f548}"
        ;;
esac

# Calculate ROLLUP_OWNER from DEPLOYER_KEY
ROLLUP_OWNER=$(cast wallet address $DEPLOYER_KEY)
echo "Rollup Owner: $ROLLUP_OWNER"

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
echo "- Rollup Owner: $ROLLUP_OWNER"
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
    elif [ "$ENV" = "local" ]; then
        # For local environment, assume L2 is already running on localhost:8547
        echo "Using local L2 RPC at $L2_RPC_URL"
    fi
fi

# Step 1: Deploy token bridge creator
echo "Step 1: Deploying token bridge creator contracts..."
DEPLOYMENT_OUTPUT=$(mktemp)

# Use host networking only for local environment
if [ "$ENV" = "local" ]; then
    # For local, use host network to access localhost:8547
    docker run --rm \
        --network host \
        -e BASECHAIN_RPC="$L1_RPC_URL" \
        -e ORBIT_RPC="$L2_RPC_URL" \
        -e BASECHAIN_DEPLOYER_KEY="$DEPLOYER_KEY" \
        -e ROLLUP_ADDRESS="$ROLLUP_ADDRESS" \
        -e INBOX_ADDRESS="$INBOX_ADDRESS" \
        -e ROLLUP_OWNER="$ROLLUP_OWNER" \
        $TOKEN_BRIDGE_IMAGE \
        run deploy:token-bridge-creator 2>&1 | tee $DEPLOYMENT_OUTPUT
else
    # For other environments, use default network
    docker run --rm \
        -e BASECHAIN_RPC="$L1_RPC_URL" \
        -e ORBIT_RPC="$L2_RPC_URL" \
        -e BASECHAIN_DEPLOYER_KEY="$DEPLOYER_KEY" \
        -e ROLLUP_ADDRESS="$ROLLUP_ADDRESS" \
        -e INBOX_ADDRESS="$INBOX_ADDRESS" \
        -e ROLLUP_OWNER="$ROLLUP_OWNER" \
        $TOKEN_BRIDGE_IMAGE \
        run deploy:token-bridge-creator 2>&1 | tee $DEPLOYMENT_OUTPUT
fi

# Clean up port forwarding if used
if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
fi

# Also check if we got "Done." in the output which indicates success
if ! grep -q "Done\." $DEPLOYMENT_OUTPUT; then
    echo "❌ ERROR: Token bridge creator deployment did not complete successfully"
    cat $DEPLOYMENT_OUTPUT
    rm -f $DEPLOYMENT_OUTPUT
    exit 1
fi

# Parse deployment output to extract creator contract addresses
echo ""
echo "Parsing token bridge creator deployment results..."

# Parse the output for creator addresses
# Look for the pattern "L1TokenBridgeCreator: 0x..." with flexible spacing
L1_TOKEN_BRIDGE_CREATOR=$(grep -E "L1TokenBridgeCreator:\s*0x[a-fA-F0-9]{40}" $DEPLOYMENT_OUTPUT | grep -o "0x[a-fA-F0-9]\{40\}" | tail -1 || echo "")
L1_RETRYABLE_SENDER=$(grep -E "L1TokenBridgeRetryableSender:\s*0x[a-fA-F0-9]{40}" $DEPLOYMENT_OUTPUT | grep -o "0x[a-fA-F0-9]\{40\}" | tail -1 || echo "")

if [ -z "$L1_TOKEN_BRIDGE_CREATOR" ] || [ -z "$L1_RETRYABLE_SENDER" ]; then
    echo "❌ ERROR: Failed to extract token bridge creator addresses from deployment output"
    echo "Output was:"
    cat $DEPLOYMENT_OUTPUT
    rm -f $DEPLOYMENT_OUTPUT
    exit 1
fi

echo "Token bridge creator deployed!"
echo "L1TokenBridgeCreator: $L1_TOKEN_BRIDGE_CREATOR"
echo "L1TokenBridgeRetryableSender: $L1_RETRYABLE_SENDER"
echo ""

# Step 2: Create token bridge using the deployed creator
echo "Step 2: Creating token bridge contracts..."
BRIDGE_OUTPUT=$(mktemp)

# Create volume for token bridge deployment
BRIDGE_VOLUME="token-bridge-deploy-$(date +%s)"
docker volume create $BRIDGE_VOLUME >/dev/null 2>&1 || true

# Use host networking only for local environment
if [ "$ENV" = "local" ]; then
    # For local, use host network to access localhost:8547
    docker run --rm \
        --network host \
        -v $BRIDGE_VOLUME:/workspace/deployments \
        -e BASECHAIN_RPC="$L1_RPC_URL" \
        -e ORBIT_RPC="$L2_RPC_URL" \
        -e BASECHAIN_DEPLOYER_KEY="$DEPLOYER_KEY" \
        -e ROLLUP_ADDRESS="$ROLLUP_ADDRESS" \
        -e INBOX_ADDRESS="$INBOX_ADDRESS" \
        -e L1_TOKEN_BRIDGE_CREATOR="$L1_TOKEN_BRIDGE_CREATOR" \
        -e L1_RETRYABLE_SENDER="$L1_RETRYABLE_SENDER" \
        -e ROLLUP_OWNER="$ROLLUP_OWNER" \
        $TOKEN_BRIDGE_IMAGE \
        run create:token-bridge --network kairos 2>&1 | tee $BRIDGE_OUTPUT
else
    # For other environments, use default network
    docker run --rm \
        -v $BRIDGE_VOLUME:/workspace/deployments \
        -e BASECHAIN_RPC="$L1_RPC_URL" \
        -e ORBIT_RPC="$L2_RPC_URL" \
        -e BASECHAIN_DEPLOYER_KEY="$DEPLOYER_KEY" \
        -e ROLLUP_ADDRESS="$ROLLUP_ADDRESS" \
        -e INBOX_ADDRESS="$INBOX_ADDRESS" \
        -e L1_TOKEN_BRIDGE_CREATOR="$L1_TOKEN_BRIDGE_CREATOR" \
        -e L1_RETRYABLE_SENDER="$L1_RETRYABLE_SENDER" \
        -e ROLLUP_OWNER="$ROLLUP_OWNER" \
        $TOKEN_BRIDGE_IMAGE \
        run create:token-bridge --network kairos 2>&1 | tee $BRIDGE_OUTPUT
fi

# Also check if we got successful completion in the output
if ! grep -q -E "(Done\.|Token bridge deployed successfully|Successfully deployed token bridge)" $BRIDGE_OUTPUT; then
    echo "❌ ERROR: Token bridge creation did not complete successfully"
    cat $BRIDGE_OUTPUT
    rm -f $DEPLOYMENT_OUTPUT $BRIDGE_OUTPUT
    exit 1
fi



# Step 3: Copy network.json from volume
echo ""
echo "Step 3: Copying network.json from deployment..."

# Create a temporary container to copy files from volume
TEMP_CONTAINER=$(docker create -v $BRIDGE_VOLUME:/workspace/deployments alpine:latest sleep 60)
docker start $TEMP_CONTAINER >/dev/null

# Try to copy network.json from the container
# First check if the file exists in the container
if docker exec $TEMP_CONTAINER test -f /workspace/deployments/network.json; then
    docker cp $TEMP_CONTAINER:/workspace/deployments/network.json ./config/$ENV/token-bridge/
    echo "✅ network.json copied successfully"

    # Display the token bridge addresses from network.json
    echo ""
    echo "Token Bridge Addresses from network.json:"
    echo "L1 Contracts:"
    echo "- Gateway Router: $(jq -r '.l1.network.tokenBridge.parentGatewayRouter // "Not found"' "config/$ENV/token-bridge/network.json")"
    echo "- ERC20 Gateway:  $(jq -r '.l1.network.tokenBridge.parentErc20Gateway // "Not found"' "config/$ENV/token-bridge/network.json")"
    echo "- WETH Gateway:   $(jq -r '.l1.network.tokenBridge.parentWethGateway // "Not found"' "config/$ENV/token-bridge/network.json")"
    echo ""
    echo "L2 Contracts:"
    echo "- Gateway Router: $(jq -r '.l2.network.tokenBridge.childGatewayRouter // "Not found"' "config/$ENV/token-bridge/network.json")"
    echo "- ERC20 Gateway:  $(jq -r '.l2.network.tokenBridge.childErc20Gateway // "Not found"' "config/$ENV/token-bridge/network.json")"
    echo "- WETH Gateway:   $(jq -r '.l2.network.tokenBridge.childWethGateway // "Not found"' "config/$ENV/token-bridge/network.json")"
    echo ""
else
    echo "⚠️  Warning: network.json not found in deployment volume"
    echo "Checking if it's in the root directory..."

    # Check if network.json is in the root directory of the container
    if docker exec $TEMP_CONTAINER test -f /network.json; then
        docker cp $TEMP_CONTAINER:/network.json ./config/$ENV/token-bridge/
        echo "✅ network.json found in root directory and copied successfully"
    else
        echo "⚠️  Warning: network.json not found in container"
        echo "Attempting to find it..."

        # List all json files in the container to help debug
        echo "Looking for JSON files in container:"
        docker exec $TEMP_CONTAINER find / -name "*.json" -type f 2>/dev/null | grep -v proc | grep -v sys || true
    fi
fi

# Clean up container
docker stop $TEMP_CONTAINER >/dev/null 2>&1
docker rm $TEMP_CONTAINER >/dev/null 2>&1

# Clean up volume and files
docker volume rm $BRIDGE_VOLUME >/dev/null 2>&1 || true
rm -f $DEPLOYMENT_OUTPUT $BRIDGE_OUTPUT

echo ""
echo "=== Token Bridge Deployment Completed! ==="
echo ""
echo "Deployed contracts:"
echo "Creator Contracts:"
echo "- L1TokenBridgeCreator:         $L1_TOKEN_BRIDGE_CREATOR"
echo "- L1TokenBridgeRetryableSender: $L1_RETRYABLE_SENDER"
echo ""

if [ -f "config/$ENV/token-bridge/network.json" ]; then
    echo "Token bridge configuration saved to: config/$ENV/token-bridge/network.json ✅"
else
    echo "⚠️  Warning: network.json was not created. Check the deployment logs."
fi

echo ""
echo "Next steps:"
echo "1. Review the network.json file for all deployed contract addresses"
echo "2. Update your application configuration with the token bridge addresses"
echo "3. Test token deposits and withdrawals between L1 and L2"
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
