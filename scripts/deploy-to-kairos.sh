#!/usr/bin/env bash

set -e

# Kaia Orderbook DEX Core - L2 Deployment Script for Kairos Testnet

# Check for environment argument
ENV=${1:-dev}
if [[ ! "$ENV" =~ ^(dev|qa|staging|production)$ ]]; then
    echo "Usage: $0 [dev|qa|staging|production]"
    echo "Environment '$ENV' is not valid"
    exit 1
fi

# Configuration
KAIROS_RPC_URL="https://archive-en-kairos.node.kaia.io"
PARENT_CHAIN_ID=1001

# Environment-specific configuration
case $ENV in
    dev)
        DEPLOYER_PRIVKEY="${DEPLOYER_PRIVKEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        OWNER_ADDRESS="${OWNER_ADDRESS:-0x74139D025E36500715DB586779D2c9Ac65da9fF1}"
        SEQUENCER_ADDRESS="${SEQUENCER_ADDRESS:-0xf07ade7aa7dd067b6e9426a38bd538c0025bc784}"
        ;;
    qa)
        DEPLOYER_PRIVKEY="${DEPLOYER_PRIVKEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        OWNER_ADDRESS="${OWNER_ADDRESS:-0x74139D025E36500715DB586779D2c9Ac65da9fF1}"
        SEQUENCER_ADDRESS="${SEQUENCER_ADDRESS:-0xf07ade7aa7dd067b6e9426a38bd538c0025bc784}"
        ;;
    staging)
        DEPLOYER_PRIVKEY="${DEPLOYER_PRIVKEY:-0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1}"
        OWNER_ADDRESS="${OWNER_ADDRESS:-0x74139D025E36500715DB586779D2c9Ac65da9fF1}"
        SEQUENCER_ADDRESS="${SEQUENCER_ADDRESS:-0xf07ade7aa7dd067b6e9426a38bd538c0025bc784}"
        ;;
    production)
        echo "Production deployment requires specific configuration"
        echo "Please set DEPLOYER_PRIVKEY, OWNER_ADDRESS, and SEQUENCER_ADDRESS environment variables"
        exit 1
        ;;
esac

# Docker images
SCRIPTS_IMAGE="asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core-testnode/scripts:1.0.0"
ROLLUPCREATOR_IMAGE="asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core-testnode/rollupcreator:1.0.0"
NITRO_NODE_IMAGE="asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core:dev"

# Use local images if USE_LOCAL is set
if [ "${USE_LOCAL:-false}" = "true" ]; then
    SCRIPTS_IMAGE="kaia-orderbook-dex-core-testnode-scripts:latest"
    NITRO_NODE_IMAGE="nitro-node:latest"
fi

echo "=== Kaia Kairos Testnet L2 Deployment ==="
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
    docker pull $NITRO_NODE_IMAGE || { echo "Failed to pull nitro node image"; exit 1; }
    echo "Images pulled successfully!"
else
    echo "Using local images (USE_LOCAL=true)"
fi
echo ""

# Create config directory and volume
mkdir -p config
CONFIG_VOLUME="kairos-deploy-config"
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
TEMP_CONTAINER=$(docker create -v $CONFIG_VOLUME:/config alpine:latest sleep 60)
docker start $TEMP_CONTAINER >/dev/null

# Copy files with overwrite
docker cp $TEMP_CONTAINER:/config/deployment.json ./config/ 2>/dev/null || true
docker cp $TEMP_CONTAINER:/config/deployed_chain_info.json ./config/ 2>/dev/null || true
docker cp $TEMP_CONTAINER:/config/l2_chain_info.json ./config/ 2>/dev/null || true
docker cp $TEMP_CONTAINER:/config/l2_chain_config.json ./config/ 2>/dev/null || true

# Check and list all directories/files to find keystore
echo "Exploring container filesystem for keystore..."
docker exec $TEMP_CONTAINER sh -c "find / -name '*keystore*' -type d 2>/dev/null | head -20 || true"
docker exec $TEMP_CONTAINER sh -c "find / -name 'UTC--*' 2>/dev/null | head -20 || true"

