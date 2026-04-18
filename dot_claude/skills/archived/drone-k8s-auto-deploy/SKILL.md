---
name: drone-k8s-auto-deploy
description: |
  Set up Drone CI pipelines that build Docker images and auto-deploy to Kubernetes.
  Use when: (1) setting up CI/CD for a project running on a k8s cluster with Drone,
  (2) need to trigger a k8s deployment update from a Drone pipeline step,
  (3) want to avoid manual kubectl rollout restart after image push. Covers pipeline
  type selection, k8s API patching via service account token, and build-number tagging.
author: Claude Code
version: 1.0.0
date: 2026-02-06
---

# Drone CI Kubernetes Auto-Deploy

## Problem
After pushing a new Docker image from Drone CI, the Kubernetes deployment still runs
the old image. Manual `kubectl rollout restart` is needed, breaking the automated
pipeline.

## Context / Trigger Conditions
- Drone CI is running on a Kubernetes cluster (not as a standalone Docker host)
- The deployment uses a specific image tag (not `:latest` with `imagePullPolicy: Always`)
- You want push-to-main to automatically build, push, and deploy
- The Drone service account has RBAC permissions to patch deployments (e.g. cluster-admin)

## Solution

### 1. Use `type: kubernetes` pipeline

When Drone runs on k8s, pipeline steps execute as pods with access to the cluster
API via mounted service account tokens.

```yaml
kind: pipeline
type: kubernetes    # NOT 'docker'
name: my-app
```

### 2. Tag images with build number

Use `${DRONE_BUILD_NUMBER}` for unique, incrementing tags. Push both `:latest` and
the build number for flexibility.

```yaml
- name: docker
  image: plugins/docker
  settings:
    repo: myregistry/myapp
    tags:
      - latest
      - "${DRONE_BUILD_NUMBER}"
    username:
      from_secret: docker_username
    password:
      from_secret: docker_password
```

### 3. Patch the deployment via k8s API

Use `curl` to PATCH the deployment's container image to the new tag. The service
account token is auto-mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token`.

```yaml
- name: deploy
  image: alpine
  commands:
    - apk add --no-cache curl
    - |
      curl -sfk -X PATCH \
        "https://<K8S_API_HOST>:6443/apis/apps/v1/namespaces/<NAMESPACE>/deployments/<DEPLOYMENT>" \
        -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
        -H "Content-Type: application/strategic-merge-patch+json" \
        -d '{"spec":{"template":{"spec":{"containers":[{"name":"<CONTAINER_NAME>","image":"myregistry/myapp:'"${DRONE_BUILD_NUMBER}"'"}]}}}}'
```

This is the API equivalent of `kubectl set image deployment/<name> <container>=<image>:<tag>`.

### 4. Required Drone secrets

Configure these in the Drone UI for the repository:
- `docker_username` — Docker Hub username
- `docker_password` — Docker Hub access token (PAT works)

No kubectl credentials needed — the pipeline uses the Drone pod's service account.

## Verification

```bash
# Check Drone build passed
# In the Drone UI, verify all 3 steps (build, docker, deploy) are green

# Verify deployment updated
kubectl -n <namespace> get deployment <name> -o jsonpath='{.spec.template.spec.containers[0].image}'
# Should show: myregistry/myapp:<build-number>

# Verify pod is running new image
kubectl -n <namespace> get pods -o jsonpath='{.items[*].status.containerStatuses[*].image}'
```

## Example

Full `.drone.yml` for a Node.js app deployed to k8s:

```yaml
kind: pipeline
type: kubernetes
name: my-app

concurrency:
  limit: 1

trigger:
  branch:
    - main
  event:
    - push

steps:
  - name: build
    image: node:18-alpine
    commands:
      - npm ci
      - npm run build

  - name: docker
    image: plugins/docker
    settings:
      repo: myuser/myapp
      tags:
        - latest
        - "${DRONE_BUILD_NUMBER}"
      username:
        from_secret: docker_username
      password:
        from_secret: docker_password

  - name: deploy
    image: alpine
    commands:
      - apk add --no-cache curl
      - |
        curl -sfk -X PATCH \
          "https://10.0.20.100:6443/apis/apps/v1/namespaces/myapp/deployments/myapp" \
          -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
          -H "Content-Type: application/strategic-merge-patch+json" \
          -d '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","image":"myuser/myapp:'"${DRONE_BUILD_NUMBER}"'"}]}}}}'
```

## Notes

- The k8s API host (`10.0.20.100:6443`) is cluster-specific — find it with `kubectl cluster-info`
- The `-k` flag on curl skips TLS verification for the k8s API (common for internal clusters with self-signed certs)
- The `-sf` flags make curl fail silently on HTTP errors and return non-zero exit code, which fails the pipeline step
- The container `name` in the PATCH must match the container name in the deployment spec
- RBAC: The Drone service account needs permissions to PATCH deployments in the target namespace
- See also: `kubernetes-latest-tag-image-pull` for why build-number tags are preferred over `:latest`

## References
- [Kubernetes API: Patch Deployment](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/deployment-v1/#patch-replace-the-specified-deployment)
- [Drone Docker Plugin](https://plugins.drone.io/plugins/docker)
- [Drone Kubernetes Pipelines](https://docs.drone.io/pipeline/kubernetes/overview/)
