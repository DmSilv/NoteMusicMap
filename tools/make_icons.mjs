// Gera a logo "Notemusic" em PNG para web, Android e iOS, e um SVG.
// Uso:  node tools/make_icons.mjs   (na raiz do projeto)
// Sem dependências: rasteriza por geometria com supersampling 4x4.
//
// Logo: mostrador de afinador "Marcas e ponteiro" (opção 2B do laboratório de logo).
// Sete marcas em leque, ponteiro verde no centro (afinado) e pivô branco, sobre petróleo.
// A mesma geometria está em lib/ui/app_logo.dart e em design/logo_lab.html.
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';

// ---- Geometria (coordenadas 0..1; ângulos em graus a partir da vertical, horário) ----
const C = { top: '#2D7790', bottom: '#2A6F83', green: '#1FE68F', tick: '#D5E9EF', hub: '#FFFFFF' };
const PV = { x: 0.5, y: 0.62 }; // pivô
const TICK_A = [-63, -42, -21, 0, 21, 42, 63].filter((a) => a !== 0); // marcas (o centro é o ponteiro)
const TICK_R0 = 0.22, TICK_R1 = 0.30, TICK_W = 0.065;
const NEEDLE = [{ x: 0.455, y: 0.62 }, { x: 0.545, y: 0.62 }, { x: 0.5, y: 0.32 }]; // ponteiro (triângulo)
const NEEDLE_PAD = 0.015; // arredondamento do ponteiro
const HUB_R = 0.075;
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
const rad = (d) => (d * Math.PI) / 180;
const pt = (a, r) => ({ x: PV.x + r * Math.sin(rad(a)), y: PV.y - r * Math.cos(rad(a)) });

