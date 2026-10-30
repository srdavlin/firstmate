// firstmate-calm under `claude plugin test`: the starship that replaces the stock
// working row while Calm is on, its cadence on the mocked clock, its size against the
// viewport, and how it lets go of a site the surface no longer draws.
import { describe, expect, test } from "claude-code/testing";
import { calmCommand, decodeCells, isStock, rasterOf, spinner, themeChange, unmeasuredSpinner, world } from "./support.ts";

const SAUCER = "▄██▄";
const BODY = "▄─▀██▀";
const BODY_LEFT = "▀██▀─▄";
const COMPACT = "▄─█";
const DEFAULT = 0x01000000;
const DARK_STAR = 0xc5cde0;
const LIGHT_STAR = 0x5c6578;
const DARK_EXHAUST = 0xff6a3d;
const LIGHT_EXHAUST = 0xc4471a;
const DARK_HULL = 0xb7bec8;
const LIGHT_HULL = 0x5c6570;
const DARK_NACELLE = 0x6ec4e0;
const LIGHT_NACELLE = 0x1a7aa3;
const DARK_BRIDGE = 0x3a4250;
const DARK_FLASH = 0xffffff;
const LIGHT_FLASH = 0x0b1018;
const LIGHT_BRIDGE = 0x2c333d;
const TICK = 220;
const TICKS_PER_MOVE = 4;
const DARK_SHIP = [DARK_HULL, DARK_NACELLE, DARK_BRIDGE, DARK_EXHAUST] as const;
const LIGHT_SHIP = [LIGHT_HULL, LIGHT_NACELLE, LIGHT_BRIDGE, LIGHT_EXHAUST] as const;
const SKY = [DEFAULT, DARK_STAR, DARK_EXHAUST] as const;
const LIGHT_SKY = [DEFAULT, LIGHT_STAR, LIGHT_EXHAUST] as const;

