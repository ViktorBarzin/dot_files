---
name: idrac-fan-control
description: |
  Control Dell server fan speed via iDRAC IPMI commands. Use when:
  (1) User asks to change fan speed, reduce fan noise, or adjust cooling,
  (2) User asks about server temperatures or thermal status,
  (3) User mentions "idrac", "ipmi", "fan speed", "fan noise", or "server loud",
  (4) User wants to check or set manual fan control on the Dell R730.
  Covers IPMI raw commands for fan override, racadm access, and thermal monitoring.
author: Claude Code
version: 1.0.0
date: 2026-03-17
---

# iDRAC Fan Control

## Problem
Dell servers run fans at high RPM by default, which can be excessively loud for home lab environments. Manual fan speed control requires IPMI raw commands that aren't well documented.

## Context / Trigger Conditions
- Server fans running too loud (~7000+ RPM)
- User wants quieter operation when thermal headroom exists
- Need to check temperatures before/after fan speed changes
- Dell PowerEdge server with iDRAC (tested on R730, service tag GCFSDN2)

## Prerequisites

### iDRAC Network Details
- **iDRAC IP**: 192.168.1.4
- **Credentials**: root / calvin
- **Redfish API**: https://192.168.1.4/redfish/v1/

### IPMI over LAN Must Be Enabled
IPMI over LAN is **disabled by default**. Enable it via racadm SSH:

```bash
# From Proxmox (192.168.1.127) which has sshpass installed:
ssh root@192.168.1.127 "sshpass -p calvin ssh -o StrictHostKeyChecking=no -o PubkeyAuthentication=no root@192.168.1.4 'racadm get iDRAC.IPMILan'"

# If Enable=Disabled, enable it:
ssh root@192.168.1.127 "sshpass -p calvin ssh -o StrictHostKeyChecking=no -o PubkeyAuthentication=no root@192.168.1.4 'racadm set iDRAC.IPMILan.Enable Enabled'"
```

### ipmitool Access
ipmitool is installed on **Proxmox** (192.168.1.127). All commands below run from there:

```bash
# Shorthand used in examples below:
IPMI_CMD="ssh root@192.168.1.127 'ipmitool -I lanplus -H 192.168.1.4 -U root -P calvin'"
```

## Solution

### Step 1: Check Current Temperatures and Fan Speeds

```bash
# Read temperatures
ssh root@192.168.1.127 "ipmitool -I lanplus -H 192.168.1.4 -U root -P calvin sdr type temperature"
# Output: Inlet Temp, Exhaust Temp, CPU Temp with °C readings

# Read fan speeds
ssh root@192.168.1.127 "ipmitool -I lanplus -H 192.168.1.4 -U root -P calvin sdr type fan"
# Output: Fan1-Fan6 with RPM readings
```

### Step 2: Set Manual Fan Speed

```bash
# 1. Disable automatic fan control (switch to manual mode)
ssh root@192.168.1.127 "ipmitool -I lanplus -H 192.168.1.4 -U root -P calvin raw 0x30 0x30 0x01 0x00"

# 2. Set fan speed percentage (0xff = all fans, last byte = hex percentage)
#    Common values: 0x0a=10%, 0x14=20%, 0x1e=30%, 0x28=40%, 0x32=50%, 0x64=100%
ssh root@192.168.1.127 "ipmitool -I lanplus -H 192.168.1.4 -U root -P calvin raw 0x30 0x30 0x02 0xff 0x14"
```

### Step 3: Verify and Monitor

```bash
# Check fan speeds dropped
ssh root@192.168.1.127 "ipmitool -I lanplus -H 192.168.1.4 -U root -P calvin sdr type fan"

# Monitor temperatures to ensure they stay safe
ssh root@192.168.1.127 "ipmitool -I lanplus -H 192.168.1.4 -U root -P calvin sdr type temperature"
```

### Restore Automatic Fan Control

```bash
# Re-enable automatic fan control (iDRAC manages fans again)
ssh root@192.168.1.127 "ipmitool -I lanplus -H 192.168.1.4 -U root -P calvin raw 0x30 0x30 0x01 0x01"
```

## Alternative: Redfish API (No ipmitool Needed)

Read-only thermal data is available via Redfish (works from any machine):

```bash
# Get fan speeds and temperatures
curl -sk -u root:calvin https://192.168.1.4/redfish/v1/Chassis/System.Embedded.1/Thermal | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
for f in d.get('Fans',[]):
    print(f'{f[\"Name\"]} = {f[\"Reading\"]} RPM')
for t in d.get('Temperatures',[]):
    print(f'{t[\"Name\"]} = {t[\"ReadingCelsius\"]}°C')
"
```

## Alternative: racadm via SSH to iDRAC

For other iDRAC settings, SSH directly via Proxmox:

```bash
ssh root@192.168.1.127 "sshpass -p calvin ssh -o StrictHostKeyChecking=no -o PubkeyAuthentication=no root@192.168.1.4 'racadm <command>'"
```

Useful racadm commands:
- `racadm getsensorinfo` — all sensor readings
- `racadm get iDRAC.IPMILan` — IPMI LAN configuration
- `racadm get System.ThermalSettings` — thermal profile settings

## Verification
- After setting fan speed, `sdr type fan` should show lower RPM values
- Monitor `sdr type temperature` for 5-10 minutes — inlet should stay under 35°C, CPU under 80°C
- If temperatures rise dangerously, immediately re-enable auto: `raw 0x30 0x30 0x01 0x01`

## Thermal Baseline (Normal Operation)
| Sensor | Typical Value |
|--------|---------------|
| Inlet Temp | ~24°C |
| Exhaust Temp | ~25-26°C |
| CPU1 Temp | ~50°C |
| Fan1-Fan6 (auto) | ~7080-7200 RPM |

## Safe Fan Speed Guidelines
| Fan % | Good For | Max Inlet Temp |
|-------|----------|----------------|
| 10% | Idle, quiet room | < 25°C |
| 20% | Normal workload | < 30°C |
| 30% | Heavy workload | < 35°C |
| 40%+ | GPU/summer | < 40°C |

## Notes
- IPMI raw commands `0x30 0x30` are Dell-specific OEM commands — won't work on HP/Supermicro
- Manual fan mode persists across iDRAC resets but NOT across full server power cycles
- The Redfish API on this firmware (v1.4.0) does NOT support the Attributes endpoint — use IPMI for control
- ipmitool must run from a host on the same network as iDRAC (192.168.1.x) — Proxmox is the relay
- sshpass + ipmitool are installed on Proxmox (installed 2026-03-17)
