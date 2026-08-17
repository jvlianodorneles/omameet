#!/usr/bin/env python3
"""
test_omameet.py - Unit & Integration tests for omameet plugin
"""

import unittest
import datetime
import os
import sys

# Import functions from omameet-sync.py
sys.path.insert(0, os.path.expanduser("~/.config/omarchy/plugins/dorneles.omameet/scripts"))
import importlib.util
spec = importlib.util.spec_from_file_location("omameet_sync", os.path.expanduser("~/.config/omarchy/plugins/dorneles.omameet/scripts/omameet-sync.py"))
omameet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(omameet)

class TestMeetingExtraction(unittest.TestCase):
    def test_google_meet(self):
        url, prov_id, name = omameet.extract_meeting_info(
            "https://meet.google.com/abc-defg-hij",
            "Meeting notes",
            ""
        )
        self.assertEqual(prov_id, "google_meet")
        self.assertEqual(url, "https://meet.google.com/abc-defg-hij")

    def test_zoom(self):
        url, prov_id, name = omameet.extract_meeting_info(
            "",
            "Join Zoom Meeting: https://company.zoom.us/j/1234567890?pwd=secretpassword\nPasscode: 123",
            ""
        )
        self.assertEqual(prov_id, "zoom")
        self.assertTrue("zoom.us/j/1234567890" in url)

    def test_teams(self):
        url, prov_id, name = omameet.extract_meeting_info(
            "Microsoft Teams Meeting",
            "Meeting link: https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz%40thread.v2/0?context=abc",
            ""
        )
        self.assertEqual(prov_id, "teams")

    def test_jitsi(self):
        url, prov_id, name = omameet.extract_meeting_info(
            "https://meet.jit.si/daily-standup-team",
            "",
            ""
        )
        self.assertEqual(prov_id, "jitsi")

    def test_webex(self):
        url, prov_id, name = omameet.extract_meeting_info(
            "",
            "Join via Cisco Webex: https://mycompany.webex.com/meet/john.doe",
            ""
        )
        self.assertEqual(prov_id, "webex")

    def test_discord(self):
        url, prov_id, name = omameet.extract_meeting_info(
            "",
            "Discord Call: https://discord.gg/invitecode123",
            ""
        )
        self.assertEqual(prov_id, "discord")

    def test_slack(self):
        url, prov_id, name = omameet.extract_meeting_info(
            "",
            "Slack Huddle: https://myteam.slack.com/huddle/C12345678",
            ""
        )
        self.assertEqual(prov_id, "slack")

class TestICalParsing(unittest.TestCase):
    def test_unfolding_and_unescaping(self):
        raw = "SUMMARY:Weekly Sync with Engineering,\n Design and Product Teams\nDESCRIPTION:First line\\nSecond line with \\, comma"
        lines = omameet.unfold_ical_lines(raw)
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0], "SUMMARY:Weekly Sync with Engineering,Design and Product Teams")
        unescaped = omameet.unescape_ical_text("Text with \\n break and \\, comma")
        self.assertEqual(unescaped, "Text with \n break and , comma")

    def test_rrule_expansion(self):
        tz = omameet.get_local_tz()
        start = datetime.datetime.now(tz)
        end = start + datetime.timedelta(hours=1)
        event = {
            "id": "recur_1",
            "summary": "Daily Standup",
            "description": "",
            "location": "https://meet.google.com/xyz-test",
            "start_dt": start,
            "end_dt": end,
            "start_iso": start.isoformat(),
            "end_iso": end.isoformat(),
            "is_all_day": False,
            "video_url": "https://meet.google.com/xyz-test",
            "provider_id": "google_meet",
            "provider_name": "Google Meet",
            "has_link": True,
            "feed_id": "test",
            "feed_name": "Test",
            "feed_color": "#3B82F6",
            "organizer": "team@company.com",
            "rrule": "FREQ=DAILY;INTERVAL=1",
            "exdates": []
        }
        window_start = start - datetime.timedelta(days=1)
        window_end = start + datetime.timedelta(days=3)
        instances = omameet.expand_recurring_events(event, window_start, window_end, tz)
        self.assertGreaterEqual(len(instances), 3)

    def test_declined_and_cancelled_detection(self):
        ics_text = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:test_declined@omameet
SUMMARY:Declined Meeting
DTSTART:20260816T140000Z
DTEND:20260816T150000Z
STATUS:CONFIRMED
ATTENDEE;PARTSTAT=DECLINED:mailto:user@example.com
END:VEVENT
BEGIN:VEVENT
UID:test_cancelled@omameet
SUMMARY:Cancelled Event
DTSTART:20260816T160000Z
DTEND:20260816T170000Z
STATUS:CANCELLED
END:VEVENT
END:VCALENDAR"""
        tz = omameet.get_local_tz()
        w_start = datetime.datetime(2026, 8, 16, 0, 0, tzinfo=datetime.timezone.utc).astimezone(tz)
        w_end = datetime.datetime(2026, 8, 17, 0, 0, tzinfo=datetime.timezone.utc).astimezone(tz)
        evts = omameet.parse_ics_content(ics_text, {"id": "test", "name": "Test"}, w_start, w_end, tz)
        self.assertEqual(len(evts), 2)
        self.assertTrue(evts[0]["is_declined"])
        self.assertTrue(evts[1]["is_declined"])

if __name__ == "__main__":
    unittest.main()
