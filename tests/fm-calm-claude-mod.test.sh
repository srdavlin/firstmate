#!/usr/bin/env bash
# Portable checks for the Claude Code Calm mod (.claude/mods/firstmate-calm) that need
# no Claude Code binary, so CI enforces them wherever Node runs:
#   - the plugin's declared shape: one hooks module and nothing else, reached from the
#     project's .claude/skills auto-load path through the tracked symlink, so nothing
#     of it can load while CLAUDE_CODE_ENABLE_FUNCTION_HOOKS is off;
#   - the harness-neutral sprite core both harnesses share: the Pi widget's rendering
#     is byte-for-byte the shared frame painted with standard ANSI codes, so extracting
#     the core changed nothing Pi draws;
#   - the Raster packing of that frame and its base64 encoder;
#   - the pure presentation policy: home resolution, preference values, working notes;
#   - the operational-input classifier's parity with bin/fm-operational-input.sh over
#     envelopes the shell owner itself encodes, its legacy shapes, and near misses.
# The engine-bound behavior runs under tests/fm-calm-claude-mod-plugin.test.sh and the
# real TUI under tests/fm-calm-claude-mod-live-e2e.test.sh.
# shellcheck disable=SC2016 # Backticks are literal historical prompt markup in the corpus.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MOD="$ROOT/.claude/mods/firstmate-calm"
PI_SHIP="$ROOT/.pi/extensions/lib/fm-calm-working-ship.ts"
PI_SPRITE="$ROOT/.pi/extensions/lib/fm-calm-working-ship-sprite.ts"
OPERATIONAL_INPUT="$ROOT/bin/fm-operational-input.sh"
TMP_ROOT=$(fm_test_tmproot fm-calm-claude-mod)

command -v node >/dev/null 2>&1 || { echo "skip: node not found for the Claude Code Calm mod checks"; exit 0; }

run_node() {  # <script-file>
  node --input-type=module <"$1"
}

