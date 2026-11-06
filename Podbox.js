// Pure podbox data helpers: JSON parsing, display formatting, distro and
// colour derivation, and argv builders. Qt-free so `bun test tests/` can run
// every rule without a shell. QML owns all Process IO and timers.

// Environment and export item names are only ever forwarded to argv when
// they match this allowlist. Dash is escaped so the class is not a range.
var SAFE_NAME = /^[A-Za-z0-9_.-]+$/;

function isSafeName(name) {
  return SAFE_NAME.test(String(name || ""));
}

function parseJson(text) {
  var raw = String(text || "").trim();
  if (raw === "") return null;
  try {
    return JSON.parse(raw);
  } catch (e) {
    return null;
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !(value instanceof Array);
}

function normalizeStatus(status) {
  var s = String(status || "").toLowerCase();
  if (s === "running" || s === "stopped" || s === "failed" || s === "unbuilt") return s;
  return "stopped";
}

function normalizeEnv(entry) {
  if (!isPlainObject(entry)) return null;
  var name = entry.name;
  if (!isSafeName(name)) return null;
  return {
    name: String(name),
    status: normalizeStatus(entry.status),
    autostart: entry.autostart === true,
    active: entry.active === true
  };
}

// `podbox list --output json` -> [{name,status,autostart,active}].
// Unsafe or malformed rows are dropped rather than rendered.
function parseList(text) {
  var parsed = parseJson(text);
  var out = [];
  if (!isPlainObject(parsed) || !(parsed.containers instanceof Array)) return out;
  for (var i = 0; i < parsed.containers.length; i++) {
    var env = normalizeEnv(parsed.containers[i]);
    if (env !== null) out.push(env);
  }
  return out;
}

// `podbox status NAME --output json`. Every field except name/status is
// optional; absent values stay missing rather than becoming a fake zero.
function parseStatus(text) {
  var parsed = parseJson(text);
  if (!isPlainObject(parsed)) return {};
  var out = {};
  if (parsed.name !== undefined && parsed.name !== null) out.name = String(parsed.name);
  if (parsed.status !== undefined && parsed.status !== null) out.status = normalizeStatus(parsed.status);
  if (parsed.installed !== undefined && parsed.installed !== null) out.installed = parsed.installed === true;
  if (parsed.base_image !== undefined && parsed.base_image !== null) out.base_image = String(parsed.base_image);
  if (parsed.started_at !== undefined && parsed.started_at !== null) out.started_at = String(parsed.started_at);
  if (parsed.schema !== undefined && parsed.schema !== null) out.schema = Number(parsed.schema);
  return out;
}

// `podbox stats NAME --no-stream --output json` returns an array today; a
// single object is accepted too so a future shape change degrades quietly.
function parseStats(text, name) {
  var parsed = parseJson(text);
  var row = null;
  if (parsed instanceof Array) {
    for (var i = 0; i < parsed.length; i++) {
      if (!isPlainObject(parsed[i])) continue;
      if (name && String(parsed[i].name || "") === String(name)) { row = parsed[i]; break; }
      if (row === null) row = parsed[i];
    }
  } else if (isPlainObject(parsed)) {
    row = parsed;
  }
  if (!row) return {};
  var out = {};
  if (row.name !== undefined && row.name !== null) out.name = String(row.name);
  if (row.cpu_percent !== undefined && row.cpu_percent !== null) out.cpu_percent = String(row.cpu_percent);
  if (row.mem_usage !== undefined && row.mem_usage !== null) out.mem_usage = String(row.mem_usage);
  if (row.mem_percent !== undefined && row.mem_percent !== null) out.mem_percent = String(row.mem_percent);
  if (row.pids !== undefined && row.pids !== null) out.pids = String(row.pids);
  if (row.memory_bytes !== undefined && row.memory_bytes !== null) out.memory_bytes = Number(row.memory_bytes);
  if (row.memory_limit_bytes !== undefined && row.memory_limit_bytes !== null) out.memory_limit_bytes = Number(row.memory_limit_bytes);
  return out;
}

// `podbox watch --output ndjson` -> {skip:true} or {event:{type,name,status}}.
// Only status events are meaningful to this plugin; unknown events are
// skipped without surfacing an error.
function parseWatchLine(line) {
  var parsed = parseJson(line);
  if (!isPlainObject(parsed)) return { skip: true };
  var type = String(parsed.event || "");
  if (type === "") return { skip: true };
  if (type !== "status") return { skip: true };
  if (!isSafeName(parsed.name)) return { skip: true };
  return {
    event: {
      type: type,
      name: String(parsed.name),
      status: normalizeStatus(parsed.status)
    }
  };
}

// Apply one watch status without disturbing row order or selection.
function applyWatchStatus(envs, event) {
  var list = envs instanceof Array ? envs : [];
  var found = -1;
  for (var i = 0; i < list.length; i++) {
    var env = list[i];
    if (isPlainObject(env) && env.name === event.name) { found = i; break; }
  }
  var status = normalizeStatus(event.status);
  if (found === -1) {
    var grown = list.slice();
    grown.push({ name: event.name, status: status, autostart: false, active: false });
    return grown;
  }
  var current = list[found];
  // Same reference back when the line carries no news: callers assign only
  // on change, which keeps the Repeater from rebuilding the rail per event.
  if (current.status === status) return list;
  var out = list.slice();
  out[found] = {
    name: current.name,
    status: status,
    autostart: current.autostart === true,
    active: current.active === true
  };
  return out;
}

// Shallow [name,status,autostart,active] comparison of two env lists.
function envsSame(a, b) {
  if (a === b) return true;
  var left = Array.isArray(a) ? a : [];
  var right = Array.isArray(b) ? b : [];
  if (left.length !== right.length) return false;
  for (var i = 0; i < left.length; i++) {
    var x = left[i], y = right[i];
    if (!isPlainObject(x) || !isPlainObject(y)) return false;
    if (x.name !== y.name) return false;
    if (x.status !== y.status) return false;
    if (!!x.autostart !== !!y.autostart) return false;
    if (!!x.active !== !!y.active) return false;
  }
  return true;
}

function stateWord(status) {
  var s = normalizeStatus(status);
  if (s === "unbuilt") return "not built";
  return s;
}

function isRunning(env) {
  return !!env && env.status === "running";
}

function runningCount(envs) {
  var n = 0;
  var list = envs instanceof Array ? envs : [];
  for (var i = 0; i < list.length; i++) if (isRunning(list[i])) n++;
  return n;
}

function hasFailure(envs) {
  var list = envs instanceof Array ? envs : [];
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].status === "failed") return true;
  return false;
}

