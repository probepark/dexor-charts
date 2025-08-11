# Docker Run Core - Quick Usage Guide

## How to Change the Docker Image

### Option 1: Edit the script
```bash
# Open the script and change the DOCKER_IMAGE variable (line 16)
vim scripts/docker-run-core.sh

# Change from:
DOCKER_IMAGE="nitro-node-dev:latest"

# To your desired image:
DOCKER_IMAGE="asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core:dev"
```

### Option 2: Use environment variable
```bash
# Set the image via environment variable before running
export DOCKER_IMAGE="your-custom-image:tag"
./scripts/docker-run-core.sh full
```

## How to Run a Full Node

### Quick Start
```bash
# Run full node (Sequencer + Validator)
./scripts/docker-run-core.sh full
```

### What Full Node Includes
- Sequencer functionality (processes transactions)
- Validator/Staker functionality (validates blocks)
- HTTP RPC on port 8547
- WebSocket on port 8548
- Metrics on port 6060
- GraphQL endpoint
- Feed output on port 9642

### Other Available Modes
```bash
# Archive node (read-only)
./scripts/docker-run-core.sh archive

# Sequencer only
./scripts/docker-run-core.sh sequencer

# Validator only
./scripts/docker-run-core.sh validator
```

### Container Management
```bash
# View logs
docker logs -f kaia-core-full

# Stop the node
docker stop kaia-core-full

# Start again
docker start kaia-core-full

# Remove completely
docker rm -f kaia-core-full
```

### Custom Data Directory
```bash
# Use a custom data directory
export DATA_DIR=/path/to/your/data
./scripts/docker-run-core.sh full
```

### Notes
- Local images (nitro-node*:latest) won't be pulled from registry
- Data is persisted in `./arbitrum-data` by default
- Container runs in foreground (add `-d` to DOCKER_OPTS for background)