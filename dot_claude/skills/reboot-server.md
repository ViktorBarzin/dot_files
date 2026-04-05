name: reboot-server
description: Safely reboot the Proxmox host, a single k8s node, or perform a rolling
  reboot of all nodes with graceful shutdown, MySQL auto-recovery, and post-boot validation.
  Use when the user asks to "reboot the server", "reboot proxmox", "reboot node",
  "restart the host", "rolling reboot", "reboot all nodes", "power cycle".
---

## Overview

This skill safely reboots infrastructure with three modes:
1. **Full host reboot** — reboot the entire Proxmox R730 host (all VMs)
2. **Single node reboot** — drain, reboot one k8s node VM, uncordon
3. **Rolling reboot** — cycle all 5 k8s nodes sequentially (workers first, master last)

## Connection Details

- **Proxmox host**: `ssh root@192.168.1.127`
- **kubectl**: `KUBECONFIG=/Users/viktorbarzin/code/config kubectl`
- **VM commands**: `ssh root@192.168.1.127 'qm <command>'`

Shorthand used below: `KC="KUBECONFIG=/Users/viktorbarzin/code/config kubectl"`

## VM Inventory & Boot Order

| Order | VMID | Name | Startup Delay | Shutdown Timeout | Notes |
|-------|------|------|---------------|------------------|-------|
| 1 | 101 | pfSense | 0s | 120s | Gateway/DHCP/DNS — must boot first |
| 2 | 9000 | TrueNAS | 60s | 300s | NFS storage — needs network from pfSense |
| 3 | 220 | docker-registry | 60s | 120s | Pull-through cache (fallback: upstream) |
| 3 | 102 | devvm | 60s | 120s | Dev VM — needs pfSense for network |
| 4 | 200 | k8s-master | 45s | 420s | Control plane — must be up before workers |
| 5 | 201 | k8s-node1 | 45s | 420s | GPU node (Tesla T4) |
| 5 | 202 | k8s-node2 | 45s | 420s | Worker |
| 5 | 203 | k8s-node3 | 45s | 420s | Worker |
| 5 | 204 | k8s-node4 | 45s | 420s | Worker |
| 6 | 103 | home-assistant | 0s | 120s | HA Sofia — no ordering dependency |
| 6 | 300 | Windows10 | 0s | 120s | Windows VM — no ordering dependency |

Shutdown order is the **reverse** of boot order (Proxmox handles this automatically).

## Node-to-VMID Mapping

```
k8s-master = 200
k8s-node1 = 201 (GPU node — Immich ML, Frigate, Ollama)
k8s-node2 = 202
k8s-node3 = 203
k8s-node4 = 204
```

## Mode Selection

Ask the user which mode they want if unclear:
1. **Full host reboot** — reboot the entire Proxmox R730 host
2. **Single node reboot** — drain, reboot one k8s node VM, uncordon
3. **Rolling reboot** — cycle all 5 k8s nodes sequentially (for kernel updates, maintenance)

---

## Shared Pre-flight Checks

These checks apply to ALL modes. Run them before proceeding.

### PF-1: Verify Proxmox SSH access
```bash
ssh -o ConnectTimeout=5 root@192.168.1.127 'hostname && uptime'
```

### PF-2: Verify cluster health
```bash
$KC get nodes
$KC get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded' | grep -v Completed | head -20
```

### PF-3: Check and configure VM boot ordering
```bash
# Check current boot order for all VMs
ssh root@192.168.1.127 'for VMID in 101 102 103 200 201 202 203 204 220 300 9000; do echo "VMID $VMID: $(qm config $VMID 2>/dev/null | grep ^startup || echo "no startup config")"; done'
```

If not configured, apply boot order (idempotent):
```bash
ssh root@192.168.1.127 '
qm set 101 --startup order=1,down=120
qm set 9000 --startup order=2,up=60,down=300
qm set 102 --startup order=3,up=60,down=120
qm set 220 --startup order=3,up=60,down=120
qm set 200 --startup order=4,up=45,down=420
qm set 201 --startup order=5,up=45,down=420
qm set 202 --startup order=5,up=45,down=420
qm set 203 --startup order=5,up=45,down=420
qm set 204 --startup order=5,up=45,down=420
qm set 103 --startup order=6,down=120
qm set 300 --startup order=6,down=120
'
```