# Try common keystore locations
for dir in /keystore /data/keystore /home/user/.ethereum/keystore /root/.ethereum/keystore; do
    echo "Checking $dir..."
    docker exec $TEMP_CONTAINER sh -c "ls -la $dir 2>/dev/null" && \
    docker cp $TEMP_CONTAINER:$dir ./config/keystore 2>/dev/null && \
    echo "✅ Copied keystore from $dir" && break || true
done

docker stop $TEMP_CONTAINER >/dev/null 2>&1
docker rm $TEMP_CONTAINER >/dev/null 2>&1

# Step 6: Create keystore for sequencer
echo "Step 6: Creating keystore for sequencer..."
mkdir -p ./config/$ENV/keystore

# Create keystore using Nitro node
echo "Creating keystore for address $SEQUENCER_ADDRESS..."
docker run --rm \
  --platform linux/amd64 \
  -v $(pwd)/config/$ENV:/config \
  -e PRIVATE_KEY="${DEPLOYER_PRIVKEY}" \
  $NITRO_NODE_IMAGE \
  --conf.file=/dev/null \
  --node.batch-poster.parent-chain-wallet.only-create-key \
  --node.batch-poster.parent-chain-wallet.password="passphrase" \
  --node.batch-poster.parent-chain-wallet.pathname="/config/keystore" || echo "Note: keystore creation attempt completed"

# List created keystore files
echo "Keystore files created:"
ls -la ./config/$ENV/keystore/ 2>/dev/null || echo "No keystore files found"

# Step 7: Generate sequencer configuration
echo "Step 7: Generating sequencer configuration..."
if [ -f "config/$ENV/deployed_chain_info.json" ]; then
    SEQUENCER_INBOX_ADDRESS=$(jq -r '.[0]."rollup"."sequencer-inbox"' config/$ENV/deployed_chain_info.json)
    CHAIN_ID=$(jq -r '.[0]."chain-config"."chainId"' config/$ENV/deployed_chain_info.json)

    cat > config/$ENV/sequencer_config.json << EOF
{
  "parent-chain": {
    "connection": {
      "url": "$KAIROS_RPC_URL"
    }
  },
  "chain": {
    "id": $CHAIN_ID,
    "info-files": [
      "/config/l2_chain_info.json"
    ]
  },
  "node": {
    "sequencer": true,
    "dangerous": {
      "no-sequencer-coordinator": true,
      "disable-blob-reader": true
    },
    "delayed-sequencer": {
      "enable": true
    },
    "batch-poster": {
      "enable": true,
      "max-delay": "30s",
      "parent-chain-wallet": {
        "account": "$SEQUENCER_ADDRESS",
        "password": "passphrase",
        "pathname": "/keystore"
      }
    },
    "data-availability": {
      "enable": false,
      "parent-chain-node-url": "$KAIROS_RPC_URL",
      "sequencer-inbox-address": "$SEQUENCER_INBOX_ADDRESS"
    }
  },
  "execution": {
    "sequencer": {
      "enable": true
    }
  },
  "http": {
    "addr": "0.0.0.0",
    "vhosts": "*",
    "corsdomain": "*"
  },
  "ws": {
    "addr": "0.0.0.0"
  }
}
EOF

    echo ""
    echo "=== Deployment Completed! ==="
    echo ""
    echo "Environment: $ENV"
    echo "Deployed contracts:"
    echo "- Rollup: $(jq -r '.[0]."rollup"."rollup"' config/$ENV/deployed_chain_info.json)"
    echo "- Bridge: $(jq -r '.[0]."rollup"."bridge"' config/$ENV/deployed_chain_info.json)"
    echo "- Inbox: $(jq -r '.[0]."rollup"."inbox"' config/$ENV/deployed_chain_info.json)"
    echo "- Sequencer Inbox: $SEQUENCER_INBOX_ADDRESS"
    echo ""
    echo "Configuration files created in ./config/$ENV/"
    echo ""
    echo "Next steps:"
    echo "1. Fund the sequencer address with KAIA tokens"
    echo "2. Upload config files to your sequencer server"
    echo "3. Run the sequencer with the generated configuration"
else
    echo "ERROR: Deployment failed - deployed_chain_info.json not found"
    exit 1
fi

# Clean up volume
docker volume rm $CONFIG_VOLUME >/dev/null 2>&1 || true