function findEnv(envs, name) {
  var list = envs instanceof Array ? envs : [];
  for (var i = 0; i < list.length; i++) {
    if (list[i] && String(list[i].name) === String(name || "")) return list[i];
  }
  return null;
}

// Keep the user's selection across polls. Default to the first running
// environment, then the first environment at all.
function pickSelection(envs, current) {
  var list = envs instanceof Array ? envs : [];
  if (list.length === 0) return "";
  if (current && findEnv(list, current)) return String(current);
  for (var i = 0; i < list.length; i++) if (isRunning(list[i])) return String(list[i].name);
  return String(list[0].name);
}

function selectionNames(envs) {
  var out = [];
  var list = envs instanceof Array ? envs : [];
  for (var i = 0; i < list.length; i++) if (list[i] && isSafeName(list[i].name)) out.push(String(list[i].name));
  return out;
}

// Clamped, not wrapping: a list has ends, and Down at the last row is a no-op.
function moveSelection(envs, current, delta) {
  var names = selectionNames(envs);
  if (names.length === 0) return "";
  var at = names.indexOf(String(current || ""));
  if (at < 0) at = 0;
  var next = Math.max(0, Math.min(names.length - 1, at + (Number(delta) || 0)));
  return names[next];
}

function primaryAction(status) {
  var s = normalizeStatus(status);
  if (s === "running") return "Stop";
  if (s === "unbuilt") return "Build";
  return "Start";
}

// ---------------------------------------------------------------- formatting

function trimFixed(value) {
  var s = String(value);
  if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "");
  return s;
}

function formatCpu(text) {
  var m = String(text || "").match(/-?\d+(?:\.\d+)?/);
  if (!m) return "";
  var n = Number(m[0]);
  if (!isFinite(n) || n < 0) return "";
  return trimFixed(n.toFixed(1)) + "%";
}

