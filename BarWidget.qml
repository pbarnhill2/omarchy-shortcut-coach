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
          root.batch = data.batch || 6
          root.learning = data.learning || []
          root.mastered = data.mastered || []
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
    tooltipText: root.opened ? "" : "Shortcut Coach · " + root.learning.length + " to learn"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  component Lesson: Item {
    id: lesson
    required property var modelData
    readonly property var item: modelData || ({})
    property bool done: !!item.mastered
    width: parent ? parent.width : 0
    height: Math.max(box.height, textCol.implicitHeight) + Style.space(14)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent"
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
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, lesson.done ? 0.08 : 0.16)
          Text {
            id: keysText
            anchors.centerIn: parent
            text: lesson.item.keys
            color: lesson.done ? root.dim : root.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: lesson.item.title
          color: lesson.done ? root.dim : root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.strikeout: lesson.done
        }
      }
      Text {
        width: parent.width
        visible: !lesson.done && lesson.item.why !== ""
        text: lesson.item.why
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
      onClicked: root.run([lesson.done ? "undo" : "done", lesson.item.id])
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
            height: title.implicitHeight + Style.space(10)
            Text {
              id: title
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              text: "Shortcut Coach"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body + 2
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.baseline: title.baseline
              text: root.mastered.length + " mastered · " + root.learning.length + " to go"
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
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
            text: "All caught up. New lessons will show up here."
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
