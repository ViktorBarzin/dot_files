---
name: kubernetes-latest-tag-image-pull
description: |
  Fix for Kubernetes pods not pulling new Docker images with :latest tag after push.
  Use when: (1) pushed a new image with :latest tag but pods still run old code,
  (2) kubectl rollout restart doesn't pick up new image, (3) pod logs show old
  behavior despite image push confirmation. Covers debugging techniques and best
  practices for image versioning in Kubernetes deployments.
author: Claude Code
version: 1.1.0
date: 2026-02-01
---

# Kubernetes :latest Tag Image Pull Issues

## Problem
After pushing a new Docker image with the `:latest` tag, Kubernetes pods continue
running the old image version. Rolling restarts and pod deletions don't help because
the node has the image cached.

## Context / Trigger Conditions
- Pushed new image to registry with same `:latest` tag
- `docker push` shows successful push with new digest
- `kubectl rollout restart deployment/<name>` completes
- Pod logs still show old application behavior
- New pods created but running old code

## Solution

### Recommended: Use Specific Image Tags (Best Practice)

The proper solution is to use unique tags for each build instead of `:latest`:

```hcl
# Use git SHA, version number, or timestamp
container {
  name  = "my-app"
  image = "myregistry/myapp:v1.2.3"  # or :abc123 (git SHA)
}
```

This ensures Kubernetes always pulls the exact version you deployed.

### Quick Fix for Debugging: Temporary imagePullPolicy

**Only use this during active debugging, then remove it:**

```hcl
container {
  name  = "my-app"
  image = "myregistry/myapp:latest"
  image_pull_policy = "Always"  # TEMPORARY - remove after debugging
}
```

**Why not leave it on permanently:**
- Slows down pod startup (always pulls even when unchanged)
- Increases registry bandwidth and costs
- Deployment fails if registry is temporarily unavailable
- Hides the real problem (using `:latest` in production)

### Alternative: Force Pull Without Config Change

Delete the pod to force Kubernetes to pull on the new node scheduling:

```bash
# Delete pods to force fresh pull
kubectl -n <namespace> delete pod -l app=<app-name>

# Or scale down and up
kubectl -n <namespace> scale deployment <name> --replicas=0
kubectl -n <namespace> scale deployment <name> --replicas=1
```

## Verification
```bash
# Check pod is running new image
kubectl -n <namespace> describe pod <pod-name> | grep "Image:"

# Check logs show new behavior
kubectl -n <namespace> logs deployment/<deployment-name> --tail=20

# Verify image digest matches what was pushed
kubectl -n <namespace> get pods -o jsonpath='{.items[*].status.containerStatuses[*].imageID}'
```

## Example

**Scenario**: API pod still running `./start.sh` after pushing image with `uvicorn` CMD

**Best approach** - Use versioned tags:
```hcl
container {
  name  = "realestate-crawler-api"
  image = "viktorbarzin/realestatecrawler:v1.2.0"  # Specific version
}
```

**Quick debug approach** - Temporary imagePullPolicy (remove after fixing):
```hcl
container {
  name  = "realestate-crawler-api"
  image = "viktorbarzin/realestatecrawler:latest"
  image_pull_policy = "Always"  # TEMPORARY
}
```

## Notes

- **Default behavior**: For `:latest` tag, Kubernetes defaults to `IfNotPresent`, which
  means it won't pull if any image with that tag exists on the node
- **Best practice**: Use specific version tags (e.g., `v1.2.3`, git SHA, or build number)
  for all deployments, especially production
- **CI/CD integration**: Have your pipeline tag images with git SHA or build ID automatically
- **imagePullPolicy: Always is a debugging tool, not a solution** - it masks the underlying
  problem of using mutable tags
- **Node caching**: Even deleting pods doesn't clear the node's image cache, but it can
  trigger a re-pull if the image was garbage collected

## References
- [Kubernetes: Updating Images](https://kubernetes.io/docs/concepts/containers/images/#updating-images)
- [Kubernetes imagePullPolicy](https://kubernetes.io/docs/concepts/containers/images/#image-pull-policy)
