// Erzeugt das App-Icon als 1024x1024-PNG.
//
// Ohne Bildbibliothek: Pixel werden gerechnet, das PNG von Hand
// zusammengesetzt (zlib ist in Node enthalten). Das Motiv folgt der Palette
// der App - Verlauf von Bordeaux nach Tuerkis, weisser Abwaertspfeil.

import { deflateSync } from "node:zlib";
import { writeFileSync } from "node:fs";

const SIZE = 1024;
const SAMPLES = 3; // Kantenglaettung durch Ueberabtastung

// Farben aus Theme.hero
const TOP_LEFT = [122, 18, 48];
const MIDDLE = [61, 18, 41];
const BOTTOM_RIGHT = [15, 90, 99];

function gradient(x, y) {
  // Diagonaler Verlauf; t laeuft von oben links nach unten rechts.
  const t = Math.min(1, Math.max(0, (x / SIZE + y / SIZE) / 2));
  const [a, b, local] = t < 0.5
    ? [TOP_LEFT, MIDDLE, t * 2]
    : [MIDDLE, BOTTOM_RIGHT, (t - 0.5) * 2];
  return [
    a[0] + (b[0] - a[0]) * local,
    a[1] + (b[1] - a[1]) * local,
    a[2] + (b[2] - a[2]) * local,
  ];
}

// --- Motiv: Abwaertspfeil ("Preis faellt") ---

const STEM_HALF_WIDTH = 78;
const STEM_TOP = 232;
const STEM_BOTTOM = 596;
const STEM_RADIUS = 78;

const HEAD_LEFT = 286;
const HEAD_RIGHT = 738;
const HEAD_TOP = 556;
const HEAD_TIP_Y = 830;

function insideStem(x, y) {
  const left = SIZE / 2 - STEM_HALF_WIDTH;
  const right = SIZE / 2 + STEM_HALF_WIDTH;
  // Abgerundetes Rechteck ueber den Abstand zum inneren Kern.
  const cx = Math.min(Math.max(x, left + STEM_RADIUS), right - STEM_RADIUS);
  const cy = Math.min(Math.max(y, STEM_TOP + STEM_RADIUS), STEM_BOTTOM);
  return Math.hypot(x - cx, y - cy) <= STEM_RADIUS;
}

function insideHead(x, y) {
  if (y < HEAD_TOP || y > HEAD_TIP_Y) return false;
  const progress = (y - HEAD_TOP) / (HEAD_TIP_Y - HEAD_TOP);
  const halfWidth = ((HEAD_RIGHT - HEAD_LEFT) / 2) * (1 - progress);
  return Math.abs(x - SIZE / 2) <= halfWidth;
}

function markCoverage(x, y) {
  let hits = 0;
  for (let sy = 0; sy < SAMPLES; sy++) {
    for (let sx = 0; sx < SAMPLES; sx++) {
      const px = x + (sx + 0.5) / SAMPLES;
      const py = y + (sy + 0.5) / SAMPLES;
      if (insideStem(px, py) || insideHead(px, py)) hits++;
    }
  }
  return hits / (SAMPLES * SAMPLES);
}

// --- Pixel erzeugen ---

const raw = Buffer.alloc(SIZE * (SIZE * 4 + 1));
let offset = 0;

for (let y = 0; y < SIZE; y++) {
  raw[offset++] = 0; // Filtertyp "none"
  for (let x = 0; x < SIZE; x++) {
    const background = gradient(x, y);
    const coverage = markCoverage(x, y);
    raw[offset++] = Math.round(background[0] + (255 - background[0]) * coverage);
    raw[offset++] = Math.round(background[1] + (255 - background[1]) * coverage);
    raw[offset++] = Math.round(background[2] + (255 - background[2]) * coverage);
    raw[offset++] = 255; // App-Icons muessen vollstaendig deckend sein
  }
}

// --- PNG zusammensetzen ---

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

const header = Buffer.alloc(13);
header.writeUInt32BE(SIZE, 0);
header.writeUInt32BE(SIZE, 4);
header[8] = 8;  // Bittiefe
header[9] = 6;  // Farbtyp RGBA
header[10] = 0; // Kompression
header[11] = 0; // Filter
header[12] = 0; // kein Interlacing

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", header),
  chunk("IDAT", deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);

const target = process.argv[2];
writeFileSync(target, png);
console.log(`geschrieben: ${target} (${(png.length / 1024).toFixed(0)} KB)`);