### PF-4: Check kubelet priority-based shutdown on all k8s nodes

Kubelet uses `shutdownGracePeriodByPodPriority` for ordered pod shutdown (lowest priority stopped first):

| Priority | Tier | Grace | Stopped |
|----------|------|-------|---------|
| 0 | unclassified | 20s | 1st |
| 200000 | tier-4-aux | 20s | 2nd |
| 400000 | tier-3-edge | 30s | 3rd |
| 600000 | tier-2-gpu | 30s | 4th |
| 800000 | tier-1-cluster (DBs) | 90s | 5th |
| 1000000 | tier-0-core | 30s | 6th |
| 1200000 | gpu-workload | 30s | 7th |
| 2000000000 | system-cluster-critical | 30s | 8th |
| 2000001000 | system-node-critical | 30s | 9th (last) |

**Total: 310s kubelet, 420s VM timeout, 480s InhibitDelay**

```bash
for VMID in 200 201 202 203 204; do
  echo "=== VMID $VMID ==="
  ssh root@192.168.1.127 "qm guest exec $VMID -- grep -c shutdownGracePeriodByPodPriority /var/lib/kubelet/config.yaml 2>/dev/null" || echo "NOT SET"
done
```

If not set on any node, patch it with the python3/yaml approach:
```bash
VMID=<target>
ssh root@192.168.1.127 "qm guest exec $VMID -- python3 -c \"
import yaml
with open('/var/lib/kubelet/config.yaml') as f:
    cfg = yaml.safe_load(f)
cfg.pop('shutdownGracePeriod', None)
cfg.pop('shutdownGracePeriodCriticalPods', None)
cfg.pop('shutdownGracePeriodByPodPriority', None)
cfg['shutdownGracePeriodByPodPriority'] = [
    {'priority': 0,          'shutdownGracePeriodSeconds': 20},
    {'priority': 200000,     'shutdownGracePeriodSeconds': 20},
    {'priority': 400000,     'shutdownGracePeriodSeconds': 30},
    {'priority': 600000,     'shutdownGracePeriodSeconds': 30},
    {'priority': 800000,     'shutdownGracePeriodSeconds': 90},
    {'priority': 1000000,    'shutdownGracePeriodSeconds': 30},
    {'priority': 1200000,    'shutdownGracePeriodSeconds': 30},
    {'priority': 2000000000, 'shutdownGracePeriodSeconds': 30},
    {'priority': 2000001000, 'shutdownGracePeriodSeconds': 30},
]
with open('/var/lib/kubelet/config.yaml', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False)
print('done')
\""

# Update systemd timeouts to match
ssh root@192.168.1.127 "qm guest exec $VMID -- bash -c '
mkdir -p /etc/systemd/logind.conf.d
echo -e \"[Login]\nInhibitDelayMaxSec=480\" > /etc/systemd/logind.conf.d/kubelet-shutdown.conf
systemctl restart systemd-logind
mkdir -p /etc/systemd/system/kubelet.service.d
echo -e \"[Service]\nTimeoutStopSec=420s\" > /etc/systemd/system/kubelet.service.d/20-shutdown.conf
systemctl daemon-reload
systemctl restart kubelet
'"
```

### PF-5: Check unattended-upgrades on k8s nodes
```bash
for VMID in 200 201 202 203 204; do
  echo "=== VMID $VMID ==="
  ssh root@192.168.1.127 "qm guest exec $VMID -- systemctl is-active unattended-upgrades 2>/dev/null" || echo "not found (good)"
done
```

If active, disable: `ssh root@192.168.1.127 "qm guest exec $VMID -- bash -c 'systemctl disable --now unattended-upgrades; apt-get remove -y unattended-upgrades'"`

### PF-6: Report pre-flight status
Summarize: all checks passed, or list what was fixed. Ask user for **final confirmation** before proceeding.

---

## Full Host Reboot Procedure

