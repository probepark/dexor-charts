# Configuration Management Guide

This guide explains how to manage configuration files for the Kaia Orderbook DEX Core Helm chart.

## Overview

The chart now supports a flexible configuration management system that:
- Stores all configuration files in a ConfigMap
- Allows easy overrides through values.yaml
- Supports dynamic generation of sequencer config
- Maintains backward compatibility

## Configuration Structure

### 1. Dynamic Sequencer Config Generation

When `config.generateSequencerConfig: true`, the chart automatically generates `sequencer_config.json` based on values:

```yaml
config:
  generateSequencerConfig: true

sequencer:
  enabled: true
  redis:
    enabled: false
  batchPoster:
    enabled: true
    maxDelay: "30s"
```

### 2. Custom Configuration Files

You can inject any configuration files through the `config.files` map:

```yaml
config:
  files:
    l2_chain_info.json: |
      {
        "chain-id": 412346,
        "parent-chain-id": 1001,
        "chain-config": {
          "chainId": 412346,
          "homesteadBlock": 0
        }
      }
    deployment.json: |
      {
        "rollup": "0x123...",
        "validators": ["0xabc..."],
        "batch-poster": "0xdef..."
      }
    custom-config.json: |
      {
        "custom": "values"
      }
```

### 3. Legacy Support

For backward compatibility, individual config fields are still supported:

```yaml
environment:
  chainConfig: |
    {
      "chainId": 412346
    }
  chainInfo: |
    {
      "chain-id": 412346
    }
  deploymentInfo: |
    {
      "rollup": "0x123..."
    }
```

## Usage Examples

### Development Environment

```yaml
# values-dev.yaml
config:
  generateSequencerConfig: true
  files:
    dev-overrides.json: |
      {
        "debug": true,
        "log-level": 5
      }
```

### Production Environment

```yaml
# values-prod.yaml
config:
  generateSequencerConfig: true
  files:
    l2_chain_info.json: |
      {{ .Files.Get "configs/prod/l2_chain_info.json" | indent 6 }}
    deployment.json: |
      {{ .Files.Get "configs/prod/deployment.json" | indent 6 }}
```

### Using with deploy-core-to-k8s.sh

The deployment script automatically:
1. Reads configuration files from `config/` directory
2. Injects them into the `config.files` map
3. Deploys to Kubernetes

```bash
# After running deploy-to-kairos.sh
./scripts/deploy-core-to-k8s.sh

# With custom namespace and release
NAMESPACE=dex-core RELEASE_NAME=my-dex ./scripts/deploy-core-to-k8s.sh
```

## ConfigMap Structure

The generated ConfigMap contains:
- `sequencer_config.json` (if generateSequencerConfig is true)
- All files from `config.files` map
- Legacy config files (if no files map is provided)

## Mounting in Pods

Configuration files are mounted at `/config/` in the container:
- `/config/sequencer_config.json`
- `/config/l2_chain_info.json`
- `/config/deployment.json`
- `/config/<any-custom-file>.json`

## Best Practices

1. **Use config.files for all config**: Prefer the new structure over legacy fields
2. **Environment-specific values**: Create separate values files for each environment
3. **Sensitive data**: Use Kubernetes Secrets for sensitive configuration
4. **Version control**: Track configuration changes in Git
5. **Validation**: Always validate JSON syntax before deployment

## Troubleshooting

Check configuration in a running pod:
```bash
kubectl exec -it <pod-name> -- ls -la /config/
kubectl exec -it <pod-name> -- cat /config/sequencer_config.json
```

View the ConfigMap:
```bash
kubectl get configmap <release-name>-config -o yaml
```

## Migration from Old Structure

To migrate from the old structure:

1. Move individual config strings to files map:
   ```yaml
   # Old
   environment:
     chainConfig: |
       {"chainId": 412346}
   
   # New
   config:
     files:
       l2_chain_config.json: |
         {"chainId": 412346}
   ```

2. Enable dynamic sequencer config generation:
   ```yaml
   config:
     generateSequencerConfig: true
   ```

3. Remove redundant configuration from StatefulSet args