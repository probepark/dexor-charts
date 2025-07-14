# Datadog Deployment Guide

## Overview
This guide explains how to deploy Datadog monitoring with log collection only.

## Deployment Steps

### 1. Enable Datadog in terraform.tfvars
```hcl
enable_datadog  = true
datadog_api_key = "your-api-key"
datadog_app_key = "your-app-key"
datadog_site    = "datadoghq.com"  # or "datadoghq.eu" for EU
```

### 2. Apply Terraform Configuration
```bash
# For dev environment
make apply-dev

# For prod environment
make apply-prod
```

### 3. Wait for Datadog Operator
```bash
kubectl get pods -n datadog
```

Wait until `datadog-operator-*` pod is Running.

### 4. Deploy DatadogAgent

For **dev** environment:
```bash
kubectl apply -f terraform/datadog-agent-dev.yaml
```

For **prod** environment:
```bash
kubectl apply -f terraform/datadog-agent-prod.yaml
```

### 5. Verify Deployment
```bash
kubectl get pods -n datadog
```

You should see:
- `datadog-operator-*` (1 pod)
- `datadog-agent-*` (1 per node)
- `datadog-cluster-agent-*` (1 for dev, 2 for prod)

## Log Collection Configuration

### Only Labeled Pods
Only pods with the label `datadog-logs-enabled=true` will have their logs collected.

### Check Which Pods Have Logs Enabled
```bash
kubectl get pods --all-namespaces -l datadog-logs-enabled=true
```

### Environment Differences

#### Dev Environment
- Cluster Agent: 1 replica
- Cluster Checks Runner: 1 replica
- Lower resource requests/limits
- No node selectors or tolerations

#### Prod Environment
- Cluster Agent: 2 replicas (HA)
- Cluster Checks Runner: 2 replicas (HA)
- Higher resource requests/limits
- Node selector: `environment: prod`
- Toleration for `environment=prod:NoSchedule` taint

## Troubleshooting

### Check Agent Logs
```bash
kubectl logs -n datadog daemonset/datadog-agent -c agent
```

### Check Cluster Agent Logs
```bash
kubectl logs -n datadog deployment/datadog-cluster-agent
```

### Verify Log Collection is Enabled
```bash
kubectl logs -n datadog daemonset/datadog-agent -c agent | grep -i "logs-agent started"
```

### Common Issues

1. **Pods in Pending State**
   - Check resource availability: `kubectl describe pod <pod-name> -n datadog`
   - Reduce resource requests in datadog-agent-*.yaml

2. **No Logs in Datadog**
   - Verify pods have `datadog-logs-enabled=true` label
   - Check agent logs for errors
   - Ensure API key is correct

3. **Agent CrashLoopBackOff**
   - Check logs: `kubectl logs <pod-name> -n datadog -c agent --previous`
   - Verify secret exists: `kubectl get secret datadog-secret -n datadog`