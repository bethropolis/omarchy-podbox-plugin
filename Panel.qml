import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "components"
import "Podbox.js" as Podbox

// Podbox panel: header, environment rail, hero card, quick actions, footer.
// State and IO live in the PodboxModel this panel co-owns; the bar owns the
// model instance and injects it here.
Panel {
  id: root
  moduleName: "io.github.bethropolis.podbox"
  ipcTarget: "io.github.bethropolis.podbox"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var model: null

  property string barLabel: ""
  property string barTooltip: ""
  property bool liveConnected: false
  property var autoDevice: null

  property bool stopConfirmOpen: false
  property string pendingStopName: ""

  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string contentIconFont: model ? String(model.iconFontFamily || "") : Style.font.family

  function refresh() {
    if (model) model.refresh()
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.stopConfirmOpen) root.cancelStop()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function closeForPopoutSwitch() {
    if (root.controller && typeof root.controller.hide === "function") root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function requestStop() {
    if (!model || !model.canStop) return
    root.pendingStopName = model.selectedName
    stopConfirm.selectedIndex = 0
    root.stopConfirmOpen = true
  }

  function confirmStop() {
    root.stopConfirmOpen = false
    if (model) model.stopSelected()
  }

  function cancelStop() {
    root.stopConfirmOpen = false
    root.pendingStopName = ""
  }

  function openExports() {
    if (!model || model.selectedName === "") return
    root.close()
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "io.github.bethropolis.podbox", JSON.stringify({ env: model.selectedName, tab: "apps" })])
  }

  Component.onCompleted: root.refresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: Style.space(600)
    contentHeight: Math.min(panel.fittedContentHeight(contentColumn.implicitHeight), Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.stopConfirmOpen ? root.cancelStop() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0 && model) model.moveSelection(dy)
      }

      Item {
        anchors.fill: parent

        Column {
          id: contentColumn
          x: 0
          width: parent.width
          height: parent.height
          y: root.opened ? 0 : Style.space(10)
          opacity: root.opened ? 1 : 0
          spacing: Style.space(14)

          Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }
          Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

          // ---- Header
          Item {
            width: parent.width
            height: Math.max(headerColumn.implicitHeight, newButton.height)

            Column {
              id: headerColumn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Row {
                spacing: Style.space(10)

                PillLogo {
                  anchors.verticalCenter: parent.verticalCenter
                  pillHeight: Style.space(17)
                  color: root.contentForeground
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "PODBOX"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  font.letterSpacing: 1.8
                }
              }

              Text {
                textFormat: Text.PlainText
                text: model ? (model.runningCount + " of " + model.total + " running") : "podbox"
                color: Commons.Color.accent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            TileButton {
              id: newButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "New"
              icon: Podbox.ICONS.plus
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              iconFontFamily: root.contentIconFont
              enabled: model ? model.canNew : false
              onClicked: if (model) model.newEnvironment()
            }
          }

          // ---- Loading
          Item {
            width: parent.width
            height: Style.space(180)
            visible: model ? model.loading : true

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "Podbox"
              color: root.contentForeground
              opacity: 0.6
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
            }
          }

          // ---- Podbox missing
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: model ? model.missing : false

            Text {
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Podbox is not installed"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: "Install podbox to manage environments from the bar."
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Install docs"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: Qt.openUrlExternally("https://github.com/bethropolis/podbox")
            }
          }

          // ---- Install failed
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: model ? model.installFailed : false

            Text {
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Podbox failed to start"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: model ? model.error : ""
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Retry"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.refresh()
            }
          }

          // ---- Empty
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: model ? model.empty : false

            Text {
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "No environments yet"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Create your first one."
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "+ New"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: if (model) model.newEnvironment()
            }
          }

          // ---- Ready
          Row {
            width: parent.width
            visible: model ? (!model.loading && !model.missing && !model.installFailed && !model.empty) : false
            spacing: Style.space(16)

            Rail {
              id: rail
              width: Style.space(150)
              height: mainColumn.height
              envs: model ? model.envs : []
              selectedName: model ? model.selectedName : ""
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onPicked: function(name) { if (model) model.select(name) }
            }

            Column {
              id: mainColumn
              width: parent.width - rail.width - Style.space(16)
              spacing: Style.space(14)

              Hero {
                id: hero
                width: parent.width
                name: model ? model.selectedName : ""
                subtitle: model ? model.selectedSubtitle : ""
                status: model ? model.selectedStatus : "stopped"
                statusLine: model ? model.selectedStatusLine : ""
                primaryLabel: model ? model.primaryAction : "Start"
                primaryEnabled: model ? model.primaryEnabled : false
                primaryUrgent: model ? model.canStop : false
                heroStart: model ? model.heroStart : Podbox.heroColors("").start
                heroEnd: model ? model.heroEnd : Podbox.heroColors("").end
                heroAccent: model ? model.heroAccent : Podbox.heroColors("").accent
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onPrimaryClicked: {
                  if (!model) return
                  if (model.canStop) root.requestStop()
                  else if (model.canBuild) model.buildSelected()
                  else if (model.canStart) model.startSelected()
                }
              }

              // ---- Quick actions
              Column {
                width: parent.width
                spacing: Style.space(8)

                PanelSectionHeader {
                  text: "QUICK ACTIONS"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  property real cellWidth: Math.max(0, (width - spacing * 2) / 3)

                  ActionTile {
                    width: parent.cellWidth
                    icon: Podbox.ICONS.terminal
                    label: "Terminal"
                    badge: 0
                    enabled: model ? model.canTerminal : false
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    iconFontFamily: root.contentIconFont
                    tileHeight: Style.space(66)
                    onClicked: if (model) model.enterSelected()
                  }

                  ActionTile {
                    width: parent.cellWidth
                    icon: Podbox.ICONS.logs
                    label: "Logs"
                    badge: 0
                    enabled: model ? model.canLogs : false
                    emphasized: model ? model.selectedStatus === "failed" : false
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    iconFontFamily: root.contentIconFont
                    tileHeight: Style.space(66)
                    onClicked: if (model) model.logsSelected()
                  }

                  ActionTile {
                    width: parent.cellWidth
                    icon: Podbox.ICONS.exports
                    label: "Exports"
                    badge: model ? model.exportedCount : 0
                    enabled: model ? model.canExports : false
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    iconFontFamily: root.contentIconFont
                    tileHeight: Style.space(66)
                    onClicked: root.openExports()
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  property real cellWidth: Math.max(0, (width - spacing) / 2)

                  ActionTile {
                    width: parent.cellWidth
                    icon: Podbox.ICONS.edit
                    label: "Edit config"
                    badge: 0
                    enabled: model ? model.canEdit : false
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    iconFontFamily: root.contentIconFont
                    tileHeight: Style.space(54)
                    onClicked: if (model) model.editSelected()
                  }

                  ActionTile {
                    width: parent.cellWidth
                    icon: Podbox.ICONS.restart
                    label: "Restart"
                    badge: 0
                    enabled: model ? model.canRestart : false
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    iconFontFamily: root.contentIconFont
                    tileHeight: Style.space(54)
                    onClicked: if (model) model.restartSelected()
                  }
                }
              }

              // ---- Status / error
              Text {
                id: statusText
                textFormat: Text.PlainText
                width: parent.width
                visible: model && model.error !== ""
                text: model ? model.error : ""
                color: Commons.Color.urgent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }
          }

          // ---- Footer
          Item {
            width: parent.width
            height: Style.space(22)

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: model ? model.versionLabel : "podbox —"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      ConfirmDialog {
        id: stopConfirm
        anchors.fill: parent
        z: 10
        opened: root.stopConfirmOpen
        message: "Stop " + root.pendingStopName + "?"
        cancelText: "Cancel"
        confirmText: "Stop"
        selectedIndex: 0
        background: root.bar ? root.bar.background : Commons.Color.background
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onCanceled: root.cancelStop()
        onConfirmed: root.confirmStop()
      }
    }
  }
}
