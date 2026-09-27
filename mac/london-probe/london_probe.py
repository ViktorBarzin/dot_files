#!/usr/bin/python3
"""London internet-drop probe for the Mac (launchd agent).

Runs only while the Mac is on the London Flint's networks (default gateway
192.168.8.1 or 192.168.9.1). Once a second it pings the Flint and two public
IPs; every 5 seconds it asks the Flint's DNS for a name. A drop is 5+ seconds
of failed public pings, or 2+ failed DNS lookups while pings work. Each drop is
classified by layer:

  wifi        the Flint itself stopped answering (the Mac's own link)
  internet    the Flint answers, the internet does not (upstream; the Flint's
              own probe reports these, so they are recorded but not alerted)
  client-dns  pings work, the Flint's DNS does not answer the Mac

When the drop ends, one event is queued and pushed to Loki
({job="london-drops", source="mac"}), retried until Loki accepts it, stamped
with the push time. Design: infra docs/plans/2026-09-27-london-flint-main-router.md.

Python 3.9 (the macOS system interpreter), standard library only.
"""
import collections
import concurrent.futures
import json
import os
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Deque, List, Optional

FLINT_GATEWAYS = ("192.168.8.1", "192.168.9.1")
PUBLIC = ("1.1.1.1", "9.9.9.9")
DNS_NAME = "example.com"
LOKI_HOST = "loki.viktorbarzin.lan"
LOKI_IP = "10.0.20.203"  # Traefik; the cert does not cover .lan, the path is the tunnel
STATE_DIR = Path.home() / "Library" / "Application Support" / "london-probe"
QUEUE = STATE_DIR / "queue.jsonl"


@dataclass
class Sample:
    t: int
    flint: bool
    public: bool
    dns: Optional[bool] = None  # None = not checked this second


@dataclass
class Drop:
    start: int
    end: int
    layer: str
    samples: List[dict] = field(default_factory=list)
    snapshot: str = ""

    @property
    def drop_id(self) -> str:
        return f"mac-{self.start}"

    @property
    def duration_s(self) -> int:
        return self.end - self.start


class Detector:
    """Turns per-second samples into finished drops."""

    def __init__(self, drop_after: int = 5, dns_drop_after: int = 2) -> None:
        self.drop_after = drop_after
        self.dns_drop_after = dns_drop_after
        self.first_fail: Optional[int] = None
        self.flint_failed = False
        self.dns_fails = 0
        self.dns_first_fail: Optional[int] = None
        self.current: Optional[Drop] = None
        self.recent: Deque[Sample] = collections.deque(maxlen=30)

    @property
    def active(self) -> bool:
        return self.current is not None

    def observe(self, x: Sample) -> Optional[Drop]:
        self.recent.append(x)
        if not x.public:
            if self.first_fail is None:
                self.first_fail = x.t
            if not x.flint:
                self.flint_failed = True
            if self.current is None and x.t - self.first_fail + 1 >= self.drop_after:
                self.current = Drop(start=self.first_fail, end=x.t, layer="")
            if self.current is not None and self.current.layer != "client-dns":
                self.current.layer = "wifi" if self.flint_failed else "internet"
            return None

        finished = None
        if self.current is not None and self.current.layer in ("wifi", "internet"):
            finished = self._finish(x.t)
        self.first_fail = None
        self.flint_failed = False

        if x.dns is True:
            if self.current is not None and self.current.layer == "client-dns":
                finished = self._finish(x.t)
            self.dns_fails = 0
            self.dns_first_fail = None
        elif x.dns is False:
            if self.dns_first_fail is None:
                self.dns_first_fail = x.t
            self.dns_fails += 1
            if self.current is None and self.dns_fails >= self.dns_drop_after:
                self.current = Drop(start=self.dns_first_fail, end=x.t, layer="client-dns")
        return finished

    def _finish(self, t: int) -> Drop:
        drop = self.current
        assert drop is not None
        drop.end = t
        drop.samples = [s.__dict__ for s in self.recent]
        self.current = None
        return drop


# ---- I/O: everything below talks to the machine and the network ----------


def run(cmd: List[str], timeout: float = 3) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", "timeout")


def ping(host: str) -> bool:
    return run(["/sbin/ping", "-c", "1", "-t", "1", "-q", host]).returncode == 0


def dns_ok(server: str) -> bool:
    r = run(["/usr/bin/dig", f"@{server}", DNS_NAME, "+time=1", "+tries=1", "+short"])
    return r.returncode == 0 and r.stdout.strip() != ""


