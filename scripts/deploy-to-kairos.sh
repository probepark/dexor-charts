#!/usr/bin/env bash

set -e

# Kaia Orderbook DEX Core - L2 Deployment Script for Kairos Testnet
# This script deploys the L2 contracts and automatically updates the
# corresponding Helm chart values files (values-dev.yaml, values-qa.yaml).

# --- Prequisites ---
# 1. Docker
# 2. gcloud CLI (for docker auth)
# 3. yq (for updating YAML files)

# Check for yq
if ! command -v yq &> /dev/null
then
    echo "❌ 'yq' command not found."
    echo "Please install it to proceed."
    echo "  - macOS: brew install yq"
    echo "  - Linux: sudo snap install yq or download from https://github.com/mikefarah/yq/"
    exit 1
fi

# Check for environment argument
ENV=${1:-dev}
if [[ ! "$ENV" =~ ^(dev|qa)$ ]]; then
    echo "Usage: $0 [dev|qa]"
    echo "Environment '$ENV' is not valid. Only 'dev' or 'qa' are supported for auto-update."
    exit 1
fi

# Configuration
KAIROS_RPC_URL="https://archive-en-kairos.node.kaia.io"
PARENT_CHAIN_ID=1001

# Environment-specific configuration
case $ENV in
    dev)
        DEPLOYER_PRIVKEY="${DEPLOYER_PRIVKEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        OWNER_ADDRESS="${OWNER_ADDRESS:-0xf07ade7aa7dd067b6e9426a38bd538c0025bc784}"
        SEQUENCER_ADDRESS="${SEQUENCER_ADDRESS:-0xf07ade7aa7dd067b6e9426a38bd538c0025bc784}"
        ;;
    qa)
        DEPLOYER_PRIVKEY="${DEPLOYER_PRIVKEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        OWNER_ADDRESS="${OWNER_ADDRESS:-0xf07ade7aa7dd067b6e9426a38bd538c0025bc784}"
        SEQUENCER_ADDRESS="${SEQUENCER_ADDRESS:-0xf07ade7aa7dd067b6e9426a38bd538c0025bc784}"
        ;;
esac

# Docker images
SCRIPTS_IMAGE="asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core-testnode/scripts:1.0.1"
ROLLUPCREATOR_IMAGE="asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core-testnode/rollupcreator:1.0.1"
NITRO_NODE_IMAGE="asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core:dev"

# Use local images if USE_LOCAL is set
if [ "${USE_LOCAL:-false}" = "true" ]; then
    NITRO_NODE_IMAGE="nitro-node:latest"
fi

echo "=== Kaia Kairos Testnet L2 Deployment for '$ENV' environment ==="
echo "RPC URL: $KAIROS_RPC_URL"
echo "Chain ID: $PARENT_CHAIN_ID"
echo "Owner Address: $OWNER_ADDRESS"
echo "Sequencer Address: $SEQUENCER_ADDRESS"
echo ""

# Pull Docker images if not using local
if [ "${USE_LOCAL:-false}" != "true" ]; then
    echo "Pulling Docker images..."
    echo "- Pulling scripts image..."
    docker pull $SCRIPTS_IMAGE || { echo "Failed to pull scripts image"; exit 1; }
    echo "- Pulling rollupcreator image..."
    docker pull $ROLLUPCREATOR_IMAGE || { echo "Failed to pull rollupcreator image"; exit 1; }
    echo "- Pulling nitro node image..."
    docker pull --platform linux/amd64 $NITRO_NODE_IMAGE || { echo "Failed to pull nitro node image"; exit 1; }
    echo "Images pulled successfully!"
else
    echo "Using local images (USE_LOCAL=true)"
fi
echo ""

# Create config directory and volume
mkdir -p config
CONFIG_VOLUME="kairos-deploy-config-$(date +%s)"
docker volume create $CONFIG_VOLUME >/dev/null 2>&1 || true

# Step 1: Write L2 configuration
echo "Step 1: Writing L2 configuration..."
docker run --rm \
  --platform linux/amd64 \
  -v $CONFIG_VOLUME:/config \
  $SCRIPTS_IMAGE \
  write-l2-chain-config --l2owner $OWNER_ADDRESS

# Step 2: Get WASM module root
echo "Step 2: Getting WASM module root..."
WASM_MODULE_ROOT=$(docker run --rm --platform linux/amd64 --entrypoint sh $NITRO_NODE_IMAGE -c "cat /home/user/target/machines/latest/module-root.txt" | tr -d '\r\n')
echo "WASM module root: $WASM_MODULE_ROOT"