var BYTE_FACTORS = {
  B: 1,
  KB: 1000,
  MB: 1000000,
  GB: 1000000000,
  TB: 1000000000000,
  PB: 1000000000000000,
  KIB: 1024,
  MIB: 1048576,
  GIB: 1073741824,
  TIB: 1099511627776,
  PIB: 1125899906842624
};

function formatBytes(bytes) {
  var n = Number(bytes);
  if (!isFinite(n) || n < 0) return "";
  if (n >= 1073741824) return trimFixed((n / 1073741824).toFixed(1)) + " GiB";
  if (n >= 1048576) return Math.round(n / 1048576) + " MiB";
  if (n >= 1024) return Math.round(n / 1024) + " KiB";
  return Math.round(n) + " B";
}

// Podman reports SI units ("2.609GB / 7.955GB"); the panel shows binary
// units, so convert through bytes once and format from there.
function formatMemoryUsage(text) {
  var first = String(text || "").split("/")[0].trim();
  if (first === "") return "";
  var m = first.match(/^([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B)$/i);
  if (!m) return "";
  var unit = m[2].toUpperCase();
  var factor = BYTE_FACTORS[unit];
  if (factor === undefined) factor = 1;
  return formatBytes(Number(m[1]) * factor);
}

function formatProcs(pids) {
  var m = String(pids || "").match(/\d+/);
  if (!m) return "";
  var n = Number(m[0]);
  if (!isFinite(n) || n < 0) return "";
  return n + (n === 1 ? " proc" : " procs");
}

// UP 2D 4H / UP 3H 10M / UP 12M. Invalid or future stamps yield "".
function formatUptime(startedAt, nowMs) {
  var started = Date.parse(String(startedAt || ""));
  if (isNaN(started)) return "";
  var now = Number(nowMs);
  if (!isFinite(now)) now = Date.now();
  var mins = Math.max(0, Math.floor((now - started) / 60000));
  if (mins < 1) return "UP <1M";
  var days = Math.floor(mins / 1440);
  var hours = Math.floor(mins / 60) % 24;
  var rest = mins % 60;
  if (days > 0) return "UP " + days + "D" + (hours > 0 ? " " + hours + "H" : "");
  if (hours > 0) return "UP " + hours + "H" + (rest > 0 ? " " + rest + "M" : "");
  return "UP " + rest + "M";
}

// Hero subtitle. Running shows uptime, stopped/failed show the state, and an
// unbuilt environment shows the image only.
function subtitle(image, status, startedAt, nowMs) {
  var info = distroInfo(image);
  var text = info.label + (info.version !== "" ? " " + info.version : "");
  var s = normalizeStatus(status);
  if (s === "unbuilt") return text;
  if (s === "running") {
    var up = formatUptime(startedAt, nowMs);
    return up === "" ? text : text + " · " + up;
  }
  if (s === "failed") return text + " · FAILED";
  if (s === "stopped") return text + " · STOPPED";
  return text;
}

// "● Running · 3.2% cpu · 812 MiB · 14 procs"; unavailable parts are omitted.
function statusLine(status, cpu, memUsage, pids) {
  var s = normalizeStatus(status);
  var word = s === "running" ? "Running"
    : s === "failed" ? "Failed"
    : s === "unbuilt" ? "Not built"
    : "Stopped";
  var parts = ["● " + word];
  if (s === "running") {
    var c = formatCpu(cpu);
    var mem = formatMemoryUsage(memUsage);
    var procs = formatProcs(pids);
    if (c !== "") parts.push(c + " cpu");
    if (mem !== "") parts.push(mem);
    if (procs !== "") parts.push(procs);
  }
  return parts.join(" · ");
}

// -------------------------------------------------------------------- distro

// Specific entries first: "cachy" before "arch", "ubuntu" before "debian".
var DISTROS = [
  { key: "cachy", label: "CACHYOS", family: "arch", match: ["cachy"] },
  { key: "nixos", label: "NIXOS", family: "nixos", match: ["nixos"] },
  { key: "opensuse", label: "OPENSUSE", family: "opensuse", match: ["opensuse", "suse", "tumbleweed"] },
  { key: "alpine", label: "ALPINE", family: "alpine", match: ["alpine"] },
  { key: "ubuntu", label: "UBUNTU", family: "debian", match: ["ubuntu"] },
  { key: "debian", label: "DEBIAN", family: "debian", match: ["debian", "mint", "kali", "elementary"] },
  { key: "fedora", label: "FEDORA", family: "fedora", match: ["fedora", "rhel", "centos", "rocky", "alma", "nobara"] },
  { key: "arch", label: "ARCH", family: "arch", match: ["arch", "manjaro", "endeavouros", "garuda"] }
];

function imageName(image) {
  var s = String(image || "").trim();
  if (s === "") return "";
  var withoutDigest = s.split("@")[0];
  var parts = withoutDigest.split("/");
  return parts[parts.length - 1];
}

function imageTag(image) {
  var base = imageName(image);
  var at = base.lastIndexOf(":");
  return at >= 0 ? base.slice(at + 1) : "";
}

function imageWithoutTag(image) {
  var base = imageName(image);
  var at = base.lastIndexOf(":");
  return at >= 0 ? base.slice(0, at) : base;
}

function distroInfo(image) {
  var raw = String(image || "").toLowerCase();
  if (raw === "") return { key: "", label: "—", version: "", family: "" };

  var match = null;
  for (var i = 0; i < DISTROS.length; i++) {
    var entry = DISTROS[i];
    for (var j = 0; j < entry.match.length; j++) {
      if (raw.indexOf(entry.match[j]) >= 0) { match = entry; break; }
    }
    if (match) break;
  }

  var tag = imageTag(image);
  var version = /^\d+(?:\.\d+)*$/.test(tag) ? tag : "";
  var label = match ? match.label : imageWithoutTag(image).toUpperCase();
  if (label === "") label = "—";

  return {
    key: match ? match.key : "",
    family: match ? match.family : "",
    label: label,
    version: version
  };
}

function distroKey(image) {
  return distroInfo(image).key;
}

// ---------------------------------------------------------------------- color

var FALLBACK_OS_COLOR = "#6366f1";

var DEFAULT_OS_COLORS =
  "fedora=#3c6eb4,arch=#1793d1,ubuntu=#e95420,debian=#d70a53," +
  "alpine=#0d597f,cachy=#00b4a0,nixos=#7ebae4,opensuse=#73ba25,default=#6366f1";

function isHexColor(value) {
  return /^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/.test(String(value || "").trim());
}

function parseOsColors(text) {
  var out = {};
  var parts = String(text || "").split(",");
  for (var i = 0; i < parts.length; i++) {
    var pair = parts[i].replace(/^\s+|\s+$/g, "");
    if (pair === "") continue;
    var eq = pair.indexOf("=");
    if (eq <= 0) continue;
    var key = pair.slice(0, eq).replace(/^\s+|\s+$/g, "").toLowerCase();
    var color = pair.slice(eq + 1).replace(/^\s+|\s+$/g, "");
    if (!/^[a-z0-9_-]+$/.test(key)) continue;
    if (!isHexColor(color)) continue;
    out[key] = color.toLowerCase();
  }
  return out;
}

// Merge user pairs over the shipped defaults so one overridden colour never
// strips the rest of the palette.
function osPalette(text) {
  var base = parseOsColors(DEFAULT_OS_COLORS);
  var custom = parseOsColors(text);
  for (var key in custom) base[key] = custom[key];
  return base;
}

var COLOR_ALIASES = {
  cachyos: "cachy",
  archlinux: "arch",
  tumbleweed: "opensuse",
  "opensuse-tumbleweed": "opensuse",
  rhel: "fedora",
  centos: "fedora",
  rocky: "fedora",
  alma: "fedora",
  nobara: "fedora",
  manjaro: "arch",
  endeavouros: "arch",
  garuda: "arch",
  mint: "debian",
  kali: "debian",
  elementary: "debian"
};

function paletteColor(palette, key) {
  var k = String(key || "").toLowerCase();
  if (k !== "" && palette[k]) return palette[k];
  if (k !== "" && COLOR_ALIASES[k] && palette[COLOR_ALIASES[k]]) return palette[COLOR_ALIASES[k]];
  return palette["default"] || FALLBACK_OS_COLOR;
}

// key -> family -> default, matching the spec's fallback order.
function osColor(setting, distro) {
  var palette = osPalette(setting);
  var info = distroInfoFromKey(distro);
  if (info.key !== "" && palette[info.key]) return palette[info.key];
  if (info.family !== "" && palette[info.family]) return palette[info.family];
  return palette["default"] || FALLBACK_OS_COLOR;
}

// The caller may pass a distro key rather than an image string. An exact
// distro key wins over a family match ("arch" must not resolve to "cachy").
function distroInfoFromKey(key) {
  var k = String(key || "").toLowerCase();
  for (var i = 0; i < DISTROS.length; i++) {
    if (DISTROS[i].key === k) return DISTROS[i];
  }
  for (var j = 0; j < DISTROS.length; j++) {
    if (DISTROS[j].family === k) return DISTROS[j];
  }
  return { key: k, family: "", label: "", match: [] };
}

function parseHexColor(hex) {
  var s = String(hex || "").trim();
  var short = s.match(/^#([0-9A-Fa-f]{3})$/);
  if (short) {
    var sh = short[1];
    s = "#" + sh.charAt(0) + sh.charAt(0) + sh.charAt(1) + sh.charAt(1) + sh.charAt(2) + sh.charAt(2);
  }
  var full = s.match(/^#([0-9A-Fa-f]{6})$/);
  if (!full) return null;
  return {
    r: parseInt(full[1].slice(0, 2), 16) / 255,
    g: parseInt(full[1].slice(2, 4), 16) / 255,
    b: parseInt(full[1].slice(4, 6), 16) / 255
  };
}

function rgbToHsl(rgb) {
  var max = Math.max(rgb.r, rgb.g, rgb.b);
  var min = Math.min(rgb.r, rgb.g, rgb.b);
  var l = (max + min) / 2;
  if (max === min) return { h: 0, s: 0, l: l };
  var d = max - min;
  var s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  var h;
  if (max === rgb.r) h = (rgb.g - rgb.b) / d + (rgb.g < rgb.b ? 6 : 0);
  else if (max === rgb.g) h = (rgb.b - rgb.r) / d + 2;
  else h = (rgb.r - rgb.g) / d + 4;
  return { h: h * 60, s: s, l: l };
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function hslToHex(h, s, l) {
  var hue = ((Number(h) % 360) + 360) % 360;
  var sat = clamp(Number(s) || 0, 0, 1);
  var light = clamp(Number(l) || 0, 0, 1);
  var c = (1 - Math.abs(2 * light - 1)) * sat;
  var x = c * (1 - Math.abs(((hue / 60) % 2) - 1));
  var m = light - c / 2;
  var r = 0, g = 0, b = 0;
  if (hue < 60) { r = c; g = x; }
  else if (hue < 120) { r = x; g = c; }
  else if (hue < 180) { g = c; b = x; }
  else if (hue < 240) { g = x; b = c; }
  else if (hue < 300) { r = x; b = c; }
  else { r = c; b = x; }
  function hex(n) {
    var v = Math.round((n + m) * 255);
    var s2 = v.toString(16);
    return s2.length === 1 ? "0" + s2 : s2;
  }
  return "#" + hex(r) + hex(g) + hex(b);
}

// Spec section 10: dark start, darker end, bright accent, all from one base.
function heroColors(baseHex) {
  var rgb = parseHexColor(baseHex) || parseHexColor(FALLBACK_OS_COLOR);
  var hsl = rgbToHsl(rgb);
  return {
    base: String(baseHex || FALLBACK_OS_COLOR),
    start: hslToHex(hsl.h - 8, hsl.s * 0.55, 0.24),
    end: hslToHex(hsl.h + 14, hsl.s * 0.60, 0.15),
    accent: hslToHex(hsl.h, clamp(hsl.s, 0.5, 0.9), 0.74)
  };
}

// -------------------------------------------------------------------- exports

function normalizeApp(entry) {
  if (!isPlainObject(entry)) return null;
  var id = entry.id !== undefined && entry.id !== null ? String(entry.id) : "";
  if (!isSafeName(id)) return null;
  var name = entry.name !== undefined && entry.name !== null && String(entry.name) !== ""
    ? String(entry.name) : id;
  return {
    id: id,
    name: name,
    desktop: id + ".desktop",
    exported: entry.exported === true
  };
}

function normalizeBin(entry) {
  if (!isPlainObject(entry)) return null;
  var name = entry.name !== undefined && entry.name !== null ? String(entry.name) : "";
  if (!isSafeName(name)) return null;
  return {
    name: name,
    path: entry.path !== undefined && entry.path !== null ? String(entry.path) : "",
    exported: entry.exported === true
  };
}

// `podbox export list -C NAME --output json`. App names and bin paths are
// optional in real output; neither is fabricated when missing.
function parseExportList(text) {
  var parsed = parseJson(text);
  var out = { apps: [], bins: [] };
  if (!isPlainObject(parsed)) return out;
  if (parsed.apps instanceof Array) {
    for (var i = 0; i < parsed.apps.length; i++) {
      var app = normalizeApp(parsed.apps[i]);
      if (app !== null) out.apps.push(app);
    }
  }
  if (parsed.bins instanceof Array) {
    for (var j = 0; j < parsed.bins.length; j++) {
      var bin = normalizeBin(parsed.bins[j]);
      if (bin !== null) out.bins.push(bin);
    }
  }
  return out;
}

function exportedTotal(list) {
  var n = 0;
  var apps = list && list.apps instanceof Array ? list.apps : [];
  var bins = list && list.bins instanceof Array ? list.bins : [];
  for (var i = 0; i < apps.length; i++) if (apps[i] && apps[i].exported === true) n++;
  for (var j = 0; j < bins.length; j++) if (bins[j] && bins[j].exported === true) n++;
  return n;
}

function filterApps(apps, query) {
  var q = String(query || "").replace(/^\s+|\s+$/g, "").toLowerCase();
  var out = [];
  var list = apps instanceof Array ? apps : [];
  for (var i = 0; i < list.length; i++) {
    var app = list[i];
    if (!app) continue;
    if (q === "") { out.push(app); continue; }
    var hay = (String(app.name || "") + " " + String(app.id || "") + " " + String(app.desktop || "")).toLowerCase();
    if (hay.indexOf(q) >= 0) out.push(app);
  }
  return out;
}

// ------------------------------------------------------------------- commands

function parseVersionOutput(text) {
  var lines = String(text || "").split("\n");
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "");
    if (line === "") continue;
    var m = line.match(/v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)/);
    if (m) return m[1];
    return null;
  }
  return null;
}

function versionCommand() {
  // Fixed string, no user data: a missing binary must exit 127 instead of
  // failing the spawn and leaving the probe wedged forever.
  return ["sh", "-c", "exec podbox --version"];
}

function listCommand() {
  return ["podbox", "list", "--output", "json"];
}

function statusCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return ["podbox", "status", "--output", "json", n];
}

function statsCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return ["podbox", "stats", "--no-stream", "--output", "json", n];
}

function watchCommand() {
  return ["podbox", "watch", "--output", "ndjson"];
}

function startCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return ["podbox", "start", n];
}

function stopCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return ["podbox", "stop", n];
}

function restartCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return ["systemctl", "--user", "restart", n + ".service"];
}

function terminalCommand(parts) {
  var out = ["omarchy-launch-tui"];
  for (var i = 0; i < parts.length; i++) out.push(String(parts[i]));
  return out;
}

function enterCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return terminalCommand(["podbox", "enter", n]);
}

function logsCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return terminalCommand(["podbox", "logs", "-f", n]);
}

function editCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return terminalCommand(["podbox", "edit", n]);
}

function buildCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return terminalCommand(["podbox", "build", n]);
}

function initCommand() {
  return terminalCommand(["podbox", "init", "-i"]);
}

function exportListCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return ["podbox", "export", "list", "--output", "json", "-C", n];
}

function exportAppCommand(name, item) {
  var n = String(name || "");
  var i = String(item || "");
  if (!isSafeName(n) || !isSafeName(i)) return null;
  return ["podbox", "export", "app", "-C", n, i];
}

function exportBinCommand(name, item) {
  var n = String(name || "");
  var i = String(item || "");
  if (!isSafeName(n) || !isSafeName(i)) return null;
  return ["podbox", "export", "bin", "-C", n, i];
}

