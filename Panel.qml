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

  property bool inSettingsView: false
  property var feedsList: []

  property string newFeedName: ""
  property string newFeedUrl: ""
  property string newFeedColor: "#3B82F6"

  // Settings tracked locally for reactive instant toggle response
  property bool marqueeEnabledState: hostWidget ? hostWidget.currentMarqueeEnabled : false
  property bool notificationsEnabledState: hostWidget ? hostWidget.currentEnableNotifications : true

  onHostWidgetChanged: {
    if (hostWidget) {
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
      marqueeEnabledState = hostWidget.currentMarqueeEnabled
      notificationsEnabledState = hostWidget.currentEnableNotifications
    }
    loadFeeds()
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
      Quickshell.execDetached(["xdg-open", url])
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

  function loadFeeds() {
    Quickshell.execDetached(["python3", "-c", "import json, os; print(open(os.path.expanduser('~/.local/state/omarchy/omameet/config.json')).read())"], function(output) {
      try {
        var parsed = JSON.parse(output)
        root.feedsList = parsed.feeds || []
      } catch (e) {}
    })
  }

  function addFeed() {
    if (newFeedName.trim() === "" || newFeedUrl.trim() === "") return
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "add-feed", newFeedName.trim(), newFeedUrl.trim(), newFeedColor], function() {
        newFeedName = ""
        newFeedUrl = ""
        loadFeeds()
        refresh()
      })
    }
  }

  function removeFeed(feedId) {
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "remove-feed", feedId], function() {
        loadFeeds()
        refresh()
      })
    }
  }

  function toggleMarquee() {
    marqueeEnabledState = !marqueeEnabledState
    updateWidgetSetting("marqueeEnabled", marqueeEnabledState)
  }

  function toggleNotifications() {
    notificationsEnabledState = !notificationsEnabledState
    updateWidgetSetting("enableNotifications", notificationsEnabledState)
  }

  function updateWidgetSetting(key, value) {
    if (hostWidget && typeof hostWidget.updateSetting === "function") {
      hostWidget.updateSetting(key, value)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: root.inSettingsView ? Style.space(350) : Style.space(290)
    contentHeight: root.inSettingsView ? Style.space(500) : (contentColumn.implicitHeight + Style.space(16))

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
        spacing: Style.space(8)

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

            // --- Section: Visual & Notification Preferences ---
            Text {
              text: "Preferences"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Toggle {
              Layout.fillWidth: true
              label: "Marquee Text Animation"
              description: "Scroll long titles on the status bar"
              checked: root.marqueeEnabledState
              onClicked: root.toggleMarquee()
            }

            Toggle {
              Layout.fillWidth: true
              label: "Desktop Notifications"
              description: "Alert before meeting starts"
              checked: root.notificationsEnabledState
              onClicked: root.toggleNotifications()
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
              implicitHeight: Style.space(32)
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
                implicitHeight: Style.space(38)
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

            // Bottom breathing space in settings view
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
        width: parent.width
        spacing: Style.space(2)

        // 1. Header: Today (Fri, 12 Feb):
        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
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
            anchors.leftMargin: Style.space(16)
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
                } else {
                  root.copyLink(modelData.summary)
                }
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(10)

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

        // 3. Tomorrow Section (if any events)
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
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
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
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(10)

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

        // 4. Separator
        Item { width: parent.width; height: Style.space(4) }
        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }
        Item { width: parent.width; height: Style.space(4) }

        // 5. Action Items
        // Action: Join next event meeting
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
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)

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

        // Action: Create meeting (Dropdown or Quick Google Meet / Jitsi)
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
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)

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

        // Action: Create Jitsi meeting
        Rectangle {
          width: parent.width
          height: Style.space(26)
          radius: Style.space(4)
          property bool isHovered: mouseJitsi.containsMouse
          color: isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

          MouseArea {
            id: mouseJitsi
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.createInstantMeeting("jitsi")
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: "Create instant room (Jitsi)"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 0.95
            }

            Text {
              text: "󰍫"
              color: "#17A2B8"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
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
              root.loadFeeds()
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)

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
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)

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

        // --- 8. Bottom Margin Padding ---
        Item {
          width: parent.width
          height: Style.space(8)
        }
      }
    }
  }
}
