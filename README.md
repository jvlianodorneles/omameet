# omameet 📅

> **Universal MeetingBar for Omarchy Quattro** — Track upcoming meetings on your status bar with countdown, get desktop reminders, and join video calls with a single click.

Inspired by [MeetingBar for macOS](https://github.com/leits/MeetingBar), **omameet** brings the same smooth, responsive, and lightweight meeting experience to **Omarchy Linux**.

---

## ✨ Features

- **1-Click Video Call Access (+50 Providers)**:
  - Automatically detects meeting links from: **Google Meet**, **Zoom**, **Microsoft Teams**, **Cisco Webex**, **Jitsi Meet**, **Discord**, **Slack Huddles**, **Skype**, **Whereby**, etc.
  - **Middle-click** the bar widget to instantly join the next upcoming or ongoing meeting in your default browser.
- **Universal Calendar Support**:
  - **Google Calendar**: Direct sync via *Secret address in iCal format* (`.ics`), public URLs, or local exports.
  - **Apple iCloud Calendar**: Native support for `webcal://` URLs, shared calendar links, and CalDAV endpoints.
  - **Microsoft Outlook / Office 365**: Direct sync via published ICS links from Outlook Web.
  - **Nextcloud / Fastmail / CalDAV**: HTTP Basic Auth & App Passwords for standard RFC 4791 CalDAV servers.
  - **Local Files (.ics / directories)**: Live monitoring of local `.ics` files and directories managed by `vdirsyncer` or `khal`.
- **Smart Status Bar Widget**:
  - Shows next meeting with provider icon, start time, and relative countdown (`in 15m`).
  - **Live Meeting Indicator**: Highlights ongoing meetings (`🔴 Sprint Sync (20m left)`).
  - **Configurable Character Limit (`maxTitleLength`)**: Set custom maximum title length on the bar.
  - **Marquee Text Animation (`marqueeEnabled`)**: Smooth horizontal scrolling animation for long titles that exceed the character limit.
- **Modern Interactive Agenda Popup**:
  - **Hero Card**: Highlighted upcoming/active meeting with large countdown, prominent "Join Meeting" CTA, and "Copy Link" button.
  - **Today's Timeline**: Chronological events with status badges (`LIVE`, `SOON`, `All Day`), provider tags, and expandable details (description, notes, organizer, attendees, location).
  - **Tomorrow's Preview**: Compact preview of tomorrow's schedule.
  - **Calendar Manager**: Add, toggle, and remove multiple calendar feeds with custom color tags.
  - **Instant Meeting Launcher**: 1-click room creation for Google Meet, Jitsi Meet, or Zoom.
- **Desktop Notifications**: Native desktop reminders before meetings start with action to join directly.
- **CLI & Hyprland Shortcuts**: Full terminal access and global keybinding integration via the `omameet` CLI.

---

## 🚀 Installation & Setup

The plugin is located in `~/.config/omarchy/plugins/dorneles.omameet/`.

### 1. Add Widget to Status Bar
To place `omameet` in your status bar:

```bash
omarchy bar move dorneles.omameet --section right
```

*(Or add `{"id": "dorneles.omameet"}` to `bar.layout.right` in `~/.config/omarchy/shell.json`)*

### 2. Install Global CLI Command
Run the setup script to link `omameet` to `~/.local/bin/omameet`:

```bash
~/.config/omarchy/plugins/dorneles.omameet/install.sh
```

---

## 📅 How to Connect Your Calendars

### 🔹 Google Calendar
1. Open [Google Calendar](https://calendar.google.com/) in your browser.
2. In the left sidebar, click the **three dots (...)** next to your calendar > **Settings and sharing**.
3. Scroll down to the **Integrate calendar** section.
4. Copy the link in the **Secret address in iCal format** field.
5. Open the `omameet` popup (click the bar widget) > **Calendars** tab > paste the URL and click **Add and Sync Calendar**.

### 🔹 Microsoft Outlook / Office 365
1. Open [Outlook Web](https://outlook.office.com/) > click the **Settings** gear icon.
2. Navigate to **Calendar** > **Shared calendars**.
3. Under **Publish a calendar**, select your calendar, choose permissions, and click **Publish**.
4. Copy the **ICS** link and add it to `omameet`.

### 🔹 Apple iCloud Calendar
1. In the macOS Calendar app or at [iCloud.com](https://www.icloud.com/calendar), click the share icon next to your calendar.
2. Enable **Public Calendar** (or copy the `webcal://...` link).
3. Paste the URL into `omameet`.

---

## ⌨️ CLI Commands (`omameet`)

```bash
# Sync all calendar feeds immediately
omameet sync

# Join current or next upcoming meeting with 1 command
omameet join

# Copy meeting link to clipboard
omameet copy-link

# Mute microphone
omameet mute-mic

# Display next meeting details
omameet next

# List today's and tomorrow's agenda in terminal
omameet list

# Add a calendar feed via terminal
omameet add-feed "Work" "https://calendar.google.com/.../basic.ics" "#10B981"

# Create an instant meeting
omameet create google   # or: omameet create jitsi / zoom / teams

# Run background notification check
omameet notify-check
```

---

## 💡 Recommended Hyprland Keybindings

Add these lines to `~/.config/hypr/bindings.lua`:

```lua
-- Join next meeting with Super + Alt + M
o.bind("$mainMod ALT, M", function() hl.exec("omameet join") end)

-- Copy next meeting link with Super + Alt + C
o.bind("$mainMod ALT, C", function() hl.exec("omameet copy-link") end)

-- Toggle agenda popup with Super + Alt + A
o.bind("$mainMod ALT, A", function() hl.exec("omarchy-shell shell toggle dorneles.omameet") end)
```

---

## 🛠️ Configuration Options

In `~/.config/omarchy/shell.json` (or via Omarchy settings panel):

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `format` | `enum` | `"title_countdown"` | Text display format (`title_countdown`, `icon_title_countdown`, `countdown_only`, `icon_time`, `title_only`, `icon_only`) |
| `maxTitleLength` | `int` | `35` | Maximum title character limit on the status bar |
| `marqueeEnabled` | `bool` | `false` | Enable smooth marquee scrolling when title exceeds character limit |
| `marqueeSpeed` | `int` | `6` | Marquee animation cycle duration in seconds |
| `showIcon` | `bool` | `true` | Show platform / calendar icon |
| `showCountdown` | `bool` | `true` | Show countdown timer (`in 15m`, `20m left`) |
| `pauseMusicOnJoin` | `bool` | `true` | Automatically pause Spotify/MPRIS media players when joining a call |
| `muteMicOnJoin` | `bool` | `false` | Automatically mute default microphone capture device when joining a call |
| `hideDeclined` | `bool` | `true` | Filter out declined or cancelled calendar events |
| `refreshIntervalMin` | `int` | `15` | Automatic background calendar sync interval in minutes |
| `urgentThresholdMin` | `int` | `5` | Minutes before meeting start for urgent highlight on the bar |
| `enableNotifications` | `bool` | `true` | Send desktop notifications before meetings start |
| `notificationLeadMin` | `int` | `5` | Minutes before meeting start to send desktop reminder |
| `hideAllDayEvents` | `bool` | `false` | Hide all-day calendar events |
| `hideWithoutLinks` | `bool` | `false` | Only show events that contain a video meeting link |

---

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.

