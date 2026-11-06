# Podbox for Omarchy

A bar widget and panel for [podbox](https://github.com/bethropolis/podbox): see how many environments are running, pick one from a rail, and act on it — terminal, logs, edit config, restart, build, and exports.

## Install

```bash
omarchy plugin add https://github.com/bethropolis/omarchy-podbox-plugin --enable
```

Or clone it and point Quickshell at it:

```bash
omarchy plugin clone
```

## Usage

- The bar pill shows the pill logo plus the number of running environments (neutral and dim when none are running). A small red dot appears when any environment has failed.
- Left click opens the panel; Escape or clicking outside closes it. Middle click refreshes.
- The panel header shows `N of M running`; `+ New` starts the interactive `podbox init -i` flow in a terminal.
- The left rail lists every environment with a status dot, name, and state word (`running`, `stopped`, `failed`, `not built`). Up/Down arrows move the selection within the panel.
- The hero card shows the selected environment's OS-coloured name, distro and uptime subtitle, a quiet status line (`● Running · 3.2% cpu · 812 MiB · 14 procs`), and the primary action: `Start` when stopped or failed, `Stop` when running (confirm first), `Build` when not built.
- Quick actions: Terminal (`podbox enter`), Logs (`podbox logs -f`), Exports (opens the exports overlay with the exported count as a badge), Edit config (`podbox edit`), Restart (`systemctl --user restart NAME.service`).
- The Exports overlay is summoned with `omarchy-shell shell summon io.github.bethropolis.podbox '{"env":"NAME","tab":"apps"}'` or from the Exports tile. It has an Apps tab (searchable, letter tile, `.desktop` name, `Export` / `✓ Exported`) and a Commands tab (add by name, binary path, same button), plus `Remove all` (confirm first) and `Done`. Escape or clicking the backdrop closes it.

> **Summon routing:** this plugin declares both `bar-widget` and `overlay` kinds. The shell's panel loader owns plugins that pair a bar widget with an overlay, so `omarchy-shell shell summon io.github.bethropolis.podbox` opens the **Exports overlay**, not the main panel. Open the main panel by clicking the bar pill, or with `omarchy-shell shell summon io.github.bethropolis.podbox '{"env":"","tab":"apps"}'` — that payload is ignored. Main-panel summon payloads are not supported in v1; click the pill.

## Configuration

Move the widget in the bar:

```bash
omarchy bar move io.github.bethropolis.podbox --section right
```

The `osColors` setting (in `shell.json` for this plugin) is a comma-separated list of `name=#hex` pairs used to colour the hero card per distro. Defaults: `fedora=#3c6eb4,arch=#1793d1,ubuntu=#e95420,debian=#d70a53,alpine=#0d597f,cachy=#00b4a0,nixos=#7ebae4,opensuse=#73ba25,default=#6366f1`. Bad entries are ignored; a specific distro's colour falls back to its family, then `default`.

There is no per-plugin settings UI in the shell, so v1 has no footer gear.

## Removal

```bash
omarchy plugin remove io.github.bethropolis.podbox
```

## Privileges

The plugin runs unsandboxed with your permissions. It invokes the `podbox` CLI (start, stop, enter, logs, edit, build, export, watch, list, status, stats) and `systemctl --user restart NAME.service`. For exports, podbox writes `.desktop` launchers and shims to `~/.local/share/applications` and `~/.local/bin` through podbox itself. The plugin never writes outside those paths and never starts a second Quickshell process.

## Development

```bash
bun test tests/
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml ExportsOverlay.qml PodboxModel.qml components/*.qml
```

`Podbox.js` is pure JavaScript (no QML types) so every parsing, formatting, and argv rule is covered by `tests/podbox.test.js` against real CLI fixtures in `tests/fixtures/`.
