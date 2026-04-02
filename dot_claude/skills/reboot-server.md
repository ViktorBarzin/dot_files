name: reboot-server
description: Safely reboot the Proxmox host or a single k8s node with graceful shutdown
  and post-boot validation. Use when the user asks to "reboot the server", "reboot
  proxmox", "reboot node", "restart the host", "restart k8s node", "power cycle".
  Supports full host reboot and single node reboot modes.
---

## Overview

This skill safely reboots either the entire Proxmox host (Dell R730) or a single Kubernetes node VM. It ensures graceful shutdown of all services and validates full recovery afterwards.

## Connection Details

- **Proxmox host**: `ssh root@192.168.1.127`
- **kubectl**: `KUBECONFIG=/Users/viktorbarzin/code/config kubectl`
- **VM commands**: `ssh root@192.168.1.127 'qm <command>'`

## VM Inventory & Boot Order

| Order | VMID | Name | Startup Delay | Shutdown Timeout | Notes |
|-------|------|------|---------------|------------------|-------|
| 1 | 101 | pfSense | 0s | 120s | Gateway/DHCP/DNS — must boot first |
| 2 | 9000 | TrueNAS | 60s | 300s | NFS/iSCSI storage — needs network from pfSense |
| 3 | 220 | docker-registry | 60s | 120s | Pull-through cache (fallback: upstream) |
| 3 | 102 | devvm | 60s | 120s | Dev VM — needs pfSense for network |
| 4 | 200 | k8s-master | 45s | 300s | Control plane — must be up before workers |
| 5 | 201 | k8s-node1 | 45s | 300s | GPU node (Tesla T4) |
| 5 | 202 | k8s-node2 | 45s | 300s | Worker |
| 5 | 203 | k8s-node3 | 45s | 300s | Worker |
| 5 | 204 | k8s-node4 | 45s | 300s | Worker |
| 6 | 103 | home-assistant | 0s | 120s | HA Sofia — no ordering dependency |
| 6 | 300 | Windows10 | 0s | 120s | Windows VM — no ordering dependency |

Shutdown order is the **reverse** of boot order (Proxmox handles this automatically).

## Node-to-VMID Mapping

```
k8s-master = 200
k8s-node1 = 201 (GPU node)
k8s-node2 = 202
k8s-node3 = 203
k8s-node4 = 204
```

## Mode Selection

Ask the user which mode they want if unclear:
1. **Full host reboot** — reboot the entire Proxmox R730 host
2. **Single node reboot** — drain, reboot one k8s node VM, uncordon

---

## Full Host Reboot Procedure

### Phase 1: Pre-flight Checks

Run ALL of these checks before proceeding. Fix issues inline if possible.

#### 1.1 Verify Proxmox SSH access
```bash
ssh -o ConnectTimeout=5 root@192.168.1.127 'hostname && uptime'
```

#### 1.2 Verify cluster health
```bash
KUBECONFIG=/Users/viktorbarzin/code/config kubectl get nodes
KUBECONFIG=/Users/viktorbarzin/code/config kubectl get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded' | head -20
```

#### 1.3 Check and configure VM boot ordering
For each VM, check if boot ordering is set. If any VM has `order=-1`, configure it:

```bash
# Check current boot order for all VMs
ssh root@192.168.1.127 'for VMID in 101 102 103 200 201 202 203 204 220 300 9000; do echo "VMID $VMID: $(qm config $VMID 2>/dev/null | grep ^startup || echo "no startup config")"; done'
```

If not configured, apply boot order (this is idempotent):
```bash
ssh root@192.168.1.127 '
qm set 101 --startup order=1,down=120
qm set 9000 --startup order=2,up=60,down=300
qm set 102 --startup order=3,up=60,down=120
qm set 220 --startup order=3,up=60,down=120
qm set 200 --startup order=4,up=45,down=300
qm set 201 --startup order=5,up=45,down=300
qm set 202 --startup order=5,up=45,down=300
qm set 203 --startup order=5,up=45,down=300
qm set 204 --startup order=5,up=45,down=300
qm set 103 --startup order=6,down=120
qm set 300 --startup order=6,down=120
'
```

#### 1.4 Check kubelet shutdownGracePeriod on all k8s nodes
```bash
for VMID in 200 201 202 203 204; do
  echo "=== VMID $VMID ==="
  ssh root@192.168.1.127 "qm guest exec $VMID -- grep -c shutdownGracePeriod /var/lib/kubelet/config.yaml 2>/dev/null" || echo "NOT SET"
done
```

