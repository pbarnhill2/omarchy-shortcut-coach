import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Shortcut Coach check-ins. While you're at the computer, it asks the script
// whether a shortcut in practice is due. If one is, a small card slides in
// under the bar: "Do you remember how to ...?" with "I know it" and "Show
// me". It waits for a pause in your typing (interruptions at a natural break
// cost the least), never takes keyboard focus, skips fullscreen apps and
// time away, and leaves at least 15 minutes between check-ins; the script
// caps them at 8 a day. Ignoring it asks again in 15 minutes.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string cli: String(Qt.resolvedUrl("shortcut-coach")).replace("file://", "")
  readonly property int gapMs: 15 * 60 * 1000
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

  IdleMonitor {
    id: idleMonitor
    timeout: 120
    respectInhibitors: false
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
      if (root.revealed) root.hide()
      else root.answer("skip")
    }
  }

  Timer {
    id: closeAfterMessage
    interval: 2200
    onTriggered: root.hide()
  }

  // Due check, skipped while a fullscreen window (a call, a video) has focus.
  Process {
    id: dueProc
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
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = String(text || "").trim()
        var result = answerProc.command[3]
        if (result === "skip") { root.hide(); return }
        if (result === "fail") return  // the card stays open showing the keys
        root.message = reply === "locked in" ? "🔒  Locked in. That one's yours."
                                             : "Nice. Next check-in " + reply.replace("back ", "") + ". Each one waits longer."
        closeAfterMessage.restart()
      }
    }
  }

  component CardButton: Rectangle {
    id: btn
    property string label: ""
    property bool primary: false
    signal clicked()
    width: btnText.implicitWidth + Style.space(28)
    height: btnText.implicitHeight + Style.space(14)
    radius: Style.space(6)
    color: primary ? (btnMouse.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent)
                   : (btnMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10) : "transparent")
    border.color: primary ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
    border.width: Math.max(1, Style.space(1))
    Text {
      id: btnText
      anchors.centerIn: parent
      text: btn.label
      color: btn.primary ? Commons.Color.popups.background : root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: btn.primary
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }

  PanelWindow {
    id: window
    visible: root.showing || card.opacity > 0
    anchors { top: true; right: true }
    margins { top: Style.space(10); right: Style.space(12) }
    implicitWidth: Style.space(400)
    implicitHeight: content.implicitHeight + Style.space(36)
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "shortcut-coach-checkin"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      id: card
      property bool hovered: cardHover.hovered
      anchors.fill: parent
      radius: Math.max(Style.space(10), Style.cornerRadius)
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: Math.max(1, Style.space(2))
      opacity: root.showing ? 1 : 0
      transform: Translate { x: root.showing ? 0 : Style.space(40) }
      Behavior on opacity { NumberAnimation { duration: 220 } }

      HoverHandler { id: cardHover }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(18)
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: kicker.implicitHeight
          Text {
            id: kicker
            text: "QUICK CHECK" + (root.item ? "  ·  " + root.item.section : "")
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }
          // One dot per check-in; filled ones are passed.
          Row {
            anchors.right: close.left
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
            id: close
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
              onClicked: root.revealed || root.message !== "" ? root.hide() : root.answer("skip")
            }
          }
        }

        Text {
          width: parent.width
          text: "Do you remember how to…"
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.item ? root.item.title : ""
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body + 4
          font.bold: true
        }

        // The answer, shown after "Show me".
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.revealed
          Rectangle {
            width: keys.implicitWidth + Style.space(16)
            height: keys.implicitHeight + Style.space(8)
            radius: Style.space(5)
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            Text {
              id: keys
              anchors.centerIn: parent
              text: root.item ? root.item.keys : ""
              color: root.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body + 2
              font.bold: true
            }
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: (root.item && root.item.why ? root.item.why + " " : "") + "Try it now. It'll come back in 10 minutes."
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          width: parent.width
          visible: root.message !== ""
          wrapMode: Text.WordWrap
          text: root.message
          color: root.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Row {
          spacing: Style.space(10)
          visible: root.message === ""
          // No second answer while one is saving.
          enabled: !answerProc.running
          CardButton {
            visible: !root.revealed
            label: "I know it"
            primary: true
            onClicked: root.answer("pass")
          }
          CardButton {
            visible: !root.revealed
            label: "Show me"
            onClicked: {
              if (answerProc.running) return
              root.revealed = true
              root.answer("fail")
              linger.restart()
            }
          }
          CardButton {
            visible: root.revealed
            label: "Got it"
            primary: true
            onClicked: root.hide()
          }
        }
      }
    }
  }
}
