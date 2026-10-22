import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Shortcut Coach: a cap icon in the bar that opens a short "up next" list of
// shortcuts to learn, followed by every lesson grouped into sections. Nothing
// is locked: up next walks the sections in order (Essentials first), and any
// lesson can be checked off from its section. All reads and writes go
// through the `shortcut-coach` script next to this file, so the panel and
// anything that calls the script (you, or an agent adding lessons) share one
// state file.
BarWidget {
  id: root
  moduleName: "pbarnhill.shortcut-coach"

  readonly property string cli: String(Qt.resolvedUrl("shortcut-coach")).replace("file://", "")
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy-shortcut-coach.json"

  property bool opened: false
  property bool popoutSwitchClosing: false
  property var upNext: []
  property var sections: []
  property int batch: 6
  property int mastered: 0
  property int total: 0
  property bool complete: false
  // Which sections are unfolded, by level.
  property var expanded: ({})
  // Done counts from the last refresh, to spot a section being finished.
  property var lastDone: ({})
  property string bannerText: ""
  property int practicing: 0
  property bool paused: false
  property bool introSeen: true
  // The practice explainer, shown the first time someone presses Later.
  property bool showIntro: false
  readonly property var current: upNext.slice(0, batch)

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property color accent: Commons.Color.accent

  function open() { opened = true; refresh() }
  function close() { opened = false; showIntro = false }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }
  function toggle() { opened ? close() : open() }

  function refresh() {
    listProc.running = false
    listProc.running = true
  }

  function run(args) {
    Quickshell.execDetached([root.cli].concat(args))
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
      root.burst(confettiLayer, confettiLayer.width * (k + 0.5) / 5, Style.space(20))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  Timer {
    id: bannerTimer
    interval: 4000
    onTriggered: root.bannerText = ""
  }

  Process {
    id: listProc
    command: [root.cli, "list", "--json"]
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
        root.upNext = data.upNext || []
        root.sections = secs
        root.mastered = data.mastered || 0
        root.total = data.total || 0
        root.complete = !!data.complete
        root.practicing = data.practicing || 0
        root.paused = !!data.paused
        root.introSeen = !!data.introSeen
        if (root.opened) {
          if (root.complete && !wasComplete) root.celebrate("🏆  Shortcut Master!")
          else if (finished !== "") root.celebrate("🎉  " + finished + " complete!")
        }
        root.lastDone = done
      }
    }
  }

  // Any change to progress (from the panel or the script) reloads the list.
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
    tooltipText: root.opened ? "" : "Shortcut Coach · " + root.mastered + " of " + root.total + " mastered"
                                  + (root.practicing > 0 ? " · " + root.practicing + " in practice" : "")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }


  // One piece of confetti. It pops up from where it was thrown, drifts
  // sideways, falls under "gravity" while spinning, fades, and removes itself.
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


  component Lesson: Item {
    id: lesson
    required property var modelData
    readonly property var item: modelData || ({})
    // Up next rows show the tip and fold away once checked; section rows are
    // compact and stay put, checked.
    property bool compact: false
    readonly property bool mastered: !!item.mastered
    // Back from practice: the keys stay hidden until "Show me".
    readonly property bool checkIn: !!item.checkIn
    property bool revealed: false
    property bool celebrating: false
    readonly property bool done: mastered || celebrating
    property real collapse: 1
    width: parent ? parent.width : 0
    height: (Math.max(box.height, textCol.implicitHeight) + Style.space(compact ? 8 : 14)) * collapse
    clip: collapse < 1

    // Not sure yet: practice it with spaced check-ins.
    function later() {
      if (celebrating) return
      if (!root.introSeen) root.showIntro = true
      celebrating = true
      laterAnimation.start()
    }

    function reveal() {
      revealed = true
      root.run(["checkin", item.id, "fail"])
    }

    function check() {
      if (celebrating) return
      if (mastered) { root.run(["undo", item.id]); return }
      celebrating = true
      var p = box.mapToItem(confettiLayer, box.width / 2, box.height / 2)
      root.burst(confettiLayer, p.x, p.y)
      if (compact) compactCelebration.start()
      else celebration.start()
    }

    SequentialAnimation {
      id: celebration
      NumberAnimation { target: strike; property: "width"; from: 0; to: titleText.width; duration: 320; easing.type: Easing.OutCubic }
      PauseAnimation { duration: 1100 }
      ParallelAnimation {
        NumberAnimation { target: lesson; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
        NumberAnimation { target: lesson; property: "collapse"; to: 0; duration: 420; easing.type: Easing.InOutQuad }
      }
      ScriptAction { script: root.run(lesson.checkIn ? ["checkin", lesson.item.id, "pass"] : ["done", lesson.item.id]) }
    }

    SequentialAnimation {
      id: laterAnimation
      ParallelAnimation {
        NumberAnimation { target: lesson; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
        NumberAnimation { target: slide; property: "x"; to: Style.space(60); duration: 380; easing.type: Easing.InQuad }
        NumberAnimation { target: lesson; property: "collapse"; to: 0; duration: 420; easing.type: Easing.InOutQuad }
      }
      ScriptAction { script: root.run(["later", lesson.item.id]) }
    }

    transform: Translate { id: slide }

    SequentialAnimation {
      id: compactCelebration
      NumberAnimation { target: strike; property: "width"; from: 0; to: titleText.width; duration: 320; easing.type: Easing.OutCubic }
      PauseAnimation { duration: 700 }
      ScriptAction { script: root.run(["done", lesson.item.id]) }
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: lesson.celebrating ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
           : rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent"
      Behavior on color { ColorAnimation { duration: 200 } }
    }

    Rectangle {
      id: box
      width: Style.space(lesson.compact ? 15 : 18); height: width
      radius: Style.space(4)
      anchors.left: parent.left
      anchors.leftMargin: Style.space(lesson.compact ? 24 : 8)
      anchors.verticalCenter: parent.verticalCenter
      color: lesson.done ? root.accent : "transparent"
      border.color: lesson.done ? root.accent : root.dim
      border.width: Math.max(1, Style.space(2))
      Behavior on color { ColorAnimation { duration: 150 } }

      // A little pop when checked.
      SequentialAnimation on scale {
        running: lesson.celebrating
        NumberAnimation { to: 1.45; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { to: 1.0; duration: 260; easing.type: Easing.OutBack }
      }

      Text {
        anchors.centerIn: parent
        visible: lesson.done
        text: "✓"
        color: Commons.Color.popups.background
        font.family: Style.font.family
        font.pixelSize: lesson.compact ? Style.font.bodySmall : Style.font.body
        font.bold: true
      }
    }

    Column {
      id: textCol
      anchors.left: box.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.rightMargin: lesson.compact ? Style.space(8) : Style.space(78)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Row {
        spacing: Style.space(10)
        Rectangle {
          id: keysChip
          width: keysText.implicitWidth + Style.space(12)
          height: keysText.implicitHeight + Style.space(4)
          radius: Style.space(4)
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, lesson.mastered ? 0.08 : 0.16)
          Text {
            id: keysText
            anchors.centerIn: parent
            text: lesson.checkIn && !lesson.revealed ? "? ? ?" : (lesson.item.keys || "")
            color: lesson.mastered ? root.dim : root.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }
        Text {
          id: titleText
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, textCol.width - keysChip.width - Style.space(10))
          elide: Text.ElideRight
          text: lesson.item.title || ""
          color: lesson.done ? root.dim : root.fg
          font.family: Style.font.family
          font.pixelSize: lesson.compact ? Style.font.bodySmall : Style.font.body
          font.strikeout: lesson.mastered
          Behavior on color { ColorAnimation { duration: 300 } }

          // The strike line that draws across while celebrating.
          Rectangle {
            id: strike
            visible: lesson.celebrating
            anchors.verticalCenter: parent.verticalCenter
            width: 0
            height: Math.max(1, Style.space(2))
            color: root.fg
          }
        }
      }
      Text {
        width: parent.width
        visible: !lesson.compact && !lesson.mastered && text !== ""
        text: lesson.checkIn && !lesson.revealed
              ? "Check-in " + (lesson.item.stage + 1) + " of " + lesson.item.steps + ". Know the keys? Tick the box."
              : (lesson.item.why || "")
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: lesson.check()
    }

    // In practice, shown in its section: how far along, and the next check-in.
    Text {
      visible: lesson.compact && lesson.item.practicing && !lesson.celebrating
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: "practice " + lesson.item.stage + "/" + lesson.item.steps + (lesson.item.backIn ? " · " + lesson.item.backIn : " · now")
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    // "Later" on new lessons, "Show me" on check-ins.
    Text {
      visible: !lesson.compact && !lesson.mastered && !lesson.celebrating && !(lesson.checkIn && lesson.revealed)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: lesson.checkIn ? "Show me" : "Later"
      color: actionMouse.containsMouse ? root.accent : root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.underline: actionMouse.containsMouse
      MouseArea {
        id: actionMouse
        anchors.fill: parent
        anchors.margins: -Style.space(8)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: lesson.checkIn ? lesson.reveal() : lesson.later()
      }
    }
  }

  component SectionLabel: Text {
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
    leftPadding: Style.space(8)
    topPadding: Style.space(10)
    bottomPadding: Style.space(2)
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      // Confetti flies over the list, and can fall past the rows.
      Item {
        id: confettiLayer
        anchors.fill: parent
        z: 10
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroll.width
          spacing: Style.space(4)

          Item {
            width: parent.width
            height: title.implicitHeight + Style.space(6)
            Text {
              id: title
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              text: root.complete ? "Shortcut Master 🏆" : "Shortcut Coach"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body + 2
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.baseline: title.baseline
              text: root.mastered + " of " + root.total + " mastered"
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          // Overall progress.
          Item {
            width: parent.width
            height: Style.space(14)
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              height: Style.space(6)
              radius: height / 2
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
              Rectangle {
                height: parent.height
                radius: parent.radius
                color: root.accent
                width: root.total > 0 ? parent.width * root.mastered / root.total : 0
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
              }
            }
          }

          // Section-complete banner.
          Rectangle {
            width: parent.width
            height: visible ? bannerLabel.implicitHeight + Style.space(18) : 0
            visible: root.bannerText !== ""
            radius: Style.space(6)
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            border.color: root.accent
            border.width: Math.max(1, Style.space(1))
            Text {
              id: bannerLabel
              anchors.centerIn: parent
              text: root.bannerText
              color: root.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body + 2
              font.bold: true
            }
          }

          // How practice works, the first time someone presses Later.
          Rectangle {
            width: parent.width
            height: visible ? intro.implicitHeight + Style.space(24) : 0
            visible: root.showIntro
            radius: Style.space(6)
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
            border.width: Math.max(1, Style.space(1))
            Column {
              id: intro
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(12)
              spacing: Style.space(8)
              Text {
                text: "⏳  Practice mode"
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.body + 1
                font.bold: true
              }
              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Not sure yet? That's how it sticks. This shortcut steps aside and comes back as a quick check-in while you work: in 10 minutes, then 1 hour, 5 hours, 1 day, 5 days and 25 days."
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "This is graduated interval recall, the Pimsleur method. Each gap is about five times the last, so every check-in lands just before you'd forget. Remembering right at that edge is what moves a skill into long-term memory."
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Know it at a check-in and it moves to the next gap. Forget, and it comes back sooner. Pass all six and it's locked in. Press Later as often as you like."
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: "Got it"
                color: introMouse.containsMouse ? root.fg : root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                font.underline: introMouse.containsMouse
                MouseArea {
                  id: introMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.showIntro = false; root.run(["intro-seen"]) }
                }
              }
            }
          }

          SectionLabel { text: "UP NEXT"; visible: root.current.length > 0 }

          Repeater {
            model: root.current
            delegate: Lesson {}
          }

          Text {
            visible: root.current.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(12)
            bottomPadding: Style.space(12)
            text: root.complete ? "Every shortcut mastered. Nicely done." : "All caught up."
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          SectionLabel { text: "ALL SHORTCUTS" }

          Repeater {
            model: root.sections
            delegate: Column {
              id: section
              required property var modelData
              readonly property bool open: !!root.expanded[modelData.level]
              readonly property bool finished: modelData.done === modelData.total
              width: column.width
              spacing: Style.space(2)

              Item {
                width: parent.width
                height: sectionName.implicitHeight + Style.space(14)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(6)
                  color: headerMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent"
                }
                MouseArea {
                  id: headerMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSection(section.modelData.level)
                }
                Text {
                  id: sectionName
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (section.open ? "▾  " : "▸  ") + section.modelData.name
                  color: section.finished ? root.accent : root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                // Check off the whole section, for shortcuts you already know.
                Text {
                  visible: section.open && !section.finished
                  anchors.right: count.left
                  anchors.rightMargin: Style.space(14)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "I know these"
                  color: knowMouse.containsMouse ? root.accent : root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.underline: knowMouse.containsMouse
                  MouseArea {
                    id: knowMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.run(["done-section", String(section.modelData.level)])
                  }
                }
                Text {
                  id: count
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: section.finished ? "✓ " + section.modelData.total : section.modelData.done + "/" + section.modelData.total
                  color: section.finished ? root.accent : root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: section.finished
                }
              }

              Repeater {
                model: section.open ? section.modelData.items : []
                delegate: Lesson { compact: true }
              }
            }
          }

          // Practice status and a pause switch for meetings.
          Item {
            width: parent.width
            height: footer.implicitHeight + Style.space(18)
            visible: root.practicing > 0 || root.paused
            Text {
              id: footer
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "⏳ " + root.practicing + " in practice · check-ins " + (root.paused ? "paused" : "on")
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.paused ? "Resume" : "Pause"
              color: pauseMouse.containsMouse ? root.accent : root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.underline: pauseMouse.containsMouse
              MouseArea {
                id: pauseMouse
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.run(["pause", root.paused ? "off" : "on"])
              }
            }
          }
        }
      }
    }
  }
}