test_plugin_shape() {
  local link resolved autoload
  link="$ROOT/.agents/skills/firstmate-calm"
  [ -L "$link" ] || fail "the Calm mod is not linked into .agents/skills, so Claude Code's project skills-dir scan cannot adopt it"
  resolved=$(cd "$link" && pwd -P) || fail "the .agents/skills/firstmate-calm link does not resolve"
  [ "$resolved" = "$(cd "$MOD" && pwd -P)" ] || fail "the .agents/skills/firstmate-calm link resolves to $resolved, not the mod"
  autoload="$ROOT/.claude/skills/firstmate-calm"
  [ -f "$autoload/.claude-plugin/plugin.json" ] || fail "the project's .claude/skills path does not reach the mod's manifest"
  [ -f "$autoload/hooks/hooks.json" ] || fail "the project's .claude/skills path does not reach the mod's hooks module declaration"
  [ -L "$PI_SPRITE" ] || fail "the Pi sprite path is not a symlink to the shared core"
  [ "$(node -e 'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' "$PI_SPRITE")" = \
    "$(node -e 'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' "$MOD/lib/fm-calm-working-ship-sprite.ts")" ] \
    || fail "the Pi sprite path does not resolve to the mod's shared core"
  [ ! -e "$MOD/SKILL.md" ] || fail "the mod carries a SKILL.md and would load as a skill on every harness"
  cat >"$TMP_ROOT/shape.mjs" <<JS
import { readFileSync, readdirSync, existsSync } from "node:fs";
const mod = ${MOD@Q};
const manifest = JSON.parse(readFileSync(\`\${mod}/.claude-plugin/plugin.json\`, "utf8"));
if (manifest.name !== "firstmate-calm") throw new Error(\`manifest name \${manifest.name}\`);
for (const key of ["commands", "agents", "skills", "hooks", "mcpServers", "lspServers", "outputStyles"]) {
  if (key in manifest) throw new Error(\`manifest declares \${key}, which would load while the flag is off\`);
}
const hooks = JSON.parse(readFileSync(\`\${mod}/hooks/hooks.json\`, "utf8"));
const keys = Object.keys(hooks).sort();
if (JSON.stringify(keys) !== JSON.stringify(["description", "modules"])) {
  throw new Error(\`hooks.json declares \${keys.join(", ")}: a classic hook would run while the flag is off\`);
}
if (JSON.stringify(hooks.modules) !== JSON.stringify(["./register.ts"])) throw new Error("hooks.json names a different module");
if (!existsSync(\`\${mod}/hooks/register.ts\`)) throw new Error("the hooks module is missing");
const entries = readdirSync(mod).filter((name) => name !== ".claude-plugin").sort();
if (JSON.stringify(entries) !== JSON.stringify(["hooks", "lib", "tests"])) {
  throw new Error(\`the mod folder holds \${entries.join(", ")}: only hooks, lib, and tests may exist\`);
}
console.log("shape-ok");
JS
  out=$(run_node "$TMP_ROOT/shape.mjs" 2>&1) || fail "plugin shape: $out"
  assert_contains "$out" "shape-ok" "plugin shape check did not complete"
  pass "the Calm mod is one hooks module, linked into the project's auto-load path, with no command, skill, agent, or classic hook path that bypasses its exact opt-in"
}

test_shared_sprite_and_pi_rendering() {
  local out
  cat >"$TMP_ROOT/sprite.mjs" <<JS
import { pathToFileURL } from "node:url";
const pi = await import(pathToFileURL(${PI_SHIP@Q}).href);
const core = await import(pathToFileURL(${MOD@Q} + "/lib/fm-calm-working-ship-sprite.ts").href);
const ESC = "\\u001b";
const ANSI = { star: ESC + "[37m", hull: ESC + "[37m", saucer: ESC + "[36m", nacelle: ESC + "[36m", bridge: ESC + "[30m", exhaust: ESC + "[31m", flash: ESC + "[97m" };
const RESET = ESC + "[39m";
const COLORS = ["plain", "star", "hull", "saucer", "nacelle", "bridge", "exhaust", "flash"];
const STAR = core.CALM_WORKING_SHIP_STAR_GLYPHS.join("");
const EXHAUST = core.CALM_WORKING_SHIP_EXHAUST_GLYPHS.join("");
const SPARK = core.CALM_WORKING_SHIP_EXHAUST_SPARK.join("");
const BODY_RIGHT = core.CALM_WORKING_SHIP_BODY_RIGHT;
const BODY_LEFT = core.CALM_WORKING_SHIP_BODY_LEFT;
const SAUCER_RIGHT = core.CALM_WORKING_SHIP_SAUCER_RIGHT;
const SAUCER_LEFT = core.CALM_WORKING_SHIP_SAUCER_LEFT;
const COMPACT_RIGHT = core.CALM_WORKING_SHIP_COMPACT_RIGHT;
const COMPACT_LEFT = core.CALM_WORKING_SHIP_COMPACT_LEFT;
const paint = (row) => row.map((run) => (run.color === "plain" ? run.text : ANSI[run.color] + run.text + RESET)).join("");
const cells = (row) => row.map((run) => run.text).join("");
const check = (condition, message) => { if (!condition) throw new Error(message); };
check(pi.CALM_WORKING_SHIP_TICK_MS === core.CALM_WORKING_SHIP_TICK_MS, "Pi re-exports a different tick");
check(pi.CALM_WORKING_SHIP_TICKS_PER_MOVE === core.CALM_WORKING_SHIP_TICKS_PER_MOVE, "Pi re-exports a different move cadence");
let frames = 0;
for (const width of [0, 1, 2, 3, 4, 5, 6, 9, 12, 24, 40, 80, 121]) {
  const animation = pi.createCalmWorkingShipAnimation();
  const sprite = core.createCalmWorkingShipSprite();
  for (let step = 0; step < 41; step += 1) {
    const rendered = animation.render(width);
    const frame = sprite.frame(width);
    const expected = frame.map(paint);
    check(JSON.stringify(rendered) === JSON.stringify(expected), \`Pi rendering diverged from the shared frame at width \${width} step \${step}: \${JSON.stringify(rendered)} vs \${JSON.stringify(expected)}\`);
    check(animation.position() === sprite.position() && animation.direction() === sprite.direction() && animation.waterPhase() === sprite.waterPhase() && animation.warpFlash() === sprite.warpFlash(), \`Pi animation state diverged at width \${width} step \${step}\`);
    if (width === 0) check(frame.length === 0, "zero width painted a row");
    if (width > 0) {
      for (const row of frame) {
        check(cells(row).length === width, \`a row is \${cells(row).length} cells at width \${width}\`);
        for (const run of row) check(COLORS.includes(run.color), \`unknown color \${run.color}\`);
      }
      if (width >= 7) {
        check(frame.length === 2, \`width \${width} did not paint two rows\`);
        const hull = cells(frame[1]);
        const saucer = cells(frame[0]);
        const travellingRight = sprite.direction() >= 0;
        check(hull.includes(travellingRight ? BODY_RIGHT : BODY_LEFT), \`width \${width} lost the directional hull\`);
        check(saucer.includes(SAUCER_RIGHT), \`width \${width} lost the round saucer\`);
        // A lit warp flash recolors the hull cells and leaves every glyph in place.
        const hullColors = sprite.warpFlash() ? ["flash"] : ["nacelle", "hull", "saucer", "bridge"];
        for (const color of hullColors) check(frame[1].some((run) => run.color === color), \`the hull row lost its \${color} cells\`);
        check(frame[1].some((run) => run.color === "exhaust"), "the hull row lost its rear exhaust");
        check(frame[0].some((run) => run.color === hullColors[0]), "the saucer row lost its twin nacelle");
      } else if (width >= 3) {
        const compact = cells(frame[0]);
        check(frame.length === 1 && (compact.includes(COMPACT_RIGHT) || compact.includes(COMPACT_LEFT)), \`width \${width} lost the compact silhouette: \${compact}\`);
      } else {
        check(frame.length === 1 && [...cells(frame[0])].every((glyph) => glyph === " " || STAR.includes(glyph)), \`width \${width} lost the starfield-only fallback: \${cells(frame[0])}\`);
      }
    }
    animation.tick();
    sprite.tick();
    frames += 1;
  }
}
// Freeze and resume: restoring the last painted frame discards later ticks on both.
{
  const animation = pi.createCalmWorkingShipAnimation();
  const sprite = core.createCalmWorkingShipSprite();
  animation.render(30); sprite.frame(30);
  for (let step = 0; step < 9; step += 1) { animation.tick(); sprite.tick(); }
  animation.render(30); sprite.frame(30);
  for (let step = 0; step < 6; step += 1) { animation.tick(); sprite.tick(); }
  animation.restoreLastRendered(); sprite.restoreLastRendered();
  check(animation.position() === sprite.position() && animation.waterPhase() === sprite.waterPhase(), "restore diverged");
  check(sprite.waterPhase() === 1 && sprite.position() === 2, \`restore landed at phase \${sprite.waterPhase()} column \${sprite.position()}\`);
  sprite.clampToWidth(8);
  check(sprite.position() === 1 && sprite.direction() === -1, "a hidden clamp did not turn the boat at the new edge");
  sprite.reset();
  check(sprite.position() === 0 && sprite.direction() === 1 && sprite.waterPhase() === 0, "reset did not restore the initial state");
}
// The Enterprise-inspired art is a top-down Constitution-class silhouette that
// flies with the saucer leading, with twin nacelles, rear glow, and a starfield.
{
  check(Array.from(SAUCER_RIGHT).length === 4 && Array.from(BODY_RIGHT).length === 6, "the starship is not a four-cell saucer over a six-cell lower hull");
  check(Array.from(SAUCER_LEFT).reverse().join("") === SAUCER_RIGHT, "the saucer disk is not left-right symmetric");
  check(Array.from(BODY_LEFT).reverse().join("") === BODY_RIGHT, "the left hull is not the right hull reversed");
  check(BODY_RIGHT.startsWith("▄") && BODY_LEFT.endsWith("▄"), "the lower hull lost its twin nacelle");
  const sprite = core.createCalmWorkingShipSprite();
  const seenBodies = new Set();
  const seenSaucers = new Set();
  const directions = new Set();
  for (let step = 0; step < 4 * 12 * 3; step += 1) {
    const frame = sprite.frame(17);
    directions.add(sprite.direction());
    const hull = cells(frame[1]);
    const saucer = cells(frame[0]);
    if (hull.includes(BODY_RIGHT)) seenBodies.add(BODY_RIGHT);
    if (hull.includes(BODY_LEFT)) seenBodies.add(BODY_LEFT);
    if (saucer.includes(SAUCER_RIGHT)) seenSaucers.add(SAUCER_RIGHT);
    if (saucer.includes(SAUCER_LEFT)) seenSaucers.add(SAUCER_LEFT);
    check(frame[1].some((run) => run.color === "exhaust" && [...run.text].some((glyph) => EXHAUST.includes(glyph))), "a full-width frame lost rear exhaust");
    const nacelleColor = sprite.warpFlash() ? "flash" : "nacelle";
    check(frame[0].some((run) => run.color === nacelleColor) && frame[1].some((run) => run.color === nacelleColor), "a full-width frame lost twin nacelles");
    sprite.tick();
  }
  check(directions.size === 2, "the sweep never travelled both directions");
  check(seenBodies.has(BODY_RIGHT) && seenBodies.has(BODY_LEFT), \`the hull never faced both ways: \${JSON.stringify([...seenBodies])}\`);
  check(seenSaucers.has(SAUCER_RIGHT), \`the round saucer never appeared: \${JSON.stringify([...seenSaucers])}\`);
  const exact = core.createCalmWorkingShipSprite();
  const full = exact.frame(7).map(cells);
  check(full[0].includes(SAUCER_RIGHT) && full[1].includes(BODY_RIGHT), "the minimum full-ship frame lost the right-facing silhouette");
  check(full[1].includes(core.CALM_WORKING_SHIP_EXHAUST_GLYPHS[0]), "the minimum full-ship frame lost its exhaust pulse");
  const compact = exact.frame(3).map(cells);
  check(JSON.stringify(compact) === JSON.stringify([COMPACT_RIGHT]), \`the compact fallback is not the three-cell silhouette: \${JSON.stringify(compact)}\`);
  check(SPARK.length === 4 && EXHAUST.length === 4, "exhaust pulse tables drifted");
}
console.log("sprite-ok frames=" + frames);
JS
  out=$(run_node "$TMP_ROOT/sprite.mjs" 2>&1) || fail "shared sprite: $out"
  assert_contains "$out" "sprite-ok frames=533" "the sprite parity sweep did not cover every width and step"
  pass "the Pi working ship renders byte-for-byte the shared sprite core's frame painted in standard ANSI, at every width, cadence step, freeze, clamp, and reset, and keeps a directional top-down Constitution-class Enterprise with twin nacelles, rear glow, and a starfield in both travel directions"
}

test_warp_flash_and_impulse_trail() {
  local out
  cat >"$TMP_ROOT/motion.mjs" <<JS
import { pathToFileURL } from "node:url";
const pi = await import(pathToFileURL(${PI_SHIP@Q}).href);
const core = await import(pathToFileURL(${MOD@Q} + "/lib/fm-calm-working-ship-sprite.ts").href);
const raster = await import(pathToFileURL(${MOD@Q} + "/lib/fm-calm-ship-raster.ts").href);
const check = (condition, message) => { if (!condition) throw new Error(message); };
const cells = (row) => row.map((run) => run.text).join("");
const colorAt = (row, column) => {
  let at = 0;
  for (const run of row) for (const glyph of Array.from(run.text)) { if (at === column) return { glyph, color: run.color }; at += 1; }
  return undefined;
};
const TRAIL = core.CALM_WORKING_SHIP_TRAIL_GLYPHS;
const LENGTHS = core.CALM_WORKING_SHIP_TRAIL_LENGTHS;
const PERIOD = core.CALM_WORKING_SHIP_WARP_FLASH_PERIOD_TICKS;
const LIT = core.CALM_WORKING_SHIP_WARP_FLASH_TICKS;
const MOVE = core.CALM_WORKING_SHIP_TICKS_PER_MOVE;
const SHIP_WIDTH = Array.from(core.CALM_WORKING_SHIP_BODY_RIGHT).length + 1;
// The trail's cells behind the rear exhaust, nearest first, read straight off a hull row.
const trailBehind = (sprite, row) => {
  const right = sprite.direction() >= 0;
  const rear = right ? sprite.position() : sprite.position() + SHIP_WIDTH - 1;
  const out = [];
  for (let step = 1; step <= 4; step += 1) {
    const at = colorAt(row, rear + (right ? -step : step));
    if (!at || at.color !== "exhaust" || !TRAIL.includes(at.glyph)) break;
    out.push(at.glyph);
  }
  return out;
};

// The flash cadence is linked to the scheduler tick, slower than a ship step, and short.
check(PERIOD % MOVE === 0 && PERIOD > MOVE, "the flash period is not a slower whole number of ship steps");
check(LIT >= 1 && LIT < MOVE, "the flash is not a brief burst shorter than one ship step");
check(pi.createCalmWorkingShipAnimation().warpFlash() === false, "the Pi animation does not start unlit");

// The trail sits behind the hull in both travel directions, fades, breathes between two and four cells, never copies the exhaust glyphs, and the saucer row carries it too.
{
  const WIDTH = 20;
  const sprite = core.createCalmWorkingShipSprite();
  const lengths = new Set();
  const seenDirections = new Set();
  for (let step = 0; step < PERIOD * 5; step += 1) {
    const frame = sprite.frame(WIDTH);
    const hull = frame[1];
    const length = trailBehind(sprite, hull).length;
    const room = sprite.direction() >= 0 ? sprite.position() : WIDTH - (sprite.position() + SHIP_WIDTH);
    const expected = Math.min(room, sprite.warpFlash() ? 4 : LENGTHS[sprite.waterPhase()]);
    check(length === expected, \`step \${step} trail was \${length} cells, expected \${expected} (room \${room})\`);
    check(JSON.stringify(trailBehind(sprite, hull)) === JSON.stringify(TRAIL.slice(0, length)), "the trail did not fade strongest-first away from the hull");
    check(JSON.stringify(trailBehind(sprite, frame[0])) === JSON.stringify(trailBehind(sprite, hull)), "the saucer row's nacelle trail differs from the hull row's");
    if (room >= 4) lengths.add(length);
    seenDirections.add(sprite.direction());
    // Nothing of the trail appears ahead of the saucer, and every trail glyph sits on the rear side.
    const right = sprite.direction() >= 0;
    const flat = cells(hull);
    const rearSide = right ? flat.slice(0, sprite.position()) : flat.slice(sprite.position() + SHIP_WIDTH);
    const frontSide = right ? flat.slice(sprite.position() + SHIP_WIDTH) : flat.slice(0, sprite.position());
    check(![...frontSide].some((glyph) => TRAIL.includes(glyph)), "a trail glyph appeared ahead of the hull");
    check([...rearSide].filter((glyph) => TRAIL.includes(glyph)).length === length, "trail glyphs drifted away from the rear exhaust");
    sprite.tick();
  }
  check(seenDirections.size === 2, "the trail sweep never flew both directions");
  check([...lengths].every((length) => length >= 2 && length <= 4) && lengths.size >= 3, \`the trail did not breathe over 2-4 cells: \${JSON.stringify([...lengths])}\`);
  const exhaustGlyphs = [...core.CALM_WORKING_SHIP_EXHAUST_GLYPHS, ...core.CALM_WORKING_SHIP_EXHAUST_SPARK];
  check(TRAIL.every((glyph) => !exhaustGlyphs.includes(glyph) && !core.CALM_WORKING_SHIP_STAR_GLYPHS.includes(glyph)), "a trail glyph is indistinguishable from the exhaust pulse or a star");
}

// The trail clips to every width, and the compact fallback keeps it short.
for (let width = 1; width <= 60; width += 1) {
  const sprite = core.createCalmWorkingShipSprite();
  for (let step = 0; step < PERIOD * 3; step += 1) {
    const frame = sprite.frame(width);
    for (const row of frame) check(cells(row).length === width, \`width \${width} row was \${cells(row).length} cells\`);
    if (width >= 3 && width < SHIP_WIDTH) {
      const trail = [...cells(frame[0])].filter((glyph) => TRAIL.includes(glyph));
      check(trail.length <= core.CALM_WORKING_SHIP_COMPACT_TRAIL_MAX, \`compact width \${width} drew a \${trail.length}-cell trail\`);
    }
    sprite.tick();
  }
}
{
  const sprite = core.createCalmWorkingShipSprite();
  let sawCompactTrail = false;
  for (let step = 0; step < PERIOD * 4; step += 1) {
    const frame = sprite.frame(6);
    if ([...cells(frame[0])].some((glyph) => TRAIL.includes(glyph))) sawCompactTrail = true;
    sprite.tick();
  }
  check(sawCompactTrail, "the compact fallback never drew a trail");
}

// The warp flash lights on a slower deterministic cadence, recolors the hull without changing its silhouette, adds a streak ahead, then returns to normal.
{
  const sprite = core.createCalmWorkingShipSprite();
  const twin = core.createCalmWorkingShipSprite();
  const lit = [];
  for (let step = 0; step < PERIOD * 3; step += 1) {
    const frame = sprite.frame(40);
    check(JSON.stringify(frame) === JSON.stringify(twin.frame(40)), "two sprites with the same ticks painted different frames");
    check(sprite.warpFlash() === (step % PERIOD >= PERIOD - LIT), \`flash lit state at tick \${step} is not the deterministic cadence\`);
    const hullGlyphs = cells(frame[1]);
    const right = sprite.direction() >= 0;
    const body = right ? core.CALM_WORKING_SHIP_BODY_RIGHT : core.CALM_WORKING_SHIP_BODY_LEFT;
    check(hullGlyphs.includes(body), "the flash changed the hull silhouette");
    const bodyStart = hullGlyphs.indexOf(body);
    const flashColumns = [];
    for (let column = 0; column < 40; column += 1) if (colorAt(frame[1], column)?.color === "flash") flashColumns.push(column);
    if (sprite.warpFlash()) {
      lit.push(step);
      for (let offset = 0; offset < Array.from(body).length; offset += 1) check(colorAt(frame[1], bodyStart + offset)?.color === "flash", "the lit hull kept a normal color");
      const aheadStart = right ? sprite.position() + SHIP_WIDTH : sprite.position() - 1;
      const streak = core.CALM_WORKING_SHIP_WARP_STREAK_GLYPHS;
      streak.forEach((glyph, offset) => {
        const at = colorAt(frame[1], aheadStart + (right ? offset : -offset));
        if (at) check(at.glyph === glyph && at.color === "flash", "the warp streak is not ahead of the saucer");
      });
    } else {
      check(flashColumns.length === 0, "an unlit frame carried flash color");
      for (const color of ["nacelle", "hull", "saucer", "bridge"]) check(frame[1].some((run) => run.color === color), \`an unlit frame lost its \${color} cells\`);
    }
    sprite.tick();
    twin.tick();
  }
  check(lit.length === LIT * 3, \`the flash lit \${lit.length} ticks in three periods, not \${LIT * 3}\`);
}

// A freeze mid-flash restores the same lit frame, trail, and streak, and a flash that started while hidden does not leak into the restored state.
{
  for (const frozenAt of [PERIOD - LIT, PERIOD - 1, 3, PERIOD + 7]) {
    for (const sprite of [core.createCalmWorkingShipSprite(), pi.createCalmWorkingShipAnimation()]) {
      const draw = (width) => (sprite.frame ? sprite.frame(width) : sprite.render(width));
      for (let step = 0; step < frozenAt; step += 1) sprite.tick();
      const before = JSON.stringify(draw(30));
      const flashBefore = sprite.warpFlash();
      for (let step = 0; step < PERIOD + 5; step += 1) sprite.tick();
      sprite.restoreLastRendered();
      check(sprite.warpFlash() === flashBefore, \`restore at tick \${frozenAt} changed the flash state\`);
      check(JSON.stringify(draw(30)) === before, \`restore at tick \${frozenAt} did not repaint the frozen frame\`);
      sprite.tick();
      sprite.reset();
      check(sprite.warpFlash() === false, "reset did not return to the unlit state");
    }
  }
}

// Pi paints the flash as bright white and the trail in the exhaust red, byte-for-byte what the shared frame says.
{
  const ESC = "\\u001b";
  const animation = pi.createCalmWorkingShipAnimation();
  const sprite = core.createCalmWorkingShipSprite();
  let sawFlash = false;
  for (let step = 0; step < PERIOD * 2; step += 1) {
    const rendered = animation.render(40);
    sprite.frame(40);
    if (animation.warpFlash()) {
      sawFlash = true;
      check(rendered.every((row) => row.includes(ESC + "[97m")), "the lit Pi hull rows carried no bright white");
    } else {
      check(rendered.every((row) => !row.includes(ESC + "[97m")), "an unlit Pi row carried the flash color");
    }
    animation.tick();
    sprite.tick();
  }
  check(sawFlash, "Pi never lit the warp flash");
}

// Claude Code's Raster gives the flash its own contrasting color per theme family, distinct from every hull class.
{
  for (const [family, colors] of Object.entries(raster.CALM_SHIP_RASTER_PALETTES)) {
    const others = ["star", "hull", "saucer", "nacelle", "bridge", "exhaust"].map((color) => colors[color]);
    check(!others.includes(colors.flash), \`\${family} flash color is not distinct\`);
  }
}
console.log("motion-ok");
JS
  out=$(run_node "$TMP_ROOT/motion.mjs" 2>&1) || fail "warp flash and impulse trail: $out"
  assert_contains "$out" "motion-ok" "the warp flash and impulse trail check did not complete"
  pass "the working ship draws a 2-4 cell fading impulse trail behind the hull in both directions, clipped to every width with a shorter compact fallback, and a brief deterministic warp flash on a slower tick cadence that recolors the unchanged silhouette, streaks ahead, and restores exactly across freeze, resume, and reset"
}

test_raster_packing() {
  local out
  cat >"$TMP_ROOT/raster.mjs" <<JS
import { pathToFileURL } from "node:url";
import { randomBytes } from "node:crypto";
const raster = await import(pathToFileURL(${MOD@Q} + "/lib/fm-calm-ship-raster.ts").href);
const core = await import(pathToFileURL(${MOD@Q} + "/lib/fm-calm-working-ship-sprite.ts").href);
const check = (condition, message) => { if (!condition) throw new Error(message); };
for (let length = 0; length <= 80; length += 1) {
  const bytes = new Uint8Array(randomBytes(length));
  check(raster.encodeBase64(bytes) === Buffer.from(bytes).toString("base64"), \`base64 diverged at length \${length}\`);
}
const decode = (cells, columns, rows) => {
  const words = new Uint32Array(new Uint8Array(Buffer.from(cells, "base64")).buffer);
  check(words.length === columns * rows * 3, \`\${words.length} words for \${columns}x\${rows}\`);
  const grid = [];
  for (let row = 0; row < rows; row += 1) {
    const line = [];
    for (let column = 0; column < columns; column += 1) {
      const offset = (row * columns + column) * 3;
      line.push({ glyph: String.fromCodePoint(words[offset]), fg: words[offset + 1], bg: words[offset + 2] });
    }
    grid.push(line);
  }
  return grid;
};
// Stars, grey hull, light-blue nacelles, dark bridge, and jet exhaust per theme family.
const palettes = raster.CALM_SHIP_RASTER_PALETTES;
check(palettes.dark.star === 0xc5cde0 && palettes.dark.hull === 0xb7bec8 && palettes.dark.nacelle === 0x6ec4e0 && palettes.dark.bridge === 0x3a4250 && palettes.dark.exhaust === 0xff6a3d, "dark palette is not slate stars, grey hull, light-blue nacelles, dark bridge, and jet exhaust");
check(palettes.light.star === 0x5c6578 && palettes.light.hull === 0x5c6570 && palettes.light.nacelle === 0x1a7aa3 && palettes.light.bridge === 0x2c333d && palettes.light.exhaust === 0xc4471a, "light palette is not slate stars, grey hull, light-blue nacelles, dark bridge, and jet exhaust");
// The saucer rim is the light blue, not the grey of the neck, in both theme families; the flash keeps its own contrasting color.
check(palettes.dark.saucer === 0x6ec4e0 && palettes.light.saucer === 0x1a7aa3, "the saucer rim is not light blue");
check(palettes.dark.saucer !== palettes.dark.hull && palettes.light.saucer !== palettes.light.hull, "the saucer rim shares the neck's grey");
check(palettes.dark.flash === 0xffffff && palettes.light.flash === 0x0b1018, "the warp flash color changed");
check(palettes.dark.plain === raster.CALM_SHIP_RASTER_DEFAULT_COLOR && palettes.light.plain === raster.CALM_SHIP_RASTER_DEFAULT_COLOR, "plain padding is not the terminal default");
for (const [theme, family] of [["dark", "dark"], ["dark-ansi", "dark"], ["dark-daltonized", "dark"], ["light", "light"], ["light-ansi", "light"], ["light-daltonized", "light"], ["auto", "light"], ["custom:rose", "light"], [undefined, "light"], [42, "light"], ["", "light"]]) {
  check(raster.calmShipPaletteFamily(theme) === family, \`theme \${JSON.stringify(theme)} chose \${raster.calmShipPaletteFamily(theme)}, not \${family}\`);
}
for (const [family, colors] of Object.entries(palettes)) for (const width of [1, 2, 3, 4, 5, 20, 77, 512]) {
  const sprite = core.createCalmWorkingShipSprite();
  for (let step = 0; step < 6; step += 1) {
    const frame = sprite.frame(width);
    const packed = raster.packCalmShipRasterCells(frame, width, colors);
    check(packed.rows === frame.length, \`rows \${packed.rows} for a \${frame.length}-row frame\`);
    const grid = decode(packed.cells, width, packed.rows);
    for (let row = 0; row < frame.length; row += 1) {
      let column = 0;
      for (const run of frame[row]) {
        for (const glyph of Array.from(run.text)) {
          const cell = grid[row][column];
          check(cell.glyph === glyph, \`glyph mismatch at \${row},\${column}: \${cell.glyph} vs \${glyph}\`);
          check(cell.fg === colors[run.color], \`\${family} color mismatch at \${row},\${column}\`);
          column += 1;
        }
      }
      for (; column < width; column += 1) {
        check(grid[row][column].glyph === " " && grid[row][column].fg === colors.plain, \`padding at \${row},\${column} is not a plain space\`);
      }
      check(grid[row].every((cell) => cell.bg === raster.CALM_SHIP_RASTER_DEFAULT_COLOR), "a background was set");
      check(grid[row].every((cell) => cell.glyph.codePointAt(0) <= 0xffff), "a glyph left the BMP");
    }
    sprite.tick();
  }
}
// The packer's pre-load default is the both-readable light fallback.
{
  const packed = raster.packCalmShipRasterCells([[{ text: "*", color: "star" }]], 1);
  check(decode(packed.cells, 1, 1)[0][0].fg === palettes.light.star, "the default packing palette is not the light fallback");
}
// A run wider than the grid is clipped, never wrapped into the next row.
{
  const packed = raster.packCalmShipRasterCells([[{ text: "********", color: "star" }], [{ text: "▄─█", color: "hull" }]], 4);
  check(packed.rows === 2, "clip changed the row count");
  const grid = decode(packed.cells, 4, 2);
  check(grid[0].map((c) => c.glyph).join("") === "****" && grid[1].map((c) => c.glyph).join("") === "▄─█ ", "clip wrapped or dropped cells");
}
check(raster.packCalmShipRasterCells([], 3).rows === 1, "an empty frame did not pack one blank row");
check(raster.calmShipRasterColumns(undefined) === 78, "unmeasured viewport width");
check(raster.calmShipRasterColumns(160) === 158, "measured viewport width");
check(raster.calmShipRasterColumns(2) === 1 && raster.calmShipRasterColumns(-5) === 1, "narrow viewport floor");
check(raster.calmShipRasterColumns(10000) === 512, "raster width ceiling");
console.log("raster-ok");
JS
  out=$(run_node "$TMP_ROOT/raster.mjs" 2>&1) || fail "raster packing: $out"
  assert_contains "$out" "raster-ok" "the raster packing check did not complete"
  pass "the Raster packing lays the shared frame out row-major in Claude Code's dark or light theme palette, using light as the both-readable fallback, with plain padding, default backgrounds, BMP glyphs, clipping, and a standard base64 encoding"
}

test_presentation_policy() {
  local out
  cat >"$TMP_ROOT/policy.mjs" <<JS
import { pathToFileURL } from "node:url";
const policy = await import(pathToFileURL(${MOD@Q} + "/lib/fm-calm-presentation.ts").href);
const piPreservation = await import(pathToFileURL(${ROOT@Q} + "/.pi/extensions/lib/fm-calm-preservation.ts").href);
const check = (condition, message) => { if (!condition) throw new Error(message); };
const plugin = "/repo/.claude/mods/firstmate-calm";
check(policy.calmPreferencePath({}, plugin) === "/repo/config/calm", "plugin-root fallback");
check(policy.calmPreferencePath({}, "/repo/.claude/skills/firstmate-calm/") === "/repo/config/calm", "trailing slash on the plugin root");
check(policy.calmPreferencePath({}, "/repo/.agents/skills/firstmate-calm") === "/repo/config/calm", ".agents/skills spelling of the plugin root");
check(policy.calmCodeRootFromPluginRoot("C:\\\\fm\\\\.claude\\\\mods\\\\firstmate-calm") === "C:\\\\fm", "Windows separators");
check(policy.calmPreferencePath({ FM_ROOT_OVERRIDE: "/override/root" }, plugin) === "/override/root/config/calm", "FM_ROOT_OVERRIDE");
check(policy.calmPreferencePath({ FM_HOME: "/home/fm", FM_ROOT_OVERRIDE: "/override/root" }, plugin) === "/home/fm/config/calm", "FM_HOME beats FM_ROOT_OVERRIDE");
check(policy.calmPreferencePath({ FM_HOME: "/home/fm", FM_CONFIG_OVERRIDE: "/cfg" }, plugin) === "/cfg/calm", "FM_CONFIG_OVERRIDE beats the home");
check(policy.calmPreferencePath({ FM_HOME: "" }, plugin) === "/repo/config/calm", "an empty FM_HOME reads as unset");
for (const [stored, expected] of [["on\\n", true], ["on", true], [" on \\n", true], ["max\\n", true], ["off\\n", false], ["", false], [undefined, false], ["ON", false], ["maybe", false]]) {
  check(policy.parseCalmPreference(stored) === expected, \`preference \${JSON.stringify(stored)}\`);
}
check(policy.serializeCalmPreference(true) === "on\\n" && policy.serializeCalmPreference(false) === "off\\n", "serialized values");
const shortNote = "Checking briefly.";
const multiLineReply = "The result is substantive.\\nHere is the context needed to continue.";
const atThresholdReply = "x".repeat(240);
const belowThresholdNote = "x".repeat(239);
check(policy.CALM_PRESERVE_MIN_CHARS === 240, "Claude preservation threshold");
check(piPreservation.CALM_PRESERVE_MIN_CHARS === policy.CALM_PRESERVE_MIN_CHARS, "Pi and Claude preservation thresholds");
for (const [text, expectedPreserved, label] of [
  [belowThresholdNote, false, "239-character single line"],
  [atThresholdReply, true, "240-character single line"],
  [multiLineReply, true, "multi-line text"],
]) {
  const claudePreserved = !policy.stepTextIsWorkingNote({ stopReason: "tool_use", toolUses: [] }, text);
  const piPreserved = piPreservation.calmTextIsSubstantive(text);
  check(claudePreserved === expectedPreserved, "Claude did not classify " + label + " as expected");
  check(piPreserved === expectedPreserved, "Pi did not classify " + label + " as expected");
}
check(policy.stepTextIsWorkingNote({ stopReason: "tool_use", toolUses: [] }, shortNote) === true, "short single-line tool_use note");
check(policy.stepTextIsWorkingNote({ stopReason: "tool_use", toolUses: [] }, multiLineReply) === false, "multi-line tool_use reply");
check(policy.stepTextIsWorkingNote({ stopReason: "tool_use", toolUses: [] }, atThresholdReply) === false, "threshold-length tool_use reply");
check(policy.stepTextIsWorkingNote({ stopReason: "tool_use", toolUses: [] }, belowThresholdNote) === true, "just-under-threshold tool_use note");
check(policy.stepTextIsWorkingNote({ stopReason: "max_tokens", toolUses: [{}] }, shortNote) === true, "max_tokens with tools");
check(policy.stepTextIsWorkingNote({ stopReason: "max_tokens", toolUses: [] }, shortNote) === false, "max_tokens without tools");
check(policy.stepTextIsWorkingNote({ stopReason: "end_turn", toolUses: [{}] }, shortNote) === false, "end_turn");
check(policy.stepTextIsWorkingNote({ stopReason: null, toolUses: [] }, shortNote) === false, "no response");
check(policy.workingNoteKey("  note \\n") === "note\\n" && policy.workingNoteKey(" note ") === "note" && policy.workingNoteKey("   ") === "", "note key");
const restored = policy.classifyRestoredTranscript([
  { role: "user", text: "go", toolUses: [] },
  { role: "assistant", text: " own call ", toolUses: [{}] },
  { role: "assistant", text: "before a tool row", toolUses: [] },
  { role: "assistant", text: "", toolUses: [{}] },
  { role: "assistant", text: "final", toolUses: [] },
  { role: "user", text: "again", toolUses: [] },
  { role: "assistant", text: "collision", toolUses: [{}] },
  { role: "assistant", text: "collision", toolUses: [] },
  { role: "user", text: "last", toolUses: [] },
  { role: "assistant", text: "plain reply", toolUses: [] },
  { role: "user", text: "multi-line case", toolUses: [] },
  { role: "assistant", text: multiLineReply, toolUses: [] },
  { role: "assistant", text: "", toolUses: [{}] },
  { role: "user", text: "threshold case", toolUses: [] },
  { role: "assistant", text: atThresholdReply, toolUses: [] },
  { role: "assistant", text: "", toolUses: [{}] },
  { role: "user", text: "below-threshold case", toolUses: [] },
  { role: "assistant", text: belowThresholdNote, toolUses: [] },
  { role: "assistant", text: "", toolUses: [{}] },
  { role: "user", text: "newline collision", toolUses: [] },
  { role: "assistant", text: "Checking.\\n", toolUses: [] },
  { role: "assistant", text: "", toolUses: [{}] },
  { role: "user", text: "single-line collision", toolUses: [] },
  { role: "assistant", text: "Checking.", toolUses: [] },
  { role: "assistant", text: "", toolUses: [{}] },
]);
check(JSON.stringify(restored.workingNotes) === JSON.stringify(["own call", "before a tool row", belowThresholdNote, "Checking."]), \`restored notes \${JSON.stringify(restored.workingNotes)}\`);
check(JSON.stringify(restored.finalReplies) === JSON.stringify(["final", "collision", "plain reply", multiLineReply + "\\n", atThresholdReply, "Checking.\\n"]), \`restored final replies \${JSON.stringify(restored.finalReplies)}\`);
check(policy.userTextIsOperational("\\u2063FIRSTMATE_OP: v1 watcher: x") && !policy.userTextIsOperational("hello"), "operational recognition");
console.log("policy-ok");
JS
  out=$(run_node "$TMP_ROOT/policy.mjs" 2>&1) || fail "presentation policy: $out"
  assert_contains "$out" "policy-ok" "the policy check did not complete"
  pass "the Calm policy resolves the shared preference exactly as Pi does, reads on, max, and off as Pi does, and shares Pi's 240-character-or-newline preservation behavior while classifying working notes by stop reason, tool use, and restored transcript shape"
}

# The classifier parity corpus: envelopes the shell owner encodes itself, its legacy
# shapes, and near misses. Each case is one file so multi-line bodies stay exact.
canonical_generic_kinds() {
  bash -c '. "$1"; printf "%s\n" "$FM_OPERATIONAL_KINDS"' firstmate "$OPERATIONAL_INPUT"
}

write_parity_corpus() {
  local dir=$1 kind index=0 body generic_kinds
  mkdir -p "$dir"
  generic_kinds=$(canonical_generic_kinds) || fail "could not read generic kinds from the operational-input owner"
  [ -n "$generic_kinds" ] || fail "the operational-input owner exposes no generic kinds"
  for kind in $generic_kinds; do
    for body in 'plain body' $'multi\nline\n\nbody' $'trailing newline\n' $'two trailing newlines\n\n' 'colon: inside: body' 'ünïcödé body ✓' ' '; do
      index=$((index + 1))
      printf '%s' "$body" | "$OPERATIONAL_INPUT" encode "$kind" >"$dir/case-$index.txt" \
        || fail "the owner could not encode kind $kind for the parity corpus"
    done
  done
  for body in 'plain body' $'multi\nline\n\nbody' $'trailing newline\n' $'two trailing newlines\n\n' 'colon: inside: body' 'ünïcödé body ✓' ' '; do
    index=$((index + 1))
    printf '%s' "$body" | "$OPERATIONAL_INPUT" encode from-firstmate >"$dir/case-$index.txt" \
      || fail "the owner could not encode from-firstmate for the parity corpus"
  done
  for body in \
    'Run `bin/fm-session-start.sh` now, exactly once, before executing any other instructions.' \
    'Run `bin/fm-session-start.sh` now, exactly once, before executing any other instructions. ' \
    $'FIRSTMATE WATCHER WAKE: signal: x\n\nRun bin/fm-wake-drain.sh first and handle the queued wake. Watcher continuity is extension-owned.' \
    $'FIRSTMATE WATCHER WAKE: \n\nRun bin/fm-wake-drain.sh first and handle the queued wake. Watcher continuity is extension-owned.' \
    $'TURN WOULD END BLIND - supervision is off. The watcher cycle is missing, failed, or unhealthy. Follow the harness recovery instruction below before ending the turn.\n\nrecover' \
    $'TURN WOULD END BLIND - supervision is off. The watcher cycle is missing, failed, or unhealthy. Follow the harness recovery instruction below before ending the turn.\n\n' \
    $'\xE2\x81\xA3Supervisor escalate (' \
    $'\xE2\x81\xA3Supervisor escalate (needs you)' \
    $'\xE2\x81\xA3FIRSTMATE_OP: untyped legacy' \
    $'\xE2\x81\xA3FIRSTMATE_OP: ' \
    $'\xE2\x81\xA3FIRSTMATE_OP: v1 watcher:' \
    $'\xE2\x81\xA3FIRSTMATE_OP: v1 watcher: ' \
    $'\xE2\x81\xA3FIRSTMATE_OP: v1 bogus: body' \
    $'\xE2\x81\xA3FIRSTMATE_OP: v2 watcher: body' \
    $'\xE2\x81\xA3FIRSTMATE_OP: v1 watcher: : x' \
    $'\xE2\x81\xA3FIRSTMATE_OP:v1 watcher: body' \
    $'[fm-from-firstmate]\xE2\x81\xA3' \
    $'[fm-from-firstmate]\xE2\x81\xA3x' \
    '[fm-from-firstmate] no separator' \
    "'"$'\xE2\x81\xA3'"FIRSTMATE_OP: v1 watcher: quoted'" \
    'FIRSTMATE_OP: v1 watcher: ascii only' \
    $'text before \xE2\x81\xA3FIRSTMATE_OP: v1 watcher: body' \
    $'\xE2\x81\xA3' \
    $'\xE2\x81\xA3unrelated' \
    'hello there' \
    '' \
    $'\n' \
    'signal: /tmp/x.status changed'
  do
    index=$((index + 1))
    printf '%s' "$body" >"$dir/case-$index.txt"
  done
  printf '%s\n' "$index"
}

test_classifier_parity_with_shell_owner() {
  local corpus count out shell_verdict port_verdict mismatches=0 compared=0 index file generic_kinds kind
  corpus="$TMP_ROOT/corpus"
  count=$(write_parity_corpus "$corpus")
  cat >"$TMP_ROOT/classify.mjs" <<JS
import { pathToFileURL } from "node:url";
import { readFileSync, writeFileSync } from "node:fs";
const port = await import(pathToFileURL(${MOD@Q} + "/lib/fm-operational-input.ts").href);
const corpus = ${corpus@Q};
const count = ${count};
const lines = [];
for (let index = 1; index <= count; index += 1) {
  const text = readFileSync(\`\${corpus}/case-\${index}.txt\`, "utf8");
  lines.push(\`\${index}\\t\${port.classifyFirstmateOperationalText(text) ?? "none"}\`);
}
writeFileSync(\`\${corpus}/port-verdicts.tsv\`, lines.join("\\n") + "\\n");
console.log("classified " + count);
JS
  out=$(run_node "$TMP_ROOT/classify.mjs" 2>&1) || fail "classifier port: $out"
  assert_contains "$out" "classified $count" "the port did not classify the whole corpus"
  index=1
  while [ "$index" -le "$count" ]; do
    file="$corpus/case-$index.txt"
    if shell_verdict=$("$OPERATIONAL_INPUT" classify <"$file" 2>/dev/null); then
      :
    else
      shell_verdict=none
    fi
    port_verdict=$(awk -F '\t' -v i="$index" '$1 == i { print $2 }' "$corpus/port-verdicts.tsv")
    compared=$((compared + 1))
    if [ "$shell_verdict" != "$port_verdict" ]; then
      mismatches=$((mismatches + 1))
      printf 'parity mismatch on case %s: shell=%s port=%s text=%s\n' "$index" "$shell_verdict" "$port_verdict" "$(od -c "$file" | head -3 | tr '\n' ' ')" >&2
    fi
    index=$((index + 1))
  done
  [ "$compared" -eq "$count" ] || fail "compared $compared of $count parity cases"
  [ "$mismatches" -eq 0 ] || fail "the TypeScript classifier diverged from bin/fm-operational-input.sh on $mismatches of $count cases"
  # The corpus must exercise every current kind and the legacy shapes, or parity is vacuous.
  generic_kinds=$(canonical_generic_kinds) || fail "could not reread generic kinds from the operational-input owner"
  [ -n "$generic_kinds" ] || fail "the operational-input owner exposes no generic kinds"
  for kind in $generic_kinds from-firstmate legacy-operational; do
    grep -q "	$kind\$" "$corpus/port-verdicts.tsv" || fail "the parity corpus never produced the $kind verdict"
  done
  grep -q '	none$' "$corpus/port-verdicts.tsv" || fail "the parity corpus never produced a non-operational verdict"
  pass "the mod's operational-input classifier agrees with bin/fm-operational-input.sh on all $count corpus cases: every current kind the owner encodes, every legacy shape, and every near miss"
}

test_plugin_shape
test_shared_sprite_and_pi_rendering
test_warp_flash_and_impulse_trail
test_raster_packing
test_presentation_policy
test_classifier_parity_with_shell_owner
