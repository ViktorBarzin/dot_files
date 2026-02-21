---
name: k8s-limitrange-oom-silent-kill
description: |
  Debug Kubernetes pods that suddenly start OOM-killing after a LimitRange is added
  to the namespace. Use when: (1) pods that previously worked fine start getting
  OOMKilled (exit code 137), (2) a LimitRange or ResourceQuota was recently added
  to the namespace, (3) deployments have `resources: {}` and inherit default limits,
  (4) periodic jobs or background workers fail silently with degraded results before
  dying. Covers diagnosing the timeline correlation between LimitRange creation and
  pod failures, and fixing by setting explicit resource requests/limits.
author: Claude Code
version: 1.0.0
date: 2026-02-21
---

# Kubernetes LimitRange Causing Silent OOM Kills

## Problem
Pods that previously ran without issues suddenly start getting OOMKilled after a
`LimitRange` is added to the namespace. Deployments with `resources: {}` silently
inherit the LimitRange's default memory limit, which may be too low for the actual
workload. The failures can be subtle: background workers may partially complete
tasks before dying, making it look like the application is buggy rather than
resource-starved.

## Context / Trigger Conditions
- Pods suddenly restarting with `Reason: OOMKilled`, `Exit Code: 137`
- A `LimitRange` was recently created in the namespace
- Deployment manifests have `resources: {}` (no explicit limits)
- Background workers (Celery, Sidekiq, etc.) process fewer items than expected
- Periodic/cron jobs that used to succeed now fail or produce partial results
- `kubectl describe pod` shows `Last State: Terminated, Reason: OOMKilled`

## Diagnosis

### Step 1: Check for OOM kills
```bash
kubectl -n <ns> describe pod <pod> | grep -A 5 "Last State"
# Look for: Reason: OOMKilled, Exit Code: 137
```

### Step 2: Check current memory usage vs limits
```bash
kubectl -n <ns> top pod <pod>
kubectl -n <ns> describe pod <pod> | grep -A 5 "Limits:"
```

### Step 3: Check for LimitRange in the namespace
```bash
kubectl -n <ns> describe limitrange
# Look for Default Limit column — this is what pods without explicit
# resources inherit
```

### Step 4: Correlate LimitRange creation with failure timeline
```bash
kubectl -n <ns> get limitrange -o yaml | grep creationTimestamp
# Compare this date with when pods started failing
# Check application data (DB timestamps, logs) to find exact failure start
```

### Step 5: Verify deployment has no explicit resources
```bash
kubectl -n <ns> get deployment <name> -o jsonpath='{.spec.template.spec.containers[0].resources}'
# If output is {} — the pod inherits LimitRange defaults
```

## Solution

Set explicit resource requests and limits on the deployment that match the
workload's actual needs:

```bash
kubectl -n <ns> patch deployment <name> --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources",
   "value": {
     "requests": {"memory": "512Mi", "cpu": "100m"},
     "limits": {"memory": "2Gi", "cpu": "2"}
   }}
]'
```

For multi-process workers (Celery prefork, Gunicorn), also reduce concurrency
to lower idle memory:

```bash
# Example: Celery worker with 16 prefork processes using ~60Mi each = ~960Mi idle
# Reduce to 4 processes: ~240Mi idle, leaving headroom for actual work
kubectl -n <ns> patch deployment <name> --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/command",
   "value": ["celery", "-A", "app", "worker", "--concurrency=4"]}
]'
```

### Choosing memory limits

1. Check idle memory: `kubectl top pod` with no active tasks
2. Check peak memory: `kubectl top pod` during heaviest workload
3. Set limit to ~2x peak to allow for spikes
4. Set request to ~idle usage so scheduler places pods correctly

## Verification
```bash
# Confirm new limits are applied
kubectl -n <ns> describe pod <new-pod> | grep -A 5 "Limits:"

# Monitor memory during workload
kubectl -n <ns> top pod <pod>

# Confirm no OOM kills after running a full workload cycle
kubectl -n <ns> describe pod <pod> | grep "Restart Count"
# Should show 0
```

## Example

**Scenario**: Celery workers processing periodic scrape jobs start failing after
a `tier-defaults` LimitRange is added with 1Gi default memory limit.

- 16 prefork workers consume ~983Mi at idle (nearly 1Gi)
- Any task execution pushes over 1Gi, triggering OOM kill
- Scrape jobs process 1-8 items instead of thousands before dying
- Eventually pods cycle between start and OOM-kill, effectively going offline

**Fix**: Set explicit 2Gi limit and reduce concurrency from 16 to 4:
- Idle memory drops to ~296Mi
- Peak during scrape: ~919Mi
- Well within 2Gi limit, zero OOM kills

## Notes
- LimitRange defaults apply at pod admission time. Existing running pods are NOT
  affected until they are recreated (e.g., by a deployment rollout)
- The failure mode is insidious: pods may partially work, processing some items
  before getting killed, making it look like an application bug
- Always set explicit `resources` on production deployments to avoid inheriting
  namespace defaults
- `resources: {}` is NOT the same as "no limits" when a LimitRange exists
- CI/CD pipelines that only patch the image tag (not resources) will preserve
  manually-set resource limits across deploys

See also: kubernetes-latest-tag-image-pull

## References
- [Kubernetes LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
