# Kaia Orderbook DEX Frontend Helm Chart

This Helm chart deploys the Kaia Orderbook DEX Frontend application on a Kubernetes cluster.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- Ingress controller (nginx recommended)

## Installing the Chart

To install the chart with the release name `my-release`:

```bash
helm install my-release ./charts/kaia-orderbook-dex-frontend
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

### Application Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `2` |
| `image.repository` | Image repository | `kaia-orderbook-frontend` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `image.tag` | Image tag (defaults to chart appVersion) | `""` |

### Service Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Service type | `ClusterIP` |
| `service.port` | Service port | `80` |
| `service.targetPort` | Container port | `80` |

### Ingress Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress class name | `nginx` |
| `ingress.hosts` | Ingress hosts | See values.yaml |
| `ingress.tls` | TLS configuration | `[]` |

### Environment Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `environment.phase` | Environment phase (dev, staging, prod) | `dev` |
| `environment.apiUrl` | Backend API URL | `https://api-orderbook.dev.kaia.io/api/v1` |
| `environment.wsUrl` | WebSocket URL | `wss://api-orderbook.dev.kaia.io/ws` |

### Resource Management

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `512Mi` |

### Autoscaling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | Enable HPA | `false` |
| `autoscaling.minReplicas` | Minimum replicas | `2` |
| `autoscaling.maxReplicas` | Maximum replicas | `10` |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80` |

## Example Usage

### Production Deployment

```yaml
environment:
  phase: "prod"
  apiUrl: "https://api-orderbook.kaia.io/api/v1"
  wsUrl: "wss://api-orderbook.kaia.io/ws"

ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: dex.kaia.io
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: dex-tls
      hosts:
        - dex.kaia.io

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
```

### Development Deployment

```yaml
environment:
  phase: "dev"
  apiUrl: "http://backend-api:8080/api/v1"
  wsUrl: "ws://backend-api:8080/ws"

replicaCount: 1

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

## Architecture

This chart deploys a React-based frontend application built with Vite. The application:

1. **Serves static files** through Nginx
2. **Connects to backend API** for data and transactions
3. **Supports WebSocket** connections for real-time updates
4. **Handles Web3 wallet** connections via RainbowKit
5. **Provides trading interface** with TradingView charts

## Docker Image

The Docker image should be built with:
- Multi-stage build for optimization
- Nginx for serving static files
- Runtime environment configuration support

Example Dockerfile:
```dockerfile
# Build stage
FROM node:20-alpine as builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Runtime stage
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

## Notes

1. The frontend requires a running backend API service
2. WebSocket support requires proper ingress configuration
3. Configure CORS settings on the backend for cross-origin requests
4. TLS/SSL is recommended for production deployments
5. The application loads environment configuration at runtime via `env-config.js`