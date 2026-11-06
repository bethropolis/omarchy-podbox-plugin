// Structural guards for the QML sources: bindings clobbered by assignment
// fail only at runtime, so assert them here. Run: bun test tests/
import { describe, it, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const qml = (name) => readFileSync(join(root, name), "utf8");
const js = (name) => readFileSync(join(root, name), "utf8");

describe("PodboxModel Process bindings", () => {
  const src = qml("PodboxModel.qml");

  // A `running: false` literal is panel-owned by design; assigning to a
  // bound one strips the binding permanently.
  const bound = [...src.matchAll(/property Process (\w+): Process \{\s*\n\s*running:\s*([^\n]*)/g)]
    .map((m) => ({ name: m[1], binding: m[2].trim() }))
    .filter((p) => /\bio\./.test(p.binding) || /&&|\|\|/.test(p.binding));

  it("treats the watch stream as the only bound Process", () => {
    expect(bound.map((b) => b.name)).toEqual(["watchProc"]);
    expect(bound[0].binding).toMatch(/io\.watchAlive/);
  });

  it("never assigns to a bound `running` property", () => {
    const offenders = bound
      .filter(({ name }) => new RegExp(`\\b${name}\\.running\\s*=`).test(src))
      .map(({ name }) => name);
    expect(offenders).toEqual([]);
  });

  it("keeps the death path idempotent so backoff arms once per dead stream", () => {
    expect(src).toMatch(/property bool watchDead/);
    expect(src).toMatch(/if \(io\.watchDead\) return/);
    expect(src).toMatch(/if \(running\) \{\s*\n\s*io\.watchDead = false/);
  });

  it("guards the overlay model with the same watch process shape", () => {
    // ExportsOverlay owns its own PodboxModel with watchEnabled off; the
    // guard above must still hold for the file that hosts it.
    const overlay = qml("ExportsOverlay.qml");
    expect(overlay).toMatch(/watchEnabled:\s*false/);
    expect(overlay).toMatch(/autoStart:\s*false/);
  });
});

describe("icon fonts", () => {
  const files = [
    "BarWidget.qml",
    "Panel.qml",
    "ExportsOverlay.qml",
    "PodboxModel.qml",
    "components/Rail.qml",
    "components/Hero.qml",
    "components/ActionTile.qml",
    "components/StatusDot.qml",
    "components/PillLogo.qml",
  ];

  // Icons are referenced in QML through the Podbox.ICONS enum, never as
  // literal glyphs. The real whitelist risk is an icon missing from
  // ICON_CODEPOINTS, because that list is what fc-match probes for a
  // covering family.
  it("every ICONS glyph is listed in ICON_CODEPOINTS", () => {
    const src = js("Podbox.js");
    const icons = [...src.matchAll(/^\s+\w+:\s*"\\u([0-9a-fA-F]{4})"/gm)].map((m) => m[1].toUpperCase());
    expect(icons.length).toBeGreaterThan(0);
    const listed = new Set(src.match(/ICON_CODEPOINTS = "([^"]+)"/)[1].split(" "));
    const unlisted = icons.filter((u) => !listed.has(u));
    expect(unlisted).toEqual([]);
  });

  it("every Podbox.ICONS.<name> referenced in QML exists in Podbox.js", () => {
    const src = js("Podbox.js");
    const defined = new Set([...src.matchAll(/^\s+(\w+):\s*"\\u/gm)].map((m) => m[1]));
    for (const f of files) {
      const qmlSrc = qml(f);
      for (const m of qmlSrc.matchAll(/Podbox\.ICONS\.(\w+)/g)) {
        expect(defined.has(m[1]), f + ": Podbox.ICONS." + m[1]).toBe(true);
      }
    }
  });

  it("probes the icon font at startup", () => {
    const src = qml("PodboxModel.qml");
    expect(src).toMatch(/iconProbeCommand/);
    expect(src).toMatch(/fontProbeProc/);
  });
});

describe("ConfirmDialog safety", () => {
  it("preselects Cancel on every ConfirmDialog", () => {
    for (const f of ["Panel.qml", "ExportsOverlay.qml"]) {
      const src = qml(f);
      const dialogs = [...src.matchAll(/ConfirmDialog \{/g)];
      expect(dialogs.length).toBe(1);
      expect(src).toMatch(/selectedIndex:\s*0/);
    }
  });
});

describe("no hardcoded hex colors", () => {
  const files = [
    "BarWidget.qml",
    "Panel.qml",
    "ExportsOverlay.qml",
    "PodboxModel.qml",
    "components/Rail.qml",
    "components/Hero.qml",
    "components/ActionTile.qml",
    "components/StatusDot.qml",
    "components/PillLogo.qml",
  ];

  it("uses theme tokens only in QML", () => {
    const hex = /#[0-9a-fA-F]{3}\b|#[0-9a-fA-F]{6}\b/;
    for (const f of files) {
      const src = qml(f);
      const hit = src.match(hex);
      expect(hit, f).toBeNull();
    }
  });
});

describe("spawn safety", () => {
  it("never uses shell string interpolation for name-bearing commands", () => {
    const src = qml("PodboxModel.qml");
    // Only the fixed version probe may use sh -c.
    const shells = [...src.matchAll(/"sh",\s*"-c"/g)];
    expect(shells.length).toBe(0);
    expect(js("Podbox.js")).toMatch(/versionCommand[\s\S]*?sh", "-c", "exec podbox/);
  });

  it("validates names before they reach a command in the model", () => {
    const src = qml("PodboxModel.qml");
    expect(src).toMatch(/isSafeName/);
    expect(src).toMatch(/execDetached\(Podbox\./);
  });
});

describe("Panel structure", () => {
  it("uses KeyboardPanel with PanelKeyCatcher", () => {
    const src = qml("Panel.qml");
    expect(src).toMatch(/KeyboardPanel/);
    expect(src).toMatch(/PanelKeyCatcher/);
    expect(src).toMatch(/contentWidth:\s*Style\.space\(600\)/);
    expect(src).toMatch(/onCloseRequested/);
    expect(src).toMatch(/onTabRequested/);
  });

  it("renders every state with its own branch", () => {
    const src = qml("Panel.qml");
    expect(src).toMatch(/model\.loading/);
    expect(src).toMatch(/model\.missing/);
    expect(src).toMatch(/model\.installFailed/);
    expect(src).toMatch(/model\.empty/);
  });

  it("wires Up/Down to moveSelection", () => {
    const src = qml("Panel.qml");
    expect(src).toMatch(/onMoveRequested/);
    expect(src).toMatch(/moveSelection/);
  });
});

describe("Overlay structure", () => {
  it("is an Item with OverlayWindow and open/close/toggle", () => {
    const src = qml("ExportsOverlay.qml");
    expect(src).toMatch(/Item \{/);
    expect(src).toMatch(/OverlayWindow/);
    expect(src).toMatch(/function open\(/);
    expect(src).toMatch(/function close\(/);
    expect(src).toMatch(/function toggle\(/);
  });

  it("closes on Escape and backdrop", () => {
    const src = qml("ExportsOverlay.qml");
    expect(src).toMatch(/Key_Escape/);
    expect(src).toMatch(/onClicked:\s*root\.dismiss/);
  });

  it("keeps search out of Commands add-field semantics", () => {
    const src = qml("ExportsOverlay.qml");
    expect(src).toMatch(/Password|Search/i);
    expect(src).toMatch(/filterApps/);
  });
});

describe("BarWidget structure", () => {
  it("owns the model and forwards IPC", () => {
    const src = qml("BarWidget.qml");
    expect(src).toMatch(/PodboxModel/);
    expect(src).toMatch(/ShellIpc/);
    expect(src).toMatch(/function open\(/);
    expect(src).toMatch(/function close\(/);
    expect(src).toMatch(/function toggle/);
    expect(src).toMatch(/opened/);
    expect(src).toMatch(/WidgetButton/);
  });
});
