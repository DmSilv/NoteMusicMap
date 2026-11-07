// Gera a logo "Notemusic" em PNG para web, Android e iOS, e um SVG.
// Uso:  node tools/make_icons.mjs   (na raiz do projeto)
// Sem dependências: rasteriza por geometria com supersampling 4x4.
//
// Logo: mostrador de afinador. Um arco vai do azul (grave) ao laranja (agudo)
// passando pelo verde (afinado); o ponteiro branco aponta quase para o centro.
// A mesma geometria está em lib/ui/app_logo.dart.
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';

// ---- Geometria (coordenadas 0..1; ângulos em graus, y para cima) ----
const C = { top: '#17323C', bottom: '#0A141C', blue: '#2E9BFF', green: '#1FE68F', orange: '#FF9226', needle: '#FFFFFF', hub: '#0F1B24' };
const PV = { x: 0.5, y: 0.60 }; // pivô do ponteiro
const R = 0.29, SW = 0.085; // raio e espessura do arco
const A0 = 205, A1 = -25; // do lado grave ao lado agudo (passa pelo topo)
const NA = 84, NL = 0.25, NW = 0.038; // ponteiro: ângulo, comprimento, espessura
// Nota musical (colcheia) no centro do mostrador.
const NOTE_HEAD = { x: 0.455, y: 0.655, rx: 0.088, ry: 0.061, tilt: 22 }; // cabeça inclinada
const NOTE_STEM = [{ x: 0.531, y: 0.645 }, { x: 0.531, y: 0.385 }]; // haste
const NOTE_FLAG = [{ x: 0.531, y: 0.385 }, { x: 0.58, y: 0.418 }, { x: 0.617, y: 0.47 }, { x: 0.602, y: 0.535 }]; // bandeira
const NOTE_W = 0.042; // espessura da haste e da bandeira
const CORNER = 0.22;

const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
function rgb2hsl([r, g, b]) {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2;
  let h = 0, s = 0;
  if (mx !== mn) {
    const d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx === r) h = ((g - b) / d + (g < b ? 6 : 0)) * 60;
    else if (mx === g) h = ((b - r) / d + 2) * 60;
    else h = ((r - g) / d + 4) * 60;
  }
  return [h, s, l];
}
function hsl2rgb([h, s, l]) {
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return [r + m, g + m, b + m].map((v) => v * 255);
}
const hslLerp = (a, b, t) => { const A = rgb2hsl(a), B = rgb2hsl(b); return hsl2rgb(A.map((v, i) => v + (B[i] - v) * t)); };
/** Logo simples: arco de uma cor só, a mesma cor de destaque do app. */
function arcColor() {
  return hex(C.green);
}
const rad = (d) => (d * Math.PI) / 180;
const pt = (a, r = R) => ({ x: PV.x + r * Math.cos(rad(a)), y: PV.y - r * Math.sin(rad(a)) });

function insideRounded(x, y) {
  const qx = Math.abs(x - 0.5) - (0.5 - CORNER);
  const qy = Math.abs(y - 0.5) - (0.5 - CORNER);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) <= CORNER;
}
function distSeg(px, py, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const t = Math.max(0, Math.min(1, ((px - a.x) * dx + (py - a.y) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(px - (a.x + t * dx), py - (a.y + t * dy));
}

/** Cor (RGBA 0..255) no ponto (x,y). variant: 'full' | 'rounded' | 'maskable'. */
function sample(x, y, variant) {
  if (variant === 'rounded' && !insideRounded(x, y)) return [0, 0, 0, 0];
  let px = x, py = y;
  if (variant === 'maskable') {
    const s = 0.78; // conteúdo dentro da zona segura dos launchers
    px = (x - 0.5) / s + 0.5;
    py = (y - 0.5) / s + 0.5;
  }
  let col = mix(hex(C.top), hex(C.bottom), y);

  // arco
  const dx = px - PV.x, dy = -(py - PV.y);
  const r = Math.hypot(dx, dy);
  let a = (Math.atan2(dy, dx) * 180) / Math.PI;
  if (a < A1) a += 360;
  if (a <= A0 && Math.abs(r - R) <= SW / 2) col = arcColor((A0 - a) / (A0 - A1));
  const inBody = a <= A0 && Math.abs(r - R) <= SW / 2;
  for (const [ang, t] of inBody ? [] : [[A0, 0], [A1, 1]]) {
    const e = pt(ang);
    if (Math.hypot(px - e.x, py - e.y) <= SW / 2) col = arcColor(t);
  }
  // nota musical
  {
    const t = rad(NOTE_HEAD.tilt);
    const ddx = px - NOTE_HEAD.x, ddy = -(py - NOTE_HEAD.y);
    const lx = ddx * Math.cos(t) + ddy * Math.sin(t);
    const ly = -ddx * Math.sin(t) + ddy * Math.cos(t);
    let on = (lx / NOTE_HEAD.rx) ** 2 + (ly / NOTE_HEAD.ry) ** 2 <= 1;
    if (distSeg(px, py, NOTE_STEM[0], NOTE_STEM[1]) <= NOTE_W / 2) on = true;
    for (let i = 0; i < NOTE_FLAG.length - 1 && !on; i++)
      if (distSeg(px, py, NOTE_FLAG[i], NOTE_FLAG[i + 1]) <= NOTE_W / 2) on = true;
    if (on) col = hex(C.needle);
  }
  return [...col, 255];
}

function render(size, variant) {
  const SS = 4;
  const buf = Buffer.alloc(size * size * 4);
  for (let j = 0; j < size; j++) {
    for (let i = 0; i < size; i++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sj = 0; sj < SS; sj++) {
        for (let si = 0; si < SS; si++) {
          const s = sample((i + (si + 0.5) / SS) / size, (j + (sj + 0.5) / SS) / size, variant);
          r += s[0] * s[3]; g += s[1] * s[3]; b += s[2] * s[3]; a += s[3];
        }
      }
      const o = (j * size + i) * 4;
      if (a > 0) { buf[o] = Math.round(r / a); buf[o + 1] = Math.round(g / a); buf[o + 2] = Math.round(b / a); }
      buf[o + 3] = Math.round(a / (SS * SS));
    }
  }
  return buf;
}

// ---- PNG ----
const crcTable = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
  return t;
})();
const crc32 = (b) => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(size, rgba) {
  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y++) { raw[y * (size * 4 + 1)] = 0; rgba.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

const cache = new Map();
function out(path, size, variant) {
  const key = `${size}-${variant}`;
  if (!cache.has(key)) cache.set(key, png(size, render(size, variant)));
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, cache.get(key));
  console.log('ok', path, `${size}px`, variant);
}

