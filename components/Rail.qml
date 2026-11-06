import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../Podbox.js" as Podbox

// Scrollable environment list: status dot, name, state word. Selection is
// clamped at the ends; the panel's PanelKeyCatcher drives it with Up/Down.
//
// The selection is drawn once, as a marker that glides between rows, so
// selection changes never rebuild delegates.
Item {
  id: root

  property var envs: []
  property string selectedName: ""
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  signal picked(string name)

  implicitHeight: listView.implicitHeight

  readonly property real rowHeight: Style.space(48)
  readonly property real rowStep: Style.space(48) + Style.space(2)
  readonly property int selectedIndex: {
    var list = root.envs || [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].name === root.selectedName) return i;
    }
    return -1;
  }

  // Keep the selected row on screen when the keyboard moves the selection.
  onSelectedIndexChanged: {
    if (root.selectedIndex < 0) return;
    var top = root.selectedIndex * root.rowStep;
    var bottom = top + root.rowHeight;
    if (top < listView.contentY) listView.contentY = top;
    else if (bottom > listView.contentY + listView.height)
      listView.contentY = bottom - listView.height;
  }

  Flickable {
    id: listView
    anchors.fill: parent
    anchors.margins: 0
    contentWidth: width
    contentHeight: railContent.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Item {
      id: railContent
      width: listView.width
      height: railColumn.implicitHeight

      // One selection marker that glides between rows.
      Rectangle {
        visible: root.selectedIndex >= 0
        y: Math.max(0, root.selectedIndex) * root.rowStep
        width: parent.width
        height: root.rowHeight
        radius: Style.cornerRadius
        color: Util.alpha(root.foreground, 0.12)
        border.width: Style.space(2)
        border.color: root.accent

        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      }

      Column {
        id: railColumn
        width: railContent.width
        spacing: Style.space(2)

        Repeater {
          model: root.envs

          Rectangle {
            id: row
            required property string name
            required property string status

            readonly property string stateWord: Podbox.stateWord(row.status)

            width: railColumn.width
            height: root.rowHeight
            radius: Style.cornerRadius
            color: rowMouse.containsMouse
              ? Util.alpha(root.foreground, 0.06) : "transparent"

            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

            StatusDot {
              id: dot
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              status: row.status
            }

            Column {
              id: labels
              anchors.left: dot.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: row.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: row.stateWord
                color: Util.alpha(root.foreground, 0.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.picked(row.name)
            }
          }
        }
      }
    }
  }
}
