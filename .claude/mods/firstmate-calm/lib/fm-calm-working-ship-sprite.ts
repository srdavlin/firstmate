// Firstmate's harness-neutral Calm working-ship sprite.
//
// This module owns the sprite geometry, the bounce track, the two linked animation
// cadences, and the freeze/resume state that every Calm working presentation shares.
// It paints each frame as rows of color-tagged runs and never as bytes, so each harness
// renders the same picture its own way: `.pi/extensions/lib/fm-calm-working-ship.ts`
// paints the runs as standard ANSI escapes for Pi's widget, and `./fm-calm-ship-raster.ts`
// packs them as Claude Code Raster cells. docs/calm.md owns the captain-facing contract
// and docs/calm-mode-feasibility.md the geometry rationale.
//
// It lives inside the Claude Code plugin folder because Claude Code 2.1.272 refuses a
// hooks-module import from outside that folder, symlinks included; the Pi extension
// reaches it through the tracked `.pi/extensions/lib/fm-calm-working-ship-sprite.ts`
// symlink. Nothing here imports a harness: every glyph is one terminal column under
// both harnesses' width rules, so widths are plain character counts.
//
// Cadence: one scheduler drives two linked cadences. Every tick twinkles the starfield
// and pulses the rear exhaust, and every CALM_WORKING_SHIP_TICKS_PER_MOVE-th tick moves
// the ship one whole cell. Ticks, not wall-clock timestamps, drive every state change,
// so tests can seek time exactly.
//
// Continuity: one caller-owned sprite instance survives hide/show within one harness
// process and extension lifetime. restoreLastRendered() freezes column, direction, pulse
// phase, and tick cadence at the last painted frame without advancing them for hidden
// wall time, and the next working period resumes from that exact logical state. A fresh
// session or new extension lifetime calls reset() and starts at the normal initial
// position. State is never a module-level or process-global singleton.

// Top-down Constitution-class silhouette that flies with the saucer leading.
// Seven cells: pulsing nacelle glow at the rear, twin nacelles, a thin neck, and a
// four-cell round saucer with a dark two-cell bridge oval. The saucer disk is the same
// both ways; travel direction is the nacelle/glow placement. Compact fallback is a
// three-cell one-row cut of nacelle, neck, and saucer.
const SAUCER_TOP = "▄██▄";
const SAUCER_BOTTOM = "▀██▀";
const NACELLE_TOP = "▀";
const NACELLE_BOTTOM = "▄";
const NECK = "─";
const TOP_RIGHT = NACELLE_TOP + NECK + SAUCER_TOP;
const BOTTOM_RIGHT = NACELLE_BOTTOM + NECK + SAUCER_BOTTOM;
const TOP_LEFT = SAUCER_TOP + NECK + NACELLE_TOP;
const BOTTOM_LEFT = SAUCER_BOTTOM + NECK + NACELLE_BOTTOM;
const COMPACT_RIGHT = NACELLE_BOTTOM + NECK + "█";
const COMPACT_LEFT = "█" + NECK + NACELLE_BOTTOM;

/** Round saucer disk as drawn on the upper row, either travel direction. */
export const CALM_WORKING_SHIP_SAUCER_RIGHT = SAUCER_TOP;
/** Round saucer disk as drawn on the upper row, either travel direction. */
export const CALM_WORKING_SHIP_SAUCER_LEFT = SAUCER_TOP;
/** Stable lower-row hull when travelling right, exhaust excluded. */
export const CALM_WORKING_SHIP_BODY_RIGHT = BOTTOM_RIGHT;
/** Stable lower-row hull when travelling left, exhaust excluded. */
export const CALM_WORKING_SHIP_BODY_LEFT = BOTTOM_LEFT;
/** Narrow single-row silhouette when travelling right. */
export const CALM_WORKING_SHIP_COMPACT_RIGHT = COMPACT_RIGHT;
/** Narrow single-row silhouette when travelling left. */
export const CALM_WORKING_SHIP_COMPACT_LEFT = COMPACT_LEFT;

