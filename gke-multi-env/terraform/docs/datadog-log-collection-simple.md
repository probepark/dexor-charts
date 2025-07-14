# Datadog 로그 수집 간편 설정 가이드

## 가장 쉬운 방법: Label 기반 필터링

### 1. Label을 사용한 로그 수집 (현재 설정)

Terraform에서 설정된 필터:
```
DD_CONTAINER_INCLUDE_LABELS = "datadog-logs-enabled=true"
```

Helm chart에서 사용법:
```yaml
# values.yaml
labels:
  datadog-logs-enabled: "true"  # 이 label만 추가하면 로그 수집됨
```

또는 기존 labels에 추가:
```yaml
commonLabels:
  app: backend
  team: platform
  datadog-logs-enabled: "true"  # 추가
```

### 2. Namespace 기반 필터링

특정 namespace의 모든 pod 로그를 수집하려면:

```hcl
# main.tf에서
{
  name  = "DD_CONTAINER_INCLUDE"
  value = "namespace:backend namespace:core namespace:api"
}
```

이렇게 하면 backend, core, api namespace의 모든 pod 로그가 자동 수집됩니다.

### 3. Helm Chart 이름 기반 필터링

```hcl
# main.tf에서
{
  name  = "DD_CONTAINER_INCLUDE_LABELS"
  value = "app.kubernetes.io/name:backend app.kubernetes.io/name:core"
}
```

대부분의 Helm chart는 자동으로 `app.kubernetes.io/name` label을 생성하므로 추가 설정이 필요 없습니다.

## 권장 방법 비교

### 방법 1: Label 사용 (권장) ✅
**장점:**
- Helm values.yaml에 한 줄만 추가
- 세밀한 제어 가능
- 환경별로 다르게 설정 가능

**설정 방법:**
```yaml
# Backend Helm chart values.yaml
labels:
  datadog-logs-enabled: "true"
```

### 방법 2: Namespace 사용
**장점:**
- Helm chart 수정 불필요
- Namespace 단위로 일괄 적용

**설정 방법:**
```bash
# Terraform main.tf 수정
DD_CONTAINER_INCLUDE = "namespace:production namespace:staging"
```

### 방법 3: 기본 Helm Labels 사용
**장점:**
- 대부분의 Helm chart에서 자동 생성되는 label 활용
- 추가 설정 최소화

**설정 방법:**
```bash
# Terraform main.tf 수정
DD_CONTAINER_INCLUDE_LABELS = "app.kubernetes.io/instance:backend app.kubernetes.io/instance:core"
```

## 실제 적용 예시

### Backend Service
```yaml
# backend/values.yaml
commonLabels:
  datadog-logs-enabled: "true"  # 이것만 추가!

# 또는 환경별 설정
commonLabels:
  datadog-logs-enabled: "{{ .Values.datadogLogsEnabled | default \"false\" }}"
```

### Core Service
```yaml
# core/values.yaml
labels:
  datadog-logs-enabled: "true"  # 이것만 추가!
```

### 환경별 설정
```yaml
# values-prod.yaml
datadogLogsEnabled: "true"

# values-dev.yaml
datadogLogsEnabled: "false"
```

## 로그 수집 확인

### 1. Label 확인
```bash
# 로그가 수집되어야 하는 pod 확인
kubectl get pods --all-namespaces -l datadog-logs-enabled=true
```

### 2. Datadog Agent 상태 확인
```bash
# Agent가 어떤 container의 로그를 수집하는지 확인
kubectl exec -n datadog <datadog-pod> -- agent status | grep -A 20 "Logs Agent"
```

### 3. Datadog UI에서 확인
1. [Datadog Logs](https://app.datadoghq.com/logs) 접속
2. 필터: `kube_labels.datadog-logs-enabled:true`

## 문제 해결

### 로그가 수집되지 않을 때

1. **Label 확인**
```bash
kubectl describe pod <pod-name> | grep Labels
```

2. **Agent 로그 확인**
```bash
kubectl logs -n datadog -l app.kubernetes.io/component=nodeAgent | grep -i "logs"
```

3. **Pod 재시작**
```bash
kubectl rollout restart deployment/<deployment-name>
```

## 고급 설정

### 특정 Container만 로그 수집
```yaml
# 여전히 annotation을 사용해야 함
podAnnotations:
  ad.datadoghq.com/nginx.logs: |
    [{"source": "nginx", "service": "frontend"}]
  # main container는 label로, sidecar는 annotation으로 제어
```

### 로그 처리 규칙 추가
Label 방식을 사용하면서도 annotation으로 상세 설정 가능:
```yaml
labels:
  datadog-logs-enabled: "true"

podAnnotations:
  ad.datadoghq.com/backend.logs: |
    [{
      "log_processing_rules": [{
        "type": "exclude_at_match",
        "name": "exclude_health",
        "pattern": "/health"
      }]
    }]
```