# Datadog 로그 수집 설정 변경 사항

## 개요
Label 기반 로그 수집 방식을 적용하여 모든 Helm chart에 Datadog 로그 수집 설정을 추가했습니다.

## Terraform 설정 변경 (main.tf)

### Datadog Operator 설정
- **로그 수집만 활성화**: APM, NPM, USM 등 모든 다른 기능 비활성화
- **Label 기반 필터링**: `datadog-logs-enabled=true` label이 있는 pod만 로그 수집

```hcl
env = [
  {
    name  = "DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL"
    value = "false"
  },
  {
    name  = "DD_LOGS_CONFIG_CONTAINER_COLLECT_USING_LABELS"
    value = "true"
  },
  {
    name  = "DD_CONTAINER_INCLUDE_LABELS"
    value = "datadog-logs-enabled=true"
  }
]
```

## Helm Chart 변경 사항

### 1. kaia-orderbook-dex-backend
**values.yaml:**
- `commonLabels.datadog-logs-enabled: "true"` 추가
- API 서비스 환경 변수 추가:
  ```yaml
  env:
    - name: DD_AGENT_HOST
      valueFrom:
        fieldRef:
          fieldPath: status.hostIP
    - name: DD_SERVICE
      value: "kaia-orderbook-api"
    - name: DD_ENV
      value: "{{ .Values.environment.phase }}"
  ```
- Event 서비스 환경 변수 추가 (DD_SERVICE: "kaia-orderbook-event")

**templates/_helpers.tpl:**
- commonLabels 지원 추가

### 2. kaia-orderbook-dex-core
**values.yaml:**
- `commonLabels.datadog-logs-enabled: "true"` 추가
- Nitro Node 환경 변수 추가 (DD_SERVICE: "kaia-orderbook-nitro-node")
- Validator 환경 변수 추가 (DD_SERVICE: "kaia-orderbook-validator")

**templates/_helpers.tpl:**
- commonLabels 지원 추가

**templates/statefulset-nitro.yaml:**
- env 배열에 `.Values.nitroNode.env` 지원 추가

**templates/statefulset-validator.yaml:**
- env 배열에 `.Values.validator.env` 지원 추가

### 3. kaia-orderbook-dex-frontend
**values.yaml:**
- `commonLabels.datadog-logs-enabled: "true"` 추가
- 환경 변수 추가 (DD_SERVICE: "kaia-orderbook-frontend")

**templates/_helpers.tpl:**
- commonLabels 지원 추가

**templates/deployment.yaml:**
- env 필드 지원 추가

## 사용 방법

### 로그 수집 활성화/비활성화

**개별 Chart에서:**
```yaml
# values.yaml
commonLabels:
  datadog-logs-enabled: "true"  # 로그 수집 활성화
  # datadog-logs-enabled: "false" # 로그 수집 비활성화
```

**환경별 설정:**
```yaml
# values-dev.yaml
commonLabels:
  datadog-logs-enabled: "false"

# values-prod.yaml  
commonLabels:
  datadog-logs-enabled: "true"
```

### 확인 방법

1. **Label 확인:**
   ```bash
   kubectl get pods -l datadog-logs-enabled=true
   ```

2. **환경 변수 확인:**
   ```bash
   kubectl describe pod <pod-name> | grep -E "DD_SERVICE|DD_ENV|DD_AGENT_HOST"
   ```

3. **Datadog UI:**
   - 필터: `service:kaia-orderbook-*`
   - 필터: `env:dev` 또는 `env:prod`

## 장점

1. **간단한 설정**: values.yaml에 한 줄만 추가
2. **세밀한 제어**: Chart별, 환경별 on/off 가능
3. **일관된 서비스 이름**: DD_SERVICE로 각 컴포넌트 구분
4. **환경 구분**: DD_ENV로 dev/prod 구분
5. **자동 Agent 연결**: DD_AGENT_HOST로 자동 연결