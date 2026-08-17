#!/usr/bin/env python3
"""
omameet-sync.py - Universal Calendar Sync & Meeting Detection Engine for Omarchy
Part of the omameet plugin (dorneles.omameet).
Zero external dependencies (uses standard Python 3 libraries).
"""

import sys
import os
import re
import json
import urllib.request
import urllib.parse
import urllib.error
import ssl
import subprocess
import datetime
import shutil
from zoneinfo import ZoneInfo
from typing import Dict, List, Any, Optional, Tuple

STATE_DIR = os.path.expanduser("~/.local/state/omarchy/omameet")
CONFIG_PATH = os.path.join(STATE_DIR, "config.json")
STATE_PATH = os.path.join(STATE_DIR, "state.json")
HOOK_DIR = os.path.expanduser("~/.config/omarchy/hooks")
HOOK_JOIN_SCRIPT = os.path.join(HOOK_DIR, "omameet-join.sh")

# Default configurations
DEFAULT_CONFIG = {
    "version": 1,
    "feeds": [],
    "bookmarks": [
        {"id": "bm_team", "name": "Team room", "url": "https://meet.jit.si/omarchy-team-room"},
        {"id": "bm_quick", "name": "Quick Meet", "url": "https://meet.google.com/new"}
    ],
    "settings": {
        "format": "title_countdown",
        "maxTitleLength": 25,
        "marqueeEnabled": False,
        "marqueeSpeed": 6,
        "showIcon": True,
        "showCountdown": True,
        "refreshIntervalMin": 15,
        "urgentThresholdMin": 5,
        "enableNotifications": True,
        "notificationLeadMin": 5,
        "hideAllDayEvents": False,
        "hideWithoutLinks": False,
        "hideDeclined": True,
        "hideTentative": False,
        "hidePending": False,
        "pauseMusicOnJoin": True,
        "preferredBrowser": "",
        "openInNativeApp": False
    }
}

# --- Video Conference Link Detection Patterns ---
VIDEO_PATTERNS = [
    # Google Meet
    ("google_meet", "Google Meet", r"https?://meet\.google\.com/([a-z0-9-]+)(?:\?[^\s\"'<>]*)?"),
    # Zoom
    ("zoom", "Zoom", r"https?://(?:[a-zA-Z0-9-]+\.)?zoom\.us/(?:j|my)/([a-zA-Z0-9-._]+)(?:\?[^\s\"'<>]*)?"),
    ("zoom", "Zoom", r"https?://(?:[a-zA-Z0-9-]+\.)?zoomgov\.com/(?:j|my)/([a-zA-Z0-9-._]+)(?:\?[^\s\"'<>]*)?"),
    # Microsoft Teams
    ("teams", "Microsoft Teams", r"https?://teams\.microsoft\.com/l/meetup-join/[^\s\"'<>]+"),
    ("teams", "Microsoft Teams", r"https?://teams\.live\.com/meet/[^\s\"'<>]+"),
    # Webex
    ("webex", "Cisco Webex", r"https?://(?:[a-zA-Z0-9-]+\.)?webex\.com/(?:meet|join|m)/([a-zA-Z0-9-._]+)(?:\?[^\s\"'<>]*)?"),
    ("webex", "Cisco Webex", r"https?://(?:[a-zA-Z0-9-]+\.)?webex\.com/[^\s\"'<>]+/j\.php\?[^\s\"'<>]+"),
    # Jitsi Meet
    ("jitsi", "Jitsi Meet", r"https?://meet\.jit\.si/([a-zA-Z0-9-_]+)(?:\?[^\s\"'<>]*)?"),
    ("jitsi", "Jitsi Meet", r"https?://(?:8x8\.vc/[^\s\"'<>]+|meet\.[a-zA-Z0-9.-]+/[a-zA-Z0-9-_]+)"),
    # Discord
    ("discord", "Discord", r"https?://(?:www\.)?discord\.(?:gg|com/invite)/([a-zA-Z0-9-_]+)"),
    ("discord", "Discord", r"https?://(?:www\.)?discord\.com/channels/[0-9]+/[0-9]+"),
    # Slack
    ("slack", "Slack Huddle", r"https?://(?:[a-zA-Z0-9-]+\.)?slack\.com/(?:huddle|archives|call)/[^\s\"'<>]+"),
    # Skype
    ("skype", "Skype", r"https?://join\.skype\.com/([a-zA-Z0-9-_]+)"),
    # Whereby
    ("whereby", "Whereby", r"https?://(?:[a-zA-Z0-9-]+\.)?whereby\.com/([a-zA-Z0-9-_]+)"),
    # Chime
    ("chime", "Amazon Chime", r"https?://app\.chime\.aws/meetings/([0-9]+)"),
    # Around
    ("around", "Around", r"https?://(?:meet\.)?around\.co/m/([a-zA-Z0-9-_]+)"),
    # RingCentral
    ("ringcentral", "RingCentral", r"https?://(?:v\.)?ringcentral\.com/join/([0-9]+)"),
    # BlueJeans
    ("bluejeans", "BlueJeans", r"https?://(?:[a-zA-Z0-9-]+\.)?bluejeans\.com/([0-9]+)"),
    # GoToMeeting
    ("gotomeeting", "GoToMeeting", r"https?://(?:global\.)?gotomeeting\.com/join/([0-9]+)"),
    # BigBlueButton
    ("bigbluebutton", "BigBlueButton", r"https?://[a-zA-Z0-9.-]+/b/join/[a-zA-Z0-9-_]+"),
    # Riverside
    ("riverside", "Riverside.fm", r"https?://(?:[a-zA-Z0-9-]+\.)?riverside\.fm/studio/([a-zA-Z0-9-_]+)"),
    # Generic URL in location / description matching http/https
    ("generic_link", "Meeting Link", r"https?://[^\s\"'<>]+")
]