/** Terminal columns a string of one-column glyphs occupies. */
function cellCount(text: string): number {
  return Array.from(text).length;
}

const BODY_WIDTH = cellCount(BOTTOM_RIGHT);
const SHIP_WIDTH = BODY_WIDTH + 1;
const COMPACT_WIDTH = cellCount(COMPACT_RIGHT);

/** One-column star glyphs; empty sky is a plain space rather than one of these. */
export const CALM_WORKING_SHIP_STAR_GLYPHS = [".", "·", "+", "*"] as const;
/** Exhaust pulse, indexed by the same 0..3 phase the freeze/resume API exposes. */
export const CALM_WORKING_SHIP_EXHAUST_GLYPHS = ["·", ":", "*", "▓"] as const;
/** Smaller pulse drawn over the top nacelle glow on the saucer row. */
export const CALM_WORKING_SHIP_EXHAUST_SPARK = ["·", "˚", "*", "·"] as const;

/** Scheduler period. One tick twinkles stars and pulses exhaust. */
export const CALM_WORKING_SHIP_TICK_MS = 220;
/** Boat moves one column every Nth tick, so it travels at 220 * 4 = 880ms per column. */
export const CALM_WORKING_SHIP_TICKS_PER_MOVE = 4;

/**
 * The color classes a frame uses. `plain` is uncolored empty sky; `star` is every
 * twinkling star; `hull` is the grey saucer rim and neck; `nacelle` is each light-blue
 * warp nacelle; `bridge` is the dark oval on the saucer; `exhaust` is the red/orange
 * nacelle glow. Each harness maps a class to its own color: Pi paints them as standard
 * ANSI white, cyan, black, and red; the Claude Code mod as Claude Code's theme colors.
 */
export type CalmWorkingShipColor = "plain" | "star" | "hull" | "nacelle" | "bridge" | "exhaust";

/** Per-cell colors of the six-cell body to the saucer side of the exhaust, travelling right. */
const BODY_COLORS_RIGHT: readonly CalmWorkingShipColor[] = [
  "nacelle",
  "hull",
  "hull",
  "bridge",
  "bridge",
  "hull",
];
/** Per-cell colors of the six-cell body, travelling left: the right-facing list reversed. */
const BODY_COLORS_LEFT: readonly CalmWorkingShipColor[] = [
  "hull",
  "bridge",
  "bridge",
  "hull",
  "hull",
  "nacelle",
];
const COMPACT_COLORS_RIGHT: readonly CalmWorkingShipColor[] = ["nacelle", "hull", "hull"];
const COMPACT_COLORS_LEFT: readonly CalmWorkingShipColor[] = ["hull", "hull", "nacelle"];

/** One same-colored run of cells inside a frame row. */
export type CalmWorkingShipRun = {
  readonly text: string;
  readonly color: CalmWorkingShipColor;
};

/** One painted frame: one or two rows of runs, each row exactly the requested width. */
export type CalmWorkingShipFrame = readonly (readonly CalmWorkingShipRun[])[];

export type CalmWorkingShipSprite = {
  /** Paint one frame that exactly fits `width`, clamping the track to it first. */
  frame(width: number): CalmWorkingShipFrame;
  /** Advance one scheduler tick: stars and exhaust every tick, boat on its slower cadence. */
  tick(): void;
  /** Return to the state of the last painted frame, discarding later ticks. */
  restoreLastRendered(): void;
  /** Restore the normal initial column, direction, pulse phase, and cadence. */
  reset(): void;
  /**
   * Clamp the frozen column and direction to `width` without advancing time.
   * Used when a terminal resize lands while the working presentation is hidden.
   */
  clampToWidth(width: number): void;
  /** Current hull column, exposed for deterministic motion assertions. */
  position(): number;
  /** Current travel direction: 1 travelling right, -1 travelling left. */
  direction(): number;
  /** Current exhaust/star pulse phase, exposed for deterministic freeze assertions. */
  waterPhase(): number;
};

