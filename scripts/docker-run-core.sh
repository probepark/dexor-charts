#!/bin/bash
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Kaia Orderbook DEX Core - Docker Quick Start ===${NC}"
echo ""

# Docker image
# DOCKER_IMAGE="asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core:dev"
#DOCKER_IMAGE="nitro-node:latest"
DOCKER_IMAGE="nitro-node-dev:latest"

# Environment variables
PARENT_CHAIN_RPC="https://archive-en-kairos.node.kaia.io"
CHILD_CHAIN_ID=412346
PARENT_CHAIN_ID=1001

# Pre-configured Private Keys
SEQUENCER_KEY="cc56168a0e292aad91d2f03a976da05910215a6d3cafff8bdad463736ac8f548"
VALIDATOR_KEY="b00ed2290acbb3a03ce2e08ae15ffc32aa163789efdae5d1edd69ae05b14d12b"

# Contract addresses (dev environment - 2025-06-19 deployment)
ROLLUP_ADDRESS="0xe4D7992e5e0F994c82073b6D805bcbd13212639f"
SEQUENCER_INBOX="0x0e4029512C2a7893669632faE2e9973cD03975a1"
VALIDATOR_WALLET_CREATOR="0xd54bEA42609092D3e7a41Cc51AE76E597Ca004e7"
WASM_MODULE_ROOT="0x184884e1eb9fefdc158f6c8ac912bb183bf3cf83f0090317e0bc4ac5860baa39"

# Find project root directory from script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Data directory
DATA_DIR="${DATA_DIR:-$PROJECT_ROOT/arbitrum-data}"
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/config"

echo "$PROJECT_ROOT/config/local/l2_chain_info.json" "$DATA_DIR/chain-info.json"

# Copy chain info file (use existing file)
cp "$PROJECT_ROOT/config/local/l2_chain_info.json" "$DATA_DIR/chain-info.json"

# Mode selection
if [[ -z "$1" ]]; then
    echo "Usage: $0 [mode]"
    echo ""
    echo "Available modes:"
    echo "  archive    - Archive Node (Read-only)"
    echo "  sequencer  - Sequencer Mode"
    echo "  validator  - Validator/Staker Mode"
    echo "  full       - Full Node (Sequencer + Validator)"
    echo ""
    echo "Example:"
    echo "  $0 archive"
    echo "  $0 full"
    exit 1
fi

MODE=$1

# Common Docker options
DOCKER_OPTS=(
#    -d
    --name kaia-core-$MODE
    --restart unless-stopped
    -v "$DATA_DIR:/data"
    -v "$DATA_DIR/chain-info.json:/config/chain-info.json:ro"
    -e ROLLUP_ADDRESS=$ROLLUP_ADDRESS
    -e SEQUENCER_INBOX_ADDRESS=$SEQUENCER_INBOX
    -e VALIDATOR_WALLET_CREATOR=$VALIDATOR_WALLET_CREATOR
    -p 8547:8547  # HTTP RPC
    -p 8548:8548  # WebSocket
    -p 6060:6060  # Metrics & pprof
    -p 9642:9642  # Feed output (sequencer/full mode)
    --log-driver json-file
    --log-opt max-size=100m
    --log-opt max-file=3
)

