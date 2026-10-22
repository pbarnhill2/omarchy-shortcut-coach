import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Shortcut Coach: a cap icon in the bar that opens a short "up next" list of
// shortcuts to learn, then every lesson grouped into sections. All reads and
// writes go through the `shortcut-coach` script next to this file, so the
// panel, the check-in card and anything that calls the script (you, or an
// agent adding lessons) share one state file.
//
// Layout rule: nothing changes size under the pointer. Rows have a fixed
// height and fixed columns, hover hints and Undo live in a fixed status
// line, and banners and the practice explainer float above the content.
BarWidget {
  id: root
  moduleName: "pbarnhill.shortcut-coach"

  readonly property string dir: String(Qt.resolvedUrl(".")).replace("file://", "")
  readonly property string cli: dir + "shortcut-coach"
  // Development: a `.preview` file in the plugin folder points the panel at
  // a scratch state file (kept outside this folder, which the shell watches),
  // so screenshots never touch real progress.
  property bool preview: false
  readonly property string statePath: preview ? Quickshell.env("HOME") + "/.local/state/omarchy-shortcut-coach-preview.json"
                                              : Quickshell.env("HOME") + "/.local/state/omarchy-shortcut-coach.json"
  readonly property var cliEnv: preview ? ({ "SHORTCUT_COACH_STATE": statePath }) : ({})

  property bool opened: false
  // The coach as its own desktop window instead of the bar popup.
  property bool detached: false
  readonly property bool showing: opened || detached
  property bool windowRestored: false
  property bool popoutSwitchClosing: false
  property var sections: []
  property var favorites: []
  property var inPractice: []
  // Shortcuts flying into In practice before their save lands, by id. Keeps
  // the section (and its landing spot) on screen for the first one.
  property var incomingIds: ({})
  readonly property int practiceIncoming: {
    var n = 0
    for (var id in incomingIds) if (inPractice.every(function(i) { return i.id !== id })) n++
    return n
  }
  // When a chip last landed, so the save that follows doesn't glow twice.
  property real lastLanding: 0
  property int batch: 6
  property int mastered: 0
  property int total: 0
  property bool complete: false
  property int practicing: 0
  property bool paused: false
  property bool introSeen: true
  // The practice explainer, shown the first time someone presses Practice.
  property bool showIntro: false
  // Set up a practice desktop: shown on first open, and from the ⓘ by the title.
  property bool showSetup: false
  property bool setupSeen: true
  property var setupKeys: ({ "desktop": "Super + 9", "terminal": "Super + Enter" })
  // Which sections are unfolded, by level.
  property var expanded: ({})
  // Done counts from the last refresh, to spot a section being finished.
  property var lastDone: ({})
  property string bannerText: ""
  // What the hovered control does; shown in the status line.
  property string hint: ""
  // The lesson whose longer explanation is open (the ⓘ button), or null.
  property var detail: null

  // The science behind the coach, opened from the welcome and practice cards.
  readonly property var method: ({
    "keys": "",
    "title": "The science behind it",
    "more": "Shortcut Coach puts a few well-studied ideas from memory research to work.\n\n"
      + "<b>Recall beats re-reading.</b> Trying to remember something strengthens it more than looking it up again (Roediger and Karpicke, 2006). That's why check-ins hide the keys until you ask.\n\n"
      + "<b>Spacing beats cramming.</b> Practice spread over days sticks far better than the same practice in one sitting. It's one of the most reliable findings in memory research.\n\n"
      + "<b>Gaps that grow.</b> Paul Pimsleur (1967) proposed recalling each item just as it starts to fade, then waiting longer each time. Later work found the first check should wait a little (Karpicke and Roediger, 2007), and that a gap a bit too long costs far less than one too short (Cepeda and colleagues, 2008). So check-ins come after 10 minutes, 1 hour, 1 day, 4 days, 2 weeks and 6 weeks.\n\n"
      + "<b>Sleep helps.</b> Finger-sequence skills improve after a night's sleep (Walker and colleagues, 2002), so the third check-in comes the next day.\n\n"
      + "<b>Doing beats reading.</b> Practice starts by pressing the shortcut once, and the practice desktop gives every lesson something to act on.\n\n"
      + "<b>Small batches, few interruptions.</b> Six shortcuts at a time. Check-ins wait for a pause in your typing, at most one every 15 minutes and 8 a day.\n\n"
      + "The full write-up, with every source, is in the plugin's docs/RESEARCH.md."
  })

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color accent: Commons.Color.accent

  // The row grid, shared by every up next row.
  readonly property int rowHeight: Style.space(58)
  readonly property int checkCol: Style.space(8)
  readonly property int pillCol: checkCol + Style.space(20) + Style.space(10)
  readonly property int pillWidth: Style.space(100)
  readonly property int textCol: pillCol + pillWidth + Style.space(14)

  function open() { opened = true; refresh() }
  function close() { opened = false; showIntro = false; showSetup = false; detail = null; hint = ""; flush() }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }
  function toggle() {
    // As a window, the bar icon takes you to it.
    if (detached) { focusWindow(); return }
    opened ? close() : open()
  }

  // Move the coach between the bar popup and a desktop window.
  function setDetached(on) {
    if (on === detached) return
    hint = ""
    if (on) {
      opened = false
      detached = true
      coachWindow.visible = true
      Qt.callLater(focusWindow)
    } else {
      detached = false
      coachWindow.visible = false
      open()
    }
    // Remembered, so the window comes back after a restart.
    run(["window", on ? "on" : "off"])
  }

  function focusWindow() {
    Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "title:^Shortcut Coach$" })'])
  }

  function refresh() {
    listProc.running = false
    listProc.running = true
  }

  // After every refresh: rows whose answer was saved but are still listed
  // (an Undo, or a failed save) drop their in-between state.
  signal refreshed()

  // Fly a row's chip into In practice. Runs here, not in the row, because the
  // row is gone before the chip lands. Order: remove the row, settle the
  // layout, then measure where the heading is now.
  function flyToPractice(id, from, keys, title) {
    var ids = Object.assign({}, incomingIds)
    ids[id] = true
    incomingIds = ids
    removeFromUpNext(id)
    Qt.callLater(function() {
      column.forceLayout()
      var to = practiceList.target(confettiLayer)
      var chip = flyingChip.createObject(confettiLayer, { x: from.x, y: from.y, sx: from.x, sy: from.y,
                                                          keys: keys, title: title, tx: to.x, ty: to.y })
      if (chip) chip.landed.connect(root.chipLanded)
    })
  }

  function chipLanded() {
    lastLanding = Date.now()
    practiceList.glowNow()
  }

  // Take a row out of up next right away, without waiting for the save.
  function removeFromUpNext(id) {
    for (var i = 0; i < upNextModel.count; i++)
      if (upNextModel.get(i).lid === id) { upNextModel.remove(i); return }
  }

  function inUpNext(id) {
    for (var i = 0; i < upNextModel.count; i++)
      if (upNextModel.get(i).lid === id) return true
    return false
  }

  function dismissSetup() {
    showSetup = false
    if (!setupSeen) run(["setup-seen"])
  }

  function toggleSection(level) {
    var next = Object.assign({}, expanded)
    next[level] = !next[level]
    expanded = next
  }

  // A banner and a big burst across the top when a section is finished.
  function celebrate(text) {
    root.bannerText = text
    bannerTimer.restart()
    for (var k = 0; k < 5; k++)
      root.burst(confettiLayer, confettiLayer.width * (k + 0.5) / 5, Style.space(30))
  }

  // ---- Saving -------------------------------------------------------------
  // Answers wait until their animation has played, then save together in one
  // locked call, one batch at a time and in order. They live here, not in a
  // row, so a refresh that rebuilds rows can't drop one.
  property var pending: []
  // Lessons answered but not saved yet, so a refresh can't bring them back.
  property var pendingIds: ({})
  property string undoTitle: ""
  property var undoArgs: null

  function commit(args, title) {
    var id = args[1]
    if (args[0] !== "undo" && id !== undefined) {
      if (pendingIds[id]) return
      var ids = Object.assign({}, pendingIds)
      ids[id] = true
      pendingIds = ids
    }
    pending = pending.concat([args])
    flushTimer.restart()
    if (title) {
      undoTitle = title
      undoArgs = ["undo", id]
      undoTimer.restart()
    }
  }

  // For settings (pause, intro): save now.
  function run(args) {
    pending = pending.concat([args])
    flush()
  }

  function flush() {
    if (pending.length === 0 || flushProc.running) return
    flushProc.command = [root.cli, "apply", JSON.stringify(pending)]
    pending = []
    flushProc.running = true
  }

  Process {
    id: flushProc
    environment: root.cliEnv
    onExited: {
      if (root.pending.length > 0) root.flush()
      else root.pendingIds = ({})
      root.refresh()
    }
  }

  Timer {
    id: flushTimer
    interval: 1100
    onTriggered: root.flush()
  }

  Timer {
    id: undoTimer
    interval: 8000
    onTriggered: root.undoTitle = ""
  }

  Timer {
    id: bannerTimer
    interval: 3500
    onTriggered: root.bannerText = ""
  }

  // ---- Up next model --------------------------------------------------------
  // Synced in place by lesson id, so rows that stay keep their delegate and
  // the list animates only what changed.
  ListModel { id: upNextModel }

  // Two queues in one list: new lessons (learn) and due check-ins (review).
  property string tab: "learn"
  property var learnItems: []
  property var reviewItems: []

  function showTab(name) {
    if (tab === name) return
    tab = name
    hint = ""
    applyTab()
  }

  function applyTab() {
    syncUpNext(learnItems.filter(function(i) { return !root.pendingIds[i.id] }))
    if (tab === "review" && reviewResult === "") nextReview()
  }

  function syncUpNext(items) {
    var want = items.slice(0, root.batch)
    var ids = want.map(function(i) { return i.id })
    for (var r = upNextModel.count - 1; r >= 0; r--)
      if (ids.indexOf(upNextModel.get(r).lid) === -1) upNextModel.remove(r)
    for (var i = 0; i < want.length; i++) {
      var payload = JSON.stringify(want[i])
      var at = -1
      for (var j = i; j < upNextModel.count; j++)
        if (upNextModel.get(j).lid === want[i].id) { at = j; break }
      if (at === -1) upNextModel.insert(i, { lid: want[i].id, payload: payload })
      else {
        if (at !== i) upNextModel.move(at, i, 1)
        if (upNextModel.get(i).payload !== payload) upNextModel.setProperty(i, "payload", payload)
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: previewCheck.running = true

  Process {
    id: previewCheck
    command: ["test", "-f", root.dir + ".preview"]
    onExited: function(code) { root.preview = code === 0; root.refresh() }
  }

  Process {
    id: listProc
    command: [root.cli, "list", "--json"]
    environment: root.cliEnv
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        var finished = ""
        var done = {}
        var secs = data.sections || []
        for (var i = 0; i < secs.length; i++) {
          var s = secs[i]
          done[s.level] = s.done
          var before = root.lastDone[s.level]
          if (before !== undefined && before < s.total && s.done === s.total) finished = s.name
        }
        var wasComplete = root.complete
        root.batch = data.batch || 6
        root.sections = secs
        root.favorites = data.favorites || []
        root.inPractice = data.inPractice || []
        if (Object.keys(root.pendingIds).length === 0) root.incomingIds = ({})
        root.mastered = data.mastered || 0
        root.total = data.total || 0
        root.complete = !!data.complete
        root.practicing = data.practicing || 0
        root.paused = !!data.paused
        root.introSeen = !!data.introSeen
        // Restore the desktop window after a restart.
        if (data.window && !root.detached && !root.windowRestored) {
          root.windowRestored = true
          root.detached = true
          coachWindow.visible = true
        }
        root.setupSeen = !!data.setupSeen
        if (data.setup) root.setupKeys = data.setup
        if (root.showing && !root.setupSeen) root.showSetup = true
        root.learnItems = data.upNext || []
        root.reviewItems = data.reviews || []
        root.applyTab()
        if (root.showing) {
          if (root.complete && !wasComplete) root.celebrate("🏆  Shortcut Master!")
          else if (finished !== "") root.celebrate("🎉  " + finished + " complete!")
        }
        root.lastDone = done
        root.refreshed()
      }
    }
  }

  // Any change to progress (from the panel, the card or the script) reloads.
  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰑴"
    slotSize: Style.bar.statusSlot
    tooltipText: root.opened ? "" : (root.detached ? "Shortcut Coach (open as a window) · " : "Shortcut Coach · ") + root.mastered + " of " + root.total + " mastered"
                                  + (root.practicing > 0 ? " · " + root.practicing + " in practice" : "")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  component ConfettiBit: Rectangle {
    id: bit
    property real dx: 0
    property real rise: 0
    property real fall: 0
    property real spin: 0
    property int life: 1500
    width: Style.space(5) + Math.random() * Style.space(4)
    height: width * (Math.random() < 0.5 ? 1 : 1.8)
    radius: Math.random() < 0.3 ? width / 2 : 1
    antialiasing: true

    ParallelAnimation {
      running: true
      onFinished: bit.destroy()
      NumberAnimation { target: bit; property: "x"; to: bit.x + bit.dx; duration: bit.life; easing.type: Easing.OutQuad }
      SequentialAnimation {
        NumberAnimation { target: bit; property: "y"; to: bit.y - bit.rise; duration: bit.life * 0.25; easing.type: Easing.OutQuad }
        NumberAnimation { target: bit; property: "y"; to: bit.y - bit.rise + bit.fall; duration: bit.life * 0.75; easing.type: Easing.InQuad }
      }
      NumberAnimation { target: bit; property: "rotation"; to: bit.spin; duration: bit.life }
      SequentialAnimation {
        PauseAnimation { duration: bit.life * 0.6 }
        NumberAnimation { target: bit; property: "opacity"; to: 0; duration: bit.life * 0.4 }
      }
    }
  }

  readonly property var confettiColors: [root.accent, "#f7768e", "#e0af68", "#9ece6a", "#7dcfff", "#bb9af7", "#ff9e64"]

  // Throws a burst of confetti from a point in the confetti layer.
  function burst(layer, px, py) {
    for (var i = 0; i < 46; i++) {
      confettiBit.createObject(layer, {
        x: px + (Math.random() - 0.5) * Style.space(20),
        y: py + (Math.random() - 0.5) * Style.space(10),
        color: confettiColors[i % confettiColors.length],
        dx: (Math.random() - 0.3) * Style.space(380),
        rise: Style.space(40) + Math.random() * Style.space(110),
        fall: Style.space(260) + Math.random() * Style.space(320),
        spin: (Math.random() - 0.5) * 900,
        life: 1300 + Math.random() * 700
      })
    }
  }

  Component { id: confettiBit; ConfettiBit {} }

  // ---- Building blocks --------------------------------------------------------

  // A fixed-width rounded button. Its size never depends on hover or state.
  component Pill: Rectangle {
    id: pill
    property string label: ""
    property bool primary: false
    property string hintText: ""
    signal clicked()
    readonly property bool hovered: pillMouse.containsMouse
    width: root.pillWidth
    height: Style.space(26)
    radius: height / 2
    color: primary ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, hovered ? 0.32 : 0.20)
                   : hovered ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : "transparent"
    border.color: primary || hovered ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.38)
    border.width: Math.max(1, Style.space(1))
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: pill.label
      color: pill.primary || pill.hovered ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.82)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: pill.primary
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
      onContainsMouseChanged: root.hint = containsMouse ? pill.hintText : (root.hint === pill.hintText ? "" : root.hint)
    }
  }

  // A checkbox with a generous click area. Checking pops it a little.
  component Check: Rectangle {
    id: check
    property bool checked: false
    property bool pop: false
    property string hintText: ""
    property int size: Style.space(20)
    signal clicked()
    readonly property bool hovered: checkMouse.containsMouse
    width: size; height: size
    radius: Style.space(4)
    color: checked ? root.accent : hovered ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : "transparent"
    border.color: checked || hovered ? root.accent : root.dim
    border.width: Math.max(1, Style.space(2))
    Behavior on color { ColorAnimation { duration: 150 } }
    SequentialAnimation on scale {
      running: check.pop
      NumberAnimation { to: 1.4; duration: 140; easing.type: Easing.OutQuad }
      NumberAnimation { to: 1.0; duration: 260; easing.type: Easing.OutBack }
    }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      visible: check.checked
      text: "✓"
      color: Commons.Color.popups.background
      font.family: Style.font.family
      font.pixelSize: check.size * 0.7
      font.bold: true
    }
    MouseArea {
      id: checkMouse
      anchors.fill: parent
      anchors.margins: -Style.space(5)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: check.clicked()
      onContainsMouseChanged: root.hint = containsMouse ? check.hintText : (root.hint === check.hintText ? "" : root.hint)
    }
  }

  // The keys, as keycaps: [SUPER] [SHIFT] [1-9]. Each key held together is its
  // own cap; a menu path (MENU › STYLE › FONT) stays one cap.
  function keyCaps(keys) {
    var text = String(keys || "").trim()
    if (text === "") return []
    if (text.indexOf("›") !== -1) return [text]
    var plus = text.indexOf(" + ")
    if (plus === -1) return [text]
    var mods = text.slice(0, plus).split(/\s+/).filter(function(m) { return m !== "" })
    return mods.concat([text.slice(plus + 3)])
  }

  component Keys: Row {
    id: keysRow
    property string keys: ""
    property bool muted: false
    property bool small: false
    property bool big: false
    spacing: Style.space(small ? 3 : big ? 6 : 4)
    Repeater {
      model: root.keyCaps(keysRow.keys)
      delegate: Rectangle {
        required property string modelData
        width: capLabel.implicitWidth + Style.space(keysRow.small ? 8 : keysRow.big ? 18 : 10)
        height: Style.space(keysRow.small ? 18 : keysRow.big ? 34 : 20)
        radius: Style.space(keysRow.big ? 6 : 4)
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, keysRow.muted ? 0.08 : 0.16)
        // A slightly firmer bottom edge reads as a key.
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: parent.radius
          anchors.rightMargin: parent.radius
          height: Math.max(1, Style.space(1))
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, keysRow.muted ? 0.12 : 0.35)
        }
        Text {
          textFormat: Text.PlainText
          id: capLabel
          anchors.centerIn: parent
          text: modelData
          color: keysRow.muted ? root.dim : root.accent
          font.family: Style.font.family
          font.pixelSize: keysRow.small ? Style.font.caption : keysRow.big ? Style.font.body + 6 : Style.font.bodySmall
          font.bold: true
        }
      }
    }
  }

  // Variants taught with a lesson, on the line under its keys, aligned with
  // them and joined by a bracket:
  // ⎡ [SUPER] [SHIFT] [1-9]        Send a window to a desktop
  // ⎣ [SUPER] [SHIFT] [ALT] [1-9]  …and stay where you are
  component Nested: Row {
    id: nested
    property var variants: []
    property bool muted: false
    spacing: Style.space(6)
    clip: true
    Repeater {
      model: nested.variants
      delegate: Row {
        required property var modelData
        required property int index
        spacing: Style.space(6)
        Text {
          textFormat: Text.PlainText
          visible: index > 0
          anchors.verticalCenter: parent.verticalCenter
          text: "·"
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        Keys {
          small: true
          muted: nested.muted
          keys: modelData.keys
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.label
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  // A thin bracket joining two lines of keys into one lesson.
  component Bracket: Item {
    id: bracket
    property real fromY: 0
    property real toY: 0
    y: fromY
    width: Style.space(5)
    height: toY - fromY
    readonly property real stroke: Math.max(1, Style.space(1.5))
    readonly property color ink: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
    Rectangle { x: 0; y: 0; width: bracket.stroke; height: parent.height; color: bracket.ink }
    Rectangle { x: 0; y: 0; width: parent.width; height: bracket.stroke; color: bracket.ink }
    Rectangle { x: 0; y: parent.height - height; width: parent.width; height: bracket.stroke; color: bracket.ink }
  }

  // In place of the keys on a check-in: which check-in this is.
  component CheckInBadge: Rectangle {
    id: badge
    property int stage: 0
    property int steps: 6
    width: badgeLabel.implicitWidth + Style.space(12)
    height: Style.space(20)
    radius: Style.space(4)
    color: "transparent"
    border.color: root.accent
    border.width: Math.max(1, Style.space(1))
    Text {
      textFormat: Text.PlainText
      id: badgeLabel
      anchors.centerIn: parent
      text: "CHECK-IN " + (badge.stage + 1) + "/" + badge.steps
      color: root.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0.6
    }
  }

  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
    leftPadding: Style.space(8)
  }

  // A clickable text link that never changes size on hover.
  component Link: Text {
    textFormat: Text.PlainText
    id: link
    property bool strong: false
    signal clicked()
    color: linkMouse.containsMouse ? root.fg : (strong ? root.accent : root.dim)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: strong
    MouseArea {
      id: linkMouse
      anchors.fill: parent
      anchors.margins: -Style.space(6)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }
  }

  // Opens the longer explanation, for lessons that have one.
  component Info: Text {
    textFormat: Text.PlainText
    id: info
    property var lesson: null
    visible: !!(lesson && lesson.more)
    text: "󰋽"
    color: infoMouse.containsMouse ? root.accent : root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    MouseArea {
      id: infoMouse
      anchors.fill: parent
      anchors.margins: -Style.space(5)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { root.hint = ""; root.detail = info.lesson }
      onContainsMouseChanged: root.hint = containsMouse ? "How it works" : (root.hint === "How it works" ? "" : root.hint)
    }
  }

  // Star a shortcut to keep it in Favorites, your own cheat sheet.
  component Star: Text {
    textFormat: Text.PlainText
    id: star
    property var lesson: null
    readonly property bool on: !!(lesson && lesson.favorite)
    width: Style.space(18)
    horizontalAlignment: Text.AlignHCenter
    text: on ? "󰓎" : "󰓒"
    color: on ? root.accent : (starMouse.containsMouse ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35))
    font.family: Style.font.family
    font.pixelSize: Style.font.body + 1
    MouseArea {
      id: starMouse
      anchors.fill: parent
      anchors.margins: -Style.space(5)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      readonly property string hintText: star.on ? "Remove from favorites" : "Add to favorites, your own cheat sheet"
      onClicked: if (star.lesson) root.run([star.on ? "unfav" : "fav", star.lesson.id])
      onContainsMouseChanged: root.hint = containsMouse ? hintText : (root.hint === hintText ? "" : root.hint)
    }
  }

  // ---- An up next row -----------------------------------------------------------
  // Fixed height, fixed columns: [checkbox] [action pill] [keys + title / tip].
  component UpNextRow: Item {
    id: row
    required property string lid
    required property string payload
    readonly property var item: JSON.parse(payload)
    readonly property bool checkIn: !!item.checkIn
    property bool revealed: false
    property bool trying: false
    property bool celebrating: false
    property bool leaving: false
    readonly property bool busy: celebrating || leaving || trying
    width: ListView.view ? ListView.view.width : 0
    height: root.rowHeight
    opacity: leaving ? 0 : 1

    Connections {
      target: root
      function onRefreshed() {
        if (!(row.celebrating || row.leaving) || root.pendingIds[row.lid] || !root.inUpNext(row.lid)) return
        row.celebrating = false
        row.leaving = false
        row.trying = false
        row.revealed = false
        strike.width = 0
      }
    }
    Behavior on opacity { NumberAnimation { duration: 200 } }

    // Ticked: known for good, or on a check-in, remembered.
    function check() {
      if (busy) return
      celebrating = true
      var p = box.mapToItem(confettiLayer, box.width / 2, box.height / 2)
      root.burst(confettiLayer, p.x, p.y)
      root.commit(checkIn ? ["checkin", item.id, "pass"] : ["done", item.id], checkIn ? "" : item.title)
      strikeAnim.start()
      root.hint = ""
    }

    function pillClicked() {
      if (busy || trying) return
      if (checkIn && revealed) {
        leaving = true
        root.commit(["checkin", item.id, "fail"], "")
      } else if (checkIn) {
        revealed = true
      } else {
        // One click: try it now, then it moves itself into In practice.
        if (!root.introSeen) root.showIntro = true
        trying = true
        tryTimer.start()
      }
      root.hint = ""
    }

    Timer {
      id: tryTimer
      interval: 2600
      onTriggered: row.flyAway()
    }

    // Hand off to the root: the chip flies to In practice, the row folds away.
    function flyAway() {
      leaving = true
      root.commit(["later", item.id], "")
      root.flyToPractice(lid, line1.mapToItem(confettiLayer, 0, 0), item.keys || "", item.title || "")
    }

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: Style.space(2)
      anchors.bottomMargin: Style.space(2)
      radius: Style.space(8)
      clip: true
      color: row.celebrating || row.trying ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
           : rowHover.hovered ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05) : "transparent"
      Behavior on color { ColorAnimation { duration: 160 } }
    }
    HoverHandler { id: rowHover }

    // While trying it: a thin line fills along the bottom of the row.
    Rectangle {
      x: Style.space(8)
      y: row.height - Style.space(4)
      height: Math.max(1, Style.space(2))
      radius: height / 2
      color: root.accent
      visible: row.trying
      width: 0
      NumberAnimation on width {
        running: row.trying
        from: 0; to: row.width - Style.space(16); duration: 2600; easing.type: Easing.Linear
      }
    }

    Check {
      id: box
      x: root.checkCol
      anchors.verticalCenter: parent.verticalCenter
      checked: row.celebrating
      pop: row.celebrating
      enabled: !row.busy
      // Flash card: grade only after seeing the answer.
      visible: !row.checkIn || row.revealed
      hintText: row.checkIn ? "Got it: back in " + (row.item.passIn || "a while")
                            : "Know it already: mark it as known"
      onClicked: row.check()
    }

    Pill {
      x: root.pillCol
      anchors.verticalCenter: parent.verticalCenter
      opacity: row.busy ? 0 : 1
      enabled: !row.busy
      primary: false
      label: row.checkIn && row.revealed ? "Missed it"
           : row.checkIn ? "󰈈 Show"
           : "󰥔 Practice"
      hintText: row.checkIn && row.revealed ? "Missed it: back in " + (row.item.missIn || "10m")
              : row.checkIn ? "Think of the keys, then flip the card"
              : "Not sure yet: try it now, then it moves to In practice"
      onClicked: row.pillClicked()
    }

    // Line 1: keys (or which check-in) and the title.
    Star {
      id: rowStar
      lesson: row.checkIn && !row.revealed ? null : row.item
      visible: !!lesson
      x: row.width - width - Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
    }

    Item {
      id: line1
      x: root.textCol
      width: row.width - root.textCol - Style.space(40)
      y: Style.space(9)
      height: Style.space(20)

      Keys {
        id: chip
        visible: !(row.checkIn && !row.revealed)
        keys: row.item.keys || ""
        anchors.verticalCenter: parent.verticalCenter
      }
      CheckInBadge {
        id: badge
        visible: row.checkIn && !row.revealed
        stage: row.item.stage || 0
        steps: row.item.steps || 6
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        textFormat: Text.PlainText
        id: title
        x: (chip.visible ? chip.width : badge.width) + Style.space(10)
        width: Math.min(implicitWidth, parent.width - x - (rowInfo.visible ? rowInfo.width + Style.space(8) : 0))
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: row.item.title || ""
        color: row.celebrating ? root.dim : root.fg
        // Cut off? Pointing at it shows the whole line below.
        HoverHandler {
          onHoveredChanged: root.hint = hovered && title.truncated ? title.text : (root.hint === title.text ? "" : root.hint)
        }
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        Behavior on color { ColorAnimation { duration: 300 } }
        Rectangle {
          id: strike
          anchors.verticalCenter: parent.verticalCenter
          width: 0
          height: Math.max(1, Style.space(2))
          color: root.fg
          NumberAnimation on width {
            id: strikeAnim
            running: false
            from: 0; to: title.width; duration: 320; easing.type: Easing.OutCubic
          }
        }
      }
      Info {
        id: rowInfo
        lesson: row.checkIn && !row.revealed ? null : row.item
        x: title.x + title.width + Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Line 2: one line, always, so the row never changes height. A lesson
    // with variants shows them here, nested under its keys; its tip moves to
    // the ⓘ. On a check-in they stay hidden until the card is flipped (Show).
    readonly property bool showNested: (item.variants || []).length > 0 && !trying && !(checkIn && !revealed)
    Nested {
      id: rowNested
      visible: row.showNested
      x: root.textCol
      y: line1.y + line1.height + Style.space(5)
      width: line1.width
      height: Style.space(18)
      variants: row.item.variants || []
    }
    Bracket {
      visible: row.showNested
      x: root.textCol - Style.space(9)
      fromY: line1.y + Style.space(4)
      toY: rowNested.y + rowNested.height - Style.space(4)
    }
    Text {
      textFormat: Text.PlainText
      id: tip
      visible: !row.showNested
      x: root.textCol
      y: line1.y + line1.height + Style.space(5)
      HoverHandler {
        onHoveredChanged: root.hint = hovered && tip.truncated ? tip.text : (root.hint === tip.text ? "" : root.hint)
      }
      width: line1.width
      elide: Text.ElideRight
      maximumLineCount: 1
      text: row.trying ? "Try it now: press " + (row.item.keys || "") + ". Moving to In practice…"
          : row.checkIn && row.revealed ? "Got it? Tick the box. If not, Missed it."
          : row.checkIn ? "What's the shortcut? Think, then Show."
          : (row.item.why || "")
      color: row.trying ? root.accent : root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  // ---- A row inside an open section -------------------------------------------
  component SectionRow: Item {
    id: srow
    required property var modelData
    readonly property var item: modelData || ({})
    readonly property bool mastered: !!item.mastered
    readonly property bool hasNested: (item.variants || []).length > 0
    property bool ticking: false
    width: parent ? parent.width : 0
    height: Style.space(hasNested ? 54 : 32)

    function toggle() {
      if (ticking) return
      if (mastered) { root.commit(["undo", item.id], ""); return }
      ticking = true
      var p = sbox.mapToItem(confettiLayer, sbox.width / 2, sbox.height / 2)
      root.burst(confettiLayer, p.x, p.y)
      root.commit(["done", item.id], item.title)
      root.hint = ""
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: srowHover.hovered ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05) : "transparent"
    }
    HoverHandler { id: srowHover }

    Check {
      id: sbox
      x: Style.space(30)
      size: Style.space(16)
      y: (Style.space(32) - height) / 2
      checked: srow.mastered || srow.ticking
      pop: srow.ticking
      hintText: srow.mastered ? "Not sure after all? Unmark it"
              : srow.item.practicing ? "Know it now? Mark it as known and stop check-ins"
              : "Know it: mark it as known"
      onClicked: srow.toggle()
    }
    Keys {
      id: skeys
      x: Style.space(58)
      y: (Style.space(32) - height) / 2
      keys: srow.item.keys || ""
      muted: srow.mastered || srow.ticking
    }
    Text {
      textFormat: Text.PlainText
      id: stitle
      x: skeys.x + skeys.width + Style.space(10)
      HoverHandler {
        onHoveredChanged: root.hint = hovered && stitle.truncated ? stitle.text : (root.hint === stitle.text ? "" : root.hint)
      }
      width: Math.min(implicitWidth, (note.visible ? note.x : sstar.x) - Style.space(10) - x
                                     - (sinfo.visible ? sinfo.width + Style.space(8) : 0))
      y: (Style.space(32) - height) / 2
      elide: Text.ElideRight
      text: srow.item.title || ""
      color: srow.mastered || srow.ticking ? root.dim : root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.strikeout: srow.mastered || srow.ticking
    }
    // Variants, nested under the keys.
    Nested {
      id: snested
      visible: srow.hasNested
      x: skeys.x
      y: Style.space(32)
      width: srow.width - x - Style.space(10)
      height: Style.space(18)
      variants: srow.item.variants || []
      muted: srow.mastered || srow.ticking
    }
    Bracket {
      visible: srow.hasNested
      x: skeys.x - Style.space(8)
      fromY: skeys.y + Style.space(3)
      toY: snested.y + snested.height - Style.space(3)
    }
    Info {
      id: sinfo
      lesson: srow.item
      x: stitle.x + stitle.width + Style.space(8)
      y: (Style.space(32) - height) / 2
    }
    Star {
      id: sstar
      lesson: srow.item
      x: srow.width - width - Style.space(10)
      y: (Style.space(32) - height) / 2
    }
    // In practice: how far along, and the next check-in.
    Text {
      textFormat: Text.PlainText
      id: note
      visible: !!srow.item.practicing && !srow.mastered && !srow.ticking
      x: sstar.x - width - Style.space(10)
      y: (Style.space(32) - height) / 2
      text: (srow.item.tricky ? "tricky · " : "") + "󰥔 " + srow.item.stage + "/" + srow.item.steps
            + (srow.item.backIn ? " · " + srow.item.backIn : " · now")
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // The shortcut's chip, flying from its row to the In practice heading.
  component FlyingChip: Rectangle {
    id: fly
    property string keys: ""
    property string title: ""
    property real tx: 0
    property real ty: 0
    signal landed()
    width: flyRow.implicitWidth + Style.space(16)
    height: Style.space(28)
    radius: height / 2
    color: Commons.Color.popups.background
    border.color: root.accent
    border.width: Math.max(1, Style.space(1))
    transformOrigin: Item.Left
    Row {
      id: flyRow
      anchors.centerIn: parent
      spacing: Style.space(8)
      Keys { keys: fly.keys; anchors.verticalCenter: parent.verticalCenter }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: fly.title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
    property real sx: 0
    property real sy: 0
    ParallelAnimation {
      running: true
      // One curve: down first, then gliding sideways into the heading,
      // slowing as it lands.
      PathAnimation {
        target: fly
        duration: 540
        easing.type: Easing.OutCubic
        path: Path {
          startX: fly.sx; startY: fly.sy
          PathQuad { x: fly.tx; y: fly.ty - fly.height / 2; controlX: fly.sx; controlY: fly.ty - fly.height / 2 }
        }
      }
      SequentialAnimation {
        NumberAnimation { target: fly; property: "scale"; to: 1.05; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: fly; property: "scale"; to: 0.5; duration: 450; easing.type: Easing.InOutCubic }
      }
      SequentialAnimation {
        PauseAnimation { duration: 400 }
        NumberAnimation { target: fly; property: "opacity"; to: 0; duration: 140 }
      }
      onFinished: { fly.landed(); fly.destroy() }
    }
  }
  Component { id: flyingChip; FlyingChip {} }

  // A folding list at the top of All shortcuts: Favorites, In practice.
  component ListSection: Column {
    id: list
    property string key: ""
    property string icon: ""
    property string title: ""
    property var items: []
    property bool openByDefault: true
    readonly property bool open: root.expanded[key] === undefined ? openByDefault : !!root.expanded[key]
    visible: items.length > 0 || (key === "practice" && root.practiceIncoming > 0)
    width: parent ? parent.width : 0

    // Where a flying chip should land, in the given item's coordinates.
    function target(layer) { return header.mapToItem(layer, Style.space(30), header.height / 2) }
    function glowNow() { arrived.restart() }

    // Light up when something arrives, so it's clear where it went.
    property int lastCount: -1
    onItemsChanged: {
      if (lastCount >= 0 && items.length > lastCount && Date.now() - root.lastLanding > 3000) arrived.restart()
      lastCount = items.length
    }
    Item {
      id: header
      width: parent.width
      height: Style.space(32)
      Rectangle {
        anchors.fill: parent
        radius: Style.space(6)
        color: listMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05) : "transparent"
      }
      Rectangle {
        id: glow
        anchors.fill: parent
        radius: Style.space(6)
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
        border.color: root.accent
        border.width: Math.max(1, Style.space(1))
        opacity: 0
        SequentialAnimation {
          id: arrived
          NumberAnimation { target: glow; property: "opacity"; to: 1; duration: 120 }
          PauseAnimation { duration: 200 }
          NumberAnimation { target: glow; property: "opacity"; to: 0; duration: 320 }
        }
      }
      MouseArea {
        id: listMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          var next = Object.assign({}, root.expanded)
          next[list.key] = !list.open
          root.expanded = next
        }
      }
      Text {
        textFormat: Text.PlainText
        x: Style.space(10)
        width: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        rotation: list.open ? 90 : 0
        Behavior on rotation { NumberAnimation { duration: 160 } }
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.body + 2
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        x: Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        text: list.icon + "  " + list.title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: list.items.length + (list.key === "practice" ? root.practiceIncoming : 0)
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
    Repeater {
      model: list.open ? list.items : []
      delegate: SectionRow {}
    }
  }

  // ---- Review: one flash card at a time ---------------------------------------
  // The card keeps showing what you graded until it moves on, so the answer
  // and the result stay put while the save happens.
  property var reviewCard: null
  property bool reviewFlipped: false
  property string reviewResult: ""
  readonly property var reviewQueue: reviewItems.filter(function(i) { return !root.pendingIds[i.id] })

  function nextReview() {
    reviewResult = ""
    reviewFlipped = false
    reviewCard = reviewQueue.length > 0 ? reviewQueue[0] : null
  }

  onReviewQueueChanged: if (!reviewCard || (reviewResult === "" && reviewQueue.every(function(i) { return i.id !== reviewCard.id }))) nextReview()

  function gradeReview(pass) {
    if (!reviewCard || reviewResult !== "") return
    var card = reviewCard
    if (pass) {
      var p = reviewGotIt.mapToItem(confettiLayer, reviewGotIt.width / 2, reviewGotIt.height / 2)
      root.burst(confettiLayer, p.x, p.y)
    }
    reviewResult = pass ? (card.passIn === "locked in" ? "🔒  Locked in. That one's yours."
                                                       : "Nice. Back in " + card.passIn + ".")
                        : "No problem. Back in " + card.missIn + "."
    root.commit(["checkin", card.id, pass ? "pass" : "fail"], "")
    reviewAdvance.restart()
  }

  Timer {
    id: reviewAdvance
    interval: 1500
    onTriggered: root.nextReview()
  }

  component ReviewButton: Rectangle {
    id: rb
    property string label: ""
    property string sub: ""
    property bool primary: false
    signal clicked()
    width: Math.max(Style.space(150), rbRow.implicitWidth + Style.space(32))
    height: Style.space(40)
    radius: Style.space(8)
    color: primary ? (rbMouse.containsMouse ? Qt.lighter(root.accent, 1.12) : root.accent)
                   : (rbMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10) : "transparent")
    border.color: primary ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
    border.width: Math.max(1, Style.space(1))
    Behavior on color { ColorAnimation { duration: 120 } }
    Row {
      id: rbRow
      anchors.centerIn: parent
      spacing: Style.space(8)
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: rb.label
        color: rb.primary ? Commons.Color.popups.background : root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        visible: rb.sub !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: rb.sub
        color: rb.primary ? Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g,
                                    Commons.Color.popups.background.b, 0.7) : root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    MouseArea {
      id: rbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: rb.clicked()
    }
  }

  component ReviewFace: Rectangle {
    anchors.fill: parent
    radius: Style.space(12)
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)
    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
    border.width: Math.max(1, Style.space(1.5))
    antialiasing: true
  }

  // ---- The panel ----------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && !root.detached
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(660))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + Style.space(42), Style.space(960))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.detail) root.detail = null
        else if (root.showSetup) root.dismissSetup()
        else if (root.showIntro) root.showIntro = false
        else root.close()
      }
    }
  }

  // The coach itself: inside the bar popup, or in its own desktop window.
  // One item, moved between the two, so everything keeps working in both.
  Item {
    id: coachView
    parent: root.detached ? coachWindow.contentItem : keyCatcher
    // In a window: a comfortable reading width, centered, however wide the tile.
    readonly property real pad: root.detached ? Style.space(16) : 0
    width: root.detached ? Math.min(parent.width - pad * 2, Style.space(760)) : parent.width
    height: parent.height - pad * 2
    x: root.detached ? (parent.width - width) / 2 : 0
    y: pad

    Flickable {
      id: scroll
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: statusLine.top
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        width: scroll.width
        spacing: 0

        // Header: title, progress count, and the progress bar.
        Item {
          width: parent.width
          height: Style.space(30)
          Text {
            textFormat: Text.PlainText
            id: heading
            x: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.complete ? "Shortcut Master 🏆" : "Shortcut Coach"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 2
            font.bold: true
          }
          // Practice desktop setup, again.
          Text {
            textFormat: Text.PlainText
            x: heading.x + heading.width + Style.space(10)
            anchors.verticalCenter: heading.verticalCenter
            text: "󰋽"
            color: setupMouse.containsMouse ? root.accent : root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            MouseArea {
              id: setupMouse
              anchors.fill: parent
              anchors.margins: -Style.space(5)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.hint = ""; root.showSetup = true }
              onContainsMouseChanged: root.hint = containsMouse ? "Set up a practice desktop" : (root.hint === "Set up a practice desktop" ? "" : root.hint)
            }
          }
          // Pop the coach out as a desktop window, or bring it back to the bar.
          Text {
            textFormat: Text.PlainText
            id: windowToggle
            anchors.right: masteredCount.left
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: heading.verticalCenter
            text: root.detached ? "󰁝" : "󰏌"
            color: windowMouse.containsMouse ? root.accent : root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 1
            readonly property string hintText: root.detached ? "Back to the bar popup" : "Open as a window on your desktop: it tiles like any app"
            MouseArea {
              id: windowMouse
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setDetached(!root.detached)
              onContainsMouseChanged: root.hint = containsMouse ? windowToggle.hintText : (root.hint === windowToggle.hintText ? "" : root.hint)
            }
          }
          Text {
            textFormat: Text.PlainText
            id: masteredCount
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.baseline: heading.baseline
            text: root.mastered + " of " + root.total + " mastered"
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
        Item {
          width: parent.width
          height: Style.space(16)
          Rectangle {
            x: Style.space(8)
            width: parent.width - Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(6)
            radius: height / 2
            color: root.faint
            Rectangle {
              height: parent.height
              radius: parent.radius
              color: root.accent
              width: root.total > 0 ? parent.width * root.mastered / root.total : 0
              Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }
          }
        }

        Item { width: 1; height: Style.space(14) }
        // Tabs: new lessons, and check-ins that are due.
        Row {
          x: Style.space(8)
          height: Style.space(22)
          spacing: Style.space(18)
          Repeater {
            model: [
              { key: "learn", label: "UP NEXT", count: 0 },
              { key: "review", label: "REVIEW", count: root.reviewItems.length }
            ]
            delegate: Item {
              required property var modelData
              readonly property bool active: root.tab === modelData.key
              width: tabLabel.implicitWidth
              height: parent.height
              Text {
                textFormat: Text.PlainText
                id: tabLabel
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label + (modelData.count > 0 ? "  " + modelData.count : "")
                color: parent.active ? root.fg : (tabMouse.containsMouse ? root.fg : root.dim)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }
              // A dot when reviews are waiting.
              Rectangle {
                visible: modelData.count > 0
                width: Style.space(6); height: width; radius: width / 2
                color: root.accent
                anchors.left: tabLabel.right
                anchors.leftMargin: Style.space(4)
                anchors.top: tabLabel.top
              }
              Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Math.max(1, Style.space(2))
                radius: height / 2
                color: root.accent
                opacity: parent.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
              }
              MouseArea {
                id: tabMouse
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showTab(modelData.key)
              }
            }
          }
        }
        Item { width: 1; height: Style.space(6) }

        // Six slots, always, on both tabs: the list never changes height as
        // rows come and go or as you switch tabs.
        Item {
          width: parent.width
          height: root.batch * root.rowHeight

          // Review: one flash card at a time.
          Item {
            id: reviewArea
            anchors.fill: parent
            anchors.margins: Style.space(8)
            visible: root.tab === "review"

            Flipable {
              id: reviewFlip
              anchors.fill: parent
              visible: !!root.reviewCard
              transform: Rotation {
                origin.x: reviewFlip.width / 2
                origin.y: reviewFlip.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: root.reviewFlipped ? 180 : 0
                Behavior on angle { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
              }

              front: ReviewFace {
                // Only the side facing you takes clicks.
                enabled: !root.reviewFlipped
                Column {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(24)
                  spacing: Style.space(12)
                  Text {
                    textFormat: Text.PlainText
                    text: "CARD 1 OF " + root.reviewQueue.length + (root.reviewCard ? "  ·  " + root.reviewCard.section : "")
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                  }
                  Item { width: 1; height: Style.space(10) }
                  Text {
                    textFormat: Text.PlainText
                    text: "What's the shortcut for…"
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.reviewCard ? root.reviewCard.title : ""
                    color: root.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body + 8
                    font.bold: true
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: "Think of it, or press it. Then flip the card."
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                ReviewButton {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(24)
                  label: "Show answer"
                  primary: true
                  onClicked: root.reviewFlipped = true
                }
              }

              back: ReviewFace {
                enabled: root.reviewFlipped
                Column {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(24)
                  spacing: Style.space(12)
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.reviewCard ? root.reviewCard.title : ""
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  Keys { big: true; keys: root.reviewCard ? root.reviewCard.keys : "" }
                  Repeater {
                    model: root.reviewCard && root.reviewCard.variants ? root.reviewCard.variants.slice(0, 2) : []
                    delegate: Row {
                      required property var modelData
                      spacing: Style.space(8)
                      Keys { keys: modelData.keys; anchors.verticalCenter: parent.verticalCenter }
                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: root.dim
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.reviewCard ? (root.reviewCard.why || "") : ""
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.82)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                // Grade it, or the result, in the same fixed spot.
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(24)
                  spacing: Style.space(12)
                  visible: root.reviewResult === ""
                  ReviewButton {
                    label: "Missed it"
                    sub: root.reviewCard ? root.reviewCard.missIn : ""
                    onClicked: root.gradeReview(false)
                  }
                  ReviewButton {
                    id: reviewGotIt
                    label: "Got it"
                    sub: root.reviewCard ? root.reviewCard.passIn : ""
                    primary: true
                    onClicked: root.gradeReview(true)
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  visible: root.reviewResult !== ""
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(34)
                  text: root.reviewResult
                  color: root.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body + 1
                  font.bold: true
                }
              }
            }

            // Nothing due.
            Column {
              visible: !root.reviewCard
              anchors.centerIn: parent
              spacing: Style.space(8)
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: "All caught up"
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body + 4
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Shortcuts in practice come back here when they're due."
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          ListView {
            id: upNext
            visible: root.tab === "learn"
            width: parent.width
            anchors.fill: parent
            interactive: false
            model: upNextModel
            delegate: UpNextRow {}
            remove: Transition {
              NumberAnimation { property: "opacity"; to: 0; duration: 220; easing.type: Easing.InQuad }
            }
            add: Transition {
              NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutQuad }
            }
            displaced: Transition {
              NumberAnimation { properties: "y"; duration: 280; easing.type: Easing.OutCubic }
            }
            move: Transition {
              NumberAnimation { properties: "y"; duration: 280; easing.type: Easing.OutCubic }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.tab === "learn" && upNextModel.count === 0
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.tab === "review" ? "Nothing to review right now. Flash cards come back on their own."
                : root.complete ? "Every shortcut mastered. Nicely done."
                : "No new shortcuts left. Keep going in Review."
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Item { width: 1; height: Style.space(14) }
        SectionLabel { text: "ALL SHORTCUTS" }
        Item { width: 1; height: Style.space(4) }

        // Starred shortcuts: your own cheat sheet. Open unless folded.
        ListSection {
          key: "fav"
          icon: "󰓎"
          title: "Favorites"
          items: root.favorites
        }

        // Shortcuts in practice, next check-in first. Folded by default.
        ListSection {
          id: practiceList
          key: "practice"
          icon: "󰥔"
          title: "In practice"
          items: root.inPractice
          openByDefault: false
        }

        Repeater {
          model: root.sections
          delegate: Column {
            id: section
            required property var modelData
            readonly property bool open: !!root.expanded[modelData.level]
            readonly property bool finished: modelData.done === modelData.total
            width: column.width

            Item {
              width: parent.width
              height: Style.space(32)
              Rectangle {
                anchors.fill: parent
                radius: Style.space(6)
                color: headerMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05) : "transparent"
              }
              MouseArea {
                id: headerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleSection(section.modelData.level)
              }
              Text {
                textFormat: Text.PlainText
                id: chevron
                x: Style.space(10)
                width: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                rotation: section.open ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 160 } }
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.body + 2
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                x: Style.space(30)
                anchors.verticalCenter: parent.verticalCenter
                text: (section.modelData.icon ? section.modelData.icon + "  " : "") + section.modelData.name
                color: section.finished ? root.accent : root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
              // Tick the whole section, for shortcuts you already know.
              Link {
                visible: section.open && !section.finished
                anchors.right: count.left
                anchors.rightMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: "I know these"
                font.pixelSize: Style.font.caption
                onClicked: root.run(["done-section", String(section.modelData.level)])
              }
              Text {
                textFormat: Text.PlainText
                id: count
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(44)
                horizontalAlignment: Text.AlignRight
                text: section.finished ? "✓ " + section.modelData.total : section.modelData.done + "/" + section.modelData.total
                color: section.finished ? root.accent : root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: section.finished
              }
            }

            Repeater {
              model: section.open ? section.modelData.items : []
              delegate: SectionRow {}
            }
          }
        }

      }
    }

    // Status line, pinned under the scrolling content at a fixed height,
    // so hints and Undo never move anything and are always in view.
    Item {
      id: statusLine
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(42)
      Rectangle { x: Style.space(8); width: parent.width - Style.space(16); height: 1; color: root.faint }
      Item {
        y: Style.space(4)
        width: parent.width
        height: Style.space(38)

              // What the hovered control does.
              Text {
                textFormat: Text.PlainText
                visible: root.hint !== ""
                x: Style.space(8)
                width: parent.width - Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.hint
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              // Undo for the last "know it", in case it was a slip.
              Item {
                anchors.fill: parent
                visible: root.hint === "" && root.undoTitle !== ""
                Text {
                  textFormat: Text.PlainText
                  x: Style.space(8)
                  width: undoLink.x - x - Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: "✓ Marked “" + root.undoTitle + "” as known"
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Link {
                  id: undoLink
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Undo"
                  strong: true
                  onClicked: {
                    if (!root.undoArgs) return
                    root.run(root.undoArgs)
                    root.undoTitle = ""
                  }
                }
              }

              // Practice status, and pause for meetings.
              Item {
                anchors.fill: parent
                visible: root.hint === "" && root.undoTitle === "" && (root.practicing > 0 || root.paused)
                Text {
                  textFormat: Text.PlainText
                  x: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰥔 " + root.practicing + " in practice · check-ins " + (root.paused ? "paused" : "on")
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Link {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.paused ? "Resume" : "Pause"
                  onClicked: root.run(["pause", root.paused ? "off" : "on"])
                }
              }
            }

      }

    // Section-complete banner, floating over the header.
    Rectangle {
      z: 20
      x: Style.space(4)
      y: Style.space(2)
      width: parent.width - Style.space(8)
      height: Style.space(44)
      radius: Style.space(8)
      visible: opacity > 0
      opacity: root.bannerText !== "" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 220 } }
      color: Commons.Color.popups.background
      border.color: root.accent
      border.width: Math.max(1, Style.space(2))
      MouseArea { anchors.fill: parent; enabled: parent.visible }
      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
      }
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.bannerText
        color: root.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body + 2
        font.bold: true
      }
    }

    // How practice works, the first time someone presses Practice.
    Rectangle {
      id: introLayer
      z: 30
      anchors.fill: parent
      visible: opacity > 0
      opacity: root.showIntro ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 200 } }
      color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g,
                     Commons.Color.popups.background.b, 0.88)
      MouseArea { anchors.fill: parent; enabled: introLayer.visible }

      Rectangle {
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        height: introText.implicitHeight + Style.space(36)
        radius: Style.space(10)
        color: Commons.Color.popups.background
        border.color: root.accent
        border.width: Math.max(1, Style.space(2))
        Column {
          id: introText
          x: Style.space(18)
          y: Style.space(18)
          width: parent.width - Style.space(36)
          spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            text: "󰥔  How practice works"
            color: root.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 2
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Try the shortcut once now; it then moves to In practice and comes back as a quick check-in while you work: after 10 minutes, 1 hour, 1 day, 4 days, 2 weeks and 6 weeks."
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.25
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Each time you recall a shortcut just as it starts to fade, the memory lasts longer, so check-ins get further apart. Recalling beats re-reading, and a night's sleep helps it stick."
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.25
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Remember it and the next gap is longer. Forget, and it comes back sooner. Pass all six and it's locked in. Check-ins wait for a pause in your typing: at most one every 15 minutes, 8 a day."
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.25
          }
          Item { width: 1; height: Style.space(2) }
          Link {
            text: "The science behind it ›"
            strong: true
            onClicked: root.detail = root.method
          }
          Pill {
            label: "Got it"
            primary: true
            onClicked: { root.showIntro = false; root.run(["intro-seen"]) }
          }
        }
      }
    }

    // First open: set up a practice desktop. Four tiled terminals on an
    // empty desktop give every lesson something to act on, nothing to click
    // instead of the shortcut, and nothing real to rearrange.
    Rectangle {
      id: setupLayer
      z: 32
      anchors.fill: parent
      visible: opacity > 0
      opacity: root.showSetup ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 200 } }
      color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g,
                     Commons.Color.popups.background.b, 0.88)
      MouseArea { anchors.fill: parent; enabled: setupLayer.visible }

      Rectangle {
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        height: setupText.implicitHeight + Style.space(40)
        radius: Style.space(10)
        color: Commons.Color.popups.background
        border.color: root.accent
        border.width: Math.max(1, Style.space(2))
        Column {
          id: setupText
          x: Style.space(20)
          y: Style.space(20)
          width: parent.width - Style.space(40)
          spacing: Style.space(12)
          // The hook first: what this is built on, in two lines.
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Learn shortcuts with a method backed by science"
            color: root.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 3
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "A few shortcuts at a time, then quick check-ins spaced out just as each one starts to fade, so it sticks for good. It's built on decades of memory research."
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.3
          }
          Link {
            text: "The science behind it ›"
            strong: true
            onClicked: root.detail = root.method
          }
          Rectangle { width: parent.width; height: 1; color: root.faint }
          Text {
            textFormat: Text.PlainText
            text: "First, set up a practice desktop"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 1
            font.bold: true
          }
          Repeater {
            model: [
              { n: "1", keys: root.setupKeys.desktop, text: "Go to an empty desktop." },
              { n: "2", keys: root.setupKeys.terminal, text: "Press it 4 times: four tiled terminals." }
            ]
            delegate: Row {
              id: step
              required property var modelData
              spacing: Style.space(10)
              Text {
                textFormat: Text.PlainText
                width: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.n
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Keys { id: stepKeys; keys: modelData.keys.toUpperCase(); anchors.verticalCenter: parent.verticalCenter }
              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                width: setupText.width - Style.space(14) - stepKeys.width - Style.space(20)
                wrapMode: Text.WordWrap
                text: modelData.text
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Try every lesson there. Four windows give each shortcut something to act on, terminals have nothing to click instead of the keys, and nothing on your real desktops gets moved."
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.82)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.3
          }
          Pill {
            label: "I'm set"
            primary: true
            onClicked: root.dismissSetup()
          }
        }
      }
    }

    // The longer explanation for one lesson (the ⓘ button).
    Rectangle {
      id: detailLayer
      z: 35
      anchors.fill: parent
      visible: opacity > 0
      opacity: root.detail ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 180 } }
      color: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g,
                     Commons.Color.popups.background.b, 0.88)
      // Kept while fading out, so the card doesn't empty mid-fade.
      property var shown: null
      Connections {
        target: root
        function onDetailChanged() { if (root.detail) detailLayer.shown = root.detail }
      }
      MouseArea {
        anchors.fill: parent
        enabled: detailLayer.visible
        onClicked: root.detail = null
      }

      Rectangle {
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        height: Math.min(parent.height - Style.space(24), detailText.implicitHeight + Style.space(36))
        radius: Style.space(10)
        color: Commons.Color.popups.background
        border.color: root.accent
        border.width: Math.max(1, Style.space(2))
        MouseArea { anchors.fill: parent }  // clicks inside don't close it

        // Scrolls when a long explanation doesn't fit.
        Flickable {
          anchors.fill: parent
          anchors.margins: Style.space(18)
          contentWidth: width
          contentHeight: detailText.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

        Column {
          id: detailText
          width: parent.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            height: Math.max(detailKeys.height, detailTitle.implicitHeight)
            Keys {
              id: detailKeys
              visible: keys !== ""
              keys: detailLayer.shown ? detailLayer.shown.keys : ""
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              textFormat: Text.PlainText
              id: detailTitle
              x: detailKeys.visible ? detailKeys.width + Style.space(10) : 0
              width: parent.width - x - Style.space(24)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: detailLayer.shown ? detailLayer.shown.title : ""
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body + 2
              font.bold: true
            }
            Link {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "✕"
              font.pixelSize: Style.font.body
              onClicked: root.detail = null
            }
          }

          Repeater {
            model: detailLayer.shown && detailLayer.shown.more ? detailLayer.shown.more.split("\n\n") : []
            delegate: Text {
              required property string modelData
              required property int index
              width: detailText.width
              wrapMode: Text.WordWrap
              // Bold only for our own methodology card; lesson text stays plain.
              textFormat: detailLayer.shown === root.method ? Text.StyledText : Text.PlainText
              text: modelData
              color: index === 0 ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.82)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              lineHeight: 1.3
            }
          }
        }
        }
      }
    }

    // Confetti flies over everything.
    Item {
      id: confettiLayer
      z: 40
      anchors.fill: parent
    }
  }

  // A normal window on the desktop: it tiles, takes the highlight like any
  // other window, and closes with Super + W (back to the bar popup).
  FloatingWindow {
    id: coachWindow
    visible: false
    title: "Shortcut Coach"
    implicitWidth: Style.space(700)
    implicitHeight: Style.space(940)
    color: Commons.Color.popups.background
    onVisibleChanged: if (!visible && root.detached) { root.detached = false; root.run(["window", "off"]) }
  }
}
