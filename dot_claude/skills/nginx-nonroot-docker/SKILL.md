---
name: nginx-nonroot-docker
description: |
  Fix nginx crashes when running as non-root user in Docker containers. Use when:
  (1) nginx fails with "open() /run/nginx.pid failed (13: Permission denied)",
  (2) nginx warns "the 'user' directive makes sense only if the master process
  runs with super-user privileges", (3) nginx can't bind to port 80 as non-root,
  (4) entrypoint scripts fail with "can not modify /etc/nginx/conf.d/default.conf
  (read-only file system?)". Covers the complete set of changes needed to run
  nginx:alpine as a non-root user in production Docker images.
author: Claude Code
version: 1.0.0
date: 2026-02-22
---

# Nginx Non-Root Docker Container

## Problem

Running `nginx:alpine` as a non-root user (`USER nginx`) causes multiple failures
that surface one at a time, making debugging iterative and frustrating.

## Context / Trigger Conditions

- Dockerfile uses `nginx:alpine` as the final stage
- `USER nginx` directive added for security hardening
- Container crashloops in Kubernetes with one of these errors:
  - `open() "/run/nginx.pid" failed (13: Permission denied)`
  - `bind() to 0.0.0.0:80 failed (13: Permission denied)`
  - `the "user" directive makes sense only if the master process runs with super-user privileges`
  - Entrypoint warning: `can not modify /etc/nginx/conf.d/default.conf`

## Solution

All four issues must be fixed together. Missing any one causes a different crash:

```dockerfile
FROM nginx:alpine

# Copy your built assets and config
COPY --from=builder /app/dist /usr/share/nginx/html
COPY --from=builder /app/nginx.conf /etc/nginx/conf.d/default.conf

# Configure nginx to run as non-root (ALL of these are required)
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /run/nginx.pid && chown nginx:nginx /run/nginx.pid && \
    sed -i 's/listen 80;/listen 8080;/' /etc/nginx/conf.d/default.conf && \
    sed -i 's/^user /#user /' /etc/nginx/nginx.conf

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1
```

### What each line fixes

| Line | Fixes |
|------|-------|
| `chown nginx:nginx /usr/share/nginx/html` | Static file access |
| `chown nginx:nginx /var/cache/nginx` | Proxy/fastcgi cache writes |
| `chown nginx:nginx /var/log/nginx` | Access/error log writes |
| `touch /run/nginx.pid && chown nginx:nginx /run/nginx.pid` | PID file creation (path is `/run/`, NOT `/var/run/`) |
| `sed 's/listen 80;/listen 8080;/'` | Port 80 requires root; use 8080+ |
| `sed 's/^user /#user /' /etc/nginx/nginx.conf` | Comment out `user nginx;` directive (can't setuid when already non-root) |

### Required Kubernetes/infrastructure changes

When switching from port 80 to 8080:
- Update `containerPort` in Deployment spec
- Update `targetPort` in Service spec
- Update any Ingress/proxy configs pointing to port 80

```bash
kubectl patch deployment my-app --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/ports/0/containerPort","value":8080}]'
kubectl patch svc my-app --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]'
```

## Verification

```bash
# Build and run locally
docker build -t test-nginx .
docker run --rm -p 8080:8080 test-nginx

# Should show clean startup with no warnings:
# nginx/1.x.x
# start worker processes
# (no "user" directive warning, no permission denied)

# Verify it serves content:
curl http://localhost:8080/
```

## Notes

- The PID file path is `/run/nginx.pid` on nginx:alpine (not `/var/run/nginx.pid`)
- The `user` directive must be commented out, not deleted — `sed '/^user /d'` may not
  match if there's leading whitespace; `sed 's/^user /#user /'` is safer
- The nginx entrypoint scripts (`/docker-entrypoint.d/`) may warn about read-only
  config files but these are non-fatal warnings
- The `wget` healthcheck works on Alpine (curl is not installed by default)
