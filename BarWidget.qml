import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "components"
import "Podbox.js" as Podbox

// Bar widget: pill plus running count. Owns the PodboxModel so the count
// keeps ticking while the panel is closed, and hosts the Panel loader.
BarWidget {
  id: root
  moduleName: "io.github.bethropolis.podbox"

  readonly property string panelLabel: model.barLabel
  readonly property string panelTooltip: model.barTooltip
  readonly property bool panelConnected: model.installOk === true
  readonly property string panelIconFont: model.iconFontFamily
  readonly property string barFontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property string barIconFont: root.panelIconFont !== "" ? root.panelIconFont : root.barFontFamily

  PodboxModel {
    id: model
    osColorsSetting: root.setting("osColors", Podbox.DEFAULT_OS_COLORS)
    themeFontFamily: root.barFontFamily
    active: panelLoader.item ? panelLoader.item.opened === true : false
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("model" in target) target.model = model
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    model.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // The built-in WidgetButton label stays for sizing and tooltip only; the
  // pill + count are drawn by our Row. Sizing follows our row, so the popout
  // indicator needs our width, not the hidden label's.
  readonly property real openPanelIndicatorWidth: labelRow.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  ShellIpc {
    target: "io.github.bethropolis.podbox"

    function refresh() { root.broadcast("refresh") }
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: model.barLabel
    labelVisible: false
    dimmed: model.podboxMissing === true
    tooltipText: model.barTooltip
    horizontalMargin: 16.5 // hidden label sizes to the count only; pill (9) + gap (6) fit centred
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: labelRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      PillLogo {
        anchors.verticalCenter: parent.verticalCenter
        pillHeight: Style.space(10)
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: model.barLabel
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        font.family: root.barFontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }

    Rectangle {
      visible: model.anyFailed === true
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(2)
      anchors.rightMargin: Style.space(2)
      width: Style.space(6)
      height: Style.space(6)
      radius: Style.space(3)
      color: Commons.Color.urgent
    }
  }
}
