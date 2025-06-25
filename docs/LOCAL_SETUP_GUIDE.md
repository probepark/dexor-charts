# 로컬 개발 환경 설정 가이드 (macOS)

이 문서는 macOS 사용자가 Homebrew를 사용하여 로컬 개발 환경에서 필요한 도구를 설치하고, `make` 명령어를 통해 dev, qa, prod 환경의 인프라를 관리하고 애플리케이션을 배포하는 방법을 안내합니다.

## 1. 사전 준비 (최초 1회)

### 1.1. Homebrew

macOS용 패키지 관리자인 [Homebrew](https://brew.sh/index_ko)가 설치되어 있어야 합니다.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 1.2. 필수 도구 설치

`gke-multi-env` 디렉토리의 `Makefile`은 `gcloud`, `terraform`, `kubectl`, `helm`, `jq` 등의 도구를 사용합니다. Homebrew로 한 번에 설치합니다.

```bash
brew install --cask google-cloud-sdk
brew install terraform kubectl helm jq
```

## 2. Google Cloud 인증 (최초 1회)

로컬 환경에서 `gcloud`와 Terraform이 Google Cloud API를 사용할 수 있도록 인증을 설정합니다.

1.  **Google 계정 로그인**:
    브라우저가 열리면 로그인하고, 사용할 프로젝트와 리전을 선택하여 `gcloud`를 초기화합니다.

    ```bash
    gcloud init
    ```

2.  **애플리케이션 기본 인증**:
    Terraform과 같은 애플리케이션이 인증을 사용할 수 있도록 설정합니다.

    ```bash
    gcloud auth application-default login
    ```

3.  **Docker 인증**:
    Google Artifact Registry에 Docker 이미지를 푸시하거나 풀하기 위해 인증합니다.

    ```bash
    gcloud auth configure-docker asia-northeast3-docker.pkg.dev
    ```
    *(리전(`asia-northeast3`)은 프로젝트에 따라 다를 수 있습니다.)*

## 3. 인프라 관리 (Terraform via Make)

`gke-multi-env` 디렉토리에서 `make` 명령어를 사용하여 환경별 인프라를 관리합니다.

**위치**: `cd gke-multi-env`

### 3.1. Dev 환경 인프라 관리

*   **Terraform 초기화**:
    ```bash
    make init-dev
    ```

*   **변경 사항 계획 (Dry-run)**:
    ```bash
    make plan-dev
    ```

*   **인프라 생성/적용**:
    ```bash
    make apply-dev
    ```

*   **`kubectl` 설정**:
    `kubectl`이 dev 클러스터를 바라보도록 설정합니다.
    ```bash
    make kubectl-dev
    ```

*   **인프라 상태 확인**:
    ```bash
    make status-dev
    ```

*   **인프라 삭제**:
    ```bash
    make destroy-dev
    ```

### 3.2. QA 환경 인프라 관리

QA 환경은 `Makefile-qa`에 별도로 정의되어 있으며, `qa-` 접두사를 사용합니다.

*   **Terraform 초기화**:
    ```bash
    make qa-init
    ```

*   **변경 사항 계획 (Dry-run)**:
    ```bash
    make qa-plan
    ```

*   **인프라 생성/적용**:
    ```bash
    make qa-apply
    ```

*   **`kubectl` 설정**:
    `Makefile`에 `kubectl-qa` 타겟이 없다면, `gcloud` 명령어로 직접 설정해야 합니다.
    ```bash
    # 'make kubectl-qa'가 없는 경우
    gcloud container clusters get-credentials <QA_CLUSTER_NAME> --region <REGION> --project <PROJECT_ID>
    ```

*   **인프라 상태 확인**:
    ```bash
    make qa-status
    ```

*   **인프라 삭제**:
    ```bash
    make qa-destroy
    ```

### 3.3. Prod 환경 인프라 관리

**주의: Prod 환경 작업은 매우 신중하게 진행해야 합니다.**

*   **Terraform 초기화**:
    ```bash
    make init-prod
    ```

*   **변경 사항 계획 (Dry-run)**:
    ```bash
    make plan-prod
    ```

*   **인프라 생성/적용**:
    ```bash
    make apply-prod
    ```

*   **`kubectl` 설정**:
    ```bash
    make kubectl-prod
    ```

*   **인프라 삭제**:
    ```bash
    make destroy-prod
    ```

## 4. 애플리케이션 배포 (Docker & Helm via Make)

프로젝트 루트 디렉토리의 `Makefile`을 사용하여 애플리케이션을 빌드하고 배포합니다.

**위치**: `cd /Users/probe/git/kaiachain/dexor-charts` (프로젝트 루트)

### 4.1. Docker 이미지 빌드 및 푸시

`TAG` 변수를 사용하여 이미지 태그를 지정할 수 있습니다. (기본값: `dev`)

*   **모든 이미지 빌드 및 푸시 (dev 태그)**:
    ```bash
    make docker-push-all
    ```

*   **특정 태그로 모든 이미지 빌드 및 푸시**:
    ```bash
    make docker-push-all TAG=v1.0.0
    ```

*   **개별 이미지 빌드 및 푸시**:
    ```bash
    make docker-push-frontend TAG=latest
    make docker-push-backend TAG=latest
    ```

### 4.2. Helm 차트 배포 (QA 예시)

`gke-multi-env/Makefile-qa`에 정의된 Helm 배포 명령어를 사용합니다.

**위치**: `cd gke-multi-env`

*   **QA 환경에 모든 애플리케이션 배포**:
    ```bash
    make qa-deploy-all
    ```

*   **개별 애플리케이션 배포**:
    ```bash
    make qa-deploy-backend
    make qa-deploy-frontend
    make qa-deploy-core
    ```

### 4.3. ArgoCD를 통한 배포 (GitOps)

`argocd-applications` 디렉토리의 매니페스트를 수정하고 Git에 푸시하면 ArgoCD가 자동으로 변경사항을 감지하여 배포합니다. 수동으로 즉시 동기화하고 싶을 경우, 각 환경별 `deploy.sh` 스크립트를 사용할 수 있습니다.

*   **QA ArgoCD 애플리케이션 배포**:
    ```bash
    # gke-multi-env/Makefile-qa 에 정의됨
    make qa-argocd-deploy
    ```

*   **Dev ArgoCD 애플리케이션 배포**:
    ```bash
    # 스크립트 직접 실행
    ./argocd-applications/dev/deploy.sh
    ```
