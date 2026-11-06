import QtQuick
import qs.Commons

// A status dot only. The state word lives beside it in the rail; the dot is
// colour, not another label.
Rectangle {
  id: root

  property string status: "stopped"
  property real dotSize: Style.space(7)

  readonly property color dotColor: {
    if (root.status === "running") return Color.accent
    if (root.status === "failed") return Color.urgent
    if (root.status === "unbuilt") return Util.alpha(Color.muted, 0.45)
    return Util.alpha(Color.muted, 0.8)
  }

  width: root.dotSize
  height: root.dotSize
  radius: root.dotSize / 2
  color: root.dotColor
}
