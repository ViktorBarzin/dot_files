"""Tests for the drop detector in london_probe.py (run: python3 -m unittest)."""
import unittest

import socket

from london_probe import Detector, Sample, current_wifi, tcp_reachable


def s(t, flint=True, public=True, dns=None):
    return Sample(t=t, flint=flint, public=public, dns=dns)


class DetectorTest(unittest.TestCase):
    """Thresholds are in seconds; samples arrive every 10 s, every 2 s after a failure."""

    def feed(self, samples):
        d = Detector(drop_after=30, dns_drop_after=30)
        events = []
        for x in samples:
            ev = d.observe(x)
            if ev:
                events.append(ev)
        return d, events

    def test_blip_under_30s_is_not_a_drop(self):
        samples = [s(0)] + [s(t, public=False) for t in range(10, 40, 2)] + [s(40)]
        _, events = self.feed(samples)
        self.assertEqual(events, [])

    def test_public_loss_of_30s_with_flint_up_is_internet_drop(self):
        samples = [s(0)] + [s(t, public=False) for t in range(10, 44, 2)] + [s(44)]
        _, events = self.feed(samples)
        self.assertEqual(len(events), 1)
        ev = events[0]
        self.assertEqual(ev.layer, "internet")
        self.assertEqual(ev.start, 10)
        self.assertEqual(ev.end, 44)
        self.assertEqual(ev.duration_s, 34)

    def test_flint_unreachable_is_wifi_drop(self):
        samples = [s(t, flint=False, public=False) for t in range(0, 32, 2)] + [s(32)]
        _, events = self.feed(samples)
        self.assertEqual([e.layer for e in events], ["wifi"])

    def test_wifi_wins_if_flint_drops_at_any_point_of_the_drop(self):
        samples = [s(t, public=False) for t in range(0, 32, 2)]
        samples[3] = s(6, flint=False, public=False)
        _, events = self.feed(samples + [s(32)])
        self.assertEqual([e.layer for e in events], ["wifi"])

    def test_dns_failing_for_30s_with_connections_ok_is_client_dns_drop(self):
        samples = [s(t, dns=False) for t in range(0, 32, 2)] + [s(32, dns=True)]
        _, events = self.feed(samples)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].layer, "client-dns")
        self.assertEqual(events[0].start, 0)
        self.assertEqual(events[0].end, 32)

    def test_short_dns_failure_is_not_a_drop(self):
        _, events = self.feed([s(0, dns=False), s(2, dns=False), s(4, dns=True)])
        self.assertEqual(events, [])

    def test_dns_is_not_judged_while_public_is_down(self):
        samples = [s(t, public=False, dns=False) for t in range(0, 32, 2)] + [s(32, dns=True)]
        _, events = self.feed(samples)
        self.assertEqual([e.layer for e in events], ["internet"])

    def test_drop_id_is_stable_and_prefixed(self):
        samples = [s(t, public=False) for t in range(100, 132, 2)] + [s(132)]
        _, events = self.feed(samples)
        self.assertEqual(events[0].drop_id, "mac-100")

    def test_active_reports_drop_in_progress(self):
        d, _ = self.feed([s(t, public=False) for t in range(0, 32, 2)])
        self.assertTrue(d.active)

    def test_pending_after_any_failure_and_clear_after_recovery(self):
        d, _ = self.feed([s(0), s(10, public=False)])
        self.assertTrue(d.pending)
        d.observe(s(12))
        self.assertFalse(d.pending)
        d.observe(s(20, dns=False))
        self.assertTrue(d.pending)
        d.observe(s(22, dns=True))
        self.assertFalse(d.pending)


class CurrentWifiTest(unittest.TestCase):
    def test_keeps_only_the_current_network_block(self):
        text = """Wi-Fi:
      Supported Channels: 1 (2GHz), 2 (2GHz), 36 (5GHz)
      Current Network Information:
        <redacted>:
          PHY Mode: 802.11ax
          Channel: 44 (5GHz, 80MHz)
          Signal / Noise: -38 dBm / -92 dBm
          Transmit Rate: 1201
      Other Local Wi-Fi Networks:
        Neighbour:
          Channel: 1 (2GHz, 20MHz)
"""
        out = current_wifi(text)
        self.assertIn("Channel: 44 (5GHz, 80MHz)", out)
        self.assertIn("Signal / Noise: -38 dBm / -92 dBm", out)
        self.assertNotIn("Supported Channels", out)
        self.assertNotIn("Neighbour", out)

    def test_not_associated_returns_marker(self):
        self.assertEqual(current_wifi("Wi-Fi:\n  Status: Off\n"), "(no current network)")


class TcpReachableTest(unittest.TestCase):
    def test_listening_port_is_reachable(self):
        srv = socket.socket()
        srv.bind(("127.0.0.1", 0))
        srv.listen(1)
        try:
            self.assertTrue(tcp_reachable("127.0.0.1", srv.getsockname()[1]))
        finally:
            srv.close()

    def test_refused_port_still_proves_the_path(self):
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()
        self.assertTrue(tcp_reachable("127.0.0.1", port))

    def test_silent_address_is_not_reachable(self):
        self.assertFalse(tcp_reachable("192.0.2.1", 80, timeout=0.3))


if __name__ == "__main__":
    unittest.main()
