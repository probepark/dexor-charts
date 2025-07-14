# Datadog Log Collection Configuration

This guide explains how to configure Datadog to collect logs using an opt-in approach where only pods with specific annotations will have their logs collected.

## Current Configuration

The Datadog Operator is configured to:
- **Enable only log collection** - All other features (APM, NPM, USM, etc.) are disabled
- **Opt-in log collection** - Only pods with Datadog annotations will have logs collected
- **No default log collection** - Pods without annotations are ignored

## Configuration Details

### 1. Feature Configuration

In `main.tf`, only log collection is enabled:

```hcl
features = {
  apm = {
    enabled = false
  }
  logCollection = {
    enabled                    = true
    containerCollectAll        = false  # Don't collect all containers
    containerCollectUsingFiles = true
  }
  liveProcessCollection = {
    enabled = false
  }
  # ... other features disabled
}
```

### 2. Opt-in Configuration

The NodeAgent is configured to NOT collect logs by default:

```hcl
env = [
  {
    name  = "DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL"
    value = "false"
  },
  {
    name  = "DD_LOGS_CONFIG_K8S_CONTAINER_USE_FILE"
    value = "true"
  },
  {
    name  = "DD_LOGS_CONFIG_AUTO_MULTI_LINE_DETECTION"
    value = "true"
  }
]
```

## How Opt-in Log Collection Works

### Annotation-Based Collection
- **No automatic collection**: Datadog Agent will NOT collect logs from any pod by default
- **Explicit opt-in required**: Pods must have Datadog annotations to enable log collection
- **Per-container control**: You can enable/disable logs for specific containers in a pod

## Enabling Log Collection for Your Helm Charts

### Basic Configuration

To enable log collection for a Helm chart, add the Datadog annotation to your pod template:

```yaml
# In your Helm chart's values.yaml
podAnnotations:
  ad.datadoghq.com/<container-name>.logs: |
    [
      {
        "source": "<source-technology>",
        "service": "<service-name>",
        "tags": ["<tag1>", "<tag2>"]
      }
    ]
```

Replace:
- `<container-name>`: The name of your container
- `<source-technology>`: The technology (e.g., nodejs, java, python, go)
- `<service-name>`: Your service name
- `<tag1>`, `<tag2>`: Any tags you want to add

### Real Examples

#### Backend Service (Node.js)
```yaml
podAnnotations:
  ad.datadoghq.com/backend.logs: |
    [
      {
        "source": "nodejs",
        "service": "backend-api",
        "tags": ["team:backend", "env:production"]
      }
    ]
```

#### Core Service (Java)
```yaml
podAnnotations:
  ad.datadoghq.com/core.logs: |
    [
      {
        "source": "java",
        "service": "core-service",
        "tags": ["team:core", "env:production"]
      }
    ]
```

## Advanced Configuration

### Per-Container Log Processing

You can add autodiscovery annotations to your pods to configure log processing:

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    ad.datadoghq.com/<container-name>.logs: |
      [
        {
          "source": "backend",
          "service": "backend-api",
          "tags": ["env:prod", "version:1.0"]
        }
      ]
```

### Log Pipeline Configuration

Configure log processing rules in your pod annotations:

```yaml
annotations:
  ad.datadoghq.com/<container-name>.logs: |
    [
      {
        "source": "nodejs",
        "service": "backend-api",
        "log_processing_rules": [
          {
            "type": "exclude_at_match",
            "name": "exclude_healthcheck",
            "pattern": "GET /health"
          }
        ]
      }
    ]
```

## Helm Chart Configuration

For backend and core Helm charts, ensure they have proper labels:

### Backend Chart values.yaml
```yaml
commonLabels:
  app.kubernetes.io/name: backend
  app.kubernetes.io/instance: backend
```

### Core Chart values.yaml
```yaml
commonLabels:
  app.kubernetes.io/name: core
  app.kubernetes.io/instance: core
```

## Verifying Log Collection

### 1. Check Datadog Agent Status

```bash
kubectl exec -it -n datadog <datadog-pod-name> -- agent status
```

### 2. Check Log Collection Status

```bash
kubectl exec -it -n datadog <datadog-pod-name> -- agent stream-logs
```

### 3. Verify in Datadog UI

1. Go to [Datadog Logs](https://app.datadoghq.com/logs)
2. Filter by:
   - `service:backend-*` or `service:core-*`
   - `kube_namespace:<your-namespace>`
   - `kube_container_name:backend*` or `kube_container_name:core*`

## Troubleshooting

### Logs Not Appearing

1. Check if containers match the filter pattern:
```bash
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
```

2. Verify pod labels:
```bash
kubectl get pods -n <namespace> --show-labels
```

3. Check Datadog Agent logs:
```bash
kubectl logs -n datadog -l app.kubernetes.io/component=nodeAgent -f | grep -i log
```

### Performance Optimization

To reduce resource usage when collecting logs:

1. Use specific container filters (as configured)
2. Set appropriate resource limits for the NodeAgent
3. Consider using log sampling for high-volume applications

## Cost Optimization

Since only log collection is enabled:
- Lower CPU and memory usage compared to full monitoring
- Reduced data ingestion costs
- No APM trace data costs
- No NPM or USM data costs

Monitor your log volume in Datadog:
- Go to [Usage & Cost](https://app.datadoghq.com/account/usage)
- Check "Indexed Logs" for volume and costs