// ---- Saídas ----
out('assets/logo/logo_1024.png', 1024, 'full');
out('assets/logo/logo_rounded_512.png', 512, 'rounded');

out('web/favicon.png', 64, 'rounded');
out('web/icons/Icon-192.png', 192, 'rounded');
out('web/icons/Icon-512.png', 512, 'rounded');
out('web/icons/Icon-maskable-192.png', 192, 'maskable');
out('web/icons/Icon-maskable-512.png', 512, 'maskable');

for (const [d, s] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
  out(`android/app/src/main/res/mipmap-${d}/ic_launcher.png`, s, 'rounded');
}

const contents = JSON.parse(readFileSync('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json', 'utf8'));
for (const im of contents.images) {
  const base = parseFloat(im.size.split('x')[0]);
  const scale = parseInt(im.scale, 10);
  out(`ios/Runner/Assets.xcassets/AppIcon.appiconset/${im.filename}`, Math.round(base * scale), 'full');
}

// ---- SVG ----
const S = 1024;
const hexOf = (c) => '#' + c.map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
const N = 72;
let segs = '';
for (let i = 0; i < N; i++) {
  const a1 = A0 - ((A0 - A1) * i) / N, a2 = A0 - ((A0 - A1) * (i + 1)) / N + (i < N - 1 ? -0.4 : 0);
  const p1 = pt(a1), p2 = pt(a2);
  segs += `<path d="M${(p1.x * S).toFixed(1)} ${(p1.y * S).toFixed(1)} A${R * S} ${R * S} 0 0 1 ${(p2.x * S).toFixed(1)} ${(p2.y * S).toFixed(1)}" stroke="${hexOf(arcColor((i + 0.5) / N))}" stroke-width="${SW * S}" fill="none"/>\n  `;
}
const e0 = pt(A0), e1 = pt(A1);
writeFileSync('assets/logo/logo.svg', `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}" width="${S}" height="${S}">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.top}"/><stop offset="1" stop-color="${C.bottom}"/></linearGradient></defs>
  <rect width="${S}" height="${S}" rx="${CORNER * S}" fill="url(#g)"/>
  ${segs}<circle cx="${e0.x * S}" cy="${e0.y * S}" r="${(SW / 2) * S}" fill="${C.green}"/>
  <circle cx="${e1.x * S}" cy="${e1.y * S}" r="${(SW / 2) * S}" fill="${C.green}"/>
  <ellipse cx="${NOTE_HEAD.x * S}" cy="${NOTE_HEAD.y * S}" rx="${NOTE_HEAD.rx * S}" ry="${NOTE_HEAD.ry * S}" transform="rotate(${-NOTE_HEAD.tilt} ${NOTE_HEAD.x * S} ${NOTE_HEAD.y * S})" fill="${C.needle}"/>
  <polyline points="${NOTE_STEM.map((p) => p.x * S + ',' + p.y * S).join(' ')}" stroke="${C.needle}" stroke-width="${NOTE_W * S}" stroke-linecap="round" fill="none"/>
  <polyline points="${NOTE_FLAG.map((p) => p.x * S + ',' + p.y * S).join(' ')}" stroke="${C.needle}" stroke-width="${NOTE_W * S}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
</svg>
`);
console.log('ok assets/logo/logo.svg');
