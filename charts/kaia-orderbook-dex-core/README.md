# Kaia Orderbook DEX Core Helm Chart

This Helm chart deploys the Kaia Orderbook DEX Core (Nitro Node) on a Kubernetes cluster.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PV provisioner support in the underlying infrastructure
- Redis instance (for sequencer coordination)
- Access to Kaia parent chain RPC endpoint

## Installing the Chart

### Quick Start with Kairos Testnet

1. First, deploy contracts to Kairos testnet:
```bash
cd ../../scripts
./deploy-to-kairos.sh
```

2. Deploy to Kubernetes using the generated configuration:
```bash
./deploy-core-to-k8s.sh
```

### Manual Installation

To install the chart with the release name `my-release`:

```bash
helm install my-release ./charts/kaia-orderbook-dex-core
```

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```bash
helm delete my-release
```

## Configuration

The following table lists the configurable parameters of the chart and their default values.

### Global Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.imageRegistry` | Global Docker image registry | `""` |
| `global.imagePullSecrets` | Global Docker registry secret names | `[]` |
| `global.storageClass` | Global storage class for persistence | `""` |

### Nitro Node Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nitroNode.enabled` | Enable Nitro node deployment | `true` |
| `nitroNode.replicaCount` | Number of Nitro node replicas | `1` |
| `nitroNode.image.repository` | Nitro node image repository | `kaia-orderbook-nitro-node` |
| `nitroNode.image.tag` | Image tag | `""` |
| `nitroNode.service.httpPort` | HTTP RPC port | `8547` |
| `nitroNode.service.wsPort` | WebSocket port | `8548` |
| `nitroNode.service.feedPort` | Feed broadcast port | `9642` |
| `nitroNode.persistence.enabled` | Enable persistent storage | `true` |
| `nitroNode.persistence.size` | PVC size | `100Gi` |
| `nitroNode.resources` | CPU/Memory resource requests/limits | See values.yaml |

### Validator Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `validator.enabled` | Enable validator deployment | `false` |
| `validator.replicaCount` | Number of validator replicas | `1` |
| `validator.image.repository` | Validator image repository | `kaia-orderbook-nitro-node-validator` |
| `validator.persistence.size` | PVC size for validator | `50Gi` |

### Sequencer Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `sequencer.enabled` | Enable sequencer mode | `true` |
| `sequencer.redis.enabled` | Enable Redis for coordination | `true` |
| `sequencer.redis.url` | Redis connection URL | `redis://redis-service:6379` |
| `sequencer.batchPoster.enabled` | Enable batch posting to L1 | `true` |
| `sequencer.dataAvailability.mode` | DA mode (onchain/anytrust) | `onchain` |

### Environment Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `environment.phase` | Deployment phase (dev/staging/prod) | `dev` |
| `environment.parentChain.rpcUrl` | Parent chain RPC URL | Kaia testnet URL |
| `environment.childChain.chainId` | L2 chain ID | `412346` |

### Orderbook Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nitroConfig.orderbook.enabled` | Enable orderbook functionality | `true` |
| `nitroConfig.orderbook.gasLimit` | Gas limit for orderbook ops | `50000000` |

## Example Usage

### Production Deployment with HA

```yaml
nitroNode:
  replicaCount: 3
  persistence:
    size: 500Gi
    storageClass: fast-ssd
  resources:
    requests:
      cpu: 4
      memory: 16Gi
    limits:
      cpu: 8
      memory: 32Gi

sequencer:
  enabled: true
  redis:
    url: "redis://redis-cluster:6379"
  batchPoster:
    enabled: true
    maxDelay: "5m"

validator:
  enabled: true
  replicaCount: 2

monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
```

### Development Deployment

```yaml
nitroNode:
  replicaCount: 1
  persistence:
    size: 20Gi
  resources:
    requests:
      cpu: 1
      memory: 2Gi
    limits:
      cpu: 2
      memory: 4Gi

sequencer:
  enabled: false

nitroConfig:
  dangerous:
    noL1Listener: true  # For local testing only
```

### Archive Node Configuration

```yaml
nitroConfig:
  archiveMode: true

nitroNode:
  persistence:
    size: 1Ti  # Archive nodes need more storage
  resources:
    requests:
      memory: 32Gi
```

## Architecture

The Nitro node is based on Arbitrum Nitro technology, providing:

1. **Layer 2 Scaling**: High-performance execution environment
2. **Orderbook DEX**: On-chain orderbook functionality
3. **EVM Compatibility**: Full Ethereum compatibility
4. **WASM Support**: Stylus smart contracts support

### Components

- **Nitro Node**: Main node handling RPC requests and block production
- **Validator**: Optional validator for block validation
- **Sequencer**: Transaction ordering and batch submission
- **Feed Broadcaster**: Real-time data feed for other services

## Persistence

The chart uses StatefulSets for both Nitro node and validator to ensure stable network identity and persistent storage. Data is stored in:

- `/data/chain`: Blockchain state
- `/data/config`: Node configuration

## Monitoring

When monitoring is enabled, the chart exposes Prometheus metrics on port 6060 at `/metrics` endpoint.

## Notes

1. The Nitro node requires significant resources, especially for archive nodes
2. Redis is required for sequencer coordination in multi-node setups
3. Ensure proper network connectivity to the parent chain
4. Contract addresses must be configured after initial deployment
5. Use PodDisruptionBudget carefully as nodes need graceful shutdown