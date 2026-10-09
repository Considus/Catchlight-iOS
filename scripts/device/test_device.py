#!/usr/bin/env python3
"""Tests for the pure parts of device.py: device choice, log text, crash filtering.

    python3 scripts/device/test_device.py

The device and build calls need a phone and are proved by running the commands.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import device  # noqa: E402


def phone(name, ident, udid, platform="iOS", pairing="paired"):
    return {"identifier": ident,
            "deviceProperties": {"name": name},
            "hardwareProperties": {"platform": platform, "udid": udid},
            "connectionProperties": {"pairingState": pairing, "tunnelState": "connected"}}


class ChooseDevice(unittest.TestCase):
    def test_single_paired_iphone_is_used(self):
        devices = [phone("Mark's iPhone 17", "68C8", "0000-A"),
                   phone("Old iPad", "11AA", "0000-B", pairing="unpaired"),
                   phone("Apple Watch", "22BB", "0000-C", platform="watchOS")]
        self.assertEqual(device.choose_device(devices)["identifier"], "68C8")

    def test_none_paired_fails_with_advice(self):
        with self.assertRaisesRegex(device.Failure, "no paired iPhone"):
            device.choose_device([phone("Old", "1", "u", pairing="unpaired")])

    def test_two_paired_needs_a_choice(self):
        devices = [phone("A", "1", "u1"), phone("B", "2", "u2")]
        with self.assertRaisesRegex(device.Failure, "pass --device"):
            device.choose_device(devices)
        self.assertEqual(device.choose_device(devices, "b")["identifier"], "2")
        self.assertEqual(device.choose_device(devices, "u1")["identifier"], "1")

    def test_part_of_a_name_matches(self):
        devices = [phone("Mark\u2019s iPhone 17", "68C8", "0000-A"), phone("Spare iPad", "11AA", "0000-B")]
        self.assertEqual(device.choose_device(devices, "iphone 17")["identifier"], "68C8")


class DiagnosticsText(unittest.TestCase):
    def setUp(self):
        # Pin local time to UTC so the expected lines are fixed literals.
        self._tz = os.environ.get("TZ")
        os.environ["TZ"] = "UTC"
        if hasattr(__import__("time"), "tzset"):
            __import__("time").tzset()

    def tearDown(self):
        if self._tz is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = self._tz
        if hasattr(__import__("time"), "tzset"):
            __import__("time").tzset()

    def test_reference_date_and_order(self):
        # 0 s is 2001-01-01 00:00:00 UTC (Foundation's reference date);
        # 812678400 s later is 2026-10-03 00:00:00 UTC.
        entries = [{"timestamp": 812678400, "category": "lifecycle", "message": "launch 2919625"},
                   {"timestamp": 0, "category": "storage", "message": "[CCIOS-101] first"}]
        self.assertEqual(device.diagnostics_text(entries),
                         "2001-01-01 00:00:00  [storage]  [CCIOS-101] first\n"
                         "2026-10-03 00:00:00  [lifecycle]  launch 2919625\n")

    def test_empty_log_is_empty_text(self):
        self.assertEqual(device.diagnostics_text([]), "")


class CrashFilter(unittest.TestCase):
    def test_keeps_only_catchlight_reports(self):
        paths = ["Catchlight-2026-10-06-120000.ips", "CatchlightWidgets-2026-10-06.ips",
                 "Retired/Catchlight-2026-09-01-080000.ips", "ExcUserFault_Catchlight-2026-10-02.ips",
                 "AlexaMobileiOS-prod-2026-10-06-171359.ips", "NotCatchlight-2026.ips",
                 "Catchlight.notes.txt", "DiagnosticLogs/sysdiag.log"]
        self.assertEqual(device.catchlight_crashes(paths),
                         ["Catchlight-2026-10-06-120000.ips", "CatchlightWidgets-2026-10-06.ips",
                          "ExcUserFault_Catchlight-2026-10-02.ips",
                          "Retired/Catchlight-2026-09-01-080000.ips"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
