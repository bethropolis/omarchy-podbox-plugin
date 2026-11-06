import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Podbox.js" as Podbox

// Exports modal: apps and commands for one environment. Owns a PodboxModel in
// on-demand mode (autoStart/watch/list polling off) so the bar's watch stream
// stays the only one. Summoned with {"env":"NAME","tab":"apps"|"commands"}.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string envName: ""
  property string tab: "apps"
  property string filterText: ""
  property string newCommand: ""
  property bool removeConfirmOpen: false

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.family
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Style.space(40)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
  property int rowHeight: Style.space(50)

  // On-demand model: no install probe, no watch, no list polling. The overlay
  // asks for one environment explicitly in open().
  PodboxModel {
    id: io
    autoStart: false
    watchEnabled: false
    listPollEnabled: false
  }

  readonly property var apps: io.exportsInfo && io.exportsInfo.apps ? io.exportsInfo.apps : []
  readonly property var bins: io.exportsInfo && io.exportsInfo.bins ? io.exportsInfo.bins : []
  readonly property var filteredApps: Podbox.filterApps(root.apps, root.filterText)
  readonly property var filteredBins: Podbox.filterApps(root.bins, root.filterText)
  readonly property var showingApps: root.tab === "apps"
  readonly property string effectiveTab: root.showingApps ? "apps" : "commands"

  function envSubtitle() {
    return (root.envName || "").toUpperCase() + " · MAKE THINGS AVAILABLE ON YOUR HOST"
  }

  function open(payloadJson) {
    var args = {}
    if (payloadJson) {
      try { args = JSON.parse(payloadJson) || {} } catch (e) { args = {} }
    }
    var env = String(args.env || "")
    var tab = String(args.tab || "apps")
    root.envName = env
    root.tab = tab === "commands" ? "commands" : "apps"
    root.filterText = ""
    root.newCommand = ""
    root.removeConfirmOpen = false
    root.opened = true
    if (Podbox.isSafeName(env)) {
      io.fetchEnvironment(env)
      io.fetchExports(env)
    } else {
      io.error = "Invalid environment name"
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.removeConfirmOpen = false
  }

  function toggle(payloadJson) {
    if (root.opened) root.close()
    else root.open(payloadJson || "{}")
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.bethropolis.podbox")
  }

  function requestRemoveAll() {
    if (io.busy) return
    removeConfirm.selectedIndex = 0
    root.removeConfirmOpen = true
  }

  function cancelRemoveAll() {
    root.removeConfirmOpen = false
  }

  function confirmRemoveAll() {
    root.removeConfirmOpen = false
    io.cleanExports()
    io.scheduleRefresh(900)
  }

  function submitNewCommand() {
    var name = String(root.newCommand || "").replace(/^\s+|\s+$/g, "")
    if (!Podbox.isSafeName(name)) return
    root.newCommand = ""
    io.exportBin(name)
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-podbox-exports"

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.removeConfirmOpen) {
            if (removeConfirm.handleKey(event)) event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          }
        }
        Component.onCompleted: forceActiveFocus()
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // ---- Header
        Item {
          width: parent.width
          height: root.headerHeight

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "Exports"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.envSubtitle()
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: 1.2
            }
          }

          Button {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Podbox.ICONS.close
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.dismiss()
          }
        }

        // ---- Segmented tabs
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: Style.space(130)
            text: "Apps " + root.apps.length
            foreground: root.foreground
            fontFamily: root.fontFamily
            selected: root.tab === "apps"
            onClicked: { root.tab = "apps"; root.filterText = "" }
          }

          Button {
            width: Style.space(130)
            text: "Commands " + root.bins.length
            foreground: root.foreground
            fontFamily: root.fontFamily
            selected: root.tab === "commands"
            onClicked: { root.tab = "commands"; root.filterText = "" }
          }
        }

        // ---- Search or add input
        TextField {
          id: filterField
          width: parent.width
          height: Style.space(36)
          placeholderText: root.showingApps ? "Search apps" : "Add a command"
          text: root.filterText
          foreground: root.foreground
          fontFamily: root.fontFamily
          onTextChanged: root.filterText = text
          Keys.onAccepted: {
            if (!root.showingApps) {
              root.newCommand = text
              root.submitNewCommand()
              text = ""
            }
          }
        }

        // ---- List
        Item {
          width: parent.width
          height: parent.height - root.headerHeight - Style.space(36) - Style.space(36) - Style.space(34) - root.contentSpacing * 4
          clip: true

          ListView {
            id: listView
            anchors.fill: parent
            model: root.showingApps ? root.filteredApps : root.filteredBins
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Style.space(4)

            delegate: Rectangle {
              required property var modelData

              readonly property string itemId: root.showingApps
                ? String(modelData.id || "")
                : String(modelData.name || "")
              readonly property string itemName: root.showingApps
                ? String(modelData.name || modelData.id || "")
                : String(modelData.name || "")
              readonly property string itemDetail: root.showingApps
                ? String(modelData.desktop || "")
                : String(modelData.path || "")
              readonly property bool exported: modelData.exported === true
              readonly property string letter: (itemName ? itemName.charAt(0) : "?").toUpperCase()

              width: listView.width
              height: root.rowHeight
              radius: Style.cornerRadius
              color: rowMouse.containsMouse && !exported
                ? Style.hoverFillFor(root.foreground, Commons.Color.accent)
                : "transparent"

              Rectangle {
                id: letterTile
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(38)
                height: Style.space(38)
                radius: Style.cornerRadius
                color: Style.normalFillFor(root.foreground, Commons.Color.accent)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: parent.parent.letter
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }
              }

              Column {
                anchors.left: letterTile.right
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: listView.width - letterTile.width - Style.space(170)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.showingApps ? itemName : itemName
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: itemDetail
                  visible: itemDetail !== ""
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: "monospace"
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Button {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: exported ? Podbox.ICONS.check + " Exported" : "Export"
                foreground: root.foreground
                fontFamily: root.fontFamily
                iconFontFamily: root.fontFamily
                enabled: !exported && !io.busy
                opacity: exported ? 0.6 : (enabled ? 1 : 0.4)
                onClicked: {
                  if (root.showingApps) io.exportApp(itemId)
                  else io.exportBin(itemId)
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
              }
            }
          }

          Column {
            anchors.centerIn: parent
            visible: (root.showingApps ? root.filteredApps.length : root.filteredBins.length) === 0

            Text {
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: io.exportsLoaded ? "Nothing here" : "Loading"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }
        }

        // ---- Error
        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: io.error !== ""
          text: io.error
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // ---- Footer
        Item {
          width: parent.width
          height: Style.space(34)

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(220)
            text: root.showingApps
              ? "Apps appear in your launcher."
              : "Commands are added to ~/.local/bin."
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Button {
              text: "Remove all"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !io.busy
              opacity: enabled ? 1 : 0.4
              onClicked: root.requestRemoveAll()
            }

            Button {
              text: "Done"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.dismiss()
            }
          }
        }
      }

      ConfirmDialog {
        id: removeConfirm
        anchors.fill: parent
        z: 10
        opened: root.removeConfirmOpen
        message: "Remove all exports from " + root.envName + "?"
        cancelText: "Cancel"
        confirmText: "Remove all"
        selectedIndex: 0
        background: root.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelRemoveAll()
        onConfirmed: root.confirmRemoveAll()
      }
    }
  }
}