If not set on any node, patch it:
```bash
VMID=<target>
ssh root@192.168.1.127 "qm guest exec $VMID -- bash -c '
# Remove any existing shutdown config to avoid duplicates
sed -i \"/shutdownGracePeriod/d; /shutdownGracePeriodCriticalPods/d\" /var/lib/kubelet/config.yaml

# Add graceful shutdown config
cat >> /var/lib/kubelet/config.yaml <<EOF
shutdownGracePeriod: \"240s\"
shutdownGracePeriodCriticalPods: \"60s\"
EOF

# Create systemd logind override for InhibitDelayMaxSec
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/kubelet-shutdown.conf <<EOF
[Login]
InhibitDelayMaxSec=300
EOF
systemctl restart systemd-logind

# Create kubelet service override for TimeoutStopSec
mkdir -p /etc/systemd/system/kubelet.service.d
cat > /etc/systemd/system/kubelet.service.d/20-shutdown.conf <<EOF
[Service]
TimeoutStopSec=300s
EOF
systemctl daemon-reload
systemctl restart kubelet
'"
```

Repeat for each node VMID (200-204) that needs patching.

#### 1.5 Check unattended-upgrades on k8s nodes
```bash
for VMID in 200 201 202 203 204; do
  echo "=== VMID $VMID ==="
  ssh root@192.168.1.127 "qm guest exec $VMID -- systemctl is-active unattended-upgrades 2>/dev/null" || echo "not found (good)"
done
```

If active on any node, disable it:
```bash
ssh root@192.168.1.127 "qm guest exec $VMID -- bash -c 'systemctl disable --now unattended-upgrades; apt-get remove -y unattended-upgrades'"
```

#### 1.6 Report pre-flight status
Summarize: all checks passed, or list what was fixed. Ask user for final confirmation before rebooting.

### Phase 2: Reboot

**IMPORTANT**: Get explicit user confirmation before proceeding.

```bash
# Reboot the Proxmox host
ssh root@192.168.1.127 'reboot'
```

Then wait for SSH to drop (confirms reboot started):
```bash
# Poll until SSH drops (host is rebooting)
for i in $(seq 1 30); do
  ssh -o ConnectTimeout=3 -o BatchMode=yes root@192.168.1.127 'true' 2>/dev/null || { echo "Host is rebooting"; break; }
  sleep 2
done
```

Then poll until Proxmox is back (timeout: 10 minutes):
```bash
# Poll every 30s until SSH is back
for i in $(seq 1 20); do
  if ssh -o ConnectTimeout=5 -o BatchMode=yes root@192.168.1.127 'uptime' 2>/dev/null; then
    echo "Proxmox host is back online"
    break
  fi
  echo "Waiting for Proxmox host... (attempt $i/20)"
  sleep 30
done
```

### Phase 3: Post-boot Validation (30 min timeout)

Run these checks in a loop, reporting progress. Timeout after 30 minutes total.

#### 3.1 Check all VMs are running
```bash
ssh root@192.168.1.127 'qm list' | grep -v stopped
```

If any critical VM (101, 9000, 200-204, 220) is not running after 5 minutes, start it:
```bash
ssh root@192.168.1.127 'qm start <VMID>'
```

#### 3.2 Check k8s API is reachable
```bash
KUBECONFIG=/Users/viktorbarzin/code/config kubectl cluster-info 2>/dev/null
```

#### 3.3 Check all nodes are Ready
```bash
KUBECONFIG=/Users/viktorbarzin/code/config kubectl get nodes
```

All 5 nodes (k8s-master, k8s-node1-4) should show `Ready`.

#### 3.4 Check critical infrastructure pods

Check these in order (reflects boot dependency chain):

```bash
KC="KUBECONFIG=/Users/viktorbarzin/code/config kubectl"

# Tier 0: Core infrastructure
$KC get pods -n metallb-system -l app=metallb
$KC get pods -n kube-system -l k8s-app=kube-dns  # CoreDNS
$KC get pods -n technitium  # DNS

# Tier 1: Storage
$KC get pods -n democratic-csi  # iSCSI-CSI
$KC get pods -n nfs-csi  # NFS-CSI

# Tier 2: Ingress + tunnel
$KC get pods -n traefik
$KC get pods -n cloudflared

# Tier 3: Security
$KC get pods -n kyverno

# Tier 4: Data layer
$KC get pods -n redis
$KC get pods -n dbaas  # MySQL + PostgreSQL

# Tier 5: Secrets + auth
$KC get pods -n vault
$KC get pods -n authentik
$KC get pods -n external-secrets
```

#### 3.5 Check Vault is unsealed
```bash
KUBECONFIG=/Users/viktorbarzin/code/config kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null | jq '.sealed'
```

Should return `false`. The auto-unseal sidecar polls every 10s — if still sealed after 5 minutes, investigate.

#### 3.6 Check PVC status
```bash
KUBECONFIG=/Users/viktorbarzin/code/config kubectl get pvc -A --field-selector 'status.phase!=Bound' 2>/dev/null | head -20
```