function exportCleanCommand(name) {
  var n = String(name || "");
  if (!isSafeName(n)) return null;
  return ["podbox", "export", "clean", "-C", n];
}

// ----------------------------------------------------------------- icon font

// One canonical list: every glyph rendered anywhere in the plugin. New icons
// must be added here or the structural test fails.
// "0.9.3-1-gb5a8948" (git describe) -> "0.9.3".
function cleanVersion(v) {
  return String(v || "").replace(/-\d+-g[0-9a-f]+(-dirty)?$/, "");
}

var ICONS = {
  search: "\uf002",
  check: "\uf00c",
  close: "\uf00d",
  restart: "\uf021",
  edit: "\uf044",
  start: "\uf04b",
  stop: "\uf04d",
  plus: "\uf067",
  exports: "\uf08e",
  build: "\uf0ad",
  logs: "\uf0f6",
  terminal: "\uf120"
};

var ICON_CODEPOINTS = "F002 F00C F00D F021 F044 F04B F04D F067 F08E F0AD F0F6 F120";

function iconProbeCommand(themeFontFamily) {
  var family = String(themeFontFamily || "monospace");
  return ["fc-match", "-f", "%{family[0]}", ":family=" + family + ":charset=" + ICON_CODEPOINTS];
}

function parseIconProbeOutput(text) {
  var line = String(text || "").split("\n")[0];
  if (!line) return "";
  return line.replace(/^\s+|\s+$/g, "");
}

