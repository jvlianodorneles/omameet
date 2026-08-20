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

class TestSystemIntegrations(unittest.TestCase):
    def test_clipboard_helper_empty(self):
        # Empty text should return False
        self.assertFalse(omameet.copy_to_clipboard(""))

    def test_mute_microphone_callable(self):
        # Function should execute without throwing uncaught exceptions
        try:
            omameet.mute_microphone()
            ran = True
        except Exception:
            ran = False
        self.assertTrue(ran)

class TestOwnerOnlyPermissions(unittest.TestCase):
    def test_state_dir_and_files_permissions(self):
        # 1. Ensure directory is created with 0700
        omameet.ensure_dirs()
        self.assertTrue(os.path.exists(omameet.STATE_DIR))
        dir_stat = os.stat(omameet.STATE_DIR)
        dir_mode = dir_stat.st_mode & 0o777
        self.assertEqual(dir_mode, 0o700, f"Expected 0o700 for state directory, got {oct(dir_mode)}")

        # 2. Test save_config creates 0600 file
        cfg = omameet.load_config()
        omameet.save_config(cfg)
        cfg_stat = os.stat(omameet.CONFIG_PATH)
        cfg_mode = cfg_stat.st_mode & 0o777
        self.assertEqual(cfg_mode, 0o600, f"Expected 0o600 for config.json, got {oct(cfg_mode)}")

        # 3. Test save_state creates 0600 file
        state = omameet.load_state()
        omameet.save_state(state)
        state_stat = os.stat(omameet.STATE_PATH)
        state_mode = state_stat.st_mode & 0o777
        self.assertEqual(state_mode, 0o600, f"Expected 0o600 for state.json, got {oct(state_mode)}")

    def test_permission_remediation(self):
        # Verify that if an existing file had loose permissions (e.g. 0644), load/save remediates it to 0600
        omameet.ensure_dirs()
        os.chmod(omameet.CONFIG_PATH, 0o644)
        omameet.load_config()
        cfg_mode = os.stat(omameet.CONFIG_PATH).st_mode & 0o777
        self.assertEqual(cfg_mode, 0o600, f"Expected remediation to 0o600, got {oct(cfg_mode)}")

        os.chmod(omameet.STATE_PATH, 0o644)
        omameet.load_state()
        state_mode = os.stat(omameet.STATE_PATH).st_mode & 0o777
        self.assertEqual(state_mode, 0o600, f"Expected remediation to 0o600, got {oct(state_mode)}")

class TestRedirectSecurity(unittest.TestCase):
    def setUp(self):
        self.handler = omameet.SafeRedirectHandler()

    def test_cross_origin_redirect_strips_auth(self):
        req = omameet.urllib.request.Request(
            "https://calendar.company.com/feed.ics",
            headers={"Authorization": "Basic dXNlcjpwYXNz"}
        )
        new_req = self.handler.redirect_request(req, None, 302, "Found", {}, "https://evil.com/feed.ics")
        self.assertIsNotNone(new_req)
        self.assertNotIn("Authorization", new_req.headers)
        self.assertNotIn("authorization", [k.lower() for k in new_req.headers.keys()])
        self.assertNotIn("authorization", [k.lower() for k in new_req.unredirected_hdrs.keys()])

    def test_https_to_http_downgrade_strips_auth(self):
        req = omameet.urllib.request.Request(
            "https://calendar.company.com/feed.ics",
            headers={"Authorization": "Basic dXNlcjpwYXNz"}
        )
        new_req = self.handler.redirect_request(req, None, 302, "Found", {}, "http://calendar.company.com/feed.ics")
        self.assertIsNotNone(new_req)
        self.assertNotIn("Authorization", new_req.headers)
        self.assertNotIn("authorization", [k.lower() for k in new_req.headers.keys()])

    def test_cross_port_redirect_strips_auth(self):
        req = omameet.urllib.request.Request(
            "https://calendar.company.com:8443/feed.ics",
            headers={"Authorization": "Basic dXNlcjpwYXNz"}
        )
        new_req = self.handler.redirect_request(req, None, 302, "Found", {}, "https://calendar.company.com:9443/feed.ics")
        self.assertIsNotNone(new_req)
        self.assertNotIn("Authorization", new_req.headers)

    def test_same_origin_redirect_preserves_auth(self):
        req = omameet.urllib.request.Request(
            "https://calendar.company.com/v1/feed.ics",
            headers={"Authorization": "Basic dXNlcjpwYXNz"}
        )
        new_req = self.handler.redirect_request(req, None, 302, "Found", {}, "https://calendar.company.com/v2/feed.ics")
        self.assertIsNotNone(new_req)
        self.assertIn("Authorization", new_req.headers)
        self.assertEqual(new_req.headers["Authorization"], "Basic dXNlcjpwYXNz")

    def test_same_origin_relative_redirect_preserves_auth(self):
        req = omameet.urllib.request.Request(
            "https://calendar.company.com/v1/feed.ics",
            headers={"Authorization": "Basic dXNlcjpwYXNz"}
        )
        new_req = self.handler.redirect_request(req, None, 302, "Found", {}, "/v2/feed.ics")
        self.assertIsNotNone(new_req)
        self.assertIn("Authorization", new_req.headers)
        self.assertEqual(new_req.headers["Authorization"], "Basic dXNlcjpwYXNz")

