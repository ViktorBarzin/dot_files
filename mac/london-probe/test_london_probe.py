"""Tests for the drop detector in london_probe.py (run: python3 -m unittest)."""
import unittest

from london_probe import Detector, Sample


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


if __name__ == "__main__":
    unittest.main()