def default_gateway() -> str:
    r = run(["/sbin/route", "-n", "get", "default"])
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.startswith("gateway:"):
            return line.split(":", 1)[1].strip()
    return ""


def current_wifi(system_profiler_text: str) -> str:
    """The "Current Network Information" block: channel, signal/noise, rate."""
    lines = system_profiler_text.splitlines()
    for i, line in enumerate(lines):
        if line.strip() == "Current Network Information:":
            block = []
            for rest in lines[i:]:
                if rest.strip() == "Other Local Wi-Fi Networks:":
                    break
                block.append(rest)
            return "\n".join(block)
    return "(no current network)"


def snapshot() -> str:
    parts = []
    for title, cmd in (
        ("route get default", ["/sbin/route", "-n", "get", "default"]),
        ("ipconfig getsummary en0", ["/usr/sbin/ipconfig", "getsummary", "en0"]),
        ("utun interfaces", ["/bin/sh", "-c", "/sbin/ifconfig | grep -E '^utun|inet ' "]),
        ("scutil --dns", ["/usr/sbin/scutil", "--dns"]),
    ):
        r = run(cmd, timeout=10)
        parts.append(f"== {title}\n{(r.stdout or r.stderr)[:3000]}")
    r = run(["/usr/sbin/system_profiler", "SPAirPortDataType"], timeout=15)
    parts.append(f"== wifi\n{current_wifi(r.stdout)}")
    return "\n".join(parts)


def loki_body(drop: Drop) -> dict:
    line = json.dumps({
        "drop_id": drop.drop_id,
        "source": "mac",
        "layer": drop.layer,
        "start": drop.start,
        "end": drop.end,
        "duration_s": drop.duration_s,
        "samples": drop.samples,
        "snapshot": drop.snapshot,
    })
    return {"streams": [{
        "stream": {"job": "london-drops", "source": "mac", "layer": drop.layer, "drop_id": drop.drop_id},
        "values": [["@NOW@", line]],
    }]}


def enqueue(drop: Drop) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with QUEUE.open("a") as f:
        f.write(json.dumps(loki_body(drop)) + "\n")


def flush() -> None:
    if not QUEUE.exists():
        return
    keep = []
    for body in QUEUE.read_text().splitlines():
        if not body.strip():
            continue
        payload = body.replace("@NOW@", f"{time.time_ns()}")
        r = run([
            "/usr/bin/curl", "-sk", "-m", "5", "-o", "/dev/null", "-w", "%{http_code}",
            "--resolve", f"{LOKI_HOST}:443:{LOKI_IP}",
            "-H", "Content-Type: application/json", "--data-binary", payload,
            f"https://{LOKI_HOST}/loki/api/v1/push",
        ], timeout=8)
        if r.stdout.strip() != "204":
            keep.append(body)
    if keep:
        QUEUE.write_text("\n".join(keep) + "\n")
    else:
        QUEUE.unlink()


def log(msg: str) -> None:
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def main() -> None:
    detector = Detector()
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=4)
    last_dns = 0
    last_flush = 0
    snap_future = None
    log("london-probe started")
    while True:
        tick = time.time()
        now = int(tick)
        gw = default_gateway()
        if gw not in FLINT_GATEWAYS:
            # Not on the London Flint (travelling, or the Hyperoptic Wi-Fi).
            # A drop in progress on the Flint's network cannot be judged here.
            if detector.active:
                detector = Detector()
            time.sleep(5)
            continue

        f_flint = pool.submit(ping, gw)
        f_pub = [pool.submit(ping, h) for h in PUBLIC]
        flint = f_flint.result()
        public = any(f.result() for f in f_pub)
        dns: Optional[bool] = None
        if public and now - last_dns >= 5:
            last_dns = now
            dns = dns_ok(gw)

        was_active = detector.active
        drop = detector.observe(Sample(t=now, flint=flint, public=public, dns=dns))
        if detector.active and not was_active:
            snap_future = pool.submit(snapshot)
            log(f"drop started: layer={detector.current.layer if detector.current else '?'}")
        if drop is not None:
            drop.snapshot = snap_future.result() if snap_future else ""
            snap_future = None
            enqueue(drop)
            log(f"drop finished: {drop.drop_id} layer={drop.layer} duration={drop.duration_s}s")

        if now - last_flush >= 10 and not detector.active:
            last_flush = now
            try:
                flush()
            except OSError as e:
                log(f"flush failed: {e}")

        time.sleep(max(0.0, 1.0 - (time.time() - tick)))


if __name__ == "__main__":
    os.umask(0o077)
    main()