### Phase 1: Pre-flight
Run [Shared Pre-flight Checks](#shared-pre-flight-checks) above.

### Phase 2: Reboot

**Get explicit user confirmation before proceeding.**

```bash
ssh root@192.168.1.127 'reboot'
```

Wait for SSH to drop:
```bash
for i in $(seq 1 30); do
  ssh -o ConnectTimeout=3 -o BatchMode=yes root@192.168.1.127 'true' 2>/dev/null || { echo "Host is rebooting"; break; }
  sleep 2
done
```

Poll until Proxmox is back (timeout: 10 minutes):
```bash
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

Run these checks in a loop, reporting progress.

#### 3.1 Check all VMs are running
```bash
ssh root@192.168.1.127 'qm list' | grep -v stopped
```
If any critical VM (101, 9000, 200-204, 220) is not running after 5 minutes: `qm start <VMID>`

#### 3.2 Check k8s API is reachable
```bash
$KC cluster-info 2>/dev/null
```

#### 3.3 Check all nodes are Ready
```bash
$KC get nodes
```
All 5 nodes should show `Ready`.

#### 3.4 Check critical infrastructure pods (tiered)

```bash
# Tier 0: Core networking
$KC get pods -n metallb-system -l app=metallb
$KC get pods -n kube-system -l k8s-app=kube-dns
$KC get pods -n technitium

# Tier 1: Storage
$KC get pods -n proxmox-csi
$KC get pods -n nfs-csi

# Tier 2: Ingress + tunnel
$KC get pods -n traefik
$KC get pods -n cloudflared

# Tier 3: Security
$KC get pods -n kyverno

# Tier 4: Data layer
$KC get pods -n redis
$KC get pods -n dbaas

# Tier 5: Secrets + auth
$KC get pods -n vault
$KC get pods -n authentik
$KC get pods -n external-secrets
```

#### 3.5 Vault Verification
```bash
# Check sealed status
$KC exec -n vault vault-0 -- vault status -format=json 2>/dev/null | jq '.sealed'

# Check all 3 Vault pods are Running
$KC get pods -n vault -l app.kubernetes.io/name=vault

# If unsealed, check Raft peers
$KC exec -n vault vault-0 -- vault operator raft list-peers 2>/dev/null
```

If sealed after 5 minutes:
```bash
# Check auto-unseal sidecar logs
$KC logs -n vault vault-0 -c auto-unseal --tail=20
```

If Raft has missing peers after unseal:
```bash
$KC exec -n vault vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
$KC exec -n vault vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
```

#### 3.6 Proxmox-LVM PVC Validation
```bash
# Check all PVCs — none should be Pending (except newly created)
$KC get pvc -A --field-selector 'status.phase!=Bound' 2>/dev/null | head -20

# Check proxmox-lvm PVCs specifically
$KC get pvc -A -o json | jq -r '.items[] | select(.spec.storageClassName=="proxmox-lvm") | "\(.metadata.namespace)/\(.metadata.name): \(.status.phase)"'
```

If any proxmox-lvm PVCs are stuck:
```bash
# Check proxmox-csi-plugin pods
$KC get pods -n proxmox-csi
# Check node LVM thin pool
ssh root@192.168.1.127 "for VMID in 200 201 202 203 204; do echo '=== VMID '\$VMID' ==='; qm guest exec \$VMID -- lvs --noheadings -o lv_name,lv_size,data_percent pve/data 2>/dev/null; done"
```

#### 3.7 MySQL InnoDB Cluster Recovery

**This is the most critical post-reboot step.** MySQL InnoDB Cluster cannot auto-recover from a complete outage.

```bash
# Get root password
ROOT_PWD=$($KC get secret cluster-secret -n dbaas -o jsonpath='{.data.ROOT_PASSWORD}' | base64 -d)

# Check cluster status
$KC exec -n dbaas mysql-cluster-0 -c mysql -- mysqlsh --js --uri "root:${ROOT_PWD}@localhost:3306" -e "print(JSON.stringify(dba.getCluster().status()))" 2>/dev/null
```

**If status shows 0 ONLINE members (complete outage):**

⚠️ **ASK USER FOR CONFIRMATION** before running rebootClusterFromCompleteOutage. Explain:
- This will designate mysql-cluster-0 as the new primary
- If data diverged between members, this picks cluster-0's data
- Partial outages should NOT use this command (use rejoinInstance instead)

If confirmed:
```bash
# Reboot cluster from complete outage
$KC exec -n dbaas mysql-cluster-0 -c mysql -- mysqlsh --js --uri "root:${ROOT_PWD}@localhost:3306" -e "dba.rebootClusterFromCompleteOutage()"

# Wait up to 10 minutes for all 3 members to come ONLINE
for i in $(seq 1 60); do
  ONLINE=$($KC exec -n dbaas mysql-cluster-0 -c mysql -- mysqlsh --js --uri "root:${ROOT_PWD}@localhost:3306" -e "print(dba.getCluster().status().defaultReplicaSet.topology)" 2>/dev/null | grep -c '"status": "ONLINE"')
  if [ "$ONLINE" = "3" ]; then
    echo "All 3 MySQL members ONLINE"
    break
  fi
  echo "MySQL members ONLINE: $ONLINE/3 (attempt $i/60)"
  sleep 10
done
```

**Fix operator/router authentication (always needed after rebootClusterFromCompleteOutage):**
```bash
# Get expected passwords from K8s secrets
ADMIN_PWD=$($KC get secret -n dbaas mysql-cluster-privsecret -o jsonpath='{.data.clusterAdminPassword}' | base64 -d 2>/dev/null)

# Reset operator admin user password
$KC exec -n dbaas mysql-cluster-0 -c mysql -- mysql -u root -p"${ROOT_PWD}" -e "
ALTER USER IF EXISTS 'mysqladmin'@'%' IDENTIFIED BY '${ADMIN_PWD}';
"

# Recreate router user with full privileges (the reboot drops it)
$KC exec -n dbaas mysql-cluster-0 -c mysql -- mysqlsh --js --uri "root:${ROOT_PWD}@localhost:3306" -e "
var c = dba.getCluster();
c.setupRouterAccount('mysqlrouter@\"%\"', {update: true});
"

# Restart operator and router pods to pick up new credentials
$KC delete pod -n dbaas -l app.kubernetes.io/name=mysql-operator
$KC delete pod -n dbaas -l app.kubernetes.io/component=router
```

**Verify MySQL is fully operational:**
```bash
# Check cluster status
$KC exec -n dbaas mysql-cluster-0 -c mysql -- mysqlsh --js --uri "root:${ROOT_PWD}@localhost:3306" -e "print(dba.getCluster().status().defaultReplicaSet.status)"

# Check router is accepting connections
$KC exec -n dbaas mysql-cluster-0 -c mysql -- mysql -u root -p"${ROOT_PWD}" -h mysql.dbaas.svc.cluster.local -e "SELECT 1"
```

#### 3.8 Redis Validation
```bash
# Check Redis pods
$KC get pods -n redis

# Check HAProxy is routing to master
HAPROXY_POD=$($KC get pods -n redis -l app=redis-haproxy -o jsonpath='{.items[0].metadata.name}')
$KC exec -n redis $HAPROXY_POD -- cat /tmp/haproxy.cfg 2>/dev/null | grep "server redis" || echo "HAProxy config not found — check haproxy pod"

# Verify writes work through master
$KC exec -n redis redis-node-1 -- redis-cli SET reboot-test ok 2>/dev/null && \
$KC exec -n redis redis-node-1 -- redis-cli DEL reboot-test 2>/dev/null && \
echo "Redis write test passed" || echo "Redis write FAILED — check master routing"
```

#### 3.9 ESO Sync Verification
```bash
# Force ESO to re-sync all secrets (Vault may have rotated passwords)
$KC annotate externalsecrets.external-secrets.io -A --all force-sync=$(date +%s) --overwrite 2>/dev/null

# Wait 60s for sync
sleep 60

# Check for failed syncs
FAILED=$($KC get externalsecrets -A --no-headers 2>/dev/null | grep -v SecretSynced | grep -v "SYNCED" || true)
if [ -n "$FAILED" ]; then
  echo "WARNING: Some ExternalSecrets failed to sync:"
  echo "$FAILED"
else
  echo "All ExternalSecrets synced successfully"
fi
```

#### 3.10 Check for stuck pods
```bash
$KC get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded' | grep -v Completed | head -30
```

### Phase 4: Final Validation

- If all checks pass: report "Cluster fully recovered in X minutes"
- If issues remain after 30 minutes: invoke the `/cluster-health` skill for diagnosis
- Store a memory summarizing the reboot: timestamp, duration, any issues encountered, lessons learned

---

## Single Node Reboot Procedure

### Phase 1: Pre-flight

#### 1.1 Identify target
Map the user's input to a node name and VMID:
- `k8s-master` / `master` / `200` → k8s-master (VMID 200)
- `k8s-node1` / `node1` / `201` → k8s-node1 (VMID 201, GPU)
- `k8s-node2` / `node2` / `202` → k8s-node2 (VMID 202)
- `k8s-node3` / `node3` / `203` → k8s-node3 (VMID 203)
- `k8s-node4` / `node4` / `204` → k8s-node4 (VMID 204)

#### 1.2 Check node status
```bash
$KC get node <node-name>
```

#### 1.3 Check what's running on the node
```bash
$KC get pods -A --field-selector spec.nodeName=<node-name> | head -30
```

Warn the user if the node runs:
- GPU workloads (node1) — Immich ML, Frigate, Ollama
- Database pods — MySQL InnoDB, PostgreSQL CNPG (check if it's primary)
- Vault pods — may need re-unseal

#### 1.4 Check PDBs won't block drain
```bash
$KC get pdb -A
```

### Phase 2: Drain + Reboot

```bash
# Drain the node
$KC drain <node-name> --ignore-daemonsets --delete-emptydir-data --timeout=300s

# Shutdown the VM gracefully
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
  STATUS=$($KC get node <node-name> --no-headers 2>/dev/null | awk '{print $2}')
  if [ "$STATUS" = "Ready" ]; then
    echo "Node is Ready"
    break
  fi
  echo "Waiting for node to become Ready... ($i/30)"
  sleep 10
done

# Uncordon the node
$KC uncordon <node-name>

# Verify DaemonSet pods are scheduled
$KC get pods -A --field-selector spec.nodeName=<node-name> | head -20

echo "Node <node-name> rebooted and uncordoned successfully"
```

---

## Rolling Reboot Procedure

Cycles all 5 k8s nodes sequentially: **workers first (node2→3→4→1), master last**.

### Phase 1: Pre-flight
Run [Shared Pre-flight Checks](#shared-pre-flight-checks).

Additionally:
```bash
# Snapshot current pod distribution
$KC get pods -A -o wide --no-headers | awk '{print $8}' | sort | uniq -c | sort -rn
echo "---"
# Check PDBs that could block drains
$KC get pdb -A
echo "---"
# Check MySQL cluster health before starting
ROOT_PWD=$($KC get secret cluster-secret -n dbaas -o jsonpath='{.data.ROOT_PASSWORD}' | base64 -d)
$KC exec -n dbaas mysql-cluster-0 -c mysql -- mysqlsh --js --uri "root:${ROOT_PWD}@localhost:3306" -e "print(dba.getCluster().status().defaultReplicaSet.status)" 2>/dev/null
```

### Phase 2: Rolling Cycle

Process nodes in this order: **k8s-node2 → k8s-node3 → k8s-node4 → k8s-node1 (GPU) → k8s-master**

For each node, execute this sequence:

```bash
NODE=<node-name>
VMID=<vmid>
echo "========================================="
echo "Rolling reboot: $NODE (VMID $VMID)"
echo "========================================="

# Step 1: Drain
echo "Draining $NODE..."
$KC drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=300s

# Step 2: Graceful shutdown
echo "Shutting down VM $VMID..."
ssh root@192.168.1.127 "qm shutdown $VMID --timeout 300"

# Step 3: Wait for VM to stop
for i in $(seq 1 60); do
  STATUS=$(ssh root@192.168.1.127 "qm status $VMID" 2>/dev/null)
  if echo "$STATUS" | grep -q stopped; then echo "VM $VMID stopped"; break; fi
  sleep 5
done

# Step 4: Start VM
echo "Starting VM $VMID..."
ssh root@192.168.1.127 "qm start $VMID"

# Step 5: Wait for node Ready
for i in $(seq 1 30); do
  STATUS=$($KC get node $NODE --no-headers 2>/dev/null | awk '{print $2}')
  if [ "$STATUS" = "Ready" ]; then echo "$NODE is Ready"; break; fi
  echo "Waiting... ($i/30)"
  sleep 10
done

# Step 6: Uncordon
$KC uncordon $NODE
echo "$NODE uncordoned"

# Step 7: Verify DaemonSets
$KC get pods -A --field-selector spec.nodeName=$NODE --no-headers | wc -l
echo "DaemonSet pods scheduled on $NODE"

# Step 8: Cool-down (2 min)
echo "Cooling down for 2 minutes before next node..."
sleep 120
```

### Phase 3: Mid-cycle Health Check (after all workers, before master)

After k8s-node1 (last worker) is back and uncordoned, check critical services before cycling the master:

```bash
echo "=== Mid-cycle health check ==="

# All 4 workers should be Ready
$KC get nodes

# Check MySQL cluster — if any member is not ONLINE, fix before cycling master
ROOT_PWD=$($KC get secret cluster-secret -n dbaas -o jsonpath='{.data.ROOT_PASSWORD}' | base64 -d)
$KC exec -n dbaas mysql-cluster-0 -c mysql -- mysqlsh --js --uri "root:${ROOT_PWD}@localhost:3306" -e "print(dba.getCluster().status().defaultReplicaSet.status)" 2>/dev/null

# Check Vault — if sealed, fix before cycling master
$KC exec -n vault vault-0 -- vault status -format=json 2>/dev/null | jq '.sealed'

# Check no pods stuck
$KC get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded' | grep -v Completed | head -10

echo "=== Proceeding to master node ==="
```

If MySQL shows issues at this point, run [MySQL InnoDB Cluster Recovery](#37-mysql-innodb-cluster-recovery) before proceeding to the master.

### Phase 4: Post-rolling Validation

After the master is back and uncordoned, run the full validation suite from [Phase 3 of Full Host Reboot](#phase-3-post-boot-validation-30-min-timeout), including:
- All nodes Ready (3.3)
- Critical pods tiered check (3.4)
- Vault verification (3.5)
- Proxmox-LVM PVC validation (3.6)
- MySQL InnoDB recovery if needed (3.7) — **with user confirmation**
- Redis validation (3.8)
- ESO sync (3.9)
- Stuck pods check (3.10)

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| VM won't start | Proxmox host disk full | `ssh root@192.168.1.127 'df -h'` — check thin pool usage with `lvs pve/data` |
| Node stays NotReady | kubelet/containerd not starting | `qm guest exec <VMID> -- systemctl status kubelet` and `systemctl status containerd` |
| NFS PVCs stuck Pending | TrueNAS not fully booted | Wait for ZFS pool import: `qm guest exec 9000 -- zpool status` |
| Proxmox-LVM PVCs stuck | proxmox-csi-plugin not running | `$KC get pods -n proxmox-csi` — check CSI node plugin on affected node. Check LVM thin pool: `qm guest exec <VMID> -- lvs` |
| Vault stays sealed | Auto-unseal sidecar not running | Check sidecar: `$KC logs -n vault vault-0 -c auto-unseal --tail=20`. Check unseal key secret exists: `$KC get secret -n vault vault-unseal-key` |
| Vault Raft peer missing | Pod restarted on different node | `$KC exec -n vault vault-1 -- vault operator raft join http://vault-0.vault-internal:8200` |
| MySQL 0 ONLINE members | Complete outage — operator can't recover | See [MySQL InnoDB Cluster Recovery](#37-mysql-innodb-cluster-recovery) — requires user confirmation |
| MySQL router auth failure | Reboot recreated internal users | Reset passwords from K8s secrets + setupRouterAccount — see section 3.7 |
| Redis READONLY errors | HAProxy routing to replica | Check HAProxy pod routing config, verify `redis` service selector points to `app=redis-haproxy` |
| ESO secrets not syncing | Vault sealed or token expired | Unseal Vault first, then force-sync: `$KC annotate externalsecrets -A --all force-sync=$(date +%s) --overwrite` |
| Pods CrashLoopBackOff | Dependencies not ready yet | Usually self-heals — wait 5 min, then check with `/cluster-health` |
| containerd won't start | Disk full or corrupted images | `qm guest exec <VMID> -- journalctl -u containerd --no-pager -n 50`. If blob corruption, see containerd cleanup procedure in memory. |
| Drain stuck on PDB | PDB minAvailable can't be met | Check PDB: `$KC get pdb -A`. May need to scale up another replica first or `--disable-eviction` |
