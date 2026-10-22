import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Shortcut Coach check-ins. While you're at the computer, it asks the script
// whether a shortcut in practice is due. If one is, a flash card slides in
// under the bar: "What's the shortcut for ...?" with Show answer. It flips
// to the keys, and you grade yourself: Missed it or Got it, each showing when
// the card comes back (the show-then-grade flow of Anki and similar). It waits for a pause in your typing (interruptions at a natural break
// cost the least), never takes keyboard focus, skips fullscreen apps and
// time away, and leaves at least 15 minutes between check-ins; the script
// caps them at 8 a day. After login, unlock or time away it waits 10 minutes
// of work before the first one. Ignoring it asks again in 15 minutes.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string cli: String(Qt.resolvedUrl("shortcut-coach")).replace("file://", "")
  // Development: a `.preview` file in the plugin folder points the card at a
  // scratch state file and skips the waits, so it can be seen on demand.
  property bool preview: false
  readonly property var cliEnv: preview
      ? ({ "SHORTCUT_COACH_STATE": Quickshell.env("HOME") + "/.local/state/omarchy-shortcut-coach-preview.json" }) : ({})
  readonly property int gapMs: preview ? 0 : 15 * 60 * 1000
  // After logging in, unlocking or coming back from away, settle in first.
  readonly property int settleMs: preview ? 0 : 10 * 60 * 1000
  property real activeSince: Date.now()
  readonly property int lingerMs: 45 * 1000

  property var item: null
  property bool showing: false
  property bool revealed: false
  property string message: ""
  property real lastShown: 0
  // Away from the computer: no check-ins.
  property bool idle: idleMonitor.isIdle
  // A few seconds without input: a natural pause to ask in.
  property bool paused: pauseMonitor.isIdle

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property color accent: Commons.Color.accent

  function check() {
    if (showing || idle || !paused || dueProc.running) return
    if (Date.now() - lastShown < gapMs) return
    if (Date.now() - activeSince < settleMs) return
    dueProc.running = true
  }

  function show(next) {
    item = next
    revealed = false
    message = ""
    showing = true
    lastShown = Date.now()
    linger.restart()
  }

  // Record an answer; the script replies with when it comes back.
  function answer(result) {
    if (answerProc.running) return
    linger.stop()
    answerProc.command = [root.cli, "checkin", item.id, result]
    answerProc.running = true
  }

  function hide() {
    showing = false
    linger.stop()
  }

  Process {
    running: true
    command: ["test", "-f", String(Qt.resolvedUrl(".preview")).replace("file://", "")]
    onExited: function(code) { root.preview = code === 0 }
  }

  IdleMonitor {
    id: idleMonitor
    timeout: 120
    respectInhibitors: false
    // Back from away (or from the lock screen): start the settling-in clock.
    onIsIdleChanged: if (!isIdle) root.activeSince = Date.now()
  }

  IdleMonitor {
    id: pauseMonitor
    timeout: 4
    respectInhibitors: false
    onIsIdleChanged: if (isIdle) root.check()
  }

  Timer {
    interval: 60 * 1000
    repeat: true
    running: true
    onTriggered: root.check()
  }

  // The first look shortly after login.
  Timer {
    interval: 30 * 1000
    running: true
    onTriggered: root.check()
  }

  // Unanswered: ask again in a bit, without moving it a step.
  Timer {
    id: linger
    interval: root.lingerMs
    onTriggered: {
      if (card.hovered) { restart(); return }
      root.answer("skip")
    }
  }

  Timer {
    id: closeAfterMessage
    interval: 2400
    onTriggered: root.hide()
  }

  // Due check, skipped while a fullscreen window (a call, a video) has focus.
  Process {
    id: dueProc
    environment: root.cliEnv
    command: ["sh", "-c", "hyprctl activewindow -j 2>/dev/null | grep -q '\"fullscreen\": 2' && echo '{}' || exec \"$0\" due --json", root.cli]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next
        try { next = JSON.parse(text) } catch (e) { return }
        if (next && next.id) root.show(next)
      }
    }
  }

  Process {
    id: answerProc
    environment: root.cliEnv
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = String(text || "").trim()
        var result = answerProc.command[3]
        if (result === "skip") { root.hide(); return }
        if (result === "fail") root.message = "No problem. It comes back in 10 minutes."
        else root.message = reply === "locked in" ? "🔒  Locked in. That one's yours."
                                                  : "Nice. It comes back " + reply.replace("back ", "") + "."
        closeAfterMessage.restart()
      }
    }
  }

  // The keys as keycaps: [SUPER] [SHIFT] [1-9]; a menu path stays one cap.
  function keyCaps(keys) {
    var text = String(keys || "").trim()
    if (text === "") return []
    if (text.indexOf("›") !== -1 || text.indexOf(" + ") === -1) return [text]
    var plus = text.indexOf(" + ")
    return text.slice(0, plus).split(/\s+/).filter(function(m) { return m !== "" }).concat([text.slice(plus + 3)])
  }

  component Caps: Row {
    id: caps
    property string keys: ""
    property bool big: false
    spacing: Style.space(big ? 6 : 4)
    Repeater {
      model: root.keyCaps(caps.keys)
      delegate: Rectangle {
        required property string modelData
        width: capText.implicitWidth + Style.space(caps.big ? 18 : 10)
        height: capText.implicitHeight + Style.space(caps.big ? 12 : 6)
        radius: Style.space(caps.big ? 6 : 4)
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
        Rectangle {
          anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
          anchors.leftMargin: parent.radius; anchors.rightMargin: parent.radius
          height: Math.max(1, Style.space(caps.big ? 2 : 1))
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
        }
        Text {
          textFormat: Text.PlainText
          id: capText
          anchors.centerIn: parent
          text: modelData
          color: root.accent
          font.family: Style.font.family
          font.pixelSize: caps.big ? Style.font.body + 6 : Style.font.bodySmall
          font.bold: true
        }
      }
    }
  }

  component CardButton: Rectangle {
    id: btn
    property string label: ""
    property string sub: ""
    property bool primary: false
    signal clicked()
    width: Math.max(Style.space(120), btnRow.implicitWidth + Style.space(28))
    height: Style.space(36)
    radius: Style.space(8)
    color: primary ? (btnMouse.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent)
                   : (btnMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10) : "transparent")
    border.color: primary ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
    border.width: Math.max(1, Style.space(1))
    Behavior on color { ColorAnimation { duration: 120 } }
    Row {
      id: btnRow
      anchors.centerIn: parent
      spacing: Style.space(8)
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: btn.label
        color: btn.primary ? Commons.Color.popups.background : root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: btn.primary
      }
      // When it comes back if you pick this.
      Text {
        textFormat: Text.PlainText
        visible: btn.sub !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: btn.sub
        color: btn.primary ? Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g,
                                     Commons.Color.popups.background.b, 0.7)
                           : root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }

  // One face of the flash card: same size both sides, so flipping never
  // moves anything under the pointer.
  component Face: Rectangle {
    anchors.fill: parent
    radius: Math.max(Style.space(12), Style.cornerRadius)
    color: Commons.Color.popups.background
    border.color: Commons.Color.popups.border
    border.width: Math.max(1, Style.space(2))
    antialiasing: true
  }

  component Kicker: Item {
    width: parent ? parent.width : 0
    height: kickerText.implicitHeight
    Text {
      textFormat: Text.PlainText
      id: kickerText
      text: "FLASH CARD" + (root.item ? "  ·  " + root.item.section : "")
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }
    // One dot per check-in; filled ones are passed.
    Row {
      anchors.right: closeX.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
      Repeater {
        model: root.item ? root.item.steps : 0
        Rectangle {
          required property int index
          width: Style.space(7); height: width; radius: width / 2
          color: index < root.item.stage ? root.accent : "transparent"
          border.color: index <= root.item.stage ? root.accent : root.dim
          border.width: Math.max(1, Style.space(1))
        }
      }
    }
    Text {
      textFormat: Text.PlainText
      id: closeX
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "✕"
      color: closeMouse.containsMouse ? root.fg : root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      MouseArea {
        id: closeMouse
        anchors.fill: parent
        anchors.margins: -Style.space(6)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.message !== "" ? root.hide() : root.answer("skip")
      }
    }
  }

  PanelWindow {
    id: window
    visible: root.showing || card.opacity > 0
    anchors { top: true; right: true }
    margins { top: Style.space(10); right: Style.space(12) }
    implicitWidth: Style.space(420)
    implicitHeight: Style.space(250)
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "shortcut-coach-checkin"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
      id: card
      property bool hovered: cardHover.hovered
      anchors.fill: parent
      opacity: root.showing ? 1 : 0
      transform: Translate { x: root.showing ? 0 : Style.space(40) }
      Behavior on opacity { NumberAnimation { duration: 220 } }
      HoverHandler { id: cardHover }

      // The card turns over to show the answer.
      Flipable {
        id: flip
        anchors.fill: parent
        property bool flipped: root.revealed
        transform: Rotation {
          id: turn
          origin.x: flip.width / 2
          origin.y: flip.height / 2
          axis { x: 0; y: 1; z: 0 }
          angle: flip.flipped ? 180 : 0
          Behavior on angle { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
        }

        // Front: the question.
        front: Face {
          // Only the side facing you takes clicks.
          enabled: !root.revealed
          Column {
            anchors.fill: parent
            anchors.margins: Style.space(20)
            spacing: Style.space(10)
            Kicker {}
            Item { width: 1; height: Style.space(6) }
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
              maximumLineCount: 2
              elide: Text.ElideRight
              text: root.item ? root.item.title : ""
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body + 6
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: "Think of it, or press it, then flip the card."
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
          CardButton {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(20)
            label: "Show answer"
            primary: true
            onClicked: { root.revealed = true; linger.restart() }
          }
        }

        // Back: the answer, and how it went.
        back: Face {
          enabled: root.revealed
          Column {
            anchors.fill: parent
            anchors.margins: Style.space(20)
            spacing: Style.space(10)
            Kicker {}
            Text {
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              text: root.item ? root.item.title : ""
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Caps { big: true; keys: root.item ? root.item.keys : "" }
            // Paired keys, if the lesson has them.
            Repeater {
              model: root.item && root.item.variants ? root.item.variants.slice(0, 2) : []
              delegate: Row {
                required property var modelData
                spacing: Style.space(8)
                Caps { keys: modelData.keys; anchors.verticalCenter: parent.verticalCenter }
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
          // Grade it, or the result once graded, in the same fixed slot.
          Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(20)
            height: Style.space(36)
            Row {
              spacing: Style.space(10)
              visible: root.message === ""
              enabled: !answerProc.running
              CardButton {
                label: "Missed it"
                sub: root.item ? root.item.missIn : ""
                onClicked: root.answer("fail")
              }
              CardButton {
                label: "Got it"
                sub: root.item ? root.item.passIn : ""
                primary: true
                onClicked: root.answer("pass")
              }
            }
            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              visible: root.message !== ""
              elide: Text.ElideRight
              text: root.message
              color: root.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }
        }
      }
    }
  }
}
