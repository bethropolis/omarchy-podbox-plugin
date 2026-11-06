import QtQuick
import qs.Commons
import qs.Commons as Commons

// One quick-action tile: an icon above a label, with an optional count badge
// and a disabled state that never receives the click.
Item {
  id: root

  property string icon: ""
  property string label: ""
  property int badge: 0
  property bool enabled: true
  property bool emphasized: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property string iconFontFamily: root.fontFamily
  property real tileHeight: Style.space(66)

  signal clicked()

  implicitHeight: root.tileHeight
  // Press feedback: the whole tile dips a hair on click.
  scale: mouse.pressed ? 0.97 : 1
  Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

  Rectangle {
    id: background
    anchors.fill: parent
    radius: Style.cornerRadius
    color: !root.enabled
      ? Util.alpha(root.foreground, 0.025)
      : (mouse.containsMouse
        ? Style.hoverFillFor(root.foreground, root.accent)
        : Style.normalFillFor(root.foreground, root.accent))
    border.width: root.emphasized ? Style.normalBorderWidth : 0
    border.color: Util.alpha(Commons.Color.urgent, 0.55)

    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Column {
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.icon
        color: root.enabled
          ? (mouse.containsMouse ? root.accent : Util.alpha(root.foreground, 0.86))
          : Qt.darker(root.foreground, 2.0)
        font.family: root.iconFontFamily
        font.pixelSize: Style.font.heading
        // Icons pop a little on hover; they ease back with a tiny bounce.
        scale: mouse.containsMouse && root.enabled ? 1.14 : 1
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
      }

      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        color: root.enabled ? root.foreground : Qt.darker(root.foreground, 2.0)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Rectangle {
      visible: root.badge > 0
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      width: Math.max(Style.space(15), badgeText.implicitWidth + Style.space(7))
      height: Style.space(15)
      radius: height / 2
      color: root.accent

      Text {
        id: badgeText
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: String(root.badge)
        color: Commons.Color.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }
}
