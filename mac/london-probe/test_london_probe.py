"""Tests for the drop detector in london_probe.py (run: python3 -m unittest)."""
import unittest

import socket

from london_probe import Detector, Sample, current_wifi, tcp_reachable


def s(t, flint=True, public=True, dns=None):
    return Sample(t=t, flint=flint, public=public, dns=dns)


class DetectorTest(unittest.TestCase):
    def feed(self, samples):
        d = Detector(drop_after=5, dns_drop_after=2)
        events = []
        for x in samples:
            ev = d.observe(x)
            if ev:
                events.append(ev)
        return d, events

    def test_short_public_blip_is_not_a_drop(self):
        _, events = self.feed([s(0), s(1, public=False), s(2, public=False), s(3, public=False), s(4)])
        self.assertEqual(events, [])

    def test_public_loss_with_flint_up_is_internet_drop(self):
        samples = [s(t, public=False) for t in range(10, 17)] + [s(17)]
        _, events = self.feed(samples)
        self.assertEqual(len(events), 1)
        ev = events[0]
        self.assertEqual(ev.layer, "internet")
        self.assertEqual(ev.start, 10)
        self.assertEqual(ev.end, 17)
        self.assertEqual(ev.duration_s, 7)

    def test_flint_unreachable_is_wifi_drop(self):
        samples = [s(t, flint=False, public=False) for t in range(0, 6)] + [s(6)]
        _, events = self.feed(samples)
        self.assertEqual([e.layer for e in events], ["wifi"])

    def test_wifi_wins_if_flint_drops_at_any_point_of_the_drop(self):
        samples = [s(0, public=False), s(1, public=False), s(2, flint=False, public=False),
                   s(3, public=False), s(4, public=False), s(5)]
        _, events = self.feed(samples)
        self.assertEqual([e.layer for e in events], ["wifi"])

    def test_dns_failures_with_ping_ok_are_client_dns_drop(self):
        samples = [s(0, dns=False), s(5, dns=False), s(10, dns=True)]
        _, events = self.feed(samples)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].layer, "client-dns")
        self.assertEqual(events[0].start, 0)
        self.assertEqual(events[0].end, 10)

    def test_single_dns_failure_is_not_a_drop(self):
        _, events = self.feed([s(0, dns=False), s(5, dns=True)])
        self.assertEqual(events, [])

    def test_dns_is_not_judged_while_public_is_down(self):
        samples = [s(t, public=False, dns=False) for t in range(0, 6)] + [s(6, dns=True)]
        _, events = self.feed(samples)
        self.assertEqual([e.layer for e in events], ["internet"])

    def test_drop_id_is_stable_and_prefixed(self):
        samples = [s(t, public=False) for t in range(100, 106)] + [s(106)]
        _, events = self.feed(samples)
        self.assertEqual(events[0].drop_id, "mac-100")

    def test_active_reports_drop_in_progress(self):
        d, _ = self.feed([s(t, public=False) for t in range(0, 6)])
        self.assertTrue(d.active)


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
