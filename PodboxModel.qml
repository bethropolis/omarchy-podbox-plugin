import QtQuick
import Quickshell
import Quickshell.Io
import "Podbox.js" as Podbox

// Every podbox Process and Timer lives here. Panel.qml and
// ExportsOverlay.qml only bind to this state and call thin action
// functions. One instance can run in list/watch mode (the bar model) or in
// on-demand mode (the exports overlay, with autoStart/watch/list polling
// disabled) without a second watch stream.
QtObject {
  id: io

  // Bar widget uses the defaults. The exports overlay turns autoStart and
  // both background feeds off, then asks for one environment explicitly.
  property bool autoStart: true
  property bool watchEnabled: true
  property bool listPollEnabled: true
  property bool active: false

  property string osColorsSetting: Podbox.DEFAULT_OS_COLORS
  property string themeFontFamily: "monospace"
  property string probedIconFont: ""
  readonly property string iconFontFamily: Podbox.iconFont(probedIconFont, themeFontFamily)

  // ---- Install and list state
  property bool installProbed: false
  property bool installOk: false
  property bool podboxMissing: false
  property string version: "—"
  property bool versionOk: false
  property bool listLoaded: false
  property var envs: []
  property string selectedName: ""

  // ---- Selected environment detail
  property var statusInfo: ({})
  property var statsInfo: ({})
  property string error: ""

  // ---- Exports
  property var exportsInfo: ({ apps: [], bins: [] })
  property bool exportsLoaded: false
  property bool busy: false

  // ---- Watch lifecycle
  property bool watchAlive: true
  property bool watchDead: false
  property bool watchRestartRequested: false
  property int watchBackoffMs: 2000
  property int watchFailures: 0

  // Timeout latches: a reaped one-shot must not report its kill as a real
  // failure on the way out.
  property bool versionTimedOut: false
  property bool listTimedOut: false
  property bool statusTimedOut: false
  property bool statsTimedOut: false
  property bool exportTimedOut: false

  // ------------------------------------------------------------ derived UI

  readonly property var selectedEnv: Podbox.findEnv(io.envs, io.selectedName)
  readonly property string selectedStatus: io.selectedEnv
    ? String(io.selectedEnv.status || "")
    : (io.statusInfo && io.statusInfo.status ? String(io.statusInfo.status) : "")
  readonly property bool selectedRunning: io.selectedStatus === "running"
  readonly property string selectedImage: io.statusInfo && io.statusInfo.base_image
    ? String(io.statusInfo.base_image) : ""
  readonly property string selectedStartedAt: io.statusInfo && io.statusInfo.started_at
    ? String(io.statusInfo.started_at) : ""
  readonly property string selectedStateWord: Podbox.stateWord(io.selectedStatus)
  // Uptime needs a clock of its own: stats ticks do not change the subtitle.
  property double nowMs: Date.now()
  readonly property string selectedSubtitle: Podbox.subtitle(
    io.selectedImage, io.selectedStatus, io.selectedStartedAt, io.nowMs)
  readonly property string selectedStatusLine: Podbox.statusLine(
    io.selectedStatus,
    io.statsInfo ? io.statsInfo.cpu_percent : "",
    io.statsInfo ? io.statsInfo.mem_usage : "",
    io.statsInfo ? io.statsInfo.pids : "")

  readonly property var hero: Podbox.heroColors(
    Podbox.osColor(io.osColorsSetting, Podbox.distroKey(io.selectedImage)))
  readonly property string heroStart: String(io.hero.start)
  readonly property string heroEnd: String(io.hero.end)
  readonly property string heroAccent: String(io.hero.accent)

  readonly property int total: io.envs.length
  readonly property int runningCount: Podbox.runningCount(io.envs)
  readonly property bool anyFailed: Podbox.hasFailure(io.envs)
  readonly property int exportedCount: Podbox.exportedTotal(io.exportsInfo)

  readonly property bool loading: !io.installProbed
  readonly property bool missing: io.installProbed && !io.installOk && io.podboxMissing
  readonly property bool installFailed: io.installProbed && !io.installOk && !io.podboxMissing
  readonly property bool empty: io.installProbed && io.installOk && io.listLoaded && io.envs.length === 0

  readonly property string versionLabel: io.version !== "—"
    ? "podbox v" + Podbox.cleanVersion(io.version) : "podbox —"
  readonly property string barLabel: io.podboxMissing ? "—" : String(io.runningCount)
  readonly property string barTooltip: {
    if (io.podboxMissing) return "Podbox: podbox is not installed"
    if (io.envs.length === 0) return "Podbox: no environments"
    return "Podbox: " + io.runningCount + " of " + io.envs.length + " running"
  }

  readonly property string primaryAction: Podbox.primaryAction(io.selectedStatus)
  readonly property bool primaryEnabled: io.installOk && io.selectedName !== ""
    && (io.canStop || io.canStart || io.canBuild)

  readonly property bool canStart: io.installOk && io.selectedName !== ""
    && (io.selectedStatus === "stopped" || io.selectedStatus === "failed")
  readonly property bool canStop: io.installOk && io.selectedRunning
  readonly property bool canBuild: io.installOk && io.selectedStatus === "unbuilt"
  readonly property bool canTerminal: io.installOk && io.selectedName !== ""
    && io.selectedStatus !== "unbuilt"
  readonly property bool canLogs: io.canTerminal
  readonly property bool canEdit: io.canTerminal
  readonly property bool canExports: io.canTerminal
  readonly property bool canRestart: io.installOk && io.selectedRunning
  readonly property bool canNew: io.installOk

  // --------------------------------------------------------- watch helpers

  function reconnectWatch() {
    if (!io.installOk || !io.watchEnabled || !io.watchAlive) return
    io.watchRestartTimer.stop()
    io.watchBackoffMs = 2000
    io.watchRestartRequested = true
    io.watchAlive = false
  }

  function noteWatchLine() {
    io.watchStreamGuard.stop()
  }

  function noteWatchFailure(code) {
    if (io.watchDead) return
    io.watchDead = true
    io.watchAlive = false
    if (io.watchRestartRequested) {
      io.watchRestartRequested = false
      io.watchAlive = true
      return
    }
    if (!io.installOk) return
    io.watchFailures += 1
    // Three quiet failures is enough: keep the list poll doing the work.
    if (io.watchFailures >= 3) {
      io.watchEnabled = false
      return
    }
    io.watchBackoffMs = Math.min(io.watchBackoffMs * 2, 30000)
    io.watchRestartTimer.restart()
  }

  function handleWatchLine(line) {
    var parsed = Podbox.parseWatchLine(line)
    if (parsed.skip) return
    io.watchBackoffMs = 2000
    io.watchFailures = 0
    io.applyWatchEvent(parsed.event)
  }

  function applyWatchEvent(event) {
    if (!event || !event.name) return
    var previous = io.selectedName
    // Same reference back means nothing changed — don't assign, so the rail
    // Repeater does not rebuild the whole list for an idle event.
    var next = Podbox.applyWatchStatus(io.envs, event)
    if (next === io.envs) {
      io.listLoaded = true
      return
    }
    io.envs = next
    io.listLoaded = true
    io.selectedName = Podbox.pickSelection(io.envs, previous)
    if (event.name === io.selectedName) {
      if (event.status !== "running") io.statsInfo = ({})
      else if (io.active) io.refreshStats()
    }
    if (io.selectedName !== previous && io.active) {
      io.refreshSelected()
      io.fetchExports(io.selectedName)
    }
  }

  // ------------------------------------------------------------ read paths

  function refresh() {
    io.error = ""
    io.watchFailures = 0
    io.watchEnabled = true
    if (!io.versionProc.running) {
      io.versionTimedOut = false
      io.versionProc.command = Podbox.versionCommand()
      io.versionProc.running = true
    }
    if (io.installOk) {
      io.reconnectWatch()
      io.refreshList()
      io.refreshSelected()
    }
  }

  function softRefresh() {
    if (!io.installOk) return
    io.refreshList()
    io.refreshSelected()
  }

  function refreshList() {
    if (!io.installOk || io.podboxMissing || io.listProc.running) return
    io.listTimedOut = false
    io.listProc.command = Podbox.listCommand()
    io.listProc.running = true
  }

  function refreshSelected() {
    if (!io.installOk || io.selectedName === "") return
    io.refreshStatus()
    io.refreshStats()
  }

  function refreshStatus() {
    if (io.selectedName === "" || io.statusProc.running) return
    var cmd = Podbox.statusCommand(io.selectedName)
    if (!cmd) return
    io.statusTimedOut = false
    io.statusProc.command = cmd
    io.statusProc.running = true
  }

  function refreshStats() {
    if (!io.installOk || !io.selectedRunning || io.statsProc.running) return
    var cmd = Podbox.statsCommand(io.selectedName)
    if (!cmd) return
    io.statsTimedOut = false
    io.statsProc.command = cmd
    io.statsProc.running = true
  }

  // Overlay entry point: no install gate, because the overlay deliberately
  // skips the startup probe.
  function fetchEnvironment(name) {
    if (!Podbox.isSafeName(name)) {
      io.error = "Invalid environment name"
      return
    }
    io.selectedName = String(name)
    io.statusInfo = ({})
    io.statsInfo = ({})
    io.refreshStatus()
  }

  function select(name) {
    if (!Podbox.isSafeName(name) || io.selectedName === String(name)) return
    io.selectedName = String(name)
    if (io.active) {
      io.refreshSelected()
      io.fetchExports(io.selectedName)
    }
  }

  function moveSelection(delta) {
    var next = Podbox.moveSelection(io.envs, io.selectedName, delta)
    if (next !== "") io.select(next)
  }

  function applyList(text) {
    var next = Podbox.parseList(text)
    var previous = io.selectedName
    // No change: keep the reference so the rail does not rebuild every
    // 5–10s poll. Still refresh the flags the callers rely on.
    if (Podbox.envsSame(next, io.envs)) {
      io.listLoaded = true
      io.podboxMissing = false
      if (io.selectedName === "") io.selectedName = Podbox.pickSelection(next, previous)
      return
    }
    io.envs = next
    io.listLoaded = true
    io.podboxMissing = false
    io.selectedName = Podbox.pickSelection(next, previous)
    if (io.selectedName !== previous && io.active) {
      io.refreshSelected()
      io.fetchExports(io.selectedName)
    }
  }

  function applyStatus(text) {
    var parsed = Podbox.parseStatus(text)
    if (!parsed || Object.keys(parsed).length === 0) return
    if (parsed.name && io.selectedName !== "" && parsed.name !== io.selectedName) return
    io.statusInfo = parsed
    if (parsed.status && io.selectedName !== "") {
      io.envs = Podbox.applyWatchStatus(io.envs, {
        name: io.selectedName,
        status: parsed.status
      })
      if (parsed.status !== "running") io.statsInfo = ({})
    }
  }

  function applyStats(text) {
    io.statsInfo = Podbox.parseStats(text, io.selectedName)
  }

  function onVersionOutput(text) {
    var v = Podbox.parseVersionOutput(text)
    if (v === null) return
    io.version = v
    io.versionOk = true
  }

  function onVersionExit(code) {
    if (io.versionTimedOut) {
      io.versionTimedOut = false
      io.installProbed = true
      io.installOk = false
      io.podboxMissing = false
      io.error = "podbox did not respond"
      return
    }
    io.installProbed = true
    if (code === 0) {
      io.installOk = true
      io.podboxMissing = false
      io.error = ""
      io.watchDead = false
      io.watchAlive = true
      io.refreshList()
      io.refreshSelected()
      return
    }
    io.installOk = false
    io.versionOk = false
    io.version = "—"
    io.podboxMissing = code === 127 || code === 5
    io.watchAlive = false
    io.watchDead = false
    io.envs = []
    io.selectedName = ""
    io.statusInfo = ({})
    io.statsInfo = ({})
    io.error = io.podboxMissing ? "" : "podbox failed (exit " + code + ")"
  }

  function onListExit(code) {
    if (io.listTimedOut) {
      io.listTimedOut = false
      io.error = "podbox list timed out"
      return
    }
    if (code === 0) {
      io.podboxMissing = false
      io.error = ""
      return
    }
    if (code === 127 || code === 5) {
      io.podboxMissing = true
      io.installOk = false
      io.envs = []
      io.selectedName = ""
      io.error = ""
      return
    }
    io.error = "podbox list failed (exit " + code + ")"
  }

  function onStatusExit(code) {
    if (io.statusTimedOut) {
      io.statusTimedOut = false
      io.error = "podbox status timed out"
      return
    }
    if (code === 0) {
      io.error = ""
      return
    }
    if (code === 3) {
      io.error = "Environment not found"
      if (io.installOk) io.refreshList()
      return
    }
    if (code === 127 || code === 5) {
      io.podboxMissing = true
      io.installOk = false
      io.error = ""
      return
    }
    io.error = "podbox status failed (exit " + code + ")"
  }

  function onStatsExit(code) {
    if (io.statsTimedOut) {
      io.statsTimedOut = false
      io.error = "podbox stats timed out"
      return
    }
    if (code === 0 || code === 3) return
    if (code === 127 || code === 5) {
      io.podboxMissing = true
      io.installOk = false
      return
    }
    io.error = "podbox stats failed (exit " + code + ")"
  }

  // --------------------------------------------------------------- exports

  property string exportTarget: ""
  property string queuedExportName: ""

  function fetchExports(name) {
    if (!Podbox.isSafeName(name)) return
    if (name !== io.exportTarget) {
      io.exportsInfo = ({ apps: [], bins: [] })
      io.exportsLoaded = false
    }
    io.exportTarget = String(name)
    if (io.exportListProc.running) {
      io.queuedExportName = String(name)
      return
    }
    var cmd = Podbox.exportListCommand(name)
    if (!cmd) return
    io.exportTimedOut = false
    io.exportListProc.command = cmd
    io.exportListProc.running = true
  }

  function applyExportList(text) {
    io.exportsInfo = Podbox.parseExportList(text)
    io.exportsLoaded = true
  }

  function onExportListExit(code) {
    var queued = io.queuedExportName
    io.queuedExportName = ""
    if (io.exportTimedOut) {
      io.exportTimedOut = false
      io.exportsLoaded = true
      io.error = "podbox export list timed out"
      return
    }
    if (code === 0) {
      io.error = ""
      io.exportsLoaded = true
    } else if (code === 127 || code === 5) {
      io.podboxMissing = true
      io.exportsLoaded = true
      io.error = ""
    } else if (code === 3) {
      io.exportsLoaded = true
      io.error = "Environment not found"
    } else {
      io.exportsLoaded = true
      io.error = "podbox export list failed (exit " + code + ")"
    }
    if (queued !== "" && queued !== io.exportTarget) io.fetchExports(queued)
  }

  function runWrite(cmd, kind) {
    if (io.busy || !cmd) return
    io.busy = true
    io.writeKind = kind
    io.writeTarget = io.selectedName
    io.writeProc.command = cmd
    io.writeProc.running = true
  }

  property string writeKind: ""
  property string writeTarget: ""

  function exportApp(item) {
    if (!io.selectedRunning) return
    io.runWrite(Podbox.exportAppCommand(io.selectedName, item), "app")
  }

  function exportBin(item) {
    io.runWrite(Podbox.exportBinCommand(io.selectedName, item), "bin")
  }

  function cleanExports() {
    io.runWrite(Podbox.exportCleanCommand(io.selectedName), "clean")
  }

  function onWriteExit(code) {
    io.busy = false
    if (code === 0) {
      io.error = ""
    } else if (code === 127 || code === 5) {
      io.podboxMissing = true
      io.installOk = false
      io.error = ""
    } else {
      var action = io.writeKind === "clean" ? "Remove exports" : "Export"
      io.error = action + " failed (exit " + code + ")"
    }
    if (io.writeTarget !== "") io.fetchExports(io.writeTarget)
    io.scheduleRefresh(900)
  }

  // --------------------------------------------------------------- actions

  function startSelected() {
    if (!io.canStart) return
    Quickshell.execDetached(Podbox.startCommand(io.selectedName))
    io.scheduleRefresh(1200)
  }

  function stopSelected() {
    if (!io.canStop) return
    Quickshell.execDetached(Podbox.stopCommand(io.selectedName))
    io.scheduleRefresh(1200)
  }

  function buildSelected() {
    if (!io.canBuild) return
    Quickshell.execDetached(Podbox.buildCommand(io.selectedName))
  }

  function restartSelected() {
    if (!io.canRestart) return
    Quickshell.execDetached(Podbox.restartCommand(io.selectedName))
    io.scheduleRefresh(1200)
  }

  function runPrimary() {
    if (io.canStop) io.stopSelected()
    else if (io.canBuild) io.buildSelected()
    else if (io.canStart) io.startSelected()
  }

  function enterSelected() {
    if (!io.canTerminal) return
    Quickshell.execDetached(Podbox.enterCommand(io.selectedName))
  }

  function logsSelected() {
    if (!io.canLogs) return
    Quickshell.execDetached(Podbox.logsCommand(io.selectedName))
  }

  function editSelected() {
    if (!io.canEdit) return
    Quickshell.execDetached(Podbox.editCommand(io.selectedName))
  }

  function newEnvironment() {
    if (!io.canNew) return
    Quickshell.execDetached(Podbox.initCommand())
  }

  function scheduleRefresh(delay) {
    io.refreshDelay.interval = Number(delay) || 900
    io.refreshDelay.restart()
  }

  function startFontProbe() {
    io.fontProbeProc.command = Podbox.iconProbeCommand(io.themeFontFamily)
    io.fontProbeProc.running = true
  }

  onThemeFontFamilyChanged: io.startFontProbe()
  Component.onCompleted: {
    io.startFontProbe()
    if (io.autoStart) io.refresh()
  }

  onActiveChanged: {
    if (io.active) {
      io.nowMs = Date.now()
      if (io.installOk && io.selectedName !== "") {
        io.refreshSelected()
        io.fetchExports(io.selectedName)
      }
    }
  }

  onSelectedRunningChanged: {
    if (io.selectedRunning && io.active) io.refreshStats()
    else if (!io.selectedRunning) io.statsInfo = ({})
  }

  // --------------------------------------------------------------- timers

  property Timer listTimer: Timer {
    interval: io.active ? 5000 : 10000
    repeat: true
    // Never while missing, never while a list read is in flight.
    running: io.installOk && io.listPollEnabled && !io.podboxMissing && !io.listProc.running
    onTriggered: io.refreshList()
  }

  property Timer statsTimer: Timer {
    interval: 2000
    repeat: true
    running: io.active && io.installOk && io.selectedRunning && !io.statsProc.running
    onTriggered: io.refreshStats()
  }

  property Timer uptimeTimer: Timer {
    interval: 30000
    repeat: true
    running: io.active
    onTriggered: io.nowMs = Date.now()
  }

  property Timer refreshDelay: Timer {
    interval: 900
    repeat: false
    onTriggered: io.softRefresh()
  }

  property Timer watchRestartTimer: Timer {
    interval: io.watchBackoffMs
    repeat: false
    onTriggered: io.watchAlive = true
  }

  property Timer watchStreamGuard: Timer {
    interval: 30000
    repeat: false
    onTriggered: {
      if (!io.watchProc.running && !io.watchAlive) return
      io.watchAlive = false
      io.noteWatchFailure(124)
    }
  }

  property Timer versionGuard: Timer {
    interval: 5000
    repeat: false
    running: io.versionProc.running
    onTriggered: {
      if (!io.versionProc.running) return
      io.versionTimedOut = true
      io.versionProc.running = false
    }
  }

  property Timer listGuard: Timer {
    interval: 5000
    repeat: false
    running: io.listProc.running
    onTriggered: {
      if (!io.listProc.running) return
      io.listTimedOut = true
      io.listProc.running = false
    }
  }

  property Timer statusGuard: Timer {
    interval: 5000
    repeat: false
    running: io.statusProc.running
    onTriggered: {
      if (!io.statusProc.running) return
      io.statusTimedOut = true
      io.statusProc.running = false
    }
  }

  property Timer statsGuard: Timer {
    interval: 5000
    repeat: false
    running: io.statsProc.running
    onTriggered: {
      if (!io.statsProc.running) return
      io.statsTimedOut = true
      io.statsProc.running = false
    }
  }

  property Timer exportGuard: Timer {
    interval: 5000
    repeat: false
    running: io.exportListProc.running
    onTriggered: {
      if (!io.exportListProc.running) return
      io.exportTimedOut = true
      io.exportListProc.running = false
    }
  }

  property Timer fontGuard: Timer {
    interval: 5000
    repeat: false
    running: io.fontProbeProc.running
    onTriggered: {
      if (io.fontProbeProc.running) io.fontProbeProc.running = false
    }
  }

  // ------------------------------------------------------------ processes

  // The only bound Process: the watch stream starts with installOk and stays
  // off while backing off. Flip the flags, never `running`.
  property Process watchProc: Process {
    running: io.installOk && io.watchAlive && io.watchEnabled
    command: Podbox.watchCommand()
    stdout: SplitParser {
      onRead: function(data) { io.noteWatchLine(); io.handleWatchLine(data) }
    }
    onRunningChanged: {
      if (running) {
        io.watchDead = false
        io.watchStreamGuard.restart()
      }
    }
    onExited: function(code) { io.noteWatchFailure(code) }
  }

  property Process versionProc: Process {
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: io.onVersionOutput(text)
    }
    onExited: function(code) { io.onVersionExit(code) }
  }

  property Process listProc: Process {
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: io.applyList(text)
    }
    onExited: function(code) { io.onListExit(code) }
  }

  property Process statusProc: Process {
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: io.applyStatus(text)
    }
    onExited: function(code) { io.onStatusExit(code) }
  }

  property Process statsProc: Process {
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: io.applyStats(text)
    }
    onExited: function(code) { io.onStatsExit(code) }
  }

  property Process exportListProc: Process {
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: io.applyExportList(text)
    }
    onExited: function(code) { io.onExportListExit(code) }
  }

  property Process writeProc: Process {
    running: false
    onExited: function(code) { io.onWriteExit(code) }
  }

  property Process fontProbeProc: Process {
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: io.probedIconFont = Podbox.parseIconProbeOutput(text)
    }
  }
}
