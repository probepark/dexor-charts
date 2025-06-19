# Arbitrum Sequencer Node Pool Configuration

This document describes the Arbitrum sequencer node pool configuration for GKE.

## Overview

The sequencer node pool is a dedicated pool of nodes designed to run Arbitrum sequencer workloads. These nodes are configured with specific resources and taints to ensure optimal performance and isolation.

## Node Pool Specifications

- **Machine Type**: `n2-standard-4` (4 vCPU, 16GB RAM)
- **Disk**: 200GB SSD
- **Preemptible**: No (sequencer nodes should be stable)
- **Auto-upgrade**: Disabled (manual control for critical workloads)

## Autoscaling Configuration

### Development Environment
- Minimum nodes: 1
- Maximum nodes: 2

### Production Environment
- Minimum nodes: 1
- Maximum nodes: 3

## Node Labels

- `environment`: dev/prod
- `node-type`: sequencer
- `workload`: arbitrum-sequencer

## Node Taints

1. **Workload Taint** (all environments):
   - Key: `workload`
   - Value: `sequencer`
   - Effect: `NO_SCHEDULE`

2. **Environment Taint** (production only):
   - Key: `environment`
   - Value: `prod`
   - Effect: `NO_SCHEDULE`

## Enabling the Sequencer Node Pool

To enable the sequencer node pool, set the following variable in your Terraform configuration:

```hcl
enable_sequencer_pool = true
```

Example in `terraform.tfvars`:
```hcl
project_id = "your-project-id"
environment = "dev"
domain_suffix = "example.com"
dns_zone_name = "example-zone"
cert_manager_email = "admin@example.com"
enable_sequencer_pool = true  # Enable sequencer node pool
```

## Deploying Workloads to Sequencer Nodes

When deploying workloads to the sequencer node pool, you need to:

1. **Add node selector** to match the node labels:
   ```yaml
   nodeSelector:
     workload: arbitrum-sequencer
   ```

2. **Add tolerations** for the node taints:
   ```yaml
   tolerations:
   - key: workload
     operator: Equal
     value: sequencer
     effect: NoSchedule
   # For production environment, also add:
   - key: environment
     operator: Equal
     value: prod
     effect: NoSchedule
   ```

## Example Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: arbitrum-sequencer
  namespace: arbitrum-sequencer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: arbitrum-sequencer
  template:
    metadata:
      labels:
        app: arbitrum-sequencer
    spec:
      serviceAccountName: arbitrum-sequencer
      nodeSelector:
        workload: arbitrum-sequencer
      tolerations:
      - key: workload
        operator: Equal
        value: sequencer
        effect: NoSchedule
      containers:
      - name: sequencer
        image: your-sequencer-image
        resources:
          requests:
            cpu: 2
            memory: 8Gi
          limits:
            cpu: 3.5
            memory: 14Gi
```

## Monitoring and Maintenance

1. **Node Pool Status**: Check the node pool status using:
   ```bash
   gcloud container node-pools describe <environment>-sequencer-pool \
     --cluster=<environment>-gke-cluster \
     --region=<region>
   ```

2. **Node Upgrades**: Since auto-upgrade is disabled, manual upgrades are required:
   ```bash
   gcloud container node-pools update <environment>-sequencer-pool \
     --cluster=<environment>-gke-cluster \
     --region=<region> \
     --cluster-version=<new-version>
   ```

## Cost Optimization

- The node pool uses autoscaling to optimize costs
- Minimum of 1 node ensures availability
- Scales up to handle increased load
- Consider using committed use discounts for production nodes