# Step 3: Deploy rollup contracts
echo "Step 3: Deploying rollup contracts to Kairos..."
docker run --rm \
  --platform linux/amd64 \
  -v $CONFIG_VOLUME:/config \
  -e PARENT_CHAIN_RPC="$KAIROS_RPC_URL" \
  -e DEPLOYER_PRIVKEY=$DEPLOYER_PRIVKEY \
  -e PARENT_CHAIN_ID=$PARENT_CHAIN_ID \
  -e CHILD_CHAIN_NAME="arb-dev-test" \
  -e MAX_DATA_SIZE=117964 \
  -e OWNER_ADDRESS=$OWNER_ADDRESS \
  -e WASM_MODULE_ROOT=$WASM_MODULE_ROOT \
  -e SEQUENCER_ADDRESS=$SEQUENCER_ADDRESS \
  -e AUTHORIZE_VALIDATORS=10 \
  -e CHILD_CHAIN_CONFIG_PATH="/config/l2_chain_config.json" \
  -e CHAIN_DEPLOYMENT_INFO="/config/deployment.json" \
  -e CHILD_CHAIN_INFO="/config/deployed_chain_info.json" \
  $ROLLUPCREATOR_IMAGE \
  create-rollup-testnode

# Step 4: Copy deployed chain info as l2_chain_info
echo "Step 4: Copying L2 chain info..."
docker run --rm \
  --platform linux/amd64 \
  -v $CONFIG_VOLUME:/config \
  --entrypoint sh \
  $ROLLUPCREATOR_IMAGE \
  -c "cp /config/deployed_chain_info.json /config/l2_chain_info.json"

# Step 5: Copy configuration files from volume
echo "Step 5: Copying configuration files..."
mkdir -p ./config/$ENV
TEMP_CONTAINER=$(docker create -v $CONFIG_VOLUME:/config alpine:latest sleep 60)
docker start $TEMP_CONTAINER >/dev/null

docker cp $TEMP_CONTAINER:/config/deployment.json ./config/$ENV/
docker cp $TEMP_CONTAINER:/config/deployed_chain_info.json ./config/$ENV/
docker cp $TEMP_CONTAINER:/config/l2_chain_info.json ./config/$ENV/
docker cp $TEMP_CONTAINER:/config/l2_chain_config.json ./config/$ENV/

docker stop $TEMP_CONTAINER >/dev/null 2>&1
docker rm $TEMP_CONTAINER >/dev/null 2>&1

# Step 6: Create keystore for sequencer (simplified)
echo "Step 6: Creating keystore for sequencer..."
mkdir -p ./config/$ENV/keystore

# Step 7: Generate sequencer configuration
echo "Step 7: Generating sequencer configuration..."
DEPLOYMENT_INFO_FILE="config/$ENV/deployed_chain_info.json"