describe("the working ship", () => {
  test("replaces the spinner with a two-row raster sized to the row inside the transcript margin", async ($, on) => {
    world(on, { preference: "on\n" });
    const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 })));
    expect(raster).toBeDefined();
    expect(raster!.key).toBe("firstmate-calm-working-ship");
    expect(raster!.columns).toBe(38);
    expect(raster!.rows).toBe(2);
    const { glyphs, foregrounds, backgrounds } = decodeCells(raster!.cells, 38, 2);
    expect(glyphs[0]).toHaveLength(38);
    expect(glyphs[1]).toHaveLength(38);
    // The boat starts at the left edge: glow, twin nacelles, neck, then the round saucer.
    expect(glyphs[1]!.indexOf(BODY)).toBe(1);
    expect(glyphs[0]!.indexOf(SAUCER)).toBe(3);
    expect(foregrounds[1]![0]).toBe(DARK_EXHAUST);
    expect(foregrounds[1]!.slice(1, 7)).toEqual([DARK_NACELLE, DARK_HULL, DARK_NACELLE, DARK_BRIDGE, DARK_BRIDGE, DARK_NACELLE]);
    expect(foregrounds[0]!.slice(1, 7)).toEqual([DARK_NACELLE, DARK_HULL, DARK_NACELLE, DARK_BRIDGE, DARK_BRIDGE, DARK_NACELLE]);
    expect(foregrounds[0]!.slice(7).every((color) => color === DEFAULT || color === DARK_STAR)).toBe(true);
    expect(foregrounds[1]!.slice(7).every((color) => color === DEFAULT || color === DARK_STAR)).toBe(true);
    expect(glyphs[0]!.slice(7) + glyphs[1]!.slice(7)).toMatch(/[.*+·]/);
    expect(backgrounds.flat().every((color) => color === DEFAULT)).toBe(true);
  });

  test("animates the starfield every tick and moves the hull one column every fourth, through blits of the mounted size", async ($, on) => {
    const { clock, journal } = world(on, { preference: "on\n" });
    await $.session.start({ cwd: "/work", surface: "terminal", isInteractive: true });
    const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 })))!;
    const first = decodeCells(raster.cells, 38, 2);
    await clock.advance(TICK);
    expect(journal.blits).toHaveLength(1);
    expect(journal.blits[0]).toMatchObject({ requestId: "agent-main", key: "firstmate-calm-working-ship", columns: 38, rows: 2 });
    const afterOne = decodeCells(journal.blits[0]!.cells, 38, 2);
    expect(afterOne.glyphs[1]!.indexOf(BODY)).toBe(1);
    expect(afterOne.glyphs[1]).not.toBe(first.glyphs[1]);
    await clock.advance(TICK * (TICKS_PER_MOVE - 1));
    expect(journal.blits).toHaveLength(TICKS_PER_MOVE);
    const afterMove = decodeCells(journal.blits[TICKS_PER_MOVE - 1]!.cells, 38, 2);
    expect(afterMove.glyphs[1]!.indexOf(BODY)).toBe(2);
    expect(afterMove.glyphs[0]!.indexOf(SAUCER)).toBe(4);
  });

  test("trails the hull and lights a brief warp flash on a slower cadence, then returns to the normal silhouette", async ($, on) => {
    const { clock, journal } = world(on, { preference: "on\n" });
    await $.session.start({ cwd: "/work", surface: "terminal", isInteractive: true });
    await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 }));
    // Eight ship steps in, the hull has left the edge and a trail of exhaust color trails its rear.
    await clock.advance(TICK * TICKS_PER_MOVE * 2);
    const trailing = decodeCells(journal.blits.at(-1)!.cells, 38, 2);
    const hullStart = trailing.glyphs[1]!.indexOf(BODY);
    expect(hullStart).toBeGreaterThan(2);
    expect(trailing.foregrounds[1]![hullStart - 2]).toBe(DARK_EXHAUST);
    expect(trailing.foregrounds[1]!.every((color) => color !== DARK_FLASH)).toBe(true);
    // Twenty-two ticks in, the flash is lit: the same hull glyphs in the flash color, then it is gone two ticks later.
    await clock.advance(TICK * (22 - TICKS_PER_MOVE * 2));
    const lit = decodeCells(journal.blits.at(-1)!.cells, 38, 2);
    const litStart = lit.glyphs[1]!.indexOf(BODY);
    expect(litStart).toBeGreaterThan(0);
    expect(lit.foregrounds[1]!.slice(litStart, litStart + 6).every((color) => color === DARK_FLASH)).toBe(true);
    expect(lit.foregrounds[0]!.some((color) => color === DARK_FLASH)).toBe(true);
    await clock.advance(TICK * 2);
    const after = decodeCells(journal.blits.at(-1)!.cells, 38, 2);
    expect(after.foregrounds[1]!.every((color) => color !== DARK_FLASH)).toBe(true);
    expect(after.glyphs[1]).toContain(BODY);
  });

  test("paints the warp flash in the light family's contrasting color", async ($, on) => {
    const { clock, journal } = world(on, { preference: "on\n", theme: "light" });
    await $.session.start({ cwd: "/work", surface: "terminal", isInteractive: true });
    await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 }));
    await clock.advance(TICK * 22);
    const lit = decodeCells(journal.blits.at(-1)!.cells, 38, 2);
    expect(lit.foregrounds[1]!.some((color) => color === LIGHT_FLASH)).toBe(true);
  });

  test("stops blitting a site the surface denies and resumes when the spinner is drawn again", async ($, on) => {
    const { clock, journal, denyBlits } = world(on, { preference: "on\n" });
    await $.session.start({ cwd: "/work", surface: "terminal", isInteractive: true });
    await $.ui.render(spinner());
    await clock.advance(TICK);
    expect(journal.blits).toHaveLength(1);
    denyBlits("nothing of firstmate-calm is mounted there");
    await clock.advance(TICK);
    expect(journal.blits).toHaveLength(2);
    await clock.advance(TICK * 5);
    expect(journal.blits).toHaveLength(2);
    denyBlits(undefined);
    await $.ui.render(spinner());
    await clock.advance(TICK);
    expect(journal.blits).toHaveLength(3);
  });

  test("never blits while off, and drops every site when toggled off", async ($, on) => {
    const { clock, journal } = world(on, { preference: "on\n" });
    await $.session.start({ cwd: "/work", surface: "terminal", isInteractive: true });
    await $.ui.render(spinner());
    await clock.advance(TICK);
    expect(journal.blits).toHaveLength(1);
    await $.command.run(calmCommand());
    await clock.advance(TICK * 4);
    expect(journal.blits).toHaveLength(1);
    expect(isStock(await $.ui.render(spinner()))).toBe(true);
    await clock.advance(TICK * 4);
    expect(journal.blits).toHaveLength(1);
  });

  test("sizes to the raster limits: an unmeasured viewport reads as 80 columns, a wide one clips at 512, a narrow one falls back to one row", async ($, on) => {
    world(on, { preference: "on\n" });
    expect(rasterOf(await $.ui.render(unmeasuredSpinner("a")))!.columns).toBe(78);
    expect(rasterOf(await $.ui.render(spinner("b", { columns: 900, rows: 40 })))!.columns).toBe(512);
    const narrow = rasterOf(await $.ui.render(spinner("c", { columns: 5, rows: 40 })))!;
    expect(narrow.columns).toBe(3);
    expect(narrow.rows).toBe(1);
    expect(decodeCells(narrow.cells, 3, 1).glyphs[0]).toBe(COMPACT);
    const tiny = rasterOf(await $.ui.render(spinner("d", { columns: 2, rows: 40 })))!;
    expect(tiny.columns).toBe(1);
    expect(tiny.rows).toBe(1);
    expect(decodeCells(tiny.cells, 1, 1).glyphs[0]).toMatch(/^[ .*+·]$/);
  });

  test("reflows to a new width on the redraw a resize causes, and blits at that width from then on", async ($, on) => {
    const { clock, journal } = world(on, { preference: "on\n" });
    await $.session.start({ cwd: "/work", surface: "terminal", isInteractive: true });
    await $.ui.render(spinner("agent-main", { columns: 80, rows: 24 }));
    await clock.advance(TICK * TICKS_PER_MOVE * 6);
    const wide = decodeCells(journal.blits.at(-1)!.cells, 78, 2);
    expect(wide.glyphs[1]!.indexOf(BODY)).toBe(7);
    const shrunk = rasterOf(await $.ui.render(spinner("agent-main", { columns: 12, rows: 24 })))!;
    expect(shrunk.columns).toBe(10);
    expect(decodeCells(shrunk.cells, 10, 2).glyphs[1]!.indexOf(BODY_LEFT)).toBe(3);
    await clock.advance(TICK);
    expect(journal.blits.at(-1)).toMatchObject({ columns: 10, rows: 2 });
  });

  test("leaves a non-terminal surface to the engine", async ($, on) => {
    const { clock, journal } = world(on, { preference: "on\n" });
    const desktop = { ...spinner(), surface: "desktop" as const };
    expect(isStock(await $.ui.render(desktop as never))).toBe(true);
    await clock.advance(TICK * 4);
    expect(journal.blits).toHaveLength(0);
  });

  test("paints the light theme family's slate stars, grey neck, light-blue saucer and nacelles, dark bridge, and jet exhaust", async ($, on) => {
    world(on, { preference: "on\n", theme: "light" });
    const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 })))!;
    const { foregrounds } = decodeCells(raster.cells, 38, 2);
    expect(foregrounds[1]![0]).toBe(LIGHT_EXHAUST);
    expect(foregrounds[1]!.slice(1, 7)).toEqual([LIGHT_NACELLE, LIGHT_HULL, LIGHT_NACELLE, LIGHT_BRIDGE, LIGHT_BRIDGE, LIGHT_NACELLE]);
    expect(foregrounds[1]!.slice(7).every((color) => color === LIGHT_STAR || color === DEFAULT)).toBe(true);
  });

  // Each theme value needs its own world, so the family rule gets one test per value.
  for (const [theme, expected, family] of [
    ["dark-ansi", DARK_STAR, "dark"],
    ["dark-daltonized", DARK_STAR, "dark"],
    ["light", LIGHT_STAR, "light"],
    ["light-daltonized", LIGHT_STAR, "light"],
    ["light-ansi", LIGHT_STAR, "light"],
    ["auto", LIGHT_STAR, "light"],
    ["custom:rose-pine", LIGHT_STAR, "light"],
  ] as const) {
    test(`paints the ${family} family for the theme value ${JSON.stringify(theme)}`, async ($, on) => {
      world(on, { preference: "on\n", theme });
      const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 })))!;
      const { foregrounds } = decodeCells(raster.cells, 38, 2);
      const sky = family === "dark" ? SKY : LIGHT_SKY;
      const ship = family === "dark" ? DARK_SHIP : LIGHT_SHIP;
      expect(foregrounds[1]!.slice(7).every((color) => color === expected || color === DEFAULT)).toBe(true);
      expect(foregrounds[1]!.every((color) => sky.includes(color as never) || ship.includes(color as never))).toBe(true);
      expect(foregrounds[1]![1]).toBe(ship[1]);
    });
  }

  test("re-paints in the new family after the theme changes, through the next drawing and every later blit", async ($, on) => {
    const { clock, journal } = world(on, { preference: "on\n", theme: "dark" });
    await $.session.start({ cwd: "/work", surface: "terminal", isInteractive: true });
    await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 }));
    await clock.advance(TICK);
    expect(SKY).toContain(decodeCells(journal.blits.at(-1)!.cells, 38, 2).foregrounds[1]!.at(-1));
    const redrawsBefore = journal.invalidations.length;
    const changed = await $.config.set(themeChange("light", "dark"));
    expect(changed.value).toBe("light");
    expect(journal.invalidations.length).toBe(redrawsBefore + 1);
    await clock.advance(TICK);
    expect(LIGHT_SKY).toContain(decodeCells(journal.blits.at(-1)!.cells, 38, 2).foregrounds[1]!.at(-1));
    const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 })))!;
    expect(LIGHT_SKY).toContain(decodeCells(raster.cells, 38, 2).foregrounds[1]!.at(-1));
    // A change within the same family redraws nothing.
    const redrawsAfter = journal.invalidations.length;
    await $.config.set(themeChange("light-ansi", "light"));
    expect(journal.invalidations.length).toBe(redrawsAfter);
  });

  test("leaves a theme change to the engine while Calm is off, and paints the new family once Calm turns on", async ($, on) => {
    const { journal } = world(on, { theme: "dark" });
    await $.session.start({ cwd: "/work", surface: "terminal", isInteractive: true });
    const redrawsBefore = journal.invalidations.length;
    await $.config.set(themeChange("light", "dark"));
    expect(journal.invalidations.length).toBe(redrawsBefore);
    await $.command.run(calmCommand());
    const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 })))!;
    expect(LIGHT_SKY).toContain(decodeCells(raster.cells, 38, 2).foregrounds[1]!.at(-1));
  });
});