class TestQmlPlainTextRendering(unittest.TestCase):
    def test_all_text_elements_in_qml_enforce_plain_text(self):
        import re
        plugin_dir = os.path.expanduser("~/.config/omarchy/plugins/dorneles.omameet")
        qml_files = ["BarWidget.qml", "Panel.qml"]

        for fname in qml_files:
            fpath = os.path.join(plugin_dir, fname)
            self.assertTrue(os.path.exists(fpath), f"File {fpath} not found")
            with open(fpath, "r", encoding="utf-8") as f:
                content = f.read()

            text_indices = [m.start() for m in re.finditer(r"\bText\s*\{", content)]
            self.assertGreater(len(text_indices), 0, f"No Text elements found in {fname}")

            for pos in text_indices:
                snippet = content[pos:pos+250]
                self.assertIn(
                    "textFormat: Text.PlainText",
                    snippet,
                    f"Text element in {fname} missing textFormat: Text.PlainText near:\n{snippet[:100]}..."
                )

    def test_widget_button_does_not_use_autotext_label(self):
        import re
        plugin_dir = os.path.expanduser("~/.config/omarchy/plugins/dorneles.omameet")
        bar_path = os.path.join(plugin_dir, "BarWidget.qml")
        with open(bar_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Ensure WidgetButton text is empty and labelVisible is false so AutoText is bypassed
        self.assertRegex(content, r'WidgetButton\s*\{[^}]*text:\s*""', "WidgetButton must set text: \"\" to prevent AutoText rendering")
        self.assertRegex(content, r'WidgetButton\s*\{[^}]*labelVisible:\s*false', "WidgetButton must set labelVisible: false")

class TestTerminalAndMarkupSanitization(unittest.TestCase):
    def test_strip_ansi_removes_escape_codes(self):
        raw = "\x1b[31mRed Title\x1b[0m \x1b]52;c;Y2F0Cg==\x07Malicious"
        cleaned = omameet.strip_ansi(raw)
        self.assertEqual(cleaned, "Red Title Malicious")
        self.assertNotIn("\x1b", cleaned)

    def test_strip_control_chars_removes_c0_c1_and_cr(self):
        raw = "Fake Line\rReal Line\x00\x07\x08"
        cleaned = omameet.strip_control_chars(raw)
        self.assertEqual(cleaned, "Fake Line Real Line")

    def test_strip_html_removes_markup(self):
        raw = '<img src="https://evil.com/leak.png"> Meeting <b>Title</b> &amp; Notes'
        cleaned = omameet.strip_html(raw)
        self.assertEqual(cleaned, " Meeting Title & Notes")
        self.assertNotIn("<img", cleaned)
        self.assertNotIn("<b", cleaned)

    def test_sanitize_text_comprehensive(self):
        raw = "\x1b[1m<script>alert(1)</script>Team\rSync\x00 \n\n Room 1"
        cleaned = omameet.sanitize_text(raw, multiline=False)
        self.assertEqual(cleaned, "Team Sync Room 1")

    def test_sanitize_terminal_output(self):
        raw = "\x1b[32m\x1b]0;hacked\x07Meeting\rOverwritten"
        cleaned = omameet.sanitize_terminal_output(raw)
        self.assertNotIn("\x1b", cleaned)
        self.assertNotIn("\r", cleaned)
        self.assertNotIn("\x07", cleaned)

    def test_ics_parser_sanitizes_titles_and_fields(self):
        ics = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:sec_test@omameet
SUMMARY:\x1b[31m<img src="http://evil.com">Malicious Meeting\x1b[0m\\nInjection
DESCRIPTION:<script>alert(1)</script>Confidential \x1b[2JNotes
LOCATION:<img src="http://tracker.com">Room A
ORGANIZER:\x1b[33mCEO <boss@corp.com>\x1b[0m
DTSTART:20260820T100000Z
DTEND:20260820T110000Z
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR"""
        tz = omameet.get_local_tz()
        w_start = datetime.datetime(2026, 8, 20, 0, 0, tzinfo=datetime.timezone.utc).astimezone(tz)
        w_end = datetime.datetime(2026, 8, 20, 23, 59, tzinfo=datetime.timezone.utc).astimezone(tz)
        evts = omameet.parse_ics_content(ics, {"id": "sec", "name": "<img src=x>Sec"}, w_start, w_end, tz)
        self.assertEqual(len(evts), 1)
        evt = evts[0]
        self.assertNotIn("<img", evt["summary"])
        self.assertNotIn("\x1b", evt["summary"])
        self.assertNotIn("\r", evt["summary"])
        self.assertEqual(evt["summary"], "Malicious Meeting Injection")
        self.assertNotIn("<script", evt["description"])
        self.assertNotIn("\x1b", evt["description"])
        self.assertNotIn("<img", evt["location"])
        self.assertNotIn("\x1b", evt["organizer"])
        self.assertNotIn("<img", evt["feed_name"])

class TestBoundedFeedResponses(unittest.TestCase):
    def test_read_bounded_stream_within_limit(self):
        import io
        data = b"A" * 1024
        stream = io.BytesIO(data)
        res = omameet.read_bounded_stream(stream, max_bytes=2048)
        self.assertEqual(len(res), 1024)

    def test_read_bounded_stream_exceeds_limit(self):
        import io
        data = b"A" * 2048
        stream = io.BytesIO(data)
        with self.assertRaises(ValueError):
            omameet.read_bounded_stream(stream, max_bytes=1024)

    def test_max_events_per_feed_limit(self):
        tz = omameet.get_local_tz()
        w_start = datetime.datetime(2026, 8, 20, 0, 0, tzinfo=datetime.timezone.utc).astimezone(tz)
        w_end = datetime.datetime(2026, 8, 20, 23, 59, tzinfo=datetime.timezone.utc).astimezone(tz)

        # Generate a large synthetic ICS
        lines = ["BEGIN:VCALENDAR", "VERSION:2.0"]
        for i in range(100):
            lines.extend([
                "BEGIN:VEVENT",
                f"UID:evt_{i}",
                f"SUMMARY:Event {i}",
                "DTSTART:20260820T100000Z",
                "DTEND:20260820T110000Z",
                "STATUS:CONFIRMED",
                "END:VEVENT"
            ])
        lines.append("END:VCALENDAR")
        ics_text = "\n".join(lines)

        orig_max = omameet.MAX_EVENTS_PER_FEED
        try:
            omameet.MAX_EVENTS_PER_FEED = 15
            evts = omameet.parse_ics_content(ics_text, {"id": "test", "name": "Test"}, w_start, w_end, tz)
            self.assertEqual(len(evts), 15)
        finally:
            omameet.MAX_EVENTS_PER_FEED = orig_max

class TestUrlSafetyAndValidation(unittest.TestCase):
    def test_safe_urls(self):
        self.assertTrue(omameet.is_safe_url("https://meet.google.com/abc-defg-hij"))
        self.assertTrue(omameet.is_safe_url("http://zoom.us/j/123456"))
        self.assertTrue(omameet.is_safe_url("webcal://calendar.company.com/feed.ics"))
        self.assertTrue(omameet.is_safe_url("zoommtg://zoom.us/join?confno=123456"))

    def test_unsafe_urls(self):
        self.assertFalse(omameet.is_safe_url("javascript:alert(1)"))
        self.assertFalse(omameet.is_safe_url("data:text/html,<script>alert(1)</script>"))
        self.assertFalse(omameet.is_safe_url("file:///etc/passwd"))
        self.assertFalse(omameet.is_safe_url("--help"))
        self.assertFalse(omameet.is_safe_url("-malicious-flag"))
        self.assertFalse(omameet.is_safe_url(""))

    def test_color_sanitization(self):
        self.assertEqual(omameet.sanitize_color("#4285F4"), "#4285F4")
        self.assertEqual(omameet.sanitize_color("#AABBCCDD"), "#AABBCCDD")
        self.assertEqual(omameet.sanitize_color("invalid_color"), "#4285F4")
        self.assertEqual(omameet.sanitize_color("#123; rm -rf /"), "#4285F4")

if __name__ == "__main__":
    unittest.main()