function iconFont(probed, fallback) {
  var p = String(probed || "");
  return p !== "" ? p : String(fallback || "");
}

if (typeof module !== "undefined") {
  module.exports = {
    isSafeName: isSafeName,
    parseJson: parseJson,
    normalizeStatus: normalizeStatus,
    normalizeEnv: normalizeEnv,
    parseList: parseList,
    parseStatus: parseStatus,
    parseStats: parseStats,
    parseWatchLine: parseWatchLine,
    applyWatchStatus: applyWatchStatus,
    envsSame: envsSame,
    stateWord: stateWord,
    isRunning: isRunning,
    runningCount: runningCount,
    hasFailure: hasFailure,
    findEnv: findEnv,
    pickSelection: pickSelection,
    selectionNames: selectionNames,
    moveSelection: moveSelection,
    primaryAction: primaryAction,
    formatCpu: formatCpu,
    formatBytes: formatBytes,
    formatMemoryUsage: formatMemoryUsage,
    formatProcs: formatProcs,
    formatUptime: formatUptime,
    subtitle: subtitle,
    statusLine: statusLine,
    distroInfo: distroInfo,
    distroKey: distroKey,
    parseOsColors: parseOsColors,
    osPalette: osPalette,
    osColor: osColor,
    heroColors: heroColors,
    parseHexColor: parseHexColor,
    parseExportList: parseExportList,
    exportedTotal: exportedTotal,
    filterApps: filterApps,
    parseVersionOutput: parseVersionOutput,
    versionCommand: versionCommand,
    listCommand: listCommand,
    statusCommand: statusCommand,
    statsCommand: statsCommand,
    watchCommand: watchCommand,
    startCommand: startCommand,
    stopCommand: stopCommand,
    restartCommand: restartCommand,
    enterCommand: enterCommand,
    logsCommand: logsCommand,
    editCommand: editCommand,
    buildCommand: buildCommand,
    initCommand: initCommand,
    exportListCommand: exportListCommand,
    exportAppCommand: exportAppCommand,
    exportBinCommand: exportBinCommand,
    exportCleanCommand: exportCleanCommand,
    iconProbeCommand: iconProbeCommand,
    parseIconProbeOutput: parseIconProbeOutput,
    iconFont: iconFont,
    cleanVersion: cleanVersion,
    ICONS: ICONS,
    ICON_CODEPOINTS: ICON_CODEPOINTS,
    DEFAULT_OS_COLORS: DEFAULT_OS_COLORS,
    FALLBACK_OS_COLOR: FALLBACK_OS_COLOR
  };
}
