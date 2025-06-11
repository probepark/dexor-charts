# Secret Manager Configuration for Go Applications

This document describes how to use the Secret Manager integration with your Go applications using the predefined struct configuration.

## Go Struct Configuration

The Secret Manager creates a JSON configuration that matches this Go struct:

```go
var secret struct {
    RWDbDSN        string `json:"rw_db_dsn"`
    RODbDSN        string `json:"ro_db_dsn"`
    KaiascanApiKey string `json:"kaiascan_api_key"`
    AuthSignKey    string `json:"auth_sign_key"`
    CryptoKey      string `json:"crypto_key"`
    RedisHost      string `json:"redis_host"`
    RedisPassword  string `json:"redis_password"`
}
```

## Secret Manager Configuration

### Automatic Values (from infrastructure)
- `rw_db_dsn` / `ro_db_dsn`: MySQL connection strings with auto-generated passwords
- `redis_host`: Redis instance host address
- `redis_password`: Redis authentication string (if enabled)

### Manual Values (in terraform.tfvars)
Configure these in your environment's `terraform.tfvars` file:

```hcl
application_secrets = {
  "kaiascan_api_key" = "your-kaiascan-api-key"
  "auth_sign_key"    = "your-auth-signing-key"
  "crypto_key"       = "your-crypto-encryption-key"
}
```

## Retrieving Configuration

### Using Make Commands

#### Development Environment
```bash
# Get the complete application configuration JSON
make app-config-dev

# Example output:
{
  "rw_db_dsn": "mysql://klaytn:generated_password@10.0.1.5:3306/dex",
  "ro_db_dsn": "mysql://klaytn:generated_password@10.0.1.5:3306/dex",
  "kaiascan_api_key": "your-kaiascan-api-key-here",
  "auth_sign_key": "your-auth-signing-key-here", 
  "crypto_key": "your-crypto-encryption-key-here",
  "redis_host": "10.0.1.6",
  "redis_password": "generated_redis_auth_string"
}
```

#### Production Environment
```bash
make app-config-prod
```

### Using gcloud CLI Directly
```bash
# Development
gcloud secrets versions access latest --secret=dev-app-config

# Production  
gcloud secrets versions access latest --secret=prod-app-config
```

## Go Application Integration

### Loading Configuration
```go
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "os/exec"
)

type Config struct {
    RWDbDSN        string `json:"rw_db_dsn"`
    RODbDSN        string `json:"ro_db_dsn"`
    KaiascanApiKey string `json:"kaiascan_api_key"`
    AuthSignKey    string `json:"auth_sign_key"`
    CryptoKey      string `json:"crypto_key"`
    RedisHost      string `json:"redis_host"`
    RedisPassword  string `json:"redis_password"`
}

func loadConfig(environment string) (*Config, error) {
    secretName := fmt.Sprintf("%s-app-config", environment)
    
    cmd := exec.Command("gcloud", "secrets", "versions", "access", "latest", 
                       "--secret", secretName)
    output, err := cmd.Output()
    if err != nil {
        return nil, fmt.Errorf("failed to get secret: %v", err)
    }
    
    var config Config
    if err := json.Unmarshal(output, &config); err != nil {
        return nil, fmt.Errorf("failed to parse config: %v", err)
    }
    
    return &config, nil
}

func main() {
    config, err := loadConfig("dev") // or "prod"
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Printf("Database DSN: %s\n", config.RWDbDSN)
    fmt.Printf("Redis Host: %s\n", config.RedisHost)
    // ... use other config values
}
```

### Using Google Cloud Secret Manager Client Library
```go
package main

import (
    "context"
    "encoding/json"
    "fmt"
    "log"
    
    secretmanager "cloud.google.com/go/secretmanager/apiv1"
    "cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"
)

func loadConfigFromSecretManager(ctx context.Context, projectID, environment string) (*Config, error) {
    client, err := secretmanager.NewClient(ctx)
    if err != nil {
        return nil, err
    }
    defer client.Close()
    
    secretName := fmt.Sprintf("projects/%s/secrets/%s-app-config/versions/latest", 
                             projectID, environment)
    
    req := &secretmanagerpb.AccessSecretVersionRequest{
        Name: secretName,
    }
    
    result, err := client.AccessSecretVersion(ctx, req)
    if err != nil {
        return nil, err
    }
    
    var config Config
    if err := json.Unmarshal(result.Payload.Data, &config); err != nil {
        return nil, err
    }
    
    return &config, nil
}
```

## Kubernetes Integration

### Using Secret Manager CSI Driver

Your pod can mount the secret as a volume:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: your-app
spec:
  serviceAccountName: secret-manager-sa  # Created by Terraform
  containers:
  - name: app
    image: your-app:latest
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets"
      readOnly: true
    env:
    - name: CONFIG_FILE
      value: "/mnt/secrets/config.json"
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "dev-app-config-provider"  # or "prod-app-config-provider"
```

### Loading from Mounted Volume
```go
func loadConfigFromFile(configPath string) (*Config, error) {
    data, err := ioutil.ReadFile(configPath)
    if err != nil {
        return nil, err
    }
    
    var config Config
    if err := json.Unmarshal(data, &config); err != nil {
        return nil, err
    }
    
    return &config, nil
}

func main() {
    configPath := os.Getenv("CONFIG_FILE")
    if configPath == "" {
        configPath = "/mnt/secrets/config.json"
    }
    
    config, err := loadConfigFromFile(configPath)
    if err != nil {
        log.Fatal(err)
    }
    
    // Use config...
}
```

## Security Considerations

1. **Database Passwords**: Automatically rotated and managed by Terraform
2. **Redis Authentication**: Generated automatically for production environments
3. **API Keys**: Must be manually configured in terraform.tfvars
4. **Workload Identity**: Used for secure access from Kubernetes pods
5. **Environment Separation**: Dev and prod secrets are completely isolated

## Terraform Outputs

Available outputs for integration:

- `app_config_secret_name`: The secret name in Secret Manager
- `app_config_secret_command`: gcloud command to retrieve the config
- `secret_manager_csi_provider_class`: CSI provider class name for Kubernetes
- `secret_manager_service_account_email`: Service account for Workload Identity