import QtQuick
import qs.Commons

// The podbox pill, one colour: a vertical capsule split by a thin gap. The
// lower half is a touch softer so the split still reads at small sizes.
// Aspect ratio follows the brand logo (width = ~0.55 of height).
Item {
  id: root

  property real pillHeight: Style.space(18)
  property color color: Commons.Color.foreground

  implicitWidth: Math.max(4, Math.round(root.pillHeight * 0.55))
  implicitHeight: root.pillHeight

  readonly property real gap: Math.max(1, Math.round(root.pillHeight * 0.1))
  readonly property real halfHeight: (root.height - root.gap) / 2

  Rectangle {
    width: parent.width
    height: root.halfHeight
    topLeftRadius: root.width / 2
    topRightRadius: root.width / 2
    bottomLeftRadius: 0
    bottomRightRadius: 0
    color: root.color
  }

  Rectangle {
    y: root.halfHeight + root.gap
    width: parent.width
    height: root.halfHeight
    topLeftRadius: 0
    topRightRadius: 0
    bottomLeftRadius: root.width / 2
    bottomRightRadius: root.width / 2
    color: root.color
    opacity: 0.55
  }
}
