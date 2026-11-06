// Unit tests for Podbox.js: parsing, formatting, distro/color, argv builders.
// Run: bun test tests/
import { describe, it, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const Podbox = require(join(dirname(fileURLToPath(import.meta.url)), "..", "Podbox.js"));
const fixture = (name) => readFileSync(join(dirname(fileURLToPath(import.meta.url)), "fixtures", name), "utf8");

describe("isSafeName", () => {
  it("accepts plain names", () => {
    expect(Podbox.isSafeName("android")).toBe(true);
    expect(Podbox.isSafeName("rust-dev")).toBe(true);
    expect(Podbox.isSafeName("a.b_c-1")).toBe(true);
  });

  it("rejects shell metacharacters", () => {
    expect(Podbox.isSafeName("a;id")).toBe(false);
    expect(Podbox.isSafeName("a b")).toBe(false);
    expect(Podbox.isSafeName("$(id)")).toBe(false);
    expect(Podbox.isSafeName("a`b`")).toBe(false);
    expect(Podbox.isSafeName("")).toBe(false);
  });
});

describe("parseList", () => {
  it("parses the real fixture", () => {
    const envs = Podbox.parseList(fixture("list.json"));
    expect(envs.length).toBe(9);
    expect(envs[0]).toEqual({ name: "android", status: "running", autostart: false, active: true });
    expect(envs.every((e) => e.status === "running" || e.status === "stopped")).toBe(true);
  });

  it("drops unsafe names", () => {
    const out = Podbox.parseList(JSON.stringify({ containers: [{ name: "ok", status: "running" }, { name: "a;rm", status: "running" }] }));
    expect(out.map((e) => e.name)).toEqual(["ok"]);
  });

  it("normalises unknown status to stopped", () => {
    const out = Podbox.parseList(JSON.stringify({ containers: [{ name: "x", status: "paused" }] }));
    expect(out[0].status).toBe("stopped");
  });

  it("returns [] for garbage", () => {
    expect(Podbox.parseList("not json")).toEqual([]);
    expect(Podbox.parseList("")).toEqual([]);
    expect(Podbox.parseList("{}")).toEqual([]);
  });
});

describe("parseStatus", () => {
  it("parses the real fixture", () => {
    const s = Podbox.parseStatus(fixture("status-android.json"));
    expect(s.name).toBe("android");
    expect(s.status).toBe("running");
    expect(s.installed).toBe(true);
    expect(s.base_image).toBe("cachyos/cachyos:latest");
    expect(s.started_at).toMatch(/2026-11-03/);
  });

  it("keeps absent fields absent", () => {
    const s = Podbox.parseStatus(JSON.stringify({ name: "x", status: "stopped" }));
    expect(s).toEqual({ name: "x", status: "stopped" });
  });
});

describe("parseStats", () => {
  it("parses the real array fixture", () => {
    const s = Podbox.parseStats(fixture("stats-android.json"), "android");
    expect(s.name).toBe("android");
    expect(s.cpu_percent).toBe("34.96%");
    expect(s.mem_usage).toBe("2.808GB / 7.955GB");
    expect(s.pids).toBe("95");
  });

  it("picks the matching row by name", () => {
    const text = JSON.stringify([{ name: "a", cpu_percent: "1%" }, { name: "b", cpu_percent: "9%" }]);
    expect(Podbox.parseStats(text, "b").cpu_percent).toBe("9%");
  });

  it("returns {} for garbage", () => {
    expect(Podbox.parseStats("nope", "x")).toEqual({});
  });
});

describe("parseWatchLine", () => {
  it("parses real lines", () => {
    const lines = fixture("watch.ndjson").trim().split("\n");
    const first = Podbox.parseWatchLine(lines[0]);
    expect(first).toEqual({ event: { type: "status", name: "android", status: "running" } });
  });

  it("skips non-status events and unsafe names", () => {
    expect(Podbox.parseWatchLine('{"event":"step","name":"x"}')).toEqual({ skip: true });
    expect(Podbox.parseWatchLine('not json')).toEqual({ skip: true });
    expect(Podbox.parseWatchLine('{"event":"status","name":"a;id","status":"running"}')).toEqual({ skip: true });
  });
});

describe("applyWatchStatus", () => {
  it("updates in place and appends new", () => {
    const envs = [{ name: "a", status: "stopped", autostart: false, active: false }];
    const out = Podbox.applyWatchStatus(envs, { name: "a", status: "running" });
    expect(out).toEqual([{ name: "a", status: "running", autostart: false, active: false }]);
    const grown = Podbox.applyWatchStatus(out, { name: "b", status: "stopped" });
    expect(grown.length).toBe(2);
    expect(grown[1]).toEqual({ name: "b", status: "stopped", autostart: false, active: false });
  });

  it("returns the same array reference when the status is unchanged", () => {
    const envs = [{ name: "a", status: "stopped", autostart: false, active: false }];
    expect(Podbox.applyWatchStatus(envs, { name: "a", status: "stopped" })).toBe(envs);
  });
});

describe("envsSame", () => {
  it("is true for identical lists and false on any difference", () => {
    const a = [{ name: "android", status: "running", autostart: false, active: true }];
    expect(Podbox.envsSame(a, a.map((e) => ({ ...e })))).toBe(true);
    expect(Podbox.envsSame(a, [...a, { name: "b", status: "stopped" }])).toBe(false);
    expect(Podbox.envsSame(a, [{ ...a[0], status: "stopped" }])).toBe(false);
    expect(Podbox.envsSame(a, [{ ...a[0], active: false }])).toBe(false);
    expect(Podbox.envsSame(a, [])).toBe(false);
  });
});

describe("stateWord / runningCount / hasFailure", () => {
  it("maps states", () => {
    expect(Podbox.stateWord("running")).toBe("running");
    expect(Podbox.stateWord("stopped")).toBe("stopped");
    expect(Podbox.stateWord("failed")).toBe("failed");
    expect(Podbox.stateWord("unbuilt")).toBe("not built");
  });

  it("counts running and failures", () => {
    const envs = [{ status: "running" }, { status: "failed" }, { status: "stopped" }];
    expect(Podbox.runningCount(envs)).toBe(1);
    expect(Podbox.hasFailure(envs)).toBe(true);
  });
});

describe("selection", () => {
  it("defaults to first running, else first", () => {
    const envs = [{ name: "a", status: "stopped" }, { name: "b", status: "running" }];
    expect(Podbox.pickSelection(envs, "")).toBe("b");
    const stopped = [{ name: "a", status: "stopped" }, { name: "b", status: "stopped" }];
    expect(Podbox.pickSelection(stopped, "")).toBe("a");
  });

  it("keeps current when present", () => {
    const envs = [{ name: "a", status: "running" }];
    expect(Podbox.pickSelection(envs, "a")).toBe("a");
    expect(Podbox.pickSelection([], "a")).toBe("");
  });

  it("moves clamped, not wrapping", () => {
    const envs = [{ name: "a" }, { name: "b" }, { name: "c" }];
    expect(Podbox.moveSelection(envs, "a", -1)).toBe("a");
    expect(Podbox.moveSelection(envs, "c", 5)).toBe("c");
    expect(Podbox.moveSelection(envs, "a", 1)).toBe("b");
  });
});

describe("primaryAction", () => {
  it("maps status to action", () => {
    expect(Podbox.primaryAction("running")).toBe("Stop");
    expect(Podbox.primaryAction("unbuilt")).toBe("Build");
    expect(Podbox.primaryAction("stopped")).toBe("Start");
    expect(Podbox.primaryAction("failed")).toBe("Start");
  });
});

describe("formatting", () => {
  it("formatCpu", () => {
    expect(Podbox.formatCpu("34.96%")).toBe("35%");
    expect(Podbox.formatCpu("35.03%")).toBe("35%");
    expect(Podbox.formatCpu("3.2%")).toBe("3.2%");
    expect(Podbox.formatCpu("")).toBe("");
  });

  it("formatMemoryUsage converts SI to binary", () => {
    expect(Podbox.formatMemoryUsage("2.808GB / 7.955GB")).toBe("2.6 GiB");
    expect(Podbox.formatMemoryUsage("883.6MB / 7.955GB")).toBe("843 MiB");
    expect(Podbox.formatMemoryUsage("")).toBe("");
  });

  it("formatProcs", () => {
    expect(Podbox.formatProcs("95")).toBe("95 procs");
    expect(Podbox.formatProcs("1")).toBe("1 proc");
    expect(Podbox.formatProcs("")).toBe("");
  });

  it("formatUptime", () => {
    const now = Date.parse("2026-11-04T10:00:00+03:00");
    expect(Podbox.formatUptime("2026-11-03T16:43:53+03:00", now)).toMatch(/^UP /);
    expect(Podbox.formatUptime("not a date", now)).toBe("");
    expect(Podbox.formatUptime("", now)).toBe("");
  });

  it("subtitle for running includes uptime", () => {
    const now = Date.parse("2026-11-04T10:00:00+03:00");
    const sub = Podbox.subtitle("cachyos/cachyos:latest", "running", "2026-11-03T16:43:53+03:00", now);
    expect(sub).toMatch(/^CACHYOS · UP /);
  });

  it("subtitle for stopped says STOPPED", () => {
    expect(Podbox.subtitle("fedora:44", "stopped", "", 0)).toBe("FEDORA 44 · STOPPED");
  });

  it("statusLine omits unavailable parts", () => {
    expect(Podbox.statusLine("running", "34.96%", "2.808GB / 7.955GB", "95")).toBe("● Running · 35% cpu · 2.6 GiB · 95 procs");
    expect(Podbox.statusLine("stopped", "", "", "")).toBe("● Stopped");
    expect(Podbox.statusLine("failed", "", "", "")).toBe("● Failed");
    expect(Podbox.statusLine("unbuilt", "", "", "")).toBe("● Not built");
  });
});

describe("distro detection", () => {
  it("detects families in the right order", () => {
    expect(Podbox.distroKey("cachyos/cachyos:latest")).toBe("cachy");
    expect(Podbox.distroKey("archlinux:latest")).toBe("arch");
    expect(Podbox.distroKey("ubuntu:24.04")).toBe("ubuntu");
    expect(Podbox.distroKey("debian:bookworm")).toBe("debian");
    expect(Podbox.distroKey("fedora:44")).toBe("fedora");
    expect(Podbox.distroKey("alpine:3.20")).toBe("alpine");
    expect(Podbox.distroKey("nixos:unstable")).toBe("nixos");
    expect(Podbox.distroKey("opensuse/tumbleweed:latest")).toBe("opensuse");
    expect(Podbox.distroKey("opensuse/leap:15")).toBe("opensuse");
  });

  it("returns empty key for unknown", () => {
    expect(Podbox.distroKey("unknown/image:v1")).toBe("");
  });

  it("extracts numeric versions only", () => {
    expect(Podbox.distroInfo("fedora:44").version).toBe("44");
    expect(Podbox.distroInfo("ubuntu:24.04").version).toBe("24.04");
    expect(Podbox.distroInfo("fedora:latest").version).toBe("");
    expect(Podbox.distroInfo("nixos:unstable").version).toBe("");
  });
});

describe("os colours", () => {
  it("parses and merges over defaults", () => {
    const palette = Podbox.osPalette("arch=#ff0000,junk,=,good=#123456");
    expect(palette.arch).toBe("#ff0000");
    expect(palette.good).toBe("#123456");
    expect(palette.fedora).toBe("#3c6eb4");
  });

  it("osColor resolves key then family then default", () => {
    expect(Podbox.osColor("", "arch")).toBe("#1793d1");
    expect(Podbox.osColor("", "cachy")).toBe("#00b4a0");
    expect(Podbox.osColor("", "unknown")).toBe("#6366f1");
    expect(Podbox.osColor("arch=#ff0000", "arch")).toBe("#ff0000");
  });

  it("heroColors tints dark", () => {
    const c = Podbox.heroColors("#1793d1");
    expect(c.start).toMatch(/^#[0-9a-f]{6}$/);
    expect(c.end).toMatch(/^#[0-9a-f]{6}$/);
    expect(c.accent).toMatch(/^#[0-9a-f]{6}$/);
  });
});

describe("exports", () => {
  it("parses the real fixture with null names", () => {
    const list = Podbox.parseExportList(fixture("export-list-arch.json"));
    expect(list.apps.length).toBe(4);
    expect(list.apps[0]).toEqual({ id: "code", name: "code", desktop: "code.desktop", exported: false });
    expect(list.apps[1]).toEqual({ id: "firefox", name: "Firefox (arch)", desktop: "firefox.desktop", exported: true });
    expect(list.bins).toEqual([]);
  });

  it("counts exported", () => {
    const list = Podbox.parseExportList(fixture("export-list-arch.json"));
    expect(Podbox.exportedTotal(list)).toBe(2);
  });

  it("filters apps", () => {
    const apps = [{ id: "firefox", name: "Firefox", desktop: "firefox.desktop" }, { id: "code", name: "Code", desktop: "code.desktop" }];
    expect(Podbox.filterApps(apps, "fire")).toEqual([apps[0]]);
    expect(Podbox.filterApps(apps, "")).toEqual(apps);
  });

  it("drops bins with null path instead of fabricating one", () => {
    const list = Podbox.parseExportList(JSON.stringify({ bins: [{ name: "rg", path: null, exported: true }] }));
    expect(list.bins).toEqual([{ name: "rg", path: "", exported: true }]);
  });
});

describe("version", () => {
  it("parses the real fixture", () => {
    expect(Podbox.parseVersionOutput(fixture("version.txt"))).toBe("0.9.3-1-gb5a8948");
  });
});

describe("argv builders", () => {
  it("rejects unsafe names", () => {
    expect(Podbox.statusCommand("a;id")).toBeNull();
    expect(Podbox.startCommand("ok")).toEqual(["podbox", "start", "ok"]);
    expect(Podbox.stopCommand("ok")).toEqual(["podbox", "stop", "ok"]);
    expect(Podbox.restartCommand("ok")).toEqual(["systemctl", "--user", "restart", "ok.service"]);
    expect(Podbox.enterCommand("ok")).toEqual(["omarchy-launch-tui", "podbox", "enter", "ok"]);
    expect(Podbox.logsCommand("ok")).toEqual(["omarchy-launch-tui", "podbox", "logs", "-f", "ok"]);
    expect(Podbox.buildCommand("ok")).toEqual(["omarchy-launch-tui", "podbox", "build", "ok"]);
    expect(Podbox.initCommand()).toEqual(["omarchy-launch-tui", "podbox", "init", "-i"]);
    expect(Podbox.exportListCommand("ok")).toEqual(["podbox", "export", "list", "--output", "json", "-C", "ok"]);
    expect(Podbox.exportAppCommand("ok", "../x")).toBeNull();
    expect(Podbox.exportBinCommand("ok", "rg")).toEqual(["podbox", "export", "bin", "-C", "ok", "rg"]);
    expect(Podbox.exportCleanCommand("ok")).toEqual(["podbox", "export", "clean", "-C", "ok"]);
    expect(Podbox.watchCommand()).toEqual(["podbox", "watch", "--output", "ndjson"]);
    expect(Podbox.listCommand()).toEqual(["podbox", "list", "--output", "json"]);
    expect(Podbox.versionCommand()).toEqual(["sh", "-c", "exec podbox --version"]);
    expect(Podbox.statsCommand("ok")).toEqual(["podbox", "stats", "--no-stream", "--output", "json", "ok"]);
    expect(Podbox.statusCommand("ok")).toEqual(["podbox", "status", "--output", "json", "ok"]);
  });
});

describe("icon fonts", () => {
  it("has a canonical codepoint list", () => {
    expect(Podbox.ICON_CODEPOINTS).toBe("F002 F00C F00D F021 F044 F04B F04D F067 F08E F0AD F0F6 F120");
    expect(Podbox.iconFont("Fonts", "monospace")).toBe("Fonts");
    expect(Podbox.iconFont("", "monospace")).toBe("monospace");
  });
});
