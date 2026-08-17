import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Panel.qml - Native MeetingBar-style menu dropdown for omameet
Panel {
  id: root
  moduleName: "dorneles.omameet"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var meetingState: null
  property string syncScriptPath: ""
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.popups.text
  readonly property color activeColor: Color.accent
  readonly property string fontFamily: Style.font.family

  readonly property var nextMeeting: meetingState ? meetingState.nextMeeting : null
  readonly property var todayEvents: meetingState ? (meetingState.todayEvents || []) : []
  readonly property var tomorrowEvents: meetingState ? (meetingState.tomorrowEvents || []) : []
  readonly property var bookmarksList: meetingState ? (meetingState.bookmarks || []) : []

  property bool inSettingsView: false
  property var feedsList: []

  property string newFeedName: ""
  property string newFeedUrl: ""
  property string newFeedColor: "#3B82F6"

  property string newBmName: ""
  property string newBmUrl: ""

  // Settings tracked locally for reactive instant UI response
  property string formatState: hostWidget ? (hostWidget.currentFormat || "title_countdown") : "title_countdown"
  property int maxTitleLengthState: hostWidget ? (hostWidget.currentMaxTitleLength || 35) : 35
  property bool marqueeEnabledState: hostWidget ? hostWidget.currentMarqueeEnabled : false
  property bool notificationsEnabledState: hostWidget ? hostWidget.currentEnableNotifications : true
  property bool pauseMusicState: true
  property bool muteMicState: false
  property bool hideDeclinedState: true
  property string instantMeetingProviderState: "google"
  property string currentSectionState: "left"

  readonly property string liveBarSection: {
    var b = root.bar || (hostWidget ? hostWidget.bar : null)
    if (b && b.layoutConfig) {
      var secList = ["left", "center", "right"]
      for (var s = 0; s < secList.length; s++) {
        var arr = b.layoutConfig[secList[s]] || []
        for (var i = 0; i < arr.length; i++) {
          var item = arr[i]
          var eid = item ? (typeof item === "string" ? item : item.id) : ""
          if (eid === "dorneles.omameet" || eid === "omameet") {
            return secList[s]
          }
        }
      }
    }
    if (hostWidget && hostWidget.parent && hostWidget.parent.region) {
      return hostWidget.parent.region
    }
    return currentSectionState || "left"
  }

  readonly property var instantProviderMeta: {
    switch (root.instantMeetingProviderState) {
      case "zoom":
        return { name: "Zoom", icon: "󰍡", color: "#2D8CFF" }
      case "jitsi":
        return { name: "Jitsi", icon: "󰍫", color: "#17A2B8" }
      case "teams":
        return { name: "Teams", icon: "󰊻", color: "#6264A7" }
      case "google":
      default:
        return { name: "Meet", icon: "󰄚", color: "#00AC47" }
    }
  }

  onHostWidgetChanged: {
    if (hostWidget) {
      formatState = hostWidget.currentFormat || "title_countdown"
      maxTitleLengthState = hostWidget.currentMaxTitleLength || 35
      marqueeEnabledState = hostWidget.currentMarqueeEnabled
      notificationsEnabledState = hostWidget.currentEnableNotifications
    }
  }

  readonly property string todayHeader: {
    var d = new Date()
    var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "Today (" + days[d.getDay()] + ", " + d.getDate() + " " + months[d.getMonth()] + "):"
  }

  readonly property string tomorrowHeader: {
    var d = new Date()
    d.setDate(d.getDate() + 1)
    var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "Tomorrow (" + days[d.getDay()] + ", " + d.getDate() + " " + months[d.getMonth()] + "):"
  }

  function open() {
    inSettingsView = false
    if (hostWidget) {
      formatState = hostWidget.currentFormat || "title_countdown"
      maxTitleLengthState = hostWidget.currentMaxTitleLength || 35
      marqueeEnabledState = hostWidget.currentMarqueeEnabled
      notificationsEnabledState = hostWidget.currentEnableNotifications
    }
    loadConfigData()
    controller.show()
  }

  function close() {
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function refresh() {
    if (hostWidget && typeof hostWidget.refresh === "function") {
      hostWidget.refresh()
    } else if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "sync"])
    }
  }

  function setDisplayFormat(fmt) {
    root.formatState = fmt
    updateWidgetSetting("format", fmt)
  }

  function joinMeeting(url) {
    if (url) {
      if (syncScriptPath !== "") {
        Quickshell.execDetached(["python3", syncScriptPath, "launch", url])
      } else {
        Quickshell.execDetached(["xdg-open", url])
      }
      close()
    }
  }

  function copyMeetingLink(url) {
    if (url && syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "copy-link", url])
    }
  }

  function joinNextMeeting() {
    if (nextMeeting && nextMeeting.videoUrl) {
      joinMeeting(nextMeeting.videoUrl)
    } else if (hostWidget && typeof hostWidget.joinNext === "function") {
      hostWidget.joinNext()
      close()
    }
  }

  function createInstantMeeting(provider) {
    var prov = provider || root.instantMeetingProviderState || "google"
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "create", prov])
      close()
    }
  }

  function setInstantMeetingProvider(prov) {
    root.instantMeetingProviderState = prov
    updateWidgetSetting("defaultInstantMeetingProvider", prov)
  }

  function setBarSection(sec) {
    root.currentSectionState = sec
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "set-section", sec])
    }
  }

  function loadConfigData() {
    Quickshell.execDetached(["python3", "-c", "import json, os; print(open(os.path.expanduser('~/.local/state/omarchy/omameet/config.json')).read())"], function(output) {
      try {
        var parsed = JSON.parse(output)
        root.feedsList = parsed.feeds || []
        if (parsed.settings) {
          root.pauseMusicState = parsed.settings.pauseMusicOnJoin !== false
          root.muteMicState = parsed.settings.muteMicOnJoin === true
          root.hideDeclinedState = parsed.settings.hideDeclined !== false
          if (parsed.settings.format) {
            root.formatState = parsed.settings.format
          }
          if (parsed.settings.defaultInstantMeetingProvider) {
            root.instantMeetingProviderState = parsed.settings.defaultInstantMeetingProvider
          }
          if (parsed.settings.maxTitleLength !== undefined) {
            root.maxTitleLengthState = Number(parsed.settings.maxTitleLength) || 35
          }
        }
      } catch (e) {}
    })

    Quickshell.execDetached(["python3", "-c", "import json, os; p = os.path.expanduser('~/.config/omarchy/shell.json'); d = json.load(open(p)) if os.path.exists(p) else {}; b = d.get('bar', {}); l = b.get('layout', b); res = [s for s in ('left','center','right') if any((isinstance(x, dict) and x.get('id') in ('dorneles.omameet','omameet')) or x in ('dorneles.omameet','omameet') for x in l.get(s, []))]; print(res[0] if res else 'left')"], function(secOut) {
      var s = (secOut || "").trim().toLowerCase()
      if (s === "left" || s === "center" || s === "right") {
        root.currentSectionState = s
      }
    })
  }

  function addFeed() {
    if (newFeedName.trim() === "" || newFeedUrl.trim() === "") return
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "add-feed", newFeedName.trim(), newFeedUrl.trim(), newFeedColor], function() {
        newFeedName = ""
        newFeedUrl = ""
        loadConfigData()
        refresh()
      })
    }
  }

  function removeFeed(feedId) {
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "remove-feed", feedId], function() {
        loadConfigData()
        refresh()
      })
    }
  }

  function addBookmark() {
    if (newBmName.trim() === "" || newBmUrl.trim() === "") return
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "add-bookmark", newBmName.trim(), newBmUrl.trim()], function() {
        newBmName = ""
        newBmUrl = ""
        loadConfigData()
        refresh()
      })
    }
  }

  function removeBookmark(bmId) {
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "remove-bookmark", bmId], function() {
        loadConfigData()
        refresh()
      })
    }
  }

  function changeMaxTitleLength(delta) {
    var target = Math.max(5, Math.min(80, root.maxTitleLengthState + delta))
    root.maxTitleLengthState = target
    updateWidgetSetting("maxTitleLength", target)
  }

  function resetMaxTitleLength() {
    root.maxTitleLengthState = 35
    updateWidgetSetting("maxTitleLength", 35)
  }

  function toggleMarquee() {
    marqueeEnabledState = !marqueeEnabledState
    updateWidgetSetting("marqueeEnabled", marqueeEnabledState)
  }

  function toggleNotifications() {
    notificationsEnabledState = !notificationsEnabledState
    updateWidgetSetting("enableNotifications", notificationsEnabledState)
  }

  function togglePauseMusic() {
    pauseMusicState = !pauseMusicState
    updateWidgetSetting("pauseMusicOnJoin", pauseMusicState)
  }

  function toggleMuteMic() {
    muteMicState = !muteMicState
    updateWidgetSetting("muteMicOnJoin", muteMicState)
  }

  function toggleHideDeclined() {
    hideDeclinedState = !hideDeclinedState
    updateWidgetSetting("hideDeclined", hideDeclinedState)
    refresh()
  }

  function updateWidgetSetting(key, value) {
    if (hostWidget && typeof hostWidget.updateSetting === "function") {
      hostWidget.updateSetting(key, value)
    }
    var valStr = typeof value === "number" ? String(value) : (typeof value === "string" ? ("\"" + value + "\"") : (value ? "True" : "False"))
    Quickshell.execDetached(["python3", "-c", "import json, os; p = os.path.expanduser('~/.local/state/omarchy/omameet/config.json'); d = json.load(open(p)); d.setdefault('settings', {})['" + key + "'] = " + valStr + "; json.dump(d, open(p, 'w'), indent=2)"])
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: root.inSettingsView ? Style.space(385) : Style.space(305)
    contentHeight: root.inSettingsView ? (settingsColumn.implicitHeight + Style.space(24)) : (contentColumn.implicitHeight + Style.space(24))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      // =========================================================
      // --- SETTINGS VIEW (ZERO SCROLLING - ALL IN ONE VIEW) ---
      // =========================================================
      Column {
        id: settingsColumn
        visible: root.inSettingsView
        width: parent.width - Style.space(16)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.space(10)
        spacing: Style.space(8)

        // Header with Back button
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Button {
            implicitWidth: Style.space(26)
            implicitHeight: Style.space(26)
            iconText: "←"
            tooltipText: "Back to Agenda"
            onClicked: root.inSettingsView = false
          }

          Text {
            text: "Preferences & Calendars"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Item { Layout.fillWidth: true }

          Button {
            implicitWidth: Style.space(26)
            implicitHeight: Style.space(26)
            iconText: "✕"
            tooltipText: "Close"
            onClicked: root.close()
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }

        // Section: Display & Length
        Item {
          width: parent.width
          height: Style.space(16)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "STATUS BAR & POSITION"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption * 0.85
            font.bold: true
          }
        }

        // 1. Max Title Length Stepper - Always shows 3 fixed buttons
        Item {
          width: parent.width
          height: Style.space(28)

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: "Max Title Length (" + root.maxTitleLengthState + " chars)"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            // Decrease Button [-]
            Button {
              implicitWidth: Style.space(24)
              implicitHeight: Style.space(24)
              text: "-"
              enabled: root.maxTitleLengthState > 5
              opacity: enabled ? 1.0 : 0.35
              tooltipText: enabled ? "Decrease length" : ""
              onClicked: if (enabled) root.changeMaxTitleLength(-5)
            }

            // Increase Button [+]
            Button {
              implicitWidth: Style.space(24)
              implicitHeight: Style.space(24)
              text: "+"
              enabled: root.maxTitleLengthState < 80
              opacity: enabled ? 1.0 : 0.35
              tooltipText: enabled ? "Increase length" : ""
              onClicked: if (enabled) root.changeMaxTitleLength(5)
            }

            // Reset Button [↺] - ALWAYS VISIBLE, disabled when already 35
            Button {
              implicitWidth: Style.space(24)
              implicitHeight: Style.space(24)
              iconText: "↺"
              enabled: root.maxTitleLengthState !== 35
              opacity: enabled ? 1.0 : 0.35
              tooltipText: enabled ? "Reset to default (35 chars)" : ""
              onClicked: if (enabled) root.resetMaxTitleLength()
            }
          }
        }

        // 2. Display Format Selector (2-row segmented layout, zero overlap)
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "Display Format"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * 0.95
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Title + Time"
              selected: root.formatState === "title_countdown"
              accent: Color.accent
              tooltipText: "Event title with countdown (Default)"
              onClicked: root.setDisplayFormat("title_countdown")
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Icon + Title"
              iconText: "󰄚"
              selected: root.formatState === "icon_title_countdown"
              accent: Color.accent
              tooltipText: "Provider icon with title and countdown"
              onClicked: root.setDisplayFormat("icon_title_countdown")
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Time only"
              selected: root.formatState === "countdown_only"
              accent: Color.accent
              tooltipText: "Countdown time to meeting only"
              onClicked: root.setDisplayFormat("countdown_only")
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Icon + Clock"
              iconText: "󰄚"
              selected: root.formatState === "icon_time"
              accent: Color.accent
              tooltipText: "Provider icon with start time"
              onClicked: root.setDisplayFormat("icon_time")
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Title only"
              selected: root.formatState === "title_only"
              accent: Color.accent
              tooltipText: "Event title only"
              onClicked: root.setDisplayFormat("title_only")
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Icon only"
              iconText: "󰄚"
              selected: root.formatState === "icon_only"
              accent: Color.accent
              tooltipText: "Provider icon only"
              onClicked: root.setDisplayFormat("icon_only")
            }
          }
        }

        // 3. Bar Position Selector (Left, Center, Right)
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "Bar Position"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * 0.95
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Left (Default)"
              iconText: "󰁍"
              selected: root.liveBarSection === "left"
              accent: Color.accent
              tooltipText: "Position plugin on the left side of the top bar"
              onClicked: root.setBarSection("left")
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Center"
              iconText: "󰁌"
              selected: root.liveBarSection === "center"
              accent: Color.accent
              tooltipText: "Position plugin in the center of the top bar"
              onClicked: root.setBarSection("center")
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Right"
              iconText: "󰁔"
              selected: root.liveBarSection === "right"
              accent: Color.accent
              tooltipText: "Position plugin on the right side of the top bar"
              onClicked: root.setBarSection("right")
            }
          }
        }

        // 3. Instant Meeting Service Selector (2-row layout, zero overlap)
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "Instant Meeting App"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * 0.95
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Meet"
              iconText: "󰄚"
              selected: root.instantMeetingProviderState === "google"
              accent: "#00AC47"
              tooltipText: "Google Meet"
              onClicked: root.setInstantMeetingProvider("google")
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Zoom"
              iconText: "󰍡"
              selected: root.instantMeetingProviderState === "zoom"
              accent: "#2D8CFF"
              tooltipText: "Zoom"
              onClicked: root.setInstantMeetingProvider("zoom")
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Jitsi"
              iconText: "󰍫"
              selected: root.instantMeetingProviderState === "jitsi"
              accent: "#17A2B8"
              tooltipText: "Jitsi Meet"
              onClicked: root.setInstantMeetingProvider("jitsi")
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(24)
              text: "Teams"
              iconText: "󰊻"
              selected: root.instantMeetingProviderState === "teams"
              accent: "#6264A7"
              tooltipText: "Microsoft Teams"
              onClicked: root.setInstantMeetingProvider("teams")
            }
          }
        }

        // 4. Marquee Switch (Borderless)
        Item {
          width: parent.width
          height: Style.space(28)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMarquee()
          }

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: "Marquee text animation"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            ToggleSwitch {
              checked: root.marqueeEnabledState
              interactive: false
            }
          }
        }

        // 5. Pause Music Switch (Borderless)
        Item {
          width: parent.width
          height: Style.space(28)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.togglePauseMusic()
          }

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: "Pause music on call join"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            ToggleSwitch {
              checked: root.pauseMusicState
              interactive: false
            }
          }
        }

        // 6. Mute Microphone Switch (Borderless)
        Item {
          width: parent.width
          height: Style.space(28)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMuteMic()
          }

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: "Mute microphone on call join"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            ToggleSwitch {
              checked: root.muteMicState
              interactive: false
            }
          }
        }

        // 7. Desktop Reminders Switch (Borderless)
        Item {
          width: parent.width
          height: Style.space(28)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleNotifications()
          }

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: "Desktop meeting reminders"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            ToggleSwitch {
              checked: root.notificationsEnabledState
              interactive: false
            }
          }
        }

        // 8. Hide Declined Switch (Borderless)
        Item {
          width: parent.width
          height: Style.space(28)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleHideDeclined()
          }

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: "Hide declined calendar events"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            ToggleSwitch {
              checked: root.hideDeclinedState
              interactive: false
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }

        // Section: Connected Feeds
        Item {
          width: parent.width
          height: Style.space(16)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "CONNECTED CALENDARS (" + root.feedsList.length + ")"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption * 0.85
            font.bold: true
          }
        }

        Repeater {
          model: root.feedsList

          Item {
            required property var modelData
            width: parent.width
            height: Style.space(26)

            RowLayout {
              anchors.fill: parent
              spacing: Style.space(6)

              Rectangle {
                width: Style.space(8)
                height: Style.space(8)
                radius: Style.space(4)
                color: modelData.color || "#3B82F6"
              }

              Text {
                Layout.fillWidth: true
                text: modelData.name || "Calendar"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                elide: Text.ElideRight
              }

              Button {
                implicitWidth: Style.space(22)
                implicitHeight: Style.space(22)
                iconText: "🗑"
                foreground: Color.urgent
                accent: Color.urgent
                onClicked: root.removeFeed(modelData.id)
              }
            }
          }
        }

        // Inline Add Feed Row
        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            Layout.preferredWidth: Style.space(90)
            placeholderText: "Name (Work)"
            text: root.newFeedName
            onTextChanged: root.newFeedName = text
          }

          TextField {
            Layout.fillWidth: true
            placeholderText: "Feed URL (.ics / webcal://)"
            text: root.newFeedUrl
            onTextChanged: root.newFeedUrl = text
          }

          Button {
            implicitWidth: Style.space(30)
            implicitHeight: Style.space(30)
            iconText: "󰐕"
            tooltipText: "Add calendar feed"
            accent: Color.accent
            foreground: "#FFFFFF"
            onClicked: root.addFeed()
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }

        // Section: Quick Bookmarks
        Item {
          width: parent.width
          height: Style.space(16)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "BOOKMARKS (" + root.bookmarksList.length + ")"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption * 0.85
            font.bold: true
          }
        }

        Repeater {
          model: root.bookmarksList

          Item {
            required property var modelData
            width: parent.width
            height: Style.space(26)

            RowLayout {
              anchors.fill: parent
              spacing: Style.space(6)

              Text {
                text: "󰌹"
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                Layout.fillWidth: true
                text: modelData.name || "Room"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                elide: Text.ElideRight
              }

              Button {
                implicitWidth: Style.space(22)
                implicitHeight: Style.space(22)
                iconText: "🗑"
                foreground: Color.urgent
                accent: Color.urgent
                onClicked: root.removeBookmark(modelData.id)
              }
            }
          }
        }

        // Inline Add Bookmark Row
        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            Layout.preferredWidth: Style.space(90)
            placeholderText: "Room Name"
            text: root.newBmName
            onTextChanged: root.newBmName = text
          }

          TextField {
            Layout.fillWidth: true
            placeholderText: "Meeting Room URL"
            text: root.newBmUrl
            onTextChanged: root.newBmUrl = text
          }

          Button {
            implicitWidth: Style.space(30)
            implicitHeight: Style.space(30)
            iconText: "󰐕"
            tooltipText: "Add bookmark"
            accent: Color.accent
            foreground: "#FFFFFF"
            onClicked: root.addBookmark()
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }

        // Centered Footer in Settings Window with GitHub Link
        Item {
          width: parent.width
          height: Style.space(38)

          ColumnLayout {
            anchors.centerIn: parent
            spacing: Style.space(2)

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: "omameet"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
              font.bold: true
            }

            Rectangle {
              Layout.alignment: Qt.AlignHCenter
              height: Style.space(16)
              width: gitRow.implicitWidth + Style.space(8)
              radius: Style.space(3)
              color: gitMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

              MouseArea {
                id: gitMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Quickshell.execDetached(["xdg-open", "https://github.com/jvlianodorneles/omameet"])
                }
              }

              RowLayout {
                id: gitRow
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  text: ""
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  text: "github.com/jvlianodorneles/omameet"
                  color: gitMouse.containsMouse ? Color.accent : Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        // Bottom breathing space
        Item {
          width: parent.width
          height: Style.space(4)
        }
      }

      // =========================================================================
      // --- OPTIMIZED AGENDA VIEW (CHRONOLOGICAL + HERO FOCUS + COMPACT FOOTER) ---
      // =========================================================================
      Column {
        id: contentColumn
        visible: !root.inSettingsView
        width: parent.width - Style.space(16)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.space(8)
        spacing: Style.space(4)

        // 1. LIVE / IMMINENT MEETING HERO FOCUS CARD
        Rectangle {
          id: heroCard
          visible: root.nextMeeting && (root.nextMeeting.status === "ongoing" || root.nextMeeting.status === "soon")
          width: parent.width
          height: Style.space(54)
          radius: Style.space(6)
          color: root.nextMeeting && root.nextMeeting.status === "ongoing" ? Qt.rgba(0.9, 0.2, 0.2, 0.16) : Qt.rgba(0.2, 0.5, 0.9, 0.16)
          border.color: root.nextMeeting && root.nextMeeting.status === "ongoing" ? Color.urgent : Color.accent
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.topMargin: Style.space(6)
            anchors.bottomMargin: Style.space(6)
            spacing: Style.space(8)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              RowLayout {
                spacing: Style.space(4)
                Text {
                  text: root.nextMeeting && root.nextMeeting.status === "ongoing" ? "🔴 HAPPENING NOW" : "⏳ UPCOMING SOON"
                  color: root.nextMeeting && root.nextMeeting.status === "ongoing" ? Color.urgent : Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption * 0.85
                  font.bold: true
                }
              }

              Text {
                Layout.fillWidth: true
                text: root.nextMeeting ? (root.nextMeeting.summary + " (" + root.nextMeeting.start + " - " + root.nextMeeting.end + ")") : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                font.bold: true
                elide: Text.ElideRight
              }
            }

            // Quick Copy Link Button
            Button {
              visible: root.nextMeeting && root.nextMeeting.videoUrl
              implicitWidth: Style.space(26)
              implicitHeight: Style.space(26)
              iconText: "󰆏"
              tooltipText: "Copy meeting link"
              onClicked: if (root.nextMeeting) root.copyMeetingLink(root.nextMeeting.videoUrl)
            }

            // Join Now Button
            Button {
              implicitWidth: Style.space(68)
              implicitHeight: Style.space(28)
              text: "Join"
              iconText: "󰐊"
              accent: root.nextMeeting && root.nextMeeting.status === "ongoing" ? Color.urgent : Color.accent
              foreground: "#FFFFFF"
              tooltipText: "Join meeting now"
              onClicked: root.joinNextMeeting()
            }
          }
        }

        Item {
          visible: heroCard.visible
          width: parent.width
          height: Style.space(4)
        }

        // 2. TIMELINE: Today Section Header
        Item {
          width: parent.width
          height: Style.space(20)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: root.todayHeader
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        // Empty state if no events today
        Item {
          visible: root.todayEvents.length === 0
          width: parent.width
          height: Style.space(24)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "No events scheduled for today"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * 0.95
            font.italic: true
          }
        }

        // Today Events List
        Repeater {
          model: root.todayEvents

          Rectangle {
            id: eventRow
            required property var modelData
            width: parent.width
            height: Style.space(26)
            radius: Style.space(4)

            readonly property bool isSelectedMeeting: root.nextMeeting && root.nextMeeting.id === modelData.id
            readonly property bool isPast: modelData.status === "past"
            property bool isHovered: mouseRow.containsMouse

            color: isSelectedMeeting ? Color.accent : (isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

            MouseArea {
              id: mouseRow
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: modelData.hasLink ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                if (modelData.hasLink) {
                  root.joinMeeting(modelData.videoUrl)
                }
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(6)

              // Calendar Color Indicator Pill
              Rectangle {
                width: Style.space(3)
                height: Style.space(12)
                radius: Style.space(2)
                color: modelData.feedColor || "#3B82F6"
                opacity: eventRow.isPast ? 0.35 : 0.9
                Layout.alignment: Qt.AlignVCenter
              }

              // Start Time
              Text {
                text: modelData.isAllDay ? "All Day" : modelData.start
                color: eventRow.isSelectedMeeting ? "#FFFFFF" : (eventRow.isPast ? Color.muted : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                font.bold: eventRow.isSelectedMeeting
                opacity: eventRow.isPast ? 0.5 : 1.0
                Layout.preferredWidth: Style.space(42)
              }

              // Event Title
              Text {
                Layout.fillWidth: true
                text: modelData.summary
                color: eventRow.isSelectedMeeting ? "#FFFFFF" : (eventRow.isPast ? Color.muted : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                font.bold: eventRow.isSelectedMeeting
                elide: Text.ElideRight
                opacity: eventRow.isPast ? 0.5 : 1.0
              }

              // Copy Link Quick Button (on hover or selected)
              Button {
                visible: modelData.hasLink && (eventRow.isHovered || eventRow.isSelectedMeeting)
                implicitWidth: Style.space(20)
                implicitHeight: Style.space(20)
                iconText: "󰆏"
                tooltipText: "Copy meeting link"
                accent: eventRow.isSelectedMeeting ? "#FFFFFF" : Color.accent
                foreground: eventRow.isSelectedMeeting ? "#FFFFFF" : root.foreground
                onClicked: root.copyMeetingLink(modelData.videoUrl)
              }

              // Provider Icon
              Text {
                visible: modelData.hasLink
                text: {
                  var meta = Model.getProviderMeta(modelData.providerId)
                  return meta.icon
                }
                color: eventRow.isSelectedMeeting ? "#FFFFFF" : Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                Layout.alignment: Qt.AlignVCenter
              }
            }
          }
        }

        // 3. TIMELINE: Tomorrow Section (Chronological continuity)
        Item {
          visible: root.tomorrowEvents.length > 0
          width: parent.width
          height: Style.space(4)
        }
        Rectangle {
          visible: root.tomorrowEvents.length > 0
          width: parent.width
          height: 1
          color: Color.popups.border
        }
        Item {
          visible: root.tomorrowEvents.length > 0
          width: parent.width
          height: Style.space(20)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: root.tomorrowHeader
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Repeater {
          model: root.tomorrowEvents

          Rectangle {
            required property var modelData
            width: parent.width
            height: Style.space(24)
            radius: Style.space(4)
            property bool isHovered: mouseTomorrow.containsMouse
            color: isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

            MouseArea {
              id: mouseTomorrow
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: modelData.hasLink ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                if (modelData.hasLink) {
                  root.joinMeeting(modelData.videoUrl)
                }
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(6)

              Rectangle {
                width: Style.space(3)
                height: Style.space(12)
                radius: Style.space(2)
                color: modelData.feedColor || "#3B82F6"
                opacity: 0.7
                Layout.alignment: Qt.AlignVCenter
              }

              Text {
                text: modelData.isAllDay ? "All Day" : modelData.start
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                Layout.preferredWidth: Style.space(42)
              }

              Text {
                Layout.fillWidth: true
                text: modelData.summary
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                elide: Text.ElideRight
              }

              Button {
                visible: modelData.hasLink && mouseTomorrow.containsMouse
                implicitWidth: Style.space(18)
                implicitHeight: Style.space(18)
                iconText: "󰆏"
                tooltipText: "Copy meeting link"
                onClicked: root.copyMeetingLink(modelData.videoUrl)
              }

              Text {
                visible: modelData.hasLink
                text: {
                  var meta = Model.getProviderMeta(modelData.providerId)
                  return meta.icon
                }
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // 4. BOOKMARKS SECTION
        Item {
          visible: root.bookmarksList.length > 0
          width: parent.width
          height: Style.space(4)
        }
        Rectangle {
          visible: root.bookmarksList.length > 0
          width: parent.width
          height: 1
          color: Color.popups.border
        }
        Item {
          visible: root.bookmarksList.length > 0
          width: parent.width
          height: Style.space(20)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: "Bookmarks"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Repeater {
          model: root.bookmarksList

          Rectangle {
            required property var modelData
            width: parent.width
            height: Style.space(24)
            radius: Style.space(4)
            property bool isHovered: mouseBm.containsMouse
            color: isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

            MouseArea {
              id: mouseBm
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.joinMeeting(modelData.url)
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(6)

              Text {
                text: "󰌹"
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                Layout.fillWidth: true
                text: modelData.name || "Room"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                elide: Text.ElideRight
              }

              Button {
                visible: mouseBm.containsMouse
                implicitWidth: Style.space(18)
                implicitHeight: Style.space(18)
                iconText: "󰆏"
                tooltipText: "Copy room link"
                onClicked: root.copyMeetingLink(modelData.url)
              }

              Text {
                text: "󰐊"
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption * 0.9
              }
            }
          }
        }

        // 5. QUICK ACTION: Create Instant Meeting (Dynamic Provider)
        Item { width: parent.width; height: Style.space(4) }
        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }
        Item { width: parent.width; height: Style.space(2) }

        Rectangle {
          width: parent.width
          height: Style.space(26)
          radius: Style.space(4)
          property bool isHovered: mouseCreate.containsMouse
          color: isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

          MouseArea {
            id: mouseCreate
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.createInstantMeeting(root.instantMeetingProviderState)
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)

            Text {
              text: "󰐕"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              Layout.fillWidth: true
              text: "Create instant meeting (" + root.instantProviderMeta.name + ")"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.92
            }

            Text {
              text: root.instantProviderMeta.icon
              color: root.instantProviderMeta.color
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // 6. COMPACT FOOTER TOOLBAR
        Item { width: parent.width; height: Style.space(2) }
        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }
        Item { width: parent.width; height: Style.space(2) }

        Item {
          width: parent.width
          height: Style.space(28)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(6)

            Item { Layout.fillWidth: true }

            Button {
              implicitHeight: Style.space(24)
              text: "Sync"
              iconText: ""
              tooltipText: "Sync all calendar feeds now"
              onClicked: root.refresh()
            }

            Button {
              implicitHeight: Style.space(24)
              text: "Preferences..."
              iconText: "⚙"
              tooltipText: "Preferences & Calendars"
              onClicked: {
                root.inSettingsView = true
                root.loadConfigData()
              }
            }
          }
        }

        // Bottom spacing
        Item {
          width: parent.width
          height: Style.space(6)
        }
      }
    }
  }
}