# Mode-specific command options
case $MODE in
    archive)
        echo -e "${GREEN}Starting Archive Node...${NC}"
        CMD_OPTS=(
            --chain.id=$CHILD_CHAIN_ID
            --parent-chain.id=$PARENT_CHAIN_ID
            --parent-chain.connection.url=$PARENT_CHAIN_RPC
            --chain.info-files=/config/chain-info.json
            --persistent.chain=/data/chain
            --persistent.global-config=/data/config
            --http.addr=0.0.0.0
            --http.port=8547
            --http.vhosts="*"
            --http.corsdomain="*"
            --http.api=net,web3,eth,debug,arb
            --ws.addr=0.0.0.0
            --ws.port=8548
            --ws.origins="*"
            --node.dangerous.disable-blob-reader
            --node.staker.enable=false
            --validation.wasm.allowed-wasm-module-roots=$WASM_MODULE_ROOT
            --validation.wasm.root-path=/data/wasm
            --node.block-validator.enable=false
            --execution.parent-chain-reader.use-finality-data=false
            --metrics
            --metrics-server.addr=0.0.0.0
            --metrics-server.port=6060
            --log-level=3
            --execution.stylus-target.amd64="x86_64-linux-unknown"
            --pprof
            --pprof-cfg.addr=0.0.0.0
            --graphql.enable
            --graphql.vhosts="*"
            --graphql.corsdomain="*"
        )
        ;;

    sequencer)
        echo -e "${GREEN}Starting Sequencer Mode...${NC}"
        CMD_OPTS=(
            --chain.id=$CHILD_CHAIN_ID
            --parent-chain.id=$PARENT_CHAIN_ID
            --parent-chain.connection.url=$PARENT_CHAIN_RPC
            --chain.info-files=/config/chain-info.json
            --persistent.chain=/data/chain
            --persistent.global-config=/data/config
            --http.addr=0.0.0.0
            --http.port=8547
            --http.vhosts="*"
            --http.corsdomain="*"
            --http.api=net,web3,eth,debug,arb
            --ws.addr=0.0.0.0
            --ws.port=8548
            --ws.origins="*"
            --node.sequencer
            --execution.sequencer.enable
            --execution.sequencer.queue-size=4096
            --execution.sequencer.max-block-speed=250ms
            --execution.sequencer.max-revert-gas-reject=0
            --execution.rpc.gas-cap=150000000
            --execution.rpc.tx-fee-cap=10
            --node.delayed-sequencer.enable
            --node.batch-poster.enable
            --node.batch-poster.parent-chain-wallet.private-key=$SEQUENCER_KEY
            --node.batch-poster.max-delay=10s
            --node.batch-poster.compression-level=6
            --node.batch-poster.l1-block-bound=latest
            --node.batch-poster.data-poster.max-mempool-transactions=20
            --node.dangerous.no-sequencer-coordinator
            --node.dangerous.disable-blob-reader
            --node.staker.enable=false
            --validation.wasm.allowed-wasm-module-roots=$WASM_MODULE_ROOT
            --validation.wasm.root-path=/data/wasm
            --node.block-validator.enable=false
            --execution.parent-chain-reader.use-finality-data=false
            --metrics
            --metrics-server.addr=0.0.0.0
            --metrics-server.port=6060
            --log-level=3
            --execution.stylus-target.amd64="x86_64-linux-unknown"
            --pprof
            --pprof-cfg.addr=0.0.0.0
            --graphql.enable
            --graphql.vhosts="*"
            --graphql.corsdomain="*"
            --node.feed.output.enable
            --node.feed.output.port=9642
        )
        ;;

    validator)
        echo -e "${GREEN}Starting Validator Mode...${NC}"
        echo "Validator: 0x6EE63697Bbd931D48d2bF1e41789A0B45e0d2235"
        CMD_OPTS=(
            --chain.id=$CHILD_CHAIN_ID
            --parent-chain.id=$PARENT_CHAIN_ID
            --parent-chain.connection.url=$PARENT_CHAIN_RPC
            --chain.info-files=/config/chain-info.json
            --persistent.chain=/data/chain
            --persistent.global-config=/data/config
            --http.addr=0.0.0.0
            --http.port=8547
            --http.vhosts="*"
            --http.corsdomain="*"
            --http.api=net,web3,eth,debug,arb
            --ws.addr=0.0.0.0
            --ws.port=8548
            --ws.origins="*"
            --node.staker.enable
            --node.staker.parent-chain-wallet.private-key=$VALIDATOR_KEY
            --node.staker.strategy=MakeNodes
            --node.bold.strategy=MakeNodes
            --node.staker.use-smart-contract-wallet
            --node.staker.dangerous.without-block-validator
            --node.staker.disable-challenge=false
            --node.staker.confirmation-blocks=10
            --node.staker.make-assertion-interval=30s
            --node.staker.enable-fast-confirmation=true
            --node.staker.data-poster.max-mempool-transactions=20
            --node.bold.rpc-block-number=latest
            --node.bold.state-provider-config.check-batch-finality=false
#            --node.bold.gas-price=250000000000
#            --node.bold.gas-limit=300000
            --node.bold.parent-chain-block-time=1s
            --node.bold.max-get-log-blocks=100
            --node.bold.assertion-scanning-interval=60s
            --node.inbox-reader.read-mode=latest
            --node.parent-chain-reader.use-finality-data=false
            --execution.parent-chain-reader.use-finality-data=false
            --ensure-rollup-deployment=false
            --node.dangerous.disable-blob-reader
            --validation.wasm.allowed-wasm-module-roots=$WASM_MODULE_ROOT
            --validation.wasm.root-path=/data/wasm
            --node.block-validator.enable=false
            --metrics
            --metrics-server.addr=0.0.0.0
            --metrics-server.port=6060
            --log-level=3
            --execution.stylus-target.amd64="x86_64-linux-unknown"
            --pprof
            --pprof-cfg.addr=0.0.0.0
            --graphql.enable
            --graphql.vhosts="*"
            --graphql.corsdomain="*"
        )
        ;;

    full)
        echo -e "${GREEN}Starting Full Node (Sequencer + Validator)...${NC}"
        CMD_OPTS=(
            --chain.id=$CHILD_CHAIN_ID
            --parent-chain.id=$PARENT_CHAIN_ID
            --parent-chain.connection.url=$PARENT_CHAIN_RPC
            --chain.info-files=/config/chain-info.json
            --persistent.chain=/data/chain
            --persistent.global-config=/data/config
            --http.addr=0.0.0.0
            --http.port=8547
            --http.vhosts="*"
            --http.corsdomain="*"
            --http.api=net,web3,eth,debug,arb,arbinternal
#            --init.latest=archive
            --ws.addr=0.0.0.0
            --ws.port=8548
            --ws.origins="*"
            --node.sequencer
            --execution.sequencer.enable
            --execution.sequencer.queue-size=4096
            --execution.sequencer.max-block-speed=250ms
            --execution.sequencer.max-revert-gas-reject=0
            --execution.rpc.gas-cap=150000000
            --execution.rpc.tx-fee-cap=10
#            --execution.caching.archive
            --node.delayed-sequencer.enable
            --node.batch-poster.enable
            --node.batch-poster.parent-chain-wallet.private-key=$SEQUENCER_KEY
            --node.batch-poster.max-delay=10s
            --node.batch-poster.compression-level=6
            --node.batch-poster.l1-block-bound=latest
            --node.batch-poster.data-poster.max-mempool-transactions=20
            --node.staker.enable
            --node.staker.parent-chain-wallet.private-key=$VALIDATOR_KEY
            --node.staker.strategy=MakeNodes
            --node.bold.strategy=MakeNodes
            --node.staker.dangerous.without-block-validator
            --node.staker.disable-challenge=false
            --node.staker.confirmation-blocks=12
            --node.staker.make-assertion-interval=60s
            --node.staker.enable-fast-confirmation=false
            --node.staker.data-poster.max-mempool-transactions=30
            --node.staker.staker-interval=30s
            --node.bold.rpc-block-number=latest
            --node.bold.state-provider-config.check-batch-finality=false
#            --node.bold.gas-price=250000000000
#            --node.bold.gas-limit=300000
            --node.bold.parent-chain-block-time=1s
            --node.bold.max-get-log-blocks=100
            --node.bold.assertion-scanning-interval=60s
            --node.bold.assertion-posting-interval=2m
            --node.inbox-reader.read-mode=latest
            --node.parent-chain-reader.use-finality-data=false
            --execution.parent-chain-reader.use-finality-data=false
            --ensure-rollup-deployment=false
            --node.dangerous.no-sequencer-coordinator
            --node.dangerous.disable-blob-reader
            --validation.wasm.allowed-wasm-module-roots=$WASM_MODULE_ROOT
            --validation.wasm.root-path=/data/wasm
            --node.block-validator.enable=false
            --metrics
            --metrics-server.addr=0.0.0.0
            --metrics-server.port=6060
            --log-level=3
            --execution.stylus-target.amd64="x86_64-linux-unknown"
            --pprof
            --pprof-cfg.addr=0.0.0.0
            --graphql.enable
            --graphql.vhosts="*"
            --graphql.corsdomain="*"
            --node.feed.output.enable
            --node.feed.output.port=9642
        )
        ;;

    *)
        echo -e "${RED}Invalid mode: $MODE${NC}"
        exit 1
        ;;
