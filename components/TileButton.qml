import QtQuick
import qs.Commons
import qs.Commons as Commons

// Small button on the same surface as the quick-action tiles, so "+ New" and
// the hero's Start/Stop/Build do not look like a different toolkit.
Item {
  id: root

  property string text: ""
  property string icon: ""
  property bool enabled: true
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property string iconFontFamily: root.fontFamily
  property real buttonHeight: Style.space(34)

  signal clicked()

  implicitHeight: root.buttonHeight
  implicitWidth: content.implicitWidth + Style.space(28)
  opacity: root.enabled ? 1 : 0.4
  scale: mouse.pressed ? 0.96 : 1
  Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouse.containsMouse && root.enabled
      ? Style.hoverFillFor(root.foreground, root.accent)
      : Style.normalFillFor(root.foreground, root.accent)

    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(7)

    Text {
      visible: root.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.icon
      color: Util.alpha(root.foreground, 0.86)
      font.family: root.iconFontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.text
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
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
