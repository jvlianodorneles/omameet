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

  // Local optimistic overrides to guarantee zero-latency reactive updates
  property string customFormat: ""
  property int customMaxTitleLength: -1
  property int customMarqueeEnabled: -1
  property int customEnableNotifications: -1

  // Settings dynamically read from root.settings (persisted in shell.json)
  readonly property string currentFormat: customFormat !== "" ? customFormat : ((root.settings && root.settings.format !== undefined) ? root.settings.format : "title_countdown")
  readonly property int currentMaxTitleLength: customMaxTitleLength > 0 ? customMaxTitleLength : ((root.settings && root.settings.maxTitleLength !== undefined) ? Number(root.settings.maxTitleLength) : 35)
  readonly property bool currentMarqueeEnabled: customMarqueeEnabled >= 0 ? (customMarqueeEnabled === 1) : ((root.settings && root.settings.marqueeEnabled !== undefined) ? root.settings.marqueeEnabled : false)
  readonly property int currentMarqueeSpeed: (root.settings && root.settings.marqueeSpeed !== undefined) ? root.settings.marqueeSpeed : 6
  readonly property bool currentShowIcon: (root.settings && root.settings.showIcon !== undefined) ? root.settings.showIcon : true
  readonly property bool currentShowCountdown: (root.settings && root.settings.showCountdown !== undefined) ? root.settings.showCountdown : true
  readonly property int currentRefreshIntervalMin: (root.settings && root.settings.refreshIntervalMin !== undefined) ? root.settings.refreshIntervalMin : 15
  readonly property int currentUrgentThresholdMin: (root.settings && root.settings.urgentThresholdMin !== undefined) ? root.settings.urgentThresholdMin : 5
  readonly property bool currentEnableNotifications: customEnableNotifications >= 0 ? (customEnableNotifications === 1) : ((root.settings && root.settings.enableNotifications !== undefined) ? root.settings.enableNotifications : true)

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
    if (key === "format") customFormat = value
    if (key === "maxTitleLength") customMaxTitleLength = value
    if (key === "marqueeEnabled") customMarqueeEnabled = value ? 1 : 0
    if (key === "enableNotifications") customEnableNotifications = value ? 1 : 0

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

  property int lastSeenDay: new Date().getDate()

  // Suspend/Sleep watchdog: detects system wake-up immediately after suspension
  Timer {
    id: suspendWatchdog
    interval: 5000
    repeat: true
    running: true
    property real lastTick: Date.now()
    onTriggered: {
      var now = Date.now()
      var delta = now - lastTick
      lastTick = now
      // If more than 12 seconds elapsed in a 5s timer, the system was suspended/sleeping
      if (delta > 12000) {
        root.refresh()
      }
    }
  }

  // Periodic calendar sync timer
  Timer {
    interval: Math.max(1, root.currentRefreshIntervalMin) * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  // Minute clock to re-evaluate relative countdowns, day transitions & notification alerts
  SystemClock {
    id: minuteClock
    precision: SystemClock.Minutes
    onDateChanged: {
      var d = new Date()
      var curDay = d.getDate()
      // Midnight rollover detection
      if (curDay !== root.lastSeenDay) {
        root.lastSeenDay = curDay
        root.refresh()
      } else if (root.currentEnableNotifications) {
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

  readonly property real marqueeSlotWidth: Math.min(Style.space(240), Math.max(Style.space(90), root.currentMaxTitleLength * 8.5))

  implicitWidth: root.vertical ? button.implicitWidth : (root.barData.needsMarquee ? (marqueeSlotWidth + Style.space(20)) : button.implicitWidth)
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
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
      width: root.marqueeSlotWidth
      height: parent.height
      clip: true

      Row {
        id: marqueeRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          text: root.barData.icon
          visible: root.barData.icon !== ""
          textFormat: Text.PlainText
          color: root.barData.isLive ? Color.urgent : (root.barData.isSoon ? Color.warning : button.foreground)
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
        }

        Item {
          id: marqueeClip
          width: marqueeContainer.width - (root.barData.icon !== "" ? Style.space(18) : 0)
          height: marqueeText.implicitHeight
          clip: true

          Text {
            id: marqueeText
            text: (root.barData.isLive ? "🔴 " : "") + root.barData.rawTitle + (root.barData.countdown ? (" " + root.barData.countdown) : "")
            textFormat: Text.PlainText
            color: root.barData.isLive ? Color.urgent : (root.barData.isSoon ? Color.warning : button.foreground)
            font.family: button.fontFamily
            font.pixelSize: button.fontSize
            renderType: Text.NativeRendering

            readonly property real overflowDist: Math.max(0, marqueeText.implicitWidth - marqueeClip.width + Style.space(8))

            SequentialAnimation {
              id: scrollAnim
              running: marqueeContainer.visible && marqueeText.overflowDist > 0
              loops: Animation.Infinite

              PauseAnimation { duration: 1200 }
              NumberAnimation {
                target: marqueeText
                property: "x"
                from: 0
                to: -marqueeText.overflowDist
                duration: Math.max(2000, Math.round(marqueeText.overflowDist * 35))
                easing.type: Easing.Linear
              }
              PauseAnimation { duration: 1500 }
              NumberAnimation {
                target: marqueeText
                property: "x"
                from: -marqueeText.overflowDist
                to: 0
                duration: 400
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