esac

# Clean up existing container
if docker ps -a | grep -q "kaia-core-$MODE"; then
    echo -e "${YELLOW}Removing existing container...${NC}"
    docker rm -f kaia-core-$MODE
fi

# Pull Docker image (skip for local images)
if [[ ! "$DOCKER_IMAGE" =~ ^nitro-node.*:latest$ ]]; then
    echo -e "${YELLOW}Pulling Docker image...${NC}"
    docker pull --platform=linux/amd64 "$DOCKER_IMAGE"
else
    echo -e "${YELLOW}Using local image: $DOCKER_IMAGE${NC}"
fi

# Run container
echo -e "${YELLOW}Starting container...${NC}"
docker run --platform=linux/amd64 "${DOCKER_OPTS[@]}" "$DOCKER_IMAGE" "${CMD_OPTS[@]}"

echo ""
echo -e "${GREEN}Container started successfully!${NC}"
echo ""
echo "Access points:"
echo "  RPC: http://localhost:8547"
echo "  WebSocket: ws://localhost:8548"
echo "  Metrics: http://localhost:6060/metrics"
echo "  GraphQL: http://localhost:8547/graphql"
echo "  pprof: http://localhost:6060/debug/pprof/"
if [[ "$MODE" == "sequencer" || "$MODE" == "full" ]]; then
    echo "  Feed: http://localhost:9642"
fi
echo ""
echo "Container management:"
echo "  View logs:   docker logs -f kaia-core-$MODE"
echo "  Stop:        docker stop kaia-core-$MODE"
echo "  Start:       docker start kaia-core-$MODE"
echo "  Remove:      docker rm -f kaia-core-$MODE"
echo ""