if [ -f "$DEPLOYMENT_INFO_FILE" ]; then
    SEQUENCER_INBOX_ADDRESS=$(jq -r '.[0]."rollup"."sequencer-inbox"' $DEPLOYMENT_INFO_FILE)
    CHAIN_ID=$(jq -r '.[0]."chain-config"."chainId"' $DEPLOYMENT_INFO_FILE)

    # Extract contract addresses
    ROLLUP_ADDRESS=$(jq -r '.[0]."rollup"."rollup"' $DEPLOYMENT_INFO_FILE)
    BRIDGE_ADDRESS=$(jq -r '.[0]."rollup"."bridge"' $DEPLOYMENT_INFO_FILE)
    INBOX_ADDRESS=$(jq -r '.[0]."rollup"."inbox"' $DEPLOYMENT_INFO_FILE)
    
    # Extract additional contract addresses
    OUTBOX_ADDRESS=$(jq -r '.[0]."rollup"."outbox" // empty' $DEPLOYMENT_INFO_FILE)
    ROLLUP_EVENT_INBOX_ADDRESS=$(jq -r '.[0]."rollup"."rollup-event-inbox" // empty' $DEPLOYMENT_INFO_FILE)
    CHALLENGE_MANAGER_ADDRESS=$(jq -r '.[0]."rollup"."challenge-manager" // empty' $DEPLOYMENT_INFO_FILE)
    ADMIN_PROXY_ADDRESS=$(jq -r '.[0]."rollup"."admin-proxy" // empty' $DEPLOYMENT_INFO_FILE)
    UPGRADE_EXECUTOR_ADDRESS=$(jq -r '.[0]."rollup"."upgrade-executor"' $DEPLOYMENT_INFO_FILE)
    VALIDATOR_WALLET_CREATOR_ADDRESS=$(jq -r '.[0]."rollup"."validator-wallet-creator"' $DEPLOYMENT_INFO_FILE)
    STAKE_TOKEN_ADDRESS=$(jq -r '.[0]."rollup"."stake-token"' $DEPLOYMENT_INFO_FILE)

    echo ""
    echo "=== Deployment Completed! ==="
    echo ""
    echo "Environment: $ENV"
    echo "Deployed contracts:"
    echo "- Rollup:          $ROLLUP_ADDRESS"
    echo "- Bridge:          $BRIDGE_ADDRESS"
    echo "- Inbox:           $INBOX_ADDRESS"
    echo "- Sequencer Inbox: $SEQUENCER_INBOX_ADDRESS"
    echo ""

    # --- Automatic Update of Helm Values ---
    echo "Step 8: Updating Helm values files for '$ENV' environment..."
    
    # Debug: Show extracted values
    echo "Extracted contract addresses:"
    echo "- Rollup:          $ROLLUP_ADDRESS"
    echo "- Bridge:          $BRIDGE_ADDRESS"
    echo "- Inbox:           $INBOX_ADDRESS"
    echo "- Sequencer Inbox: $SEQUENCER_INBOX_ADDRESS"
    echo ""
    
    # Validate that we have the essential addresses
    if [ -z "$ROLLUP_ADDRESS" ] || [ "$ROLLUP_ADDRESS" = "null" ]; then
        echo "❌ ERROR: Failed to extract rollup address from deployment info"
        exit 1
    fi
    if [ -z "$SEQUENCER_INBOX_ADDRESS" ] || [ "$SEQUENCER_INBOX_ADDRESS" = "null" ]; then
        echo "❌ ERROR: Failed to extract sequencer inbox address from deployment info"
        exit 1
    fi

    CORE_VALUES_FILE="charts/kaia-orderbook-dex-core/values-$ENV.yaml"
    BACKEND_VALUES_FILE="charts/kaia-orderbook-dex-backend/values-$ENV.yaml"

    # Update Core values - contracts are under environment key
    if [ -f "$CORE_VALUES_FILE" ]; then
        echo "Updating Core values file..."
        
        # Update child chain ID
        yq e -i ".environment.childChain.chainId = $CHAIN_ID" "$CORE_VALUES_FILE"
        
        # Update contract addresses
        yq e -i ".environment.contracts.rollup = \"$ROLLUP_ADDRESS\"" "$CORE_VALUES_FILE"
        yq e -i ".environment.contracts.bridge = \"$BRIDGE_ADDRESS\"" "$CORE_VALUES_FILE"
        yq e -i ".environment.contracts.inbox = \"$INBOX_ADDRESS\"" "$CORE_VALUES_FILE"
        yq e -i ".environment.contracts.sequencerInbox = \"$SEQUENCER_INBOX_ADDRESS\"" "$CORE_VALUES_FILE"
        
        # Update additional contracts if they exist
        if [ -n "$OUTBOX_ADDRESS" ]; then
            yq e -i ".environment.contracts.outbox = \"$OUTBOX_ADDRESS\"" "$CORE_VALUES_FILE"
        fi
        if [ -n "$ROLLUP_EVENT_INBOX_ADDRESS" ]; then
            yq e -i ".environment.contracts.rollupEventInbox = \"$ROLLUP_EVENT_INBOX_ADDRESS\"" "$CORE_VALUES_FILE"
        fi
        if [ -n "$CHALLENGE_MANAGER_ADDRESS" ]; then
            yq e -i ".environment.contracts.challengeManager = \"$CHALLENGE_MANAGER_ADDRESS\"" "$CORE_VALUES_FILE"
        fi
        if [ -n "$ADMIN_PROXY_ADDRESS" ]; then
            yq e -i ".environment.contracts.adminProxy = \"$ADMIN_PROXY_ADDRESS\"" "$CORE_VALUES_FILE"
        fi
        yq e -i ".environment.contracts.upgradeExecutor = \"$UPGRADE_EXECUTOR_ADDRESS\"" "$CORE_VALUES_FILE"
        yq e -i ".environment.contracts.validatorWalletCreator = \"$VALIDATOR_WALLET_CREATOR_ADDRESS\"" "$CORE_VALUES_FILE"
        yq e -i ".environment.contracts.stakeToken = \"$STAKE_TOKEN_ADDRESS\"" "$CORE_VALUES_FILE"
        
        echo "✅ Updated $CORE_VALUES_FILE"
        
        # Update config.files section with deployment JSON files
        echo "Updating config.files section..."
        
        # Update l2_chain_config.json
        if [ -f "./config/$ENV/l2_chain_config.json" ]; then
            echo "Processing l2_chain_config.json..."
            # Read the JSON file and format it properly
            L2_CHAIN_CONFIG=$(cat "./config/$ENV/l2_chain_config.json" | jq .)
            # Create a temporary file to store the formatted JSON
            echo "$L2_CHAIN_CONFIG" > /tmp/l2_chain_config_formatted.json
            # Use yq to update the value with proper multiline formatting
            yq e -i ".config.files.\"l2_chain_config.json\" = load_str(\"/tmp/l2_chain_config_formatted.json\")" "$CORE_VALUES_FILE"
            yq e -i '.config.files."l2_chain_config.json" style="literal"' "$CORE_VALUES_FILE"
            rm -f /tmp/l2_chain_config_formatted.json
            echo "✅ Updated l2_chain_config.json in config.files"
        fi
        
        # Update l2_chain_info.json
        if [ -f "./config/$ENV/l2_chain_info.json" ]; then
            echo "Processing l2_chain_info.json..."
            L2_CHAIN_INFO=$(cat "./config/$ENV/l2_chain_info.json" | jq .)
            echo "$L2_CHAIN_INFO" > /tmp/l2_chain_info_formatted.json
            yq e -i ".config.files.\"l2_chain_info.json\" = load_str(\"/tmp/l2_chain_info_formatted.json\")" "$CORE_VALUES_FILE"
            yq e -i '.config.files."l2_chain_info.json" style="literal"' "$CORE_VALUES_FILE"
            rm -f /tmp/l2_chain_info_formatted.json
            echo "✅ Updated l2_chain_info.json in config.files"
        fi
        
        # Update deployment.json
        if [ -f "./config/$ENV/deployment.json" ]; then
            echo "Processing deployment.json..."
            DEPLOYMENT_JSON=$(cat "./config/$ENV/deployment.json" | jq .)
            echo "$DEPLOYMENT_JSON" > /tmp/deployment_formatted.json
            yq e -i ".config.files.\"deployment.json\" = load_str(\"/tmp/deployment_formatted.json\")" "$CORE_VALUES_FILE"
            yq e -i '.config.files."deployment.json" style="literal"' "$CORE_VALUES_FILE"
            rm -f /tmp/deployment_formatted.json
            echo "✅ Updated deployment.json in config.files"
        fi
        
    else
        echo "⚠️  Warning: $CORE_VALUES_FILE not found. Skipping update."
    fi

    # Update Backend values
    if [ -f "$BACKEND_VALUES_FILE" ]; then
        yq e -i ".contracts.rollup = \"$ROLLUP_ADDRESS\"" "$BACKEND_VALUES_FILE"
        yq e -i ".contracts.sequencerInbox = \"$SEQUENCER_INBOX_ADDRESS\"" "$BACKEND_VALUES_FILE"
        echo "✅ Updated $BACKEND_VALUES_FILE"
    else
        echo "⚠️  Warning: $BACKEND_VALUES_FILE not found. Skipping update."
    fi

    # Update Backend config TOML file
    BACKEND_CONFIG_FILE="charts/kaia-orderbook-dex-backend/config/$ENV.toml"
    if [ -f "$BACKEND_CONFIG_FILE" ]; then
        # Use sed to update the sequencer_inbox_address in the [kaia_EN] section
        sed -i.bak "s/^sequencer_inbox_address = .*/sequencer_inbox_address = \"$SEQUENCER_INBOX_ADDRESS\"/" "$BACKEND_CONFIG_FILE"
        rm -f "${BACKEND_CONFIG_FILE}.bak"  # Remove backup file
        echo "✅ Updated sequencer_inbox_address in $BACKEND_CONFIG_FILE"
    else
        echo "⚠️  Warning: $BACKEND_CONFIG_FILE not found. Skipping update."
    fi

    echo ""
    echo "Helm values and backend config updated successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Commit the updated values-$ENV.yaml files and config/$ENV.toml to your Git repository."
    echo "2. ArgoCD will automatically sync the changes to the '$ENV' environment."

else
    echo "❌ ERROR: Deployment failed - $DEPLOYMENT_INFO_FILE not found"
    exit 1
fi

# Clean up volume
docker volume rm $CONFIG_VOLUME >/dev/null 2>&1 || true