/** Longest hull start column that still fits the sprite in `width` usable cells. */
function trackSpan(width: number): number {
  if (width >= SHIP_WIDTH) return width - SHIP_WIDTH;
  if (width >= COMPACT_WIDTH) return width - COMPACT_WIDTH;
  return 0;
}

function mix(value: number): number {
  let hashed = value >>> 0;
  hashed ^= hashed >>> 16;
  hashed = Math.imul(hashed, 0x7feb352d) >>> 0;
  hashed ^= hashed >>> 15;
  hashed = Math.imul(hashed, 0x846ca68b) >>> 0;
  hashed ^= hashed >>> 16;
  return hashed >>> 0;
}

/**
 * Deterministic twinkle at one cell. Most cells stay empty sky; a sparse set of
 * columns lights a star whose glyph and visibility cycle with ticks so the field
 * reads as random without using a non-replayable RNG.
 */
function starGlyph(column: number, row: number, ticks: number): string {
  const seed = mix(Math.imul(column + 1, 0x9e3779b1) ^ Math.imul(row + 1, 0x85ebca6b));
  if (seed % 13 > 2) return " ";
  if ((seed + ticks) % 5 === 0) return " ";
  const index = (seed + Math.floor(ticks / 2)) % CALM_WORKING_SHIP_STAR_GLYPHS.length;
  return CALM_WORKING_SHIP_STAR_GLYPHS[index] ?? ".";
}

type Cell = { text: string; color: CalmWorkingShipColor };

function coalesce(cells: readonly Cell[]): CalmWorkingShipRun[] {
  const runs: CalmWorkingShipRun[] = [];
  for (const cell of cells) {
    const last = runs[runs.length - 1];
    if (last && last.color === cell.color) {
      runs[runs.length - 1] = { text: last.text + cell.text, color: last.color };
    } else {
      runs.push({ text: cell.text, color: cell.color });
    }
  }
  return runs;
}

function exhaustGlyph(phase: number): string {
  return CALM_WORKING_SHIP_EXHAUST_GLYPHS[phase] ?? CALM_WORKING_SHIP_EXHAUST_GLYPHS[0];
}

function sparkGlyph(phase: number): string {
  return CALM_WORKING_SHIP_EXHAUST_SPARK[phase] ?? CALM_WORKING_SHIP_EXHAUST_SPARK[0];
}