function insideRounded(x, y) {
  const qx = Math.abs(x - 0.5) - (0.5 - CORNER);
  const qy = Math.abs(y - 0.5) - (0.5 - CORNER);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) <= CORNER;
}
function inNeedle(x, y) {
  const [a, b, c] = NEEDLE;
  const side = (p, q) => (q.x - p.x) * (y - p.y) - (q.y - p.y) * (x - p.x);
  const s1 = side(a, b), s2 = side(b, c), s3 = side(c, a);
  if ((s1 >= 0 && s2 >= 0 && s3 >= 0) || (s1 <= 0 && s2 <= 0 && s3 <= 0)) return true;
  return [[a, b], [b, c], [c, a]].some(([p, q]) => distSeg(x, y, p, q) <= NEEDLE_PAD);
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
  if (variant === 'badge') {
    // Ícone pequeno de notificação (Android): só a silhueta em branco, sem fundo, maior que no ícone normal.
    const s = 1.35;
    px = (x - 0.5) / s + 0.5;
    py = (y - 0.5) / s + 0.5;
  }
  let col = mix(hex(C.top), hex(C.bottom), y);
  let hit = false;
  for (const a of TICK_A) if (distSeg(px, py, pt(a, TICK_R0), pt(a, TICK_R1)) <= TICK_W / 2) { col = hex(C.tick); hit = true; }
  if (inNeedle(px, py)) { col = hex(C.green); hit = true; }
  if (Math.hypot(px - PV.x, py - PV.y) <= HUB_R) { col = hex(C.hub); hit = true; }
  if (variant === 'badge') return hit ? [255, 255, 255, 255] : [0, 0, 0, 0];
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
out('web/icons/badge-96.png', 96, 'badge');

for (const [d, s] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
  out(`android/app/src/main/res/mipmap-${d}/ic_launcher.png`, s, 'rounded');
}

const contents = JSON.parse(readFileSync('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json', 'utf8'));
for (const im of contents.images) {
  const base = parseFloat(im.size.split('x')[0]);
  const scale = parseInt(im.scale, 10);
  out(`ios/Runner/Assets.xcassets/AppIcon.appiconset/${im.filename}`, Math.round(base * scale), 'full');
}

// ---- Apple touch icon (página inicial do iPhone): quadrado cheio, o iOS arredonda ----
out('web/icons/apple-touch-icon.png', 180, 'full');

// ---- Tela de abertura: iOS (LaunchImage) e Android (launch_logo) ----
out('ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png', 120, 'rounded');
out('ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png', 240, 'rounded');
out('ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png', 360, 'rounded');
out('android/app/src/main/res/drawable-nodpi/launch_logo.png', 240, 'rounded');

// ---- Android: ícone adaptativo (fundo + primeiro plano + camada de uma cor) ----
// Camada de 108 dp; o desenho (60% do lado) fica dentro da zona segura de 66 dp.
const V = 108, v = (n) => +(n * V).toFixed(2);
function adaptiveParts(mono) {
  const tick = mono ? '#FF000000' : C.tick, green = mono ? '#FF000000' : C.green, hub = mono ? '#FF000000' : C.hub;
  const col = (c) => (c.length === 7 ? '#FF' + c.slice(1) : c);
  let s = '';
  for (const a of TICK_A) {
    const p = pt(a, TICK_R0), q = pt(a, TICK_R1);
    s += `    <path android:pathData="M${v(p.x)},${v(p.y)} L${v(q.x)},${v(q.y)}" android:strokeColor="${col(tick)}" android:strokeWidth="${v(TICK_W)}" android:strokeLineCap="round"/>
`;
  }
  const [a, b, c] = NEEDLE;
  s += `    <path android:pathData="M${v(a.x)},${v(a.y)} L${v(b.x)},${v(b.y)} L${v(c.x)},${v(c.y)} Z" android:fillColor="${col(green)}" android:strokeColor="${col(green)}" android:strokeWidth="${v(NEEDLE_PAD * 2)}" android:strokeLineJoin="round"/>
`;
  const r = v(HUB_R), cx = v(PV.x), cy = v(PV.y);
  s += `    <path android:pathData="M${(cx - r).toFixed(2)},${cy} a${r},${r} 0 1,0 ${(2 * r).toFixed(2)},0 a${r},${r} 0 1,0 -${(2 * r).toFixed(2)},0 Z" android:fillColor="${col(hub)}"/>
`;
  return s;
}
const vec = (body) => `<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
${body}</vector>
`;
const RES = 'android/app/src/main/res/';
function res(path, text) { mkdirSync(dirname(RES + path), { recursive: true }); writeFileSync(RES + path, text); console.log('ok', RES + path); }
res('drawable/ic_launcher_foreground.xml', vec(adaptiveParts(false)));
res('drawable/ic_launcher_monochrome.xml', vec(adaptiveParts(true)));
res('drawable/ic_launcher_background.xml', `<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android" xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
    <path android:pathData="M0,0h108v108h-108z">
        <aapt:attr name="android:fillColor">
            <gradient android:startX="54" android:startY="0" android:endX="54" android:endY="108" android:type="linear"
                android:startColor="#FF${C.top.slice(1)}" android:endColor="#FF${C.bottom.slice(1)}"/>
        </aapt:attr>
    </path>
</vector>
`);
res('mipmap-anydpi-v26/ic_launcher.xml', `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
`);

// ---- SVG ----
const S = 1024;
const f = (n) => (n * S).toFixed(1);
let ticks = '';
for (const a of TICK_A) { const p = pt(a, TICK_R0), q = pt(a, TICK_R1); ticks += `<line x1="${f(p.x)}" y1="${f(p.y)}" x2="${f(q.x)}" y2="${f(q.y)}" stroke="${C.tick}" stroke-width="${f(TICK_W)}" stroke-linecap="round"/>
  `; }
writeFileSync('assets/logo/logo.svg', `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}" width="${S}" height="${S}">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.top}"/><stop offset="1" stop-color="${C.bottom}"/></linearGradient></defs>
  <rect width="${S}" height="${S}" rx="${CORNER * S}" fill="url(#g)"/>
  ${ticks}<polygon points="${NEEDLE.map((p) => f(p.x) + ',' + f(p.y)).join(' ')}" fill="${C.green}" stroke="${C.green}" stroke-width="${f(NEEDLE_PAD * 2)}" stroke-linejoin="round"/>
  <circle cx="${f(PV.x)}" cy="${f(PV.y)}" r="${f(HUB_R)}" fill="${C.hub}"/>
</svg>
`);
console.log('ok assets/logo/logo.svg');
