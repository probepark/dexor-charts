# Kaia Orderbook DEX Backend Helm Chart

This Helm chart deploys the Kaia Orderbook DEX Backend services on a Kubernetes cluster.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PV provisioner support in the underlying infrastructure (if persistence is needed)
- External MySQL database
- External Redis instance

## Installing the Chart

To install the chart with the release name `my-release`:

```bash
helm install my-release ./charts/kaia-orderbook-dex-backend
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
| `global.imagePullSecrets` | Global Docker registry secret names as an array | `[]` |
| `global.storageClass` | Global storage class for dynamic provisioning | `""` |

### API Service Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `api.enabled` | Enable API service | `true` |
| `api.replicaCount` | Number of API replicas | `2` |
| `api.image.repository` | API image repository | `kaia-orderbook-api` |
| `api.image.pullPolicy` | API image pull policy | `IfNotPresent` |
| `api.image.tag` | API image tag (defaults to chart appVersion) | `""` |
| `api.service.type` | API service type | `ClusterIP` |
| `api.service.port` | API service port | `8080` |
| `api.resources` | API pod resources | See values.yaml |
| `api.autoscaling.enabled` | Enable HPA for API | `false` |
| `api.ingress.enabled` | Enable ingress for API | `false` |

### Event Service Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `event.enabled` | Enable Event service | `true` |
| `event.replicaCount` | Number of Event replicas | `1` |
| `event.image.repository` | Event image repository | `kaia-orderbook-event` |
| `event.image.pullPolicy` | Event image pull policy | `IfNotPresent` |
| `event.image.tag` | Event image tag (defaults to chart appVersion) | `""` |
| `event.service.type` | Event service type | `ClusterIP` |
| `event.service.port` | Event service port | `8081` |
| `event.resources` | Event pod resources | See values.yaml |

### Environment Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `environment.phase` | Environment phase (dev, staging, prod) | `dev` |

## Example Usage

### Configuration Management

This chart has been simplified to focus on Kubernetes deployment. All application configuration including database connections, Redis settings, and secrets are managed at the application level through:
- Default configurations in the code
- AWS/GCP Secret Manager for sensitive data
- Environment variable `KAIA_ORDERBOOK_PHASE` to select the environment

### Enabling Ingress

```yaml
api:
  ingress:
    enabled: true
    className: "nginx"
    hosts:
      - host: api.orderbook.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: orderbook-tls
        hosts:
          - api.orderbook.example.com
```

### Setting Environment

```yaml
environment:
  phase: "prod"  # dev, staging, prod
```

### Custom Resource Limits

```yaml
api:
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi
    requests:
      cpu: 1000m
      memory: 1Gi

event:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 500m
      memory: 512Mi
```

## Upgrading

To upgrade the deployment:

```bash
helm upgrade my-release ./charts/kaia-orderbook-dex-backend
```

## Notes

1. All application configuration is managed at the code level
2. Sensitive data is retrieved from AWS/GCP Secret Manager at runtime
3. The chart focuses purely on Kubernetes deployment aspects
4. External dependencies (MySQL, Redis, blockchain nodes) must be accessible from the cluster
5. Configure appropriate resource limits based on your workload
6. Enable monitoring and configure alerts for production deployments