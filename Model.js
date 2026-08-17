// Model.js - Data helpers, formatters, and provider metadata for omameet plugin
.pragma library

var FORMAT_RING = [
  "title_countdown",
  "icon_title_countdown",
  "countdown_only",
  "icon_time",
  "title_only",
  "icon_only"
];

/**
 * Returns metadata (icon, brand color, display name) for a given provider ID.
 */
function getProviderMeta(providerId) {
  var id = String(providerId || "").toLowerCase();
  switch (id) {
    case "google_meet":
      return {
        id: "google_meet",
        name: "Google Meet",
        icon: "󰄚",
        color: "#00AC47",
        accentColor: "#34A853",
        isVideo: true
      };
    case "zoom":
      return {
        id: "zoom",
        name: "Zoom",
        icon: "󰍡",
        color: "#2D8CFF",
        accentColor: "#2D8CFF",
        isVideo: true
      };
    case "teams":
      return {
        id: "teams",
        name: "Microsoft Teams",
        icon: "󰊻",
        color: "#6264A7",
        accentColor: "#5B5FC7",
        isVideo: true
      };
    case "webex":
      return {
        id: "webex",
        name: "Cisco Webex",
        icon: "󰍫",
        color: "#00BCEB",
        accentColor: "#005073",
        isVideo: true
      };
    case "jitsi":
      return {
        id: "jitsi",
        name: "Jitsi Meet",
        icon: "󰍫",
        color: "#17A2B8",
        accentColor: "#17A2B8",
        isVideo: true
      };
    case "discord":
      return {
        id: "discord",
        name: "Discord",
        icon: "󰙯",
        color: "#5865F2",
        accentColor: "#5865F2",
        isVideo: true
      };
    case "slack":
      return {
        id: "slack",
        name: "Slack",
        icon: "󰒱",
        color: "#ECB22E",
        accentColor: "#E01E5A",
        isVideo: true
      };
    case "skype":
      return {
        id: "skype",
        name: "Skype",
        icon: "󰒲",
        color: "#00AFF0",
        accentColor: "#00AFF0",
        isVideo: true
      };
    case "whereby":
      return {
        id: "whereby",
        name: "Whereby",
        icon: "󰍫",
        color: "#FFAE9E",
        accentColor: "#FFAE9E",
        isVideo: true
      };
    case "web":
    case "generic_link":
      return {
        id: "web",
        name: "Meeting Link",
        icon: "󰖟",
        color: "#3B82F6",
        accentColor: "#3B82F6",
        isVideo: true
      };
    default:
      return {
        id: "calendar",
        name: "Calendar",
        icon: "󰃭",
        color: "#8B5CF6",
        accentColor: "#8B5CF6",
        isVideo: false
      };
  }
}

/**
 * Truncates text with ellipsis so that result.length <= maxLen.
 */
function truncate(text, maxLen) {
  if (!text) return "";
  var str = String(text).trim();
  var limit = parseInt(maxLen, 10);
  if (isNaN(limit) || limit <= 0) return str;
  if (str.length <= limit) return str;
  if (limit <= 1) return "…";
  return str.substring(0, limit - 1) + "…";
}

/**
 * Formats relative countdown string (e.g. "in 15 min", "20 min left", "now").
 */
function formatCountdown(minutesToStart, minutesRemaining, status) {
  if (status === "ongoing") {
    if (minutesRemaining > 0) {
      if (minutesRemaining < 60) return minutesRemaining + " min left";
      var remHours = Math.floor(minutesRemaining / 60);
      var remMins = minutesRemaining % 60;
      return remHours + "h" + (remMins > 0 ? (" " + remMins + " min") : "") + " left";
    }
    return "in progress";
  }

  if (minutesToStart === undefined || minutesToStart === null) return "";
  if (minutesToStart <= 0) return "now";
  if (minutesToStart === 1) return "in 1 min";
  if (minutesToStart < 60) return "in " + minutesToStart + " min";

  var hours = Math.floor(minutesToStart / 60);
  var mins = minutesToStart % 60;
  if (mins === 0) return "in " + hours + "h";
  return "in " + hours + "h " + mins + " min";
}

/**
 * Formats the bar widget text based on format and settings.
 * Strictly guarantees that non-marquee text will NEVER exceed maxTitleLength characters.
 */