def ensure_dirs():
    os.makedirs(STATE_DIR, exist_ok=True)

def get_local_tz() -> datetime.tzinfo:
    """Detects local machine timezone robustly without throwing ZoneInfo errors."""
    if os.path.exists("/etc/localtime"):
        try:
            real = os.path.realpath("/etc/localtime")
            if "zoneinfo/" in real:
                iana = real.split("zoneinfo/")[-1]
                return ZoneInfo(iana)
        except Exception:
            pass
    if os.path.exists("/etc/timezone"):
        try:
            with open("/etc/timezone", "r") as f:
                iana = f.read().strip()
                if iana:
                    return ZoneInfo(iana)
        except Exception:
            pass
    tz = datetime.datetime.now().astimezone().tzinfo
    if tz:
        return tz
    return datetime.timezone.utc

def load_config() -> Dict[str, Any]:
    ensure_dirs()
    if not os.path.exists(CONFIG_PATH):
        save_config(DEFAULT_CONFIG)
        return DEFAULT_CONFIG
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            cfg = json.load(f)
            if "settings" not in cfg:
                cfg["settings"] = DEFAULT_CONFIG["settings"]
            else:
                for k, v in DEFAULT_CONFIG["settings"].items():
                    if k not in cfg["settings"]:
                        cfg["settings"][k] = v
            if "feeds" not in cfg:
                cfg["feeds"] = []
            if "bookmarks" not in cfg:
                cfg["bookmarks"] = DEFAULT_CONFIG["bookmarks"]
            return cfg
    except Exception as e:
        print(f"[omameet] Error reading config: {e}", file=sys.stderr)
        return DEFAULT_CONFIG

def save_config(cfg: Dict[str, Any]):
    ensure_dirs()
    temp_path = CONFIG_PATH + ".tmp"
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    os.replace(temp_path, CONFIG_PATH)

def load_state() -> Dict[str, Any]:
    if not os.path.exists(STATE_PATH):
        return {"version": 1, "nextMeeting": None, "todayEvents": [], "tomorrowEvents": [], "lastSyncedAt": 0, "feedsCount": 0, "bookmarks": []}
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[omameet] Error reading state: {e}", file=sys.stderr)
        return {"version": 1, "nextMeeting": None, "todayEvents": [], "tomorrowEvents": [], "lastSyncedAt": 0, "feedsCount": 0, "bookmarks": []}

def save_state(state: Dict[str, Any]):
    ensure_dirs()
    temp_path = STATE_PATH + ".tmp"
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
    os.replace(temp_path, STATE_PATH)

# --- Media & System Integration ---

