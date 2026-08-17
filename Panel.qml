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
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

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
  property int maxTitleLengthState: hostWidget ? (hostWidget.currentMaxTitleLength || 25) : 25
  property bool marqueeEnabledState: hostWidget ? hostWidget.currentMarqueeEnabled : false
  property bool notificationsEnabledState: hostWidget ? hostWidget.currentEnableNotifications : true
  property bool pauseMusicState: true
  property bool hideDeclinedState: true

  onHostWidgetChanged: {
    if (hostWidget) {
      maxTitleLengthState = hostWidget.currentMaxTitleLength || 25
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
      maxTitleLengthState = hostWidget.currentMaxTitleLength || 25
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

  function joinNextMeeting() {
    if (nextMeeting && nextMeeting.videoUrl) {
      joinMeeting(nextMeeting.videoUrl)
    } else if (hostWidget && typeof hostWidget.joinNext === "function") {
      hostWidget.joinNext()
      close()
    }
  }

  function createInstantMeeting(provider) {
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "create", provider])
      close()
    }
  }

  function loadConfigData() {
    Quickshell.execDetached(["python3", "-c", "import json, os; print(open(os.path.expanduser('~/.local/state/omarchy/omameet/config.json')).read())"], function(output) {
      try {
        var parsed = JSON.parse(output)
        root.feedsList = parsed.feeds || []
        if (parsed.settings) {
          root.pauseMusicState = parsed.settings.pauseMusicOnJoin !== false
          root.hideDeclinedState = parsed.settings.hideDeclined !== false
          if (parsed.settings.maxTitleLength !== undefined) {
            root.maxTitleLengthState = parsed.settings.maxTitleLength
          }
        }
      } catch (e) {}
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
    root.maxTitleLengthState = 25
    updateWidgetSetting("maxTitleLength", 25)
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

  function toggleHideDeclined() {
    hideDeclinedState = !hideDeclinedState
    updateWidgetSetting("hideDeclined", hideDeclinedState)
    refresh()
  }

  function updateWidgetSetting(key, value) {
    if (hostWidget && typeof hostWidget.updateSetting === "function") {
      hostWidget.updateSetting(key, value)
    }
    var valStr = typeof value === "number" ? String(value) : (value ? "True" : "False")
    Quickshell.execDetached(["python3", "-c", "import json, os; p = os.path.expanduser('~/.local/state/omarchy/omameet/config.json'); d = json.load(open(p)); d.setdefault('settings', {})['" + key + "'] = " + valStr + "; json.dump(d, open(p, 'w'), indent=2)"])
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: root.inSettingsView ? Style.space(350) : Style.space(290)
    contentHeight: root.inSettingsView ? Style.space(520) : (contentColumn.implicitHeight + Style.space(24))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      // ==========================================
      // --- SETTINGS VIEW ---
      // ==========================================
      ColumnLayout {
        visible: root.inSettingsView
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(10)

        // Header with Back button
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Button {
            implicitWidth: Style.space(28)
            implicitHeight: Style.space(28)
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
            implicitWidth: Style.space(28)
            implicitHeight: Style.space(28)
            iconText: "✕"
            tooltipText: "Close"
            onClicked: root.close()
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        ScrollView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true

          ColumnLayout {
            width: parent.width
            spacing: Style.space(10)

            // --- Section: Bar Display Preferences ---
            Text {
              text: "Status Bar Display"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            // --- Character Limit (Length) Stepper Row (BORDERLESS) ---
            Item {
              Layout.fillWidth: true
              implicitHeight: Style.space(36)

              RowLayout {
                anchors.fill: parent
                spacing: Style.space(8)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    text: "Max Title Length"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    text: root.maxTitleLengthState + " characters"
                    color: Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Button {
                  implicitWidth: Style.space(26)
                  implicitHeight: Style.space(26)
                  text: "-"
                  tooltipText: "Decrease character limit"
                  onClicked: root.changeMaxTitleLength(-5)
                }

                Button {
                  implicitWidth: Style.space(26)
                  implicitHeight: Style.space(26)
                  text: "+"
                  tooltipText: "Increase character limit"
                  onClicked: root.changeMaxTitleLength(5)
                }

                Button {
                  visible: root.maxTitleLengthState !== 25
                  implicitWidth: Style.space(26)
                  implicitHeight: Style.space(26)
                  iconText: "↺"
                  tooltipText: "Reset to default (25 chars)"
                  onClicked: root.resetMaxTitleLength()
                }
              }
            }

            // --- BORDERLESS Switch Rows ---
            // 1. Marquee Text Animation Switch
            Item {
              Layout.fillWidth: true
              implicitHeight: Style.space(36)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleMarquee()
              }

              RowLayout {
                anchors.fill: parent
                spacing: Style.space(8)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    text: "Marquee Text Animation"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    text: "Scroll titles exceeding character limit"
                    color: Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                ToggleSwitch {
                  checked: root.marqueeEnabledState
                  interactive: false
                }
              }
            }

            // 2. Pause Music on Join Switch
            Item {
              Layout.fillWidth: true
              implicitHeight: Style.space(36)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.togglePauseMusic()
              }

              RowLayout {
                anchors.fill: parent
                spacing: Style.space(8)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    text: "Pause Music on Join"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    text: "Pause media players when joining call"
                    color: Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                ToggleSwitch {
                  checked: root.pauseMusicState
                  interactive: false
                }
              }
            }

            // 3. Desktop Meeting Reminders Switch
            Item {
              Layout.fillWidth: true
              implicitHeight: Style.space(36)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleNotifications()
              }

              RowLayout {
                anchors.fill: parent
                spacing: Style.space(8)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    text: "Desktop Reminders"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    text: "Send alert before meetings start"
                    color: Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                ToggleSwitch {
                  checked: root.notificationsEnabledState
                  interactive: false
                }
              }
            }

            // 4. Hide Declined Events Switch
            Item {
              Layout.fillWidth: true
              implicitHeight: Style.space(36)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleHideDeclined()
              }

              RowLayout {
                anchors.fill: parent
                spacing: Style.space(8)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    text: "Hide Declined Events"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    text: "Filter out declined or cancelled events"
                    color: Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                ToggleSwitch {
                  checked: root.hideDeclinedState
                  interactive: false
                }
              }
            }

            PanelSeparator { Layout.fillWidth: true }

            // --- Section: Bookmarks Manager ---
            Text {
              text: "Add Quick Bookmark / Room"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            TextField {
              Layout.fillWidth: true
              placeholderText: "Room Name (e.g. Daily Room)"
              text: root.newBmName
              onTextChanged: root.newBmName = text
            }

            TextField {
              Layout.fillWidth: true
              placeholderText: "https://meet.google.com/xyz or meet.jit.si/..."
              text: root.newBmUrl
              onTextChanged: root.newBmUrl = text
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(30)
              text: "Add Bookmark"
              iconText: "󰃃"
              accent: Color.accent
              foreground: "#FFFFFF"
              onClicked: root.addBookmark()
            }

            PanelSeparator { Layout.fillWidth: true }

            // --- Section: Add Calendar Feed ---
            Text {
              text: "Add Calendar Feed (.ics / webcal://)"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            TextField {
              Layout.fillWidth: true
              placeholderText: "Calendar Name (e.g. Work)"
              text: root.newFeedName
              onTextChanged: root.newFeedName = text
            }

            TextField {
              Layout.fillWidth: true
              placeholderText: "https://calendar.google.com/.../basic.ics"
              text: root.newFeedUrl
              onTextChanged: root.newFeedUrl = text
            }

            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(30)
              text: "Add Calendar Feed"
              iconText: "󰐕"
              accent: Color.accent
              foreground: "#FFFFFF"
              onClicked: root.addFeed()
            }

            PanelSeparator { Layout.fillWidth: true }

            // --- Section: Connected Feeds ---
            Text {
              text: "Connected Feeds (" + root.feedsList.length + ")"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Repeater {
              model: root.feedsList

              Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Style.space(36)
                color: Color.popups.surface
                radius: Style.space(4)
                border.color: Color.popups.border
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
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
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Button {
                    implicitWidth: Style.space(24)
                    implicitHeight: Style.space(24)
                    iconText: "🗑"
                    foreground: Color.urgent
                    accent: Color.urgent
                    onClicked: root.removeFeed(modelData.id)
                  }
                }
              }
            }

            Item {
              Layout.fillWidth: true
              implicitHeight: Style.space(12)
            }
          }
        }
      }

      // ==========================================
      // --- MEETINGBAR CLASSIC MENU LIST VIEW ---
      // ==========================================
      Column {
        id: contentColumn
        visible: !root.inSettingsView
        width: parent.width - Style.space(16)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.space(8)
        spacing: Style.space(2)

        // 1. Header: Today (Fri, 12 Feb):
        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
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
          height: Style.space(26)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            text: "No events scheduled"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * 0.95
            font.italic: true
          }
        }

        // 2. Events List (Today)
        Repeater {
          model: root.todayEvents

          Rectangle {
            id: eventRow
            required property var modelData
            width: parent.width
            height: Style.space(26)
            radius: Style.space(4)

            // Highlighting: Current/Next active meeting gets blue accent highlight
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
              spacing: Style.space(8)

              // Start Time
              Text {
                text: modelData.isAllDay ? "All Day" : modelData.start
                color: eventRow.isSelectedMeeting ? "#FFFFFF" : (eventRow.isPast ? Color.muted : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                font.bold: eventRow.isSelectedMeeting
                opacity: eventRow.isPast ? 0.5 : 1.0
                Layout.preferredWidth: Style.space(44)
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

              // Meeting Video Provider Icon
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

        // 3. Action Items (Join, Create)
        Item { width: parent.width; height: Style.space(4) }
        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }
        Item { width: parent.width; height: Style.space(4) }

        Rectangle {
          width: parent.width
          height: Style.space(26)
          radius: Style.space(4)
          property bool isHovered: mouseJoin.containsMouse
          color: isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

          MouseArea {
            id: mouseJoin
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.joinNextMeeting()
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: "Join next event meeting"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            Text {
              text: "󰐊"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

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
            onClicked: root.createInstantMeeting("google")
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: "Create instant meeting (Meet)"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            Text {
              text: "󰄚"
              color: "#00AC47"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // 4. Bookmarks Section (MeetingBar style)
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
            anchors.leftMargin: Style.space(6)
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

              Text {
                Layout.fillWidth: true
                text: modelData.name || "Room"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                elide: Text.ElideRight
              }

              Text {
                text: "󰌹"
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // 5. Tomorrow Section (if any)
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
            anchors.leftMargin: Style.space(6)
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
              spacing: Style.space(8)

              Text {
                text: modelData.isAllDay ? "All Day" : modelData.start
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                Layout.preferredWidth: Style.space(44)
              }

              Text {
                Layout.fillWidth: true
                text: modelData.summary
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 0.95
                elide: Text.ElideRight
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

        // 6. Separator
        Item { width: parent.width; height: Style.space(4) }
        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }
        Item { width: parent.width; height: Style.space(4) }

        // 7. Footer: Preferences & Sync
        Rectangle {
          width: parent.width
          height: Style.space(26)
          radius: Style.space(4)
          property bool isHovered: mousePrefs.containsMouse
          color: isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

          MouseArea {
            id: mousePrefs
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.inSettingsView = true
              root.loadConfigData()
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: "Preferences & Calendars..."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            Text {
              text: "⚙"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Action: Sync Calendars
        Rectangle {
          width: parent.width
          height: Style.space(26)
          radius: Style.space(4)
          property bool isHovered: mouseSync.containsMouse
          color: isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

          MouseArea {
            id: mouseSync
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.refresh()
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: "Sync Calendars"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            Text {
              text: ""
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // 8. Bottom Margin Padding
        Item {
          width: parent.width
          height: Style.space(8)
        }
      }
    }
  }
}