export function createCalmWorkingShipSprite(): CalmWorkingShipSprite {
  let position = 0;
  let direction = 1;
  let span = 0;
  let phase = 0;
  let ticks = 0;
  let renderedPosition = position;
  let renderedDirection = direction;
  let renderedSpan = span;
  let renderedPhase = phase;
  let renderedTicks = ticks;

  // Reversing the moment the boat lands on an endpoint means the endpoint frame already
  // carries the new heading, so the silhouette flips with the bounce rather than one
  // step later.
  const settleDirectionAtEdges = (): void => {
    if (span <= 0) return;
    if (position >= span) direction = -1;
    else if (position <= 0) direction = 1;
  };

  const applyWidth = (width: number): void => {
    if (width <= 0) {
      span = 0;
      position = 0;
      return;
    }
    span = trackSpan(width);
    position = Math.min(position, span);
    settleDirectionAtEdges();
  };

  const commitRenderedState = (): void => {
    renderedPosition = position;
    renderedDirection = direction;
    renderedSpan = span;
    renderedPhase = phase;
    renderedTicks = ticks;
  };

  const restoreLastRenderedState = (): void => {
    position = renderedPosition;
    direction = renderedDirection;
    span = renderedSpan;
    phase = renderedPhase;
    ticks = renderedTicks;
  };

  const paintSky = (width: number, row: number): Cell[] => {
    const cells: Cell[] = [];
    for (let column = 0; column < width; column += 1) {
      const glyph = starGlyph(column, row, ticks);
      cells.push(glyph === " " ? { text: " ", color: "plain" } : { text: glyph, color: "star" });
    }
    return cells;
  };

  const stamp = (cells: Cell[], column: number, glyph: string, color: CalmWorkingShipColor): void => {
    if (column < 0 || column >= cells.length) return;
    if (glyph === " ") return;
    cells[column] = { text: glyph, color };
  };

  const stampColored = (
    cells: Cell[],
    column: number,
    glyphs: string,
    colors: readonly CalmWorkingShipColor[],
  ): void => {
    let offset = 0;
    for (const glyph of Array.from(glyphs)) {
      stamp(cells, column + offset, glyph, colors[offset] ?? "hull");
      offset += 1;
    }
  };

  const paintFullShip = (width: number): CalmWorkingShipFrame => {
    const saucerRow = paintSky(width, 0);
    const hullRow = paintSky(width, 1);
    const exhaust = exhaustGlyph(phase);
    const spark = sparkGlyph(phase);
    if (direction >= 0) {
      stamp(saucerRow, position, spark, "exhaust");
      stamp(hullRow, position, exhaust, "exhaust");
      stampColored(saucerRow, position + 1, TOP_RIGHT, BODY_COLORS_RIGHT);
      stampColored(hullRow, position + 1, BOTTOM_RIGHT, BODY_COLORS_RIGHT);
    } else {
      stamp(saucerRow, position + SHIP_WIDTH - 1, spark, "exhaust");
      stamp(hullRow, position + SHIP_WIDTH - 1, exhaust, "exhaust");
      stampColored(saucerRow, position, TOP_LEFT, BODY_COLORS_LEFT);
      stampColored(hullRow, position, BOTTOM_LEFT, BODY_COLORS_LEFT);
    }
    return [coalesce(saucerRow), coalesce(hullRow)];
  };

  const paintCompactShip = (width: number): CalmWorkingShipFrame => {
    const row = paintSky(width, 0);
    const travellingRight = direction >= 0;
    const silhouette = travellingRight ? COMPACT_RIGHT : COMPACT_LEFT;
    const colors = travellingRight ? COMPACT_COLORS_RIGHT : COMPACT_COLORS_LEFT;
    stampColored(row, position, silhouette, colors);
    const exhaustColumn = travellingRight ? position - 1 : position + COMPACT_WIDTH;
    stamp(row, exhaustColumn, exhaustGlyph(phase), "exhaust");
    return [coalesce(row)];
  };

  return {
    position: () => position,
    direction: () => direction,
    waterPhase: () => phase,

    restoreLastRendered: restoreLastRenderedState,

    reset(): void {
      position = 0;
      direction = 1;
      span = 0;
      phase = 0;
      ticks = 0;
      commitRenderedState();
    },

    clampToWidth(width: number): void {
      applyWidth(width);
    },

    tick(): void {
      ticks += 1;
      phase = (phase + 1) % CALM_WORKING_SHIP_TICKS_PER_MOVE;
      if (ticks % CALM_WORKING_SHIP_TICKS_PER_MOVE !== 0) return;
      if (span <= 0) {
        position = 0;
        return;
      }
      position = Math.min(span, Math.max(0, position + direction));
      settleDirectionAtEdges();
    },

    frame(width: number): CalmWorkingShipFrame {
      if (width <= 0) return [];

      // A resize lands here before the next frame, so recompute and clamp the track
      // immediately rather than trusting a position measured against the old width.
      applyWidth(width);

      let frame: CalmWorkingShipFrame;
      if (width < COMPACT_WIDTH) {
        frame = [coalesce(paintSky(width, 0))];
      } else if (width < SHIP_WIDTH) {
        frame = paintCompactShip(width);
      } else {
        frame = paintFullShip(width);
      }

      commitRenderedState();
      return frame;
    },
  };
}
