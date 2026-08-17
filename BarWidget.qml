import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// BarWidget.qml - Status Bar Widget for omameet (Universal MeetingBar)
BarWidget {
  id: root
  moduleName: "dorneles.omameet"

  // Settings dynamically read from root.settings (persisted in shell.json)
  readonly property string currentFormat: setting("format", "title_countdown")
  readonly property int currentMaxTitleLength: setting("maxTitleLength", 25)
  readonly property int currentFontSize: setting("fontSize", 0)
  readonly property bool currentMarqueeEnabled: setting("marqueeEnabled", false)
  readonly property int currentMarqueeSpeed: setting("marqueeSpeed", 6)
  readonly property bool currentShowIcon: setting("showIcon", true)
  readonly property bool currentShowCountdown: setting("showCountdown", true)
  readonly property int currentRefreshIntervalMin: setting("refreshIntervalMin", 15)
  readonly property int currentUrgentThresholdMin: setting("urgentThresholdMin", 5)
  readonly property bool currentEnableNotifications: setting("enableNotifications", true)

  // Live state parsed from state.json
  property var meetingState: null
  readonly property var nextMeeting: meetingState ? meetingState.nextMeeting : null
  readonly property var todayEvents: meetingState ? (meetingState.todayEvents || []) : []
  readonly property int feedsCount: meetingState ? (meetingState.feedsCount || 0) : 0

  // Computed visual content
  readonly property var barData: Model.formatBarContent(
    nextMeeting,
    currentFormat,
    currentMaxTitleLength,
    currentMarqueeEnabled,
    currentShowIcon,
    currentShowCountdown
  )

  readonly property string syncScriptPath: Qt.resolvedUrl("scripts/omameet-sync.py").toString().replace(/^file:\/\//, "")

  // Watch state.json for instant live updates
  property FileView stateFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/omameet/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.meetingState = JSON.parse(text())
      } catch (e) {
        // Keep previous state on parse error
      }
    }
  }

  function refresh() {
    if (!syncProcess.running) {
      syncProcess.command = ["python3", syncScriptPath, "sync"]
      syncProcess.running = true
    }
  }

  function joinNext() {
    if (nextMeeting && nextMeeting.videoUrl) {
      if (syncScriptPath !== "") {
        Quickshell.execDetached(["python3", syncScriptPath, "launch", nextMeeting.videoUrl])
      } else {
        Quickshell.execDetached(["xdg-open", nextMeeting.videoUrl])
      }
    } else {
      if (!joinProcess.running) {
        joinProcess.command = ["python3", syncScriptPath, "join"]
        joinProcess.running = true
      }
    }
  }

  function cycleFormat() {
    var next = Model.nextFormat(currentFormat)
    updateSetting("format", next)
  }

  function updateSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
  }

  // --- Popup Panel Coordination ---
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("meetingState" in target) target.meetingState = root.meetingState
    if ("syncScriptPath" in target) target.syncScriptPath = root.syncScriptPath
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onMeetingStateChanged: injectPanel()

  Component.onCompleted: {
    stateFile.reload()
    refresh()
  }

  // Background processes
  Process {
    id: syncProcess
    running: false
    onExited: function(exitCode, exitStatus) {
      stateFile.reload()
    }
  }

  Process {
    id: joinProcess
    running: false
  }

  // Periodic calendar sync timer
  Timer {
    interval: Math.max(1, root.currentRefreshIntervalMin) * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  // Minute clock to re-evaluate relative countdowns & notification alerts
  SystemClock {
    id: minuteClock
    precision: SystemClock.Minutes
    onDateChanged: {
      // Periodic notification check
      if (root.currentEnableNotifications) {
        Quickshell.execDetached(["python3", syncScriptPath, "notify-check"])
      }
    }
  }

  // Popup panel loader
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // IPC Handler for Hyprland keybindings & CLI control
  IpcHandler {
    target: "dorneles.omameet"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
    function joinNext(): void { root.joinNext() }
    function cycleFormat(): void { root.cycleFormat() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: root.currentFontSize > 0 ? root.currentFontSize : (root.bar ? root.bar.fontSize : Style.font.body)
    text: (root.vertical || root.barData.needsMarquee) ? "" : root.barData.fullText
    labelVisible: !root.vertical && !root.barData.needsMarquee
    hasVisualContent: true
    horizontalMargin: 8.5
    verticalPadding: 6
    tooltipText: "omameet • " + (root.nextMeeting ? (root.nextMeeting.summary + " (" + root.nextMeeting.start + " - " + root.nextMeeting.end + ")") : "No upcoming meetings") +
                 "\n──────────────────────────" +
                 "\n• Left-click: Open Agenda" +
                 "\n• Middle-click: Join Meeting (1-Click Join)" +
                 "\n• Scroll wheel: Cycle format (" + root.currentFormat + ")"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        root.joinNext()
      } else if (b === Qt.RightButton) {
        root.togglePanel()
      } else {
        root.togglePanel()
      }
    }

    onWheelMoved: function(delta) {
      root.cycleFormat()
    }

    // --- Custom Marquee Container (Horizontal Bar) ---
    Item {
      id: marqueeContainer
      visible: !root.vertical && root.barData.needsMarquee
      anchors.centerIn: parent
      width: Math.min(Style.space(220), Math.max(Style.space(80), root.currentMaxTitleLength * 8.5))
      height: parent.height
      clip: true

      Row {
        id: marqueeRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          text: root.barData.icon
          visible: root.barData.icon !== ""
          color: root.barData.isLive ? Color.urgent : (root.barData.isSoon ? Color.warning : button.foreground)
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
        }

        Item {
          id: marqueeClip
          width: marqueeContainer.width - (root.barData.icon !== "" ? Style.space(20) : 0)
          height: marqueeText.implicitHeight
          clip: true

          Text {
            id: marqueeText
            text: root.barData.rawTitle + (root.barData.countdown ? (" " + root.barData.countdown) : "")
            color: root.barData.isLive ? Color.urgent : (root.barData.isSoon ? Color.warning : button.foreground)
            font.family: button.fontFamily
            font.pixelSize: button.fontSize
            renderType: Text.NativeRendering

            readonly property real overflowDist: Math.max(0, marqueeText.implicitWidth - marqueeClip.width + Style.space(16))

            SequentialAnimation {
              id: scrollAnim
              running: marqueeContainer.visible && marqueeText.overflowDist > 0
              loops: Animation.Infinite

              PauseAnimation { duration: 1500 }
              NumberAnimation {
                target: marqueeText
                property: "x"
                from: 0
                to: -marqueeText.overflowDist
                duration: Math.max(2000, root.currentMarqueeSpeed * 1000)
                easing.type: Easing.Linear
              }
              PauseAnimation { duration: 1500 }
              NumberAnimation {
                target: marqueeText
                property: "x"
                from: -marqueeText.overflowDist
                to: 0
                duration: 500
                easing.type: Easing.OutCubic
              }
            }
          }
        }
      }
    }

    // --- Vertical Mode Layout ---
    Column {
      id: verticalLayout
      visible: root.vertical
      anchors.fill: parent

      OpticalGlyph {
        width: button.width
        height: Style.bar.iconSlot
        text: root.barData.icon !== "" ? root.barData.icon : "󰃭"
        fontFamily: button.fontFamily
        fontSize: button.fontSize
        color: root.barData.isLive ? Color.urgent : (root.barData.isSoon ? Color.warning : button.foreground)
      }
    }
  }
}
