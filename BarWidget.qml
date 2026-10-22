import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Shortcut Coach: a cap icon in the bar that opens a short checklist of the
// shortcuts you're learning. Checking one off marks it mastered and the next
// lesson takes its place. All reads and writes go through the
// `shortcut-coach` script next to this file, so the panel and anything that
// calls the script (you, or an agent adding lessons) share one state file.
BarWidget {
  id: root
  moduleName: "pbarnhill.shortcut-coach"

  readonly property string cli: String(Qt.resolvedUrl("shortcut-coach")).replace("file://", "")
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy-shortcut-coach.json"

  property bool opened: false
  property bool popoutSwitchClosing: false
  property bool showMastered: false
  property var learning: []
  property var mastered: []
  property int batch: 6
  property int level: 0
  property int levels: 0
  property string levelName: ""
  property int levelDone: 0
  property int levelTotal: 0
  property bool complete: false
  property int total: 0
  // Set when a refresh lands on a higher level than before.
  property string levelUpText: ""
  readonly property var current: learning.slice(0, batch)

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property color accent: Commons.Color.accent

  function open() { opened = true; refresh() }
  function close() { opened = false; showMastered = false }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }
  function toggle() { opened ? close() : open() }

  // A big burst across the top of the panel and a banner for a new level.
  function celebrateLevel() {
    root.levelUpText = root.complete ? "🏆  Shortcut Master!" : "🎉  Level " + root.level + " unlocked: " + root.levelName
    levelUpTimer.restart()
    for (var k = 0; k < 5; k++)
      root.burst(confettiLayer, confettiLayer.width * (k + 0.5) / 5, Style.space(20))
  }

  Timer {
    id: levelUpTimer
    interval: 4000
    onTriggered: root.levelUpText = ""
  }

  function refresh() {
    listProc.running = false
    listProc.running = true
  }

  function run(args) {
    Quickshell.execDetached([root.cli].concat(args))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  Process {
    id: listProc
    command: [root.cli, "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          var before = root.level
          var wasComplete = root.complete
          root.batch = data.batch || 6
          root.levels = data.levels || 0
          root.levelName = data.levelName || ""
          root.levelDone = data.levelDone || 0
          root.levelTotal = data.levelTotal || 0
          root.complete = !!data.complete
          root.total = data.total || 0
          root.level = data.level || 0
          root.learning = data.learning || []
          root.mastered = data.mastered || []
          if (before > 0 && root.opened && (root.level > before || (root.complete && !wasComplete)))
            root.celebrateLevel()
        } catch (e) {}
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
    tooltipText: root.opened ? "" : (root.complete ? "Shortcut Coach · all levels complete" : "Shortcut Coach · Level " + root.level + ": " + root.levelName)
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
    readonly property bool mastered: !!item.mastered
    // Checked in the panel and celebrating; saved once the animation ends.
    property bool celebrating: false
    readonly property bool done: mastered || celebrating
    property real collapse: 1
    width: parent ? parent.width : 0
    height: (Math.max(box.height, textCol.implicitHeight) + Style.space(14)) * collapse
    clip: collapse < 1

    function check() {
      if (celebrating) return
      if (mastered) { root.run(["undo", item.id]); return }
      celebrating = true
      var p = box.mapToItem(confettiLayer, box.width / 2, box.height / 2)
      root.burst(confettiLayer, p.x, p.y)
      celebration.start()
    }

    SequentialAnimation {
      id: celebration
      NumberAnimation { target: strike; property: "width"; from: 0; to: titleText.implicitWidth; duration: 320; easing.type: Easing.OutCubic }
      PauseAnimation { duration: 1100 }
      ParallelAnimation {
        NumberAnimation { target: lesson; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
        NumberAnimation { target: lesson; property: "collapse"; to: 0; duration: 420; easing.type: Easing.InOutQuad }
      }
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
      width: Style.space(18); height: width
      radius: Style.space(4)
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      color: lesson.done ? root.accent : "transparent"
      border.color: lesson.done ? root.accent : root.dim
      border.width: Math.max(1, Style.space(2))
      scale: lesson.celebrating ? 1.0 : 1.0
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
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    Column {
      id: textCol
      anchors.left: box.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Row {
        spacing: Style.space(10)
        Rectangle {
          width: keysText.implicitWidth + Style.space(12)
          height: keysText.implicitHeight + Style.space(4)
          radius: Style.space(4)
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, lesson.mastered ? 0.08 : 0.16)
          Text {
            id: keysText
            anchors.centerIn: parent
            text: lesson.item.keys || ""
            color: lesson.mastered ? root.dim : root.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }
        Text {
          id: titleText
          anchors.verticalCenter: parent.verticalCenter
          text: lesson.item.title || ""
          color: lesson.done ? root.dim : root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
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
        visible: !lesson.mastered && (lesson.item.why || "") !== ""
        text: lesson.item.why || ""
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
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(820))

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
              text: root.complete ? "Shortcut Master" : "Level " + root.level + " · " + root.levelName
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body + 2
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.baseline: title.baseline
              text: root.complete ? root.total + " of " + root.total + " mastered"
                                  : root.levelDone + " of " + root.levelTotal + " · level " + root.level + " of " + root.levels
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          // Progress through the current level.
          Item {
            width: parent.width
            height: Style.space(14)
            Rectangle {
              id: track
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
                width: root.complete ? parent.width
                     : root.levelTotal > 0 ? parent.width * root.levelDone / root.levelTotal : 0
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
              }
            }
          }

          // Level-up banner.
          Rectangle {
            width: parent.width
            height: visible ? levelUp.implicitHeight + Style.space(18) : 0
            visible: root.levelUpText !== ""
            radius: Style.space(6)
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            border.color: root.accent
            border.width: Math.max(1, Style.space(1))
            Text {
              id: levelUp
              anchors.centerIn: parent
              text: root.levelUpText
              color: root.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body + 2
              font.bold: true
            }
          }

          Repeater {
            model: root.current
            delegate: Lesson {}
          }

          Text {
            visible: root.learning.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(12)
            bottomPadding: Style.space(12)
            text: root.complete ? "Every level done. You've mastered Omarchy." : "All caught up. New lessons will show up here."
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Item {
            width: parent.width
            height: toggleText.implicitHeight + Style.space(14)
            visible: root.mastered.length > 0
            Text {
              id: toggleText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: (root.showMastered ? "▾ " : "▸ ") + "Mastered (" + root.mastered.length + ")"
              color: toggleMouse.containsMouse ? root.fg : root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: toggleMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showMastered = !root.showMastered
            }
          }

          Repeater {
            model: root.showMastered ? root.mastered : []
            delegate: Lesson {}
          }
        }
      }
    }
  }
}