No PVCs should be in Pending state (indicates CSI driver issues).

#### 3.7 Check for stuck pods
```bash
KUBECONFIG=/Users/viktorbarzin/code/config kubectl get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded' | grep -v Completed | head -30
```

Known slow starters to ignore: MySQL InnoDB pods (up to 60 min init), Vault pods (auto-unseal takes a minute).

### Phase 4: Final Validation

- If all checks pass: report "Cluster fully recovered in X minutes"
- If issues remain after 30 minutes: invoke the `/cluster-health` skill for diagnosis and remediation
- Store a memory summarizing the reboot: timestamp, duration, any issues encountered

---

## Single Node Reboot Procedure

### Phase 1: Pre-flight

#### 1.1 Identify target
Map the user's input to a node name and VMID:
- `k8s-master` / `master` / `200` → k8s-master (VMID 200)
- `k8s-node1` / `node1` / `201` → k8s-node1 (VMID 201, GPU node)
- `k8s-node2` / `node2` / `202` → k8s-node2 (VMID 202)
- `k8s-node3` / `node3` / `203` → k8s-node3 (VMID 203)
- `k8s-node4` / `node4` / `204` → k8s-node4 (VMID 204)

#### 1.2 Check node status
```bash
KUBECONFIG=/Users/viktorbarzin/code/config kubectl get node <node-name>
```

#### 1.3 Check what's running on the node
```bash
KUBECONFIG=/Users/viktorbarzin/code/config kubectl get pods -A --field-selector spec.nodeName=<node-name> | head -30
```

Warn the user if the node runs:
- GPU workloads (node1) — Immich ML, Frigate, Ollama
- Database pods — MySQL InnoDB, PostgreSQL CNPG (long recovery)
- Vault pods — may need re-unseal

#### 1.4 Check PDBs won't block drain
```bash
KUBECONFIG=/Users/viktorbarzin/code/config kubectl get pdb -A
```

Verify that draining this node won't violate any PDB (e.g., Traefik minAvailable=2 — if 2 of 3 Traefik pods are on other nodes, drain is safe).

### Phase 2: Drain + Reboot

```bash
# Drain the node (300s timeout for graceful eviction)
KUBECONFIG=/Users/viktorbarzin/code/config kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --timeout=300s

# Shutdown the VM gracefully (300s timeout for kubelet + systemd shutdown)
ssh root@192.168.1.127 "qm shutdown <VMID> --timeout 300"

# Wait for VM to stop
for i in $(seq 1 60); do
  STATUS=$(ssh root@192.168.1.127 "qm status <VMID>" 2>/dev/null)
  if echo "$STATUS" | grep -q stopped; then
    echo "VM stopped"
    break
  fi
  echo "Waiting for VM to stop... ($i/60)"
  sleep 5
done

# Start the VM
ssh root@192.168.1.127 "qm start <VMID>"
```

### Phase 3: Recovery

```bash
# Wait for node to become Ready (timeout: 5 min)
for i in $(seq 1 30); do
  STATUS=$(KUBECONFIG=/Users/viktorbarzin/code/config kubectl get node <node-name> --no-headers 2>/dev/null | awk '{print $2}')
  if [ "$STATUS" = "Ready" ]; then
    echo "Node is Ready"
    break
  fi
  echo "Waiting for node to become Ready... ($i/30)"
  sleep 10
done

# Uncordon the node
KUBECONFIG=/Users/viktorbarzin/code/config kubectl uncordon <node-name>

# Verify DaemonSet pods are scheduled
KUBECONFIG=/Users/viktorbarzin/code/config kubectl get pods -A --field-selector spec.nodeName=<node-name> | head -20

# Report status
echo "Node <node-name> rebooted and uncordoned successfully"
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| VM won't start | Proxmox host disk full | `ssh root@192.168.1.127 'df -h'` — check thin pool |
| Node stays NotReady | kubelet/containerd not starting | `qm guest exec <VMID> -- systemctl status kubelet` |
| NFS PVCs stuck Pending | TrueNAS not fully booted | Wait for TrueNAS ZFS pool import, or `qm guest exec 9000 -- zpool status` |
| Vault stays sealed | Auto-unseal sidecar not running | Check sidecar logs: `kubectl logs -n vault vault-0 -c vault-unseal` |
| MySQL slow to recover | InnoDB init containers (~20 min each) | Normal — monitor progress with `kubectl logs -n dbaas` |
| Pods CrashLoopBackOff | Dependencies not ready yet | Usually self-heals — wait 5 min, then check with `/cluster-health` |
| containerd won't start | Disk full or corrupted images | `qm guest exec <VMID> -- journalctl -u containerd --no-pager -n 50` |