def pause_media_players():
    """Pauses any active MPRIS media player via DBus."""
    try:
        res = subprocess.run(
            ['dbus-send', '--session', '--dest=org.freedesktop.DBus', '--type=method_call', '--print-reply', '/org/freedesktop/DBus', 'org.freedesktop.DBus.ListNames'],
            capture_output=True, text=True, timeout=2
        )
        for line in res.stdout.splitlines():
            if 'org.mpris.MediaPlayer2.' in line and '\"' in line:
                service = line.split('\"')[1]
                subprocess.Popen(
                    ['dbus-send', '--session', f'--dest={service}', '--type=method_call', '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2.Player.Pause'],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
    except Exception:
        pass

def run_join_hooks(url: str, provider_id: str, summary: str):
    """Executes user-defined meeting-join hooks if present."""
    if os.path.isfile(HOOK_JOIN_SCRIPT) and os.access(HOOK_JOIN_SCRIPT, os.X_OK):
        try:
            subprocess.Popen([HOOK_JOIN_SCRIPT, url, provider_id, summary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

def launch_url(url: str, provider_id: str = "web", summary: str = "Meeting"):
    """Opens meeting URL according to preferred browser, native app, and triggers automations."""
    config = load_config()
    settings = config.get("settings", {})

    if settings.get("pauseMusicOnJoin", True):
        pause_media_players()

    run_join_hooks(url, provider_id, summary)

    # Check for native app preferences (e.g. Zoom or Teams native apps)
    if settings.get("openInNativeApp", False):
        if provider_id == "zoom" and shutil.which("zoom"):
            # Native Zoom app format: zoommtg://zoom.us/join?confno=...
            m = re.search(r"zoom\.us/j/([0-9]+)", url)
            if m:
                zoom_uri = f"zoommtg://zoom.us/join?confno={m.group(1)}"
                subprocess.Popen(["zoom", zoom_uri], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return

    preferred_browser = settings.get("preferredBrowser", "").strip()
    if preferred_browser and shutil.which(preferred_browser):
        subprocess.Popen([preferred_browser, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# --- Meeting Link Extraction ---
def extract_meeting_info(location: str, description: str, url_field: str) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """
    Scans URL, location, and description to find meeting video link and provider.
    Returns (video_url, provider_id, provider_name).
    """
    text_corpus = f"{url_field or ''}\n{location or ''}\n{description or ''}"
    if not text_corpus.strip():
        return None, None, None

    for prov_id, prov_name, pattern in VIDEO_PATTERNS:
        if prov_id == "generic_link":
            continue
        match = re.search(pattern, text_corpus, re.IGNORECASE)
        if match:
            url = match.group(0).rstrip(".,;)>]")
            return url, prov_id, prov_name

    if location and re.match(r"^https?://[^\s]+$", location.strip(), re.IGNORECASE):
        url = location.strip().rstrip(".,;)>]")
        return url, "web", "Meeting Link"

    if url_field and re.match(r"^https?://[^\s]+$", url_field.strip(), re.IGNORECASE):
        url = url_field.strip().rstrip(".,;)>]")
        return url, "web", "Meeting Link"

    return None, None, None

# --- RFC 5545 iCalendar Parser ---

def unfold_ical_lines(raw_text: str) -> List[str]:
    lines = []
    current_line = ""
    for raw_line in raw_text.splitlines():
        line = raw_line.rstrip("\r\n")
        if not line:
            continue
        if line.startswith(" ") or line.startswith("\t"):
            current_line += line[1:]
        else:
            if current_line:
                lines.append(current_line)
            current_line = line
    if current_line:
        lines.append(current_line)
    return lines

def unescape_ical_text(val: str) -> str:
    if not val:
        return ""
    val = val.replace("\\n", "\n").replace("\\N", "\n")
    val = val.replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")
    return val

def parse_ical_datetime(val: str, params: Dict[str, str], local_tz: datetime.tzinfo) -> Tuple[datetime.datetime, bool]:
    is_all_day = False
    val = val.strip()

    if params.get("VALUE") == "DATE" or (len(val) == 8 and val.isdigit()):
        is_all_day = True
        try:
            dt = datetime.datetime.strptime(val[:8], "%Y%m%d")
            return dt.replace(tzinfo=local_tz), True
        except ValueError:
            return datetime.datetime.now(local_tz), True

    tz_name = params.get("TZID")
    tz_obj = None
    if tz_name:
        try:
            tz_obj = ZoneInfo(tz_name)
        except Exception:
            cleaned_tz = tz_name.strip('"').replace(" ", "_")
            try:
                tz_obj = ZoneInfo(cleaned_tz)
            except Exception:
                tz_obj = local_tz

    if val.endswith("Z"):
        clean_val = val[:-1]
        try:
            dt = datetime.datetime.strptime(clean_val, "%Y%m%dT%H%M%S").replace(tzinfo=datetime.timezone.utc)
            return dt.astimezone(local_tz), False
        except ValueError:
            pass

    try:
        dt_naive = datetime.datetime.strptime(val, "%Y%m%dT%H%M%S")
        if tz_obj:
            dt_aware = dt_naive.replace(tzinfo=tz_obj)
            return dt_aware.astimezone(local_tz), False
        else:
            return dt_naive.replace(tzinfo=local_tz), False
    except ValueError:
        pass

    try:
        iso_dt = datetime.datetime.fromisoformat(val)
        if iso_dt.tzinfo is None:
            iso_dt = iso_dt.replace(tzinfo=local_tz)
        return iso_dt.astimezone(local_tz), False
    except Exception:
        return datetime.datetime.now(local_tz), False

def parse_rrule(rrule_str: str) -> Dict[str, Any]:
    parts = rrule_str.split(";")
    res = {}
    for part in parts:
        if "=" in part:
            k, v = part.split("=", 1)
            res[k.upper()] = v
    return res

def expand_recurring_events(event_dict: Dict[str, Any], window_start: datetime.datetime, window_end: datetime.datetime, local_tz: datetime.tzinfo) -> List[Dict[str, Any]]:
    rrule_str = event_dict.get("rrule")
    if not rrule_str:
        return [event_dict]

    start_dt = event_dict["start_dt"]
    end_dt = event_dict["end_dt"]
    duration = end_dt - start_dt

    rule = parse_rrule(rrule_str)
    freq = rule.get("FREQ")
    interval = int(rule.get("INTERVAL", "1"))
    count = int(rule.get("COUNT", "0")) if "COUNT" in rule else None
    until_str = rule.get("UNTIL")
    until_dt = None
    if until_str:
        until_dt, _ = parse_ical_datetime(until_str, {}, local_tz)

    exdates = event_dict.get("exdates", [])

    instances = []
    cur_start = start_dt
    cur_end = end_dt
    generated_count = 0

    byday = rule.get("BYDAY", "").split(",") if rule.get("BYDAY") else None
    weekday_map = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}

    max_iterations = 400
    iteration = 0

    while iteration < max_iterations:
        iteration += 1
        if until_dt and cur_start > until_dt:
            break
        if count is not None and generated_count >= count:
            break
        if cur_start > window_end:
            break

        if cur_end >= window_start and cur_start <= window_end:
            is_excluded = False
            for ex in exdates:
                if abs((ex - cur_start).total_seconds()) < 60:
                    is_excluded = True
                    break

            if not is_excluded:
                inst = dict(event_dict)
                inst["start_dt"] = cur_start
                inst["end_dt"] = cur_end
                inst["start_iso"] = cur_start.isoformat()
                inst["end_iso"] = cur_end.isoformat()
                inst["id"] = f"{event_dict['id']}_{cur_start.strftime('%Y%m%dT%H%M%S')}"
                instances.append(inst)

        generated_count += 1

        if freq == "DAILY":
            cur_start += datetime.timedelta(days=interval)
            cur_end = cur_start + duration
        elif freq == "WEEKLY":
            if byday:
                cur_weekday = cur_start.weekday()
                byday_indices = sorted([weekday_map[d] for d in byday if d in weekday_map])
                next_day_idx = None
                for idx in byday_indices:
                    if idx > cur_weekday:
                        next_day_idx = idx
                        break
                if next_day_idx is not None:
                    delta_days = next_day_idx - cur_weekday
                    cur_start += datetime.timedelta(days=delta_days)
                else:
                    first_idx = byday_indices[0] if byday_indices else 0
                    delta_days = (7 * interval) - cur_weekday + first_idx
                    cur_start += datetime.timedelta(days=delta_days)
                cur_end = cur_start + duration
            else:
                cur_start += datetime.timedelta(weeks=interval)
                cur_end = cur_start + duration
        elif freq == "MONTHLY":
            month = cur_start.month + interval
            year = cur_start.year + (month - 1) // 12
            month = ((month - 1) % 12) + 1
            day = min(cur_start.day, 28)
            cur_start = cur_start.replace(year=year, month=month, day=day)
            cur_end = cur_start + duration
        elif freq == "YEARLY":
            cur_start = cur_start.replace(year=cur_start.year + interval)
            cur_end = cur_start + duration
        else:
            break

    return instances

def parse_ics_content(ics_text: str, feed_meta: Dict[str, Any], window_start: datetime.datetime, window_end: datetime.datetime, local_tz: datetime.tzinfo) -> List[Dict[str, Any]]:
    lines = unfold_ical_lines(ics_text)
    events = []
    in_event = False
    cur_props: Dict[str, Any] = {}
    exdates = []
    attendee_partstats = []

    for line in lines:
        if line.startswith("BEGIN:VEVENT"):
            in_event = True
            cur_props = {"exdates": []}
            exdates = []
            attendee_partstats = []
            continue
        if line.startswith("END:VEVENT"):
            in_event = False
            if "DTSTART" in cur_props:
                dtstart_val, dtstart_params = cur_props["DTSTART"]
                start_dt, is_all_day = parse_ical_datetime(dtstart_val, dtstart_params, local_tz)

                if "DTEND" in cur_props:
                    dtend_val, dtend_params = cur_props["DTEND"]
                    end_dt, _ = parse_ical_datetime(dtend_val, dtend_params, local_tz)
                elif "DURATION" in cur_props:
                    end_dt = start_dt + datetime.timedelta(hours=1)
                else:
                    end_dt = start_dt + (datetime.timedelta(days=1) if is_all_day else datetime.timedelta(hours=1))

                summary = unescape_ical_text(cur_props.get("SUMMARY", ("Untitled Event", {}))[0])
                description = unescape_ical_text(cur_props.get("DESCRIPTION", ("", {}))[0])
                location = unescape_ical_text(cur_props.get("LOCATION", ("", {}))[0])
                url_field = cur_props.get("URL", ("", {}))[0]
                status = cur_props.get("STATUS", ("CONFIRMED", {}))[0].upper()

                # Check if marked as cancelled or declined
                is_declined = ("DECLINED" in attendee_partstats) or (status == "CANCELLED")
                is_tentative = ("TENTATIVE" in attendee_partstats) or (status == "TENTATIVE")
                is_pending = "NEEDS-ACTION" in attendee_partstats

                organizer = unescape_ical_text(cur_props.get("ORGANIZER", ("", {}))[0])
                uid = cur_props.get("UID", (f"evt_{len(events)}", {}))[0]
                rrule = cur_props.get("RRULE", ("", {}))[0]

                video_url, provider_id, provider_name = extract_meeting_info(location, description, url_field)

                event_dict = {
                    "id": uid,
                    "summary": summary,
                    "description": description,
                    "location": location,
                    "start_dt": start_dt,
                    "end_dt": end_dt,
                    "start_iso": start_dt.isoformat(),
                    "end_iso": end_dt.isoformat(),
                    "is_all_day": is_all_day,
                    "video_url": video_url,
                    "provider_id": provider_id or "calendar",
                    "provider_name": provider_name or "Calendar",
                    "has_link": video_url is not None,
                    "feed_id": feed_meta.get("id", "default"),
                    "feed_name": feed_meta.get("name", "Calendar"),
                    "feed_color": feed_meta.get("color", "#4285F4"),
                    "organizer": organizer,
                    "rrule": rrule,
                    "exdates": exdates,
                    "is_declined": is_declined,
                    "is_tentative": is_tentative,
                    "is_pending": is_pending,
                    "status_code": status
                }

                if rrule:
                    expanded = expand_recurring_events(event_dict, window_start, window_end, local_tz)
                    events.extend(expanded)
                else:
                    if end_dt >= window_start and start_dt <= window_end:
                        events.append(event_dict)
            continue

        if in_event and ":" in line:
            prop_header, prop_value = line.split(":", 1)
            params = {}
            if ";" in prop_header:
                parts = prop_header.split(";")
                prop_name = parts[0].upper()
                for p in parts[1:]:
                    if "=" in p:
                        pk, pv = p.split("=", 1)
                        params[pk.upper()] = pv.strip('"')
            else:
                prop_name = prop_header.upper()

            if prop_name == "EXDATE":
                ex_dt, _ = parse_ical_datetime(prop_value, params, local_tz)
                exdates.append(ex_dt)
            elif prop_name == "ATTENDEE":
                if "PARTSTAT" in params:
                    attendee_partstats.append(params["PARTSTAT"].upper())
                cur_props[prop_name] = (prop_value, params)
            else:
                cur_props[prop_name] = (prop_value, params)

    return events

# --- Feed Fetcher ---

def fetch_feed_content(feed: Dict[str, Any]) -> str:
    url = feed.get("url", "").strip()
    if not url:
        return ""

    if url.startswith("webcal://"):
        url = "https://" + url[9:]

    if url.startswith("file://") or url.startswith("/") or url.startswith("~"):
        file_path = os.path.expanduser(url.replace("file://", ""))
        if os.path.isdir(file_path):
            combined = ["BEGIN:VCALENDAR\nVERSION:2.0"]
            for fname in os.listdir(file_path):
                if fname.endswith(".ics"):
                    fpath = os.path.join(file_path, fname)
                    try:
                        with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                            content = f.read()
                            vevents = re.findall(r"BEGIN:VEVENT.*?END:VEVENT", content, re.DOTALL)
                            combined.extend(vevents)
                    except Exception:
                        pass
            combined.append("END:VCALENDAR")
            return "\n".join(combined)
        elif os.path.isfile(file_path):
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                return f.read()
        else:
            raise FileNotFoundError(f"Local file not found: {file_path}")

    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "omameet/1.0 (Omarchy Linux; +https://omarchy.org)",
            "Accept": "text/calendar, application/json, text/plain, */*"
        }
    )

    username = feed.get("username")
    password = feed.get("password")
    if username and password:
        import base64
        auth_header = "Basic " + base64.b64encode(f"{username}:{password}".encode()).decode()
        req.add_header("Authorization", auth_header)

    ctx = ssl.create_default_context()
    if feed.get("allowInsecureSSL", False):
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

    with urllib.request.urlopen(req, timeout=15, context=ctx) as response:
        return response.read().decode("utf-8", errors="ignore")

# --- Sync & State Builder ---

def run_sync() -> Dict[str, Any]:
    config = load_config()
    feeds = config.get("feeds", [])
    bookmarks = config.get("bookmarks", [])
    settings = config.get("settings", {})

    local_tz = get_local_tz()
    now = datetime.datetime.now(local_tz)

    start_of_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    window_start = start_of_today - datetime.timedelta(hours=6)
    window_end = start_of_today + datetime.timedelta(days=2, hours=12)

    all_events = []
    feed_errors = []

    for feed in feeds:
        if not feed.get("enabled", True):
            continue
        try:
            content = fetch_feed_content(feed)
            if content:
                feed_events = parse_ics_content(content, feed, window_start, window_end, local_tz)
                all_events.extend(feed_events)
        except Exception as e:
            feed_name = feed.get("name", feed.get("url", "Feed"))
            feed_errors.append(f"{feed_name}: {str(e)}")
            print(f"[omameet] Error syncing feed '{feed_name}': {e}", file=sys.stderr)

    hide_all_day = settings.get("hideAllDayEvents", False)
    hide_without_links = settings.get("hideWithoutLinks", False)
    hide_declined = settings.get("hideDeclined", True)
    hide_tentative = settings.get("hideTentative", False)
    hide_pending = settings.get("hidePending", False)

    filtered_events = []
    for evt in all_events:
        if hide_all_day and evt["is_all_day"]:
            continue
        if hide_without_links and not evt["has_link"]:
            continue
        if hide_declined and evt.get("is_declined", False):
            continue
        if hide_tentative and evt.get("is_tentative", False):
            continue
        if hide_pending and evt.get("is_pending", False):
            continue
        filtered_events.append(evt)

    filtered_events.sort(key=lambda x: (x["start_dt"], x["end_dt"]))

    unique_events = []
    seen = set()
    for evt in filtered_events:
        key = f"{evt['summary']}_{evt['start_iso']}"
        if key not in seen:
            seen.add(key)
            unique_events.append(evt)

    today_date = now.date()
    tomorrow_date = (now + datetime.timedelta(days=1)).date()

    today_events = []
    tomorrow_events = []
    next_meeting = None

    for evt in unique_events:
        evt_start = evt["start_dt"]
        evt_end = evt["end_dt"]
        evt_date = evt_start.date()

        if evt["is_all_day"]:
            evt_status = "all_day"
        elif evt_start <= now < evt_end:
            evt_status = "ongoing"
        elif now < evt_start:
            diff_min = (evt_start - now).total_seconds() / 60
            if diff_min <= settings.get("urgentThresholdMin", 5):
                evt_status = "soon"
            else:
                evt_status = "upcoming"
        else:
            evt_status = "past"

        minutes_to_start = int((evt_start - now).total_seconds() / 60)
        minutes_remaining = int((evt_end - now).total_seconds() / 60)
        duration_minutes = max(1, int((evt_end - evt_start).total_seconds() / 60))

        serializable_event = {
            "id": evt["id"],
            "summary": evt["summary"],
            "description": evt["description"],
            "location": evt["location"],
            "start": evt_start.strftime("%H:%M"),
            "end": evt_end.strftime("%H:%M"),
            "startDate": evt_start.strftime("%Y-%m-%d"),
            "startIso": evt["start_iso"],
            "endIso": evt["end_iso"],
            "isAllDay": evt["is_all_day"],
            "durationMin": duration_minutes,
            "minutesToStart": minutes_to_start,
            "minutesRemaining": minutes_remaining,
            "status": evt_status,
            "videoUrl": evt["video_url"],
            "providerId": evt["provider_id"],
            "providerName": evt["provider_name"],
            "hasLink": evt["has_link"],
            "feedName": evt["feed_name"],
            "feedColor": evt["feed_color"],
            "organizer": evt["organizer"]
        }

        if evt_date == today_date or (evt["is_all_day"] and evt_start.date() <= today_date <= evt_end.date()):
            today_events.append(serializable_event)
        elif evt_date == tomorrow_date:
            tomorrow_events.append(serializable_event)

        if not evt["is_all_day"]:
            if evt_status == "ongoing":
                if next_meeting is None or next_meeting["status"] != "ongoing":
                    next_meeting = serializable_event
            elif evt_status in ("soon", "upcoming") and next_meeting is None:
                next_meeting = serializable_event

    state = {
        "version": 1,
        "nextMeeting": next_meeting,
        "todayEvents": today_events,
        "tomorrowEvents": tomorrow_events,
        "bookmarks": bookmarks,
        "lastSyncedAt": int(now.timestamp() * 1000),
        "feedsCount": len([f for f in feeds if f.get("enabled", True)]),
        "errors": feed_errors
    }

    save_state(state)
    return state

# --- Actions & CLI ---

def action_join_next():
    state = load_state()
    next_m = state.get("nextMeeting")

    if next_m and next_m.get("videoUrl"):
        url = next_m["videoUrl"]
        prov = next_m.get("providerId", "web")
        summary = next_m.get("summary", "Meeting")
        print(f"[omameet] Joining meeting: {summary} ({url})")
        launch_url(url, prov, summary)
        return True

    for evt in state.get("todayEvents", []):
        if evt.get("status") in ("ongoing", "soon", "upcoming") and evt.get("videoUrl"):
            url = evt["videoUrl"]
            prov = evt.get("providerId", "web")
            summary = evt.get("summary", "Meeting")
            print(f"[omameet] Joining meeting: {summary} ({url})")
            launch_url(url, prov, summary)
            return True

    print("[omameet] No meeting with a video link found right now.")
    return False

def action_create_instant(provider: str = "google"):
    urls = {
        "google": "https://meet.google.com/new",
        "zoom": "https://zoom.us/start/videomeeting",
        "jitsi": f"https://meet.jit.si/omameet-{int(datetime.datetime.now().timestamp())}",
        "teams": "https://teams.microsoft.com/l/meetup-join/instant"
    }
    url = urls.get(provider.lower(), urls["google"])
    print(f"[omameet] Creating instant meeting ({provider}): {url}")
    launch_url(url, provider, f"Instant {provider.capitalize()} Meeting")

def action_notify_check():
    config = load_config()
    settings = config.get("settings", {})
    if not settings.get("enableNotifications", True):
        return

    state = run_sync()
    lead_min = settings.get("notificationLeadMin", 5)

    for evt in state.get("todayEvents", []):
        if evt.get("isAllDay"):
            continue
        to_start = evt.get("minutesToStart", 999)
        if 0 <= to_start <= lead_min and evt.get("status") in ("soon", "upcoming"):
            summary = evt.get("summary", "Meeting")
            start_time = evt.get("start", "")
            prov = evt.get("providerName", "Video")
            url = evt.get("videoUrl", "")

            msg = f"Starts at {start_time} (in {to_start} min) • {prov}"
            icon = "calendar"

            cmd = ["notify-send", "-a", "omameet", "-i", icon, f"📅 {summary}", msg]
            if url:
                cmd.extend(["--action=join=Join Meeting"])
            try:
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass
            break

def action_list():
    state = run_sync()
    today = state.get("todayEvents", [])
    tomorrow = state.get("tomorrowEvents", [])
    next_m = state.get("nextMeeting")
    bookmarks = state.get("bookmarks", [])

    print("\n\033[1;36m━━━ 📅 OMAMEET AGENDA ━━━\033[0m\n")

    if next_m:
        status_icon = "🔴 LIVE" if next_m.get("status") == "ongoing" else f"⏳ in {next_m.get('minutesToStart')}m"
        print(f"\033[1;32m👉 Next Meeting:\033[0m {next_m.get('summary')} ({next_m.get('start')} - {next_m.get('end')}) [{status_icon}]")
        if next_m.get("videoUrl"):
            print(f"   \033[34mLink:\033[0m {next_m.get('videoUrl')} ({next_m.get('providerName')})")
        print()

    print(f"\033[1m📅 Today ({len(today)} events):\033[0m")
    if not today:
        print("  \033[90m(No events scheduled for today)\033[0m")
    for e in today:
        link_badge = f"\033[34m[{e.get('providerName')}]\033[0m" if e.get("hasLink") else ""
        status_tag = f"\033[33m({e.get('status')})\033[0m" if e.get("status") in ("ongoing", "soon") else ""
        time_str = "All Day" if e.get("isAllDay") else f"{e.get('start')} - {e.get('end')}"
        print(f"  • \033[1m{time_str}\033[0m: {e.get('summary')} {link_badge} {status_tag}")

    print(f"\n\033[1m📅 Tomorrow ({len(tomorrow)} events):\033[0m")
    if not tomorrow:
        print("  \033[90m(No events scheduled for tomorrow)\033[0m")
    for e in tomorrow:
        link_badge = f"\033[34m[{e.get('providerName')}]\033[0m" if e.get("hasLink") else ""
        time_str = "All Day" if e.get("isAllDay") else f"{e.get('start')} - {e.get('end')}"
        print(f"  • \033[1m{time_str}\033[0m: {e.get('summary')} {link_badge}")

    if bookmarks:
        print(f"\n\033[1m🔖 Bookmarks & Quick Rooms ({len(bookmarks)}):\033[0m")
        for b in bookmarks:
            print(f"  • \033[1m{b.get('name')}\033[0m: {b.get('url')}")
    print()

def main():
    if len(sys.argv) < 2:
        action_list()
        return

    cmd = sys.argv[1].lower().lstrip("-")

    if cmd in ("sync", "refresh", "s"):
        state = run_sync()
        print(json.dumps(state, indent=2, ensure_ascii=False))

    elif cmd in ("join", "j", "join-next"):
        action_join_next()

    elif cmd in ("launch", "open"):
        if len(sys.argv) > 2:
            url = sys.argv[2]
            launch_url(url)
        else:
            action_join_next()

    elif cmd in ("next", "n"):
        state = run_sync()
        if "--json" in sys.argv:
            print(json.dumps(state.get("nextMeeting"), indent=2, ensure_ascii=False))
        else:
            nm = state.get("nextMeeting")
            if nm:
                print(f"{nm.get('summary')} ({nm.get('start')} - {nm.get('end')}) - {nm.get('providerName')}")
            else:
                print("No upcoming meetings")

    elif cmd in ("list", "ls", "agenda"):
        if "--json" in sys.argv:
            state = run_sync()
            print(json.dumps(state, indent=2, ensure_ascii=False))
        else:
            action_list()

    elif cmd in ("create", "instant"):
        provider = sys.argv[2] if len(sys.argv) > 2 else "google"
        action_create_instant(provider)

    elif cmd in ("notify-check", "notify"):
        action_notify_check()

    elif cmd in ("add-feed", "add"):
        if len(sys.argv) < 4:
            print("Usage: omameet add-feed <name> <url> [hex_color]", file=sys.stderr)
            sys.exit(1)
        name = sys.argv[2]
        url = sys.argv[3]
        color = sys.argv[4] if len(sys.argv) > 4 else "#4285F4"
        cfg = load_config()
        feed_id = f"feed_{int(datetime.datetime.now().timestamp())}"
        cfg["feeds"].append({
            "id": feed_id,
            "name": name,
            "url": url,
            "color": color,
            "enabled": True
        })
        save_config(cfg)
        print(f"[omameet] Calendar '{name}' added successfully! Syncing...")
        run_sync()

    elif cmd in ("remove-feed", "rm"):
        if len(sys.argv) < 3:
            print("Usage: omameet remove-feed <id_or_name>", file=sys.stderr)
            sys.exit(1)
        target = sys.argv[2]
        cfg = load_config()
        cfg["feeds"] = [f for f in cfg["feeds"] if f.get("id") != target and f.get("name") != target]
        save_config(cfg)
        print(f"[omameet] Calendar '{target}' removed.")
        run_sync()

    elif cmd in ("list-feeds", "feeds"):
        cfg = load_config()
        feeds = cfg.get("feeds", [])
        if "--json" in sys.argv:
            print(json.dumps(feeds, indent=2, ensure_ascii=False))
        else:
            print(f"\n\033[1mConfigured Calendars ({len(feeds)}):\033[0m")
            for f in feeds:
                status = "✓ Active" if f.get("enabled", True) else "✗ Disabled"
                print(f"  • [{f.get('id')}] \033[1m{f.get('name')}\033[0m: {f.get('url')} ({status})")
            print()

    elif cmd in ("add-bookmark", "bookmark"):
        if len(sys.argv) < 4:
            print("Usage: omameet add-bookmark <name> <url>", file=sys.stderr)
            sys.exit(1)
        name = sys.argv[2]
        url = sys.argv[3]
        cfg = load_config()
        if "bookmarks" not in cfg:
            cfg["bookmarks"] = []
        bm_id = f"bm_{int(datetime.datetime.now().timestamp())}"
        cfg["bookmarks"].append({"id": bm_id, "name": name, "url": url})
        save_config(cfg)
        print(f"[omameet] Bookmark '{name}' added!")
        run_sync()

    elif cmd in ("remove-bookmark", "rm-bm"):
        if len(sys.argv) < 3:
            print("Usage: omameet remove-bookmark <id_or_name>", file=sys.stderr)
            sys.exit(1)
        target = sys.argv[2]
        cfg = load_config()
        cfg["bookmarks"] = [b for b in cfg.get("bookmarks", []) if b.get("id") != target and b.get("name") != target]
        save_config(cfg)
        print(f"[omameet] Bookmark '{target}' removed.")
        run_sync()

    elif cmd in ("list-bookmarks", "bookmarks"):
        cfg = load_config()
        bms = cfg.get("bookmarks", [])
        if "--json" in sys.argv:
            print(json.dumps(bms, indent=2, ensure_ascii=False))
        else:
            print(f"\n\033[1mSaved Bookmarks ({len(bms)}):\033[0m")
            for b in bms:
                print(f"  • [{b.get('id')}] \033[1m{b.get('name')}\033[0m: {b.get('url')}")
            print()

    elif cmd in ("help", "h"):
        print("""
omameet - Universal MeetingBar for Omarchy Quattro

Usage:
  omameet [command]

Commands:
  sync, refresh              Sync all calendar feeds and update state
  join, join-next            Immediately join the current or next meeting in default browser
  launch <url>               Open a meeting URL with media pause and automation hooks
  next [--json]              Display next meeting information
  list, agenda [--json]      List today's and tomorrow's agenda and bookmarks
  create [google|zoom|jitsi] Open instant meeting room
  add-feed <name> <url>      Add a new calendar feed (iCal, webcal:// or local path)
  remove-feed <id>           Remove a configured calendar
  list-feeds [--json]        List all configured calendars
  add-bookmark <name> <url>  Bookmark a recurring room or video link
  remove-bookmark <id>       Remove a bookmarked room
  list-bookmarks [--json]    List all saved bookmarks
  notify-check               Check upcoming meetings and trigger desktop reminder
""")

    else:
        print(f"[omameet] Unknown command: {cmd}. Run 'omameet help' for usage.", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
