import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Podbox.js" as Podbox

// Selected-environment card: OS-derived gradient, tilted pill decoration,
// name, accent subtitle, quiet status line, and the primary action button.
Item {
  id: root

  property string name: ""
  property string subtitle: ""
  property string status: "stopped"
  property string statusLine: ""
  property string primaryLabel: ""
  property bool primaryEnabled: false
  property bool primaryUrgent: false
  property color heroStart: Podbox.heroColors("").start
  property color heroEnd: Podbox.heroColors("").end
  property color heroAccent: Podbox.heroColors("").accent
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property string iconFontFamily: root.fontFamily

  signal primaryClicked()

  readonly property bool failed: root.status === "failed"
  readonly property bool running: root.status === "running"
  readonly property color statusColor: root.failed
    ? Commons.Color.urgent
    : (root.running ? Commons.Color.accent : Util.alpha(root.foreground, 0.45))
  // statusLine arrives as "● Running · …"; the bullet is replaced by the dot.
  readonly property string lineText: root.statusLine.replace(/^●\s*/, "")

  // The card recolours smoothly when another environment is picked.
  Behavior on heroStart { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
  Behavior on heroEnd { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
  Behavior on heroAccent { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }

  onNameChanged: swap.restart()

  NumberAnimation {
    id: swap
    targets: [heroLabels, statusRow]
    property: "opacity"
    from: 0
    to: 1
    duration: 240
    easing.type: Easing.OutCubic
  }

  implicitHeight: Style.space(118)
  clip: true

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    gradient: Gradient {
      orientation: Gradient.Vertical
      GradientStop { position: 0; color: root.heroStart }
      GradientStop { position: 1; color: root.heroEnd }
    }
  }

  // Light from the right: a soft accent wash over the base gradient.
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 1.0; color: Util.alpha(root.heroAccent, 0.16) }
    }
  }

  // Scrim under the status line so it stays readable on any OS colour.
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    gradient: Gradient {
      orientation: Gradient.Vertical
      GradientStop { position: 0.45; color: "transparent" }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.28) }
    }
  }

  // Hairline edge so the card reads as one surface.
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
  }

  // Faint tilted pill at the top right, split by a thin gap (the logo shape).
  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: -Style.space(26)
    anchors.rightMargin: Style.space(22)
    width: Style.space(84)
    height: Style.space(170)
    rotation: 18
    opacity: 0.07

    Rectangle {
      width: parent.width
      height: (parent.height - Style.space(8)) / 2
      topLeftRadius: width / 2
      topRightRadius: width / 2
      color: "white"
    }

    Rectangle {
      y: (parent.height + Style.space(8)) / 2
      width: parent.width
      height: (parent.height - Style.space(8)) / 2
      bottomLeftRadius: width / 2
      bottomRightRadius: width / 2
      color: "white"
    }
  }

  Column {
    id: heroLabels
    anchors.left: parent.left
    anchors.leftMargin: Style.space(18)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(140)
    anchors.top: parent.top
    anchors.topMargin: Style.space(16)
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: root.name
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: root.subtitle
      color: root.heroAccent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      font.letterSpacing: 1.6
      elide: Text.ElideRight
    }
  }

  Row {
    id: statusRow
    anchors.left: parent.left
    anchors.leftMargin: Style.space(18)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(18)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(14)
    spacing: Style.space(9)

    Rectangle {
      id: statusDot
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(9)
      height: Style.space(9)
      radius: width / 2
      color: root.statusColor

      // A soft pulse while the environment runs; static otherwise.
      SequentialAnimation on opacity {
        running: root.running
        loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: 1100; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(18)
      text: root.lineText
      color: root.failed ? Commons.Color.urgent : root.foreground
      opacity: root.failed ? 1 : 0.85
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      fontSizeMode: Text.HorizontalFit
      minimumPixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  TileButton {
    id: primaryButton
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    text: root.primaryLabel
    foreground: root.foreground
    accent: root.primaryUrgent ? Commons.Color.urgent : Commons.Color.accent
    fontFamily: root.fontFamily
    enabled: root.primaryEnabled
    onClicked: root.primaryClicked()
  }
}
