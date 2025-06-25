# 데이터베이스 연결 방법

이 문서는 로컬 개발 환경에서 Google Cloud SQL 데이터베이스에 안전하게 접속하는 방법을 안내합니다. Cloud SQL Auth Proxy를 사용하는 것이 가장 안전하고 권장되는 표준 방식입니다.

## 1. 사전 준비

### 1.1. 필수 도구 설치

*   **gcloud & kubectl**: `docs/LOCAL_SETUP_GUIDE.md` 문서를 참고하여 `gcloud` CLI를 설치하고 인증을 완료하세요. `kubectl`도 설치되어 있어야 합니다.
*   **Database Client**: MySQL 클라이언트가 필요합니다. Homebrew를 사용하여 설치할 수 있습니다.
    ```bash
    brew install mysql-client
    ```
*   **Cloud SQL Auth Proxy**: Google Cloud SQL에 안전하게 연결하기 위한 프록시입니다.
    ```bash
    brew install --cask google-cloud-sql-proxy
    ```

## 2. 데이터베이스 연결 (권장 방법)

로컬 머신에서 Cloud SQL Auth Proxy를 직접 실행하여 데이터베이스에 연결합니다.

### 1단계: 데이터베이스 연결 정보 확인

먼저 접속하려는 환경의 데이터베이스 정보를 확인해야 합니다. `gke-multi-env` 디렉토리에서 `make` 명령어를 사용합니다.

**위치**: `cd gke-multi-env`

#### **Dev 환경**

1.  **DB 연결 이름 확인**:
    ```bash
    make db-status-dev
    ```
    출력된 `Database Connection Name` 값을 확인합니다. (예: `kaia-dex-dev-123456:asia-northeast3:kaia-dex-dev-mysql`)

2.  **DB 사용자 및 비밀번호 확인**:
    먼저 `make kubectl-dev`를 실행하여 `kubectl`이 dev 클러스터를 가리키도록 설정한 후, 아래 명령어를 실행합니다.
    ```bash
    kubectl get secret mysql-credentials -n default -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'
    ```

#### **QA 환경**

1.  **DB 연결 이름 확인**:
    ```bash
    make qa-connections
    ```
    출력된 `MySQL Host` 값이 DB 연결 이름입니다.

2.  **DB 사용자 및 비밀번호 확인**:
    먼저 `gcloud` 명령어로 `kubectl`이 QA 클러스터를 가리키도록 설정해야 합니다.
    ```bash
    # 프로젝트 ID와 클러스터 이름은 확인 후 입력해야 합니다.
    gcloud container clusters get-credentials <QA_CLUSTER_NAME> --region asia-northeast3 --project <QA_PROJECT_ID>
    ```
    그런 다음, 아래 명령어를 실행하여 `username`과 `password`를 확인합니다.
    ```bash
    kubectl get secret mysql-credentials -n kaia-dex-qa -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'
    ```
    *(QA 환경의 Kubernetes Namespace는 `kaia-dex-qa` 입니다.)*

### 2단계: Cloud SQL Auth Proxy 실행

새 터미널 창을 열고, 아래 명령어를 실행하여 프록시를 시작합니다. `<INSTANCE_CONNECTION_NAME>` 부분은 **1단계**에서 확인한 값으로 대체합니다.

```bash
cloud-sql-proxy <INSTANCE_CONNECTION_NAME>
```

**예시 (Dev 환경):**
```bash
cloud-sql-proxy kaia-dex-dev-123456:asia-northeast3:kaia-dex-dev-mysql
```

**예시 (QA 환경):**
```bash
# make qa-connections 로 확인한 MySQL Host 값을 입력합니다.
cloud-sql-proxy <QA_MYSQL_HOST_VALUE>
```

프록시가 성공적으로 실행되면, `Ready for new connections`라는 로그가 표시됩니다. 이제 로컬 머신의 `127.0.0.1:3306` 포트가 Cloud SQL 데이터베이스로 안전하게 전달됩니다.

### 3단계: 데이터베이스 클라이언트로 연결

이제 `mysql` CLI나 DBeaver, DataGrip 같은 GUI 도구를 사용하여 데이터베이스에 접속할 수 있습니다.

*   **Host**: `127.0.0.1`
*   **Port**: `3306`
*   **User**: **1단계**에서 확인한 `username`
*   **Password**: **1단계**에서 확인한 `password`
*   **Database**: `orderbook_dex` (또는 접속하려는 데이터베이스 이름)

**MySQL CLI 접속 예시:**
```bash
mysql -u <USERNAME> -p -h 127.0.0.1 -P 3306 --database=orderbook_dex
```
비밀번호를 입력하라는 메시지가 나타나면 **1단계**에서 확인한 비밀번호를 입력합니다.

## 3. 대체 방법 (디버깅용)

`make` 명령어에 정의된 Kubernetes `port-forward` 기능을 사용하여 접속할 수도 있습니다. 이 방법은 로컬에 Cloud SQL Auth Proxy를 설치하지 않아도 되지만, 연결이 불안정할 수 있어 디버깅 용도로만 사용하는 것을 권장합니다.

**위치**: `cd gke-multi-env`

*   **Dev DB에 Port-Forwarding**:
    ```bash
    make k8s-db-proxy-dev
    ```
    이 명령어를 실행하면 로컬 포트 `3306`이 클러스터 내의 Cloud SQL Proxy Pod로 전달됩니다. 이후 **3단계**와 동일한 방법으로 접속할 수 있습니다.

*   **Prod DB에 Port-Forwarding**:
    ```bash
    make k8s-db-proxy-prod
    ```
    Prod 환경은 로컬 포트 `3307`을 사용합니다. 접속 시 포트를 `3307`로 지정해야 합니다.

**참고**: 현재 QA 환경에 대해서는 `make` 명령어를 통한 port-forwarding이 정의되어 있지 않습니다. QA DB에 접속하려면 **2번(권장 방법)**을 사용하세요.
