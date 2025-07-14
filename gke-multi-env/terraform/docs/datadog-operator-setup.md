# Datadog Operator Setup Guide

This guide explains how to deploy and configure the Datadog Operator in your GKE cluster using Terraform.

## Prerequisites

1. A Datadog account with API and Application keys
2. GKE cluster deployed using this Terraform configuration
3. `kubectl` configured to access your cluster
4. Terraform installed and initialized

## Configuration

### 1. Enable Datadog in Terraform Variables

Create or update your `terraform.tfvars` file:

```hcl
# Enable Datadog monitoring
enable_datadog = true

# Datadog credentials (keep these secure!)
datadog_api_key = "your-datadog-api-key"
datadog_app_key = "your-datadog-app-key"

# Datadog site (use datadoghq.eu for EU region)
datadog_site = "datadoghq.com"
```

### 2. Apply Terraform Configuration

```bash
# Plan the changes
terraform plan

# Apply the configuration
terraform apply
```

### 3. Verify Installation

Check that the Datadog Operator and agents are running:

```bash
# Check operator pod
kubectl get pods -n datadog

# Check DatadogAgent resource
kubectl get datadogagent -n datadog

# View agent logs
kubectl logs -n datadog -l app.kubernetes.io/name=datadog-agent
```

## Features Enabled

The following Datadog features are automatically enabled:

- **APM (Application Performance Monitoring)**: Trace collection on port 8126
- **Log Collection**: Automatic log collection from all containers
- **Live Process Monitoring**: Real-time process visibility
- **Live Container Monitoring**: Container metrics and metadata
- **Network Performance Monitoring (NPM)**: Network flow monitoring
- **Orchestrator Explorer**: Kubernetes resource visualization
- **Prometheus Scraping**: Automatic discovery of Prometheus endpoints
- **Universal Service Monitoring (USM)**: Service dependency mapping

## Customization

### Adding Custom Monitors

Create a DatadogMonitor resource:

```yaml
apiVersion: datadoghq.com/v1alpha1
kind: DatadogMonitor
metadata:
  name: nginx-high-error-rate
  namespace: datadog
spec:
  name: "High Error Rate on NGINX"
  type: "metric alert"
  message: "NGINX error rate is above threshold"
  query: "avg(last_5m):sum:nginx.requests.errors{environment:prod} by {host} > 100"
  tags:
    - "env:prod"
    - "service:nginx"
  thresholds:
    critical: 100
    warning: 50
```

### Application APM Setup

Add these environment variables to your application pods:

```yaml
env:
  - name: DD_AGENT_HOST
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP
  - name: DD_TRACE_AGENT_PORT
    value: "8126"
  - name: DD_SERVICE
    value: "your-service-name"
  - name: DD_ENV
    value: "prod"
  - name: DD_VERSION
    value: "1.0.0"
```

### Custom Log Processing

Add annotations to your pods for custom log parsing:

```yaml
annotations:
  ad.datadoghq.com/your-container.logs: |
    [{
      "source": "your-app",
      "service": "your-service",
      "log_processing_rules": [{
        "type": "multi_line",
        "name": "log_start_with_date",
        "pattern": "\\d{4}-\\d{2}-\\d{2}"
      }]
    }]
```

## Resource Allocation

Resources are automatically adjusted based on environment:

### Development Environment
- Node Agent: 200m CPU, 256Mi memory
- Cluster Agent: 1 replica, 200m CPU, 256Mi memory
- Minimal resource usage for cost efficiency

### Production Environment
- Node Agent: 1000m CPU, 512Mi memory
- Cluster Agent: 2 replicas, 1000m CPU, 512Mi memory
- High availability configuration

## Troubleshooting

### Agent Not Starting

1. Check secrets:
```bash
kubectl get secret datadog-secret -n datadog -o yaml
```

2. View pod events:
```bash
kubectl describe pod -n datadog -l app.kubernetes.io/name=datadog-agent
```

### No Metrics in Datadog

1. Verify cluster name in Datadog UI matches your configuration
2. Check agent connectivity:
```bash
kubectl exec -it -n datadog <agent-pod> -- agent status
```

3. Ensure outbound HTTPS traffic is allowed to:
   - `api.datadoghq.com` (or `.eu` for EU)
   - `intake.logs.datadoghq.com`

### APM Traces Not Appearing

1. Verify trace agent is listening:
```bash
kubectl exec -it -n datadog <agent-pod> -- netstat -tlnp | grep 8126
```

2. Check application is sending traces to the correct endpoint
3. Review application APM library configuration

## Cost Optimization Tips

1. **Log Sampling**: Configure sampling for high-volume services
2. **Custom Metrics**: Use sparingly to control costs
3. **APM Sampling**: Adjust trace sampling rates based on traffic
4. **Retention**: Configure appropriate data retention policies
5. **Environment Separation**: Consider using different Datadog organizations for dev/prod

## Security Best Practices

1. **Rotate Keys**: Regularly rotate API and App keys
2. **RBAC**: Limit access to the datadog namespace
3. **Secrets Management**: Use external secret managers for production
4. **Audit Logging**: Enable audit logs for configuration changes
5. **Network Policies**: Implement network policies to restrict agent traffic

## Uninstalling

To remove Datadog monitoring:

1. Update Terraform variables:
```hcl
enable_datadog = false
```

2. Apply changes:
```bash
terraform apply
```

This will remove:
- Datadog namespace
- Datadog Operator
- DatadogAgent resources
- Associated secrets and configurations

## Additional Resources

- [Datadog Operator Documentation](https://docs.datadoghq.com/containers/datadog_operator/)
- [Kubernetes Integration Guide](https://docs.datadoghq.com/containers/kubernetes/)
- [APM Setup for Kubernetes](https://docs.datadoghq.com/tracing/setup_overview/setup/kubernetes/)
- [Log Collection Setup](https://docs.datadoghq.com/containers/kubernetes/log/)