function formatBarContent(meeting, format, maxTitleLength, marqueeEnabled, showIcon, showCountdown) {
  var maxLen = parseInt(maxTitleLength, 10);
  if (isNaN(maxLen) || maxLen <= 0) maxLen = 25;

  if (!meeting) {
    var emptyText = "No meetings";
    return {
      icon: showIcon ? "󰃭" : "",
      title: emptyText,
      rawTitle: emptyText,
      time: "",
      countdown: "",
      fullText: showIcon ? "󰃭 " + emptyText : emptyText,
      isLive: false,
      isSoon: false,
      hasLink: false,
      needsMarquee: false
    };
  }

  var meta = getProviderMeta(meeting.providerId);
  var icon = showIcon ? meta.icon : "";
  var rawTitle = (meeting.summary || "Meeting").trim();
  var timeStr = meeting.isAllDay ? "All Day" : (meeting.start || "");
  var countdownStr = showCountdown ? formatCountdown(meeting.minutesToStart, meeting.minutesRemaining, meeting.status) : "";
  var isLive = meeting.status === "ongoing";
  var isSoon = meeting.status === "soon";
  var hasLink = !!meeting.videoUrl;

  var livePrefix = isLive ? "🔴 " : (icon ? icon + " " : "");
  var timeSuffix = "";
  if (isLive) {
    timeSuffix = countdownStr ? (" (" + countdownStr + ")") : "";
  } else {
    timeSuffix = countdownStr ? (" " + countdownStr) : (timeStr ? (" " + timeStr) : "");
  }

  var rawFullText = "";
  switch (format) {
    case "icon_only":
      rawFullText = icon !== "" ? icon : "󰃭";
      break;

    case "title_only":
      rawFullText = rawTitle;
      break;

    case "countdown_only":
    case "icon_countdown":
      rawFullText = (icon ? icon + " " : "") + (isLive ? "🔴 " : "") + (countdownStr ? countdownStr : timeStr);
      break;

    case "icon_time":
      rawFullText = (icon ? icon + " " : "") + (isLive ? "🔴 " : "") + timeStr + " " + rawTitle;
      break;

    case "icon_title_countdown":
      rawFullText = livePrefix + rawTitle + timeSuffix;
      break;

    case "title_countdown":
    default:
      var pfx = isLive ? "🔴 " : "";
      rawFullText = pfx + rawTitle + timeSuffix;
      break;
  }

  rawFullText = rawFullText.trim();
  var needsMarquee = marqueeEnabled && (rawFullText.length > maxLen || rawTitle.length > maxLen);

  var fullText = "";
  if (needsMarquee) {
    // When marquee is enabled, keep full text for smooth scrolling
    fullText = rawFullText;
  } else {
    // Strictly cap text at maxLen characters
    if (rawFullText.length <= maxLen) {
      fullText = rawFullText;
    } else {
      var pfxStr = format === "title_countdown" ? (isLive ? "🔴 " : "") : livePrefix;
      var availTitle = maxLen - pfxStr.length - timeSuffix.length;

      if (availTitle >= 4) {
        var truncTitle = truncate(rawTitle, availTitle);
        fullText = pfxStr + truncTitle + timeSuffix;
      } else {
        fullText = truncate(rawFullText, maxLen);
      }
    }
  }

  return {
    icon: icon,
    title: rawTitle,
    rawTitle: rawTitle,
    rawFullText: rawFullText,
    time: timeStr,
    countdown: countdownStr,
    fullText: fullText.trim(),
    isLive: isLive,
    isSoon: isSoon,
    hasLink: hasLink,
    needsMarquee: needsMarquee,
    meta: meta
  };
}

/**
 * Returns the next format in the format ring.
 */
function nextFormat(current) {
  var idx = FORMAT_RING.indexOf(current);
  if (idx === -1) return FORMAT_RING[0];
  return FORMAT_RING[(idx + 1) % FORMAT_RING.length];
}

/**
 * Formats duration in minutes to human readable (e.g. 45 min, 1h, 1h 30 min).
 */
function formatDuration(minutes) {
  if (!minutes || minutes <= 0) return "";
  if (minutes < 60) return minutes + " min";
  var h = Math.floor(minutes / 60);
  var m = minutes % 60;
  if (m === 0) return h + "h";
  return h + "h " + m + " min";
}
