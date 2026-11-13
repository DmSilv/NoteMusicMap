// Dedilhado do violino (método de Flesch) editado pelo administrador.
//
// O app traz as escalas já conferidas (packages/afina_core/lib/violin_fingering.dart). O administrador pode corrigir uma
// delas ou incluir outra pelo painel; o que ele salva fica no Redis (um hash só, `fing:violin`) e o app o busca uma vez
// por abertura (GET /api/fingering, com cache de CDN: o Redis quase não é tocado). O que está no servidor vale no lugar do
// que vem no app.
//
// Esta parte é só dados e regras (sem rede): valida o que o administrador digita, calcula as notas de cada escala (para o
// formulário mostrar "nº 10 · Sol♭5") e avisa quando um "0" (corda solta) não cai numa corda solta do violino.
'use strict';

const HASH = 'fing:violin';

/** Passos de cada tipo (igual a ScaleType em packages/afina_core/lib/pitch_grid.dart). */
const TYPES = {
  major: { steps: [0, 2, 4, 5, 7, 9, 11], minor: false, label: 'Maior' },
  naturalMinor: { steps: [0, 2, 3, 5, 7, 8, 10], minor: true, label: 'Menor natural' },
  harmonicMinor: { steps: [0, 2, 3, 5, 7, 8, 11], minor: true, label: 'Menor harmônica' },
  melodicMinor: { steps: [0, 2, 3, 5, 7, 9, 11], down: [0, 2, 3, 5, 7, 8, 10], minor: true, label: 'Menor melódica' },
  majorPentatonic: { steps: [0, 2, 4, 7, 9], minor: false, label: 'Pentatônica maior' },
  chromatic: { steps: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], minor: false, label: 'Cromática' },
  majorTriad: { steps: [0, 4, 7], minor: false, arpeggio: true, label: 'Arpejo maior' },
  minorTriad: { steps: [0, 3, 7], minor: true, arpeggio: true, label: 'Arpejo menor' },
  majorTriad1: { steps: [0, 3, 8], start: 4, minor: false, arpeggio: true, label: 'Arpejo maior (1ª inversão)' },
  minorTriad1: { steps: [0, 4, 9], start: 3, minor: true, arpeggio: true, label: 'Arpejo menor (1ª inversão)' },
  majorTriad2: { steps: [0, 5, 9], start: 7, minor: false, arpeggio: true, label: 'Arpejo maior (2ª inversão)' },
  minorTriad2: { steps: [0, 5, 8], start: 7, minor: true, arpeggio: true, label: 'Arpejo menor (2ª inversão)' },
  dominantSeventh: { steps: [0, 4, 7, 10], minor: false, arpeggio: true, label: 'Arpejo de 7ª da dominante' },
  diminishedSeventh: { steps: [0, 3, 6, 9], minor: false, arpeggio: true, label: 'Arpejo de 7ª diminuta' },
};

const OPEN_STRINGS = new Set([55, 62, 69, 76]); // Sol3, Ré4, Lá4, Mi5

// Tônicas com outra grafia (Fá♯ ↔ Sol♭): classe de altura -> letra (0 = Dó) e acidente.
const MAJOR_ALT = { 1: [0, 1], 6: [4, -1], 11: [0, -1] };
const MINOR_ALT = { 3: [1, 1], 8: [5, -1], 10: [5, 1] };
const MAJOR_TONIC = [[0, 0], [1, -1], [1, 0], [2, -1], [2, 0], [3, 0], [3, 1], [4, 0], [5, -1], [5, 0], [6, -1], [6, 0]];
const MINOR_TONIC = [[0, 0], [0, 1], [1, 0], [2, -1], [2, 0], [3, 0], [3, 1], [4, 0], [4, 1], [5, 0], [6, -1], [6, 0]];
const NAT_PC = [0, 2, 4, 5, 7, 9, 11];
const LETTERS = ['Dó', 'Ré', 'Mi', 'Fá', 'Sol', 'Lá', 'Si'];

// Distância em letras do grau até a tônica, por distância em semitons (igual a scale_spelling.dart).
const L_MAJOR = { 0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6 };
const L_NMIN = { 0: 0, 2: 1, 3: 2, 5: 3, 7: 4, 8: 5, 10: 6 };
const L_HMIN = { 0: 0, 2: 1, 3: 2, 5: 3, 7: 4, 8: 5, 11: 6 };
const L_MELUP = { 0: 0, 2: 1, 3: 2, 5: 3, 7: 4, 9: 5, 11: 6 };
const L_PENT = { 0: 0, 2: 1, 4: 2, 7: 4, 9: 5 };
const L_MAJTRI = { 0: 0, 4: 2, 7: 4 };
const L_MINTRI = { 0: 0, 3: 2, 7: 4 };
const L_DOM7 = { 0: 0, 4: 2, 7: 4, 10: 6 };
const L_DIM7 = { 0: 0, 3: 2, 6: 4, 9: 5 };
// 7ª diminuta de Dó♯, Ré♯ e Sol♯: raiz com sustenido e a letra da 7ª (Dó♯ Mi Sol Si♭); igual a scale_spelling.dart
const L_DIM7_SEVENTH = { 0: 0, 3: 2, 6: 4, 9: 6 };
const DIM7_SHARP_ROOT = { 1: [0, 1], 3: [1, 1], 8: [4, 1] };
function letterMap(type, ascending) {
  switch (type) {
    case 'major': return L_MAJOR;
    case 'naturalMinor': return L_NMIN;
    case 'harmonicMinor': return L_HMIN;
    case 'melodicMinor': return ascending ? L_MELUP : L_NMIN;
    case 'majorPentatonic': return L_PENT;
    case 'chromatic': return null;
    case 'majorTriad': case 'majorTriad1': case 'majorTriad2': return L_MAJTRI;
    case 'minorTriad': case 'minorTriad1': case 'minorTriad2': return L_MINTRI;
    case 'dominantSeventh': return L_DOM7;
    case 'diminishedSeventh': return L_DIM7;
    default: return null;
  }
}

const mod = (a, n) => ((a % n) + n) % n;

/** Tônica (MIDI) como o app escolhe: a oitava mais perto da corda Sol do violino (Sol3 = 55). */
function tonicMidi(pc, start = 0) { return 55 + mod(pc + start - 55, 12) - start; }

function hasAlt(pc, type) {
  const t = TYPES[type];
  return !!t && Object.prototype.hasOwnProperty.call(t.minor ? MINOR_ALT : MAJOR_ALT, pc);
}

function tonicSpelling(pc, type, alt) {
  const t = TYPES[type];
  if (type === 'diminishedSeventh' && DIM7_SHARP_ROOT[pc]) return DIM7_SHARP_ROOT[pc];
  if (alt) {
    const a = (t.minor ? MINOR_ALT : MAJOR_ALT)[pc];
    if (a) return a;
  }
  return (t.minor ? MINOR_TONIC : MAJOR_TONIC)[pc];
}

/** Notas da sequência "subindo e descendo", como o exercício do app (a nota do topo aparece uma vez). */
function sequence(pc, type, oct) {
  const t = TYPES[type];
  const base = tonicMidi(pc, t.start || 0) + (t.start || 0);
  const up = [];
  for (let o = 0; o < oct; o++) for (const s of t.steps) up.push(base + 12 * o + s);
  up.push(base + 12 * oct);
  const down = [];
  const ds = t.down || t.steps;
  for (let o = oct - 1; o >= 0; o--) for (let i = ds.length - 1; i >= 0; i--) down.push(base + 12 * o + ds[i]);
  return { midis: [...up, ...down], upCount: up.length };
}

/** Quantas notas tem a sequência (sem montar). */
function seqLength(type, oct) { return 2 * oct * TYPES[type].steps.length + 1; }

/** Nome (com ♯ ♭) e oitava de cada nota, como o app escreve (letra por grau, sobe e desce diferente na menor melódica). */
function noteRows(pc, alt, type, oct) {
  const { midis, upCount } = sequence(pc, type, oct);
  const tonic = tonicMidi(pc, TYPES[type].start || 0); // a raiz (nas inversões a escala começa em outra nota, mas a grafia parte da raiz)
  const [tl] = tonicSpelling(pc, type, alt);
  return midis.map((m, i) => {
    const asc = i < upCount;
    const p = m % 12;
    const map = type === 'diminishedSeventh' && DIM7_SHARP_ROOT[mod(tonic, 12)] ? L_DIM7_SEVENTH : letterMap(type, asc);
    let letter, acc;
    if (!map) {
      const up = [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [3, 0], [3, 1], [4, 0], [4, 1], [5, 0], [5, 1], [6, 0]];
      const down = [[0, 0], [1, -1], [1, 0], [2, -1], [2, 0], [3, 0], [4, -1], [4, 0], [5, -1], [5, 0], [6, -1], [6, 0]];
      [letter, acc] = (asc ? up : down)[p];
    } else {
      const off = map[mod(m - tonic, 12)];
      if (off === undefined) { [letter, acc] = (TYPES[type].minor ? MINOR_TONIC : MAJOR_TONIC)[p]; } else {
        letter = (tl + off) % 7;
        acc = mod(p - NAT_PC[letter] + 6, 12) - 6;
      }
    }
    const octave = Math.floor((m - acc) / 12) - 1;
    return { i, asc, midi: m, name: LETTERS[letter] + (acc === 1 ? '♯' : acc === -1 ? '♭' : acc === 2 ? '♯♯' : acc === -2 ? '♭♭' : ''), octave, open: OPEN_STRINGS.has(m) };
  });
}

/**
 * Sugestão a partir do "molde" que as três páginas lidas (Si♭, Mi♭ e Sol♭ maiores, 3 oitavas) têm em comum: os pontos de mudança
 * (notas 9, 15, 17, 21, 22, 26 e 29) e, nas cordas soltas Ré, Lá e Mi, o 4º dedo subindo e a corda solta descendo (o que o Si♭ maior
 * faz). NÃO é o livro: é um ponto de partida para o administrador conferir com a página antes de salvar.
 */
const MOLD = { 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3' };
function suggest(pc, alt, type, oct) {
  if (type !== 'major' || oct !== 3) return { error: 'Só há molde para escala maior de 3 oitavas (as páginas lidas até agora).' };
  const marks = { ...MOLD };
  const notes = ['Pontos de mudança (1 1 1, 4 4, 3 3) iguais aos de Si♭, Mi♭, Sol♭ e Ré maiores.'];
  let open = 0;
  // O 4º dedo no lugar da corda solta só aparece nas escalas que começam na corda Sol, de Sol3 a Si♭3 (Si♭, Lá, Sol; o Dó4 não).
  const startsOnG = tonicMidi(pc) < 59; // Sol, Lá♭, Lá, Si♭ (o Dó maior, que começa no Dó4, não usa)
  for (const r of startsOnG ? noteRows(pc, alt, type, oct) : []) {
    if ([62, 69, 76].includes(r.midi) && marks[r.i] === undefined) {
      marks[r.i] = r.asc ? '4' : '0';
      open++;
    }
  }
  if (open) notes.push('Começa na corda Sol: 4º dedo no lugar das cordas soltas Ré, Lá e Mi subindo e corda solta descendo, como no Si♭ maior.');
  notes.push('Não inclui o dedo da primeira nota nem o 8va: veja na página.');
  return { marks, ottava: null, notes };
}

/** Nome da tônica (com a grafia) de cada tonalidade possível, para a lista do que falta preencher. */
function tonicChoices(minor) {
  const probe = minor ? 'naturalMinor' : 'major';
  const out = [];
  for (let pc = 0; pc < 12; pc++) {
    for (const alt of hasAlt(pc, probe) ? [false, true] : [false]) {
      const [l, a] = tonicSpelling(pc, probe, alt);
      out.push({ pc, alt, name: LETTERS[l] + (a === 1 ? '♯' : a === -1 ? '♭' : '') });
    }
  }
  return out;
}

const keyOf = (pc, alt, type, oct) => `${pc}|${alt ? 1 : 0}|${type}|${oct}`;

/**
 * Confere o que o administrador mandou. Devolve { entry } ou { error }. `warnings` avisa, sem impedir, de um "0" fora de corda
 * solta (o mais provável erro de leitura da página).
 */
function validate(b) {
  const pc = Number(b.pc);
  const oct = Number(b.oct);
  const type = String(b.type || '');
  const alt = b.alt === true || b.alt === 1 || b.alt === '1';
  if (!Number.isInteger(pc) || pc < 0 || pc > 11) return { error: 'Tônica inválida.' };
  if (!TYPES[type]) return { error: 'Tipo de escala desconhecido.' };
  if (!Number.isInteger(oct) || oct < 1 || oct > 4) return { error: 'Oitavas: de 1 a 4.' };
  if (alt && !hasAlt(pc, type)) return { error: 'Esta tônica não tem outra grafia.' };
  const n = seqLength(type, oct);
  const marks = {};
  const raw = b.marks && typeof b.marks === 'object' && !Array.isArray(b.marks) ? b.marks : {};
  for (const [k, v] of Object.entries(raw)) {
    const i = Number(k);
    if (!Number.isInteger(i) || i < 0 || i >= n) return { error: `A nota ${k} não existe nesta escala (de 0 a ${n - 1}).` };
    const f = String(v).trim();
    if (f === '') continue;
    if (!/^[0-4]$/.test(f)) return { error: `Dedo inválido na nota ${i}: use de 0 a 4.` };
    marks[i] = f;
  }
  let ottava = null;
  if (Array.isArray(b.ottava) && b.ottava.length === 2 && b.ottava[0] !== null && b.ottava[0] !== '') {
    const a = Number(b.ottava[0]);
    const z = Number(b.ottava[1]);
    if (!Number.isInteger(a) || !Number.isInteger(z) || a < 0 || z >= n || a > z) return { error: `O 8va precisa ir de uma nota a outra entre 0 e ${n - 1}.` };
    ottava = [a, z];
  }
  const warnings = [];
  const rows = noteRows(pc, alt, type, oct);
  for (const [i, f] of Object.entries(marks)) {
    if (f === '0' && !rows[Number(i)].open) warnings.push(`Nota ${i} (${rows[Number(i)].name}${rows[Number(i)].octave}): o 0 (corda solta) não cai numa corda solta do violino.`);
  }
  return { entry: { pc, alt, type, oct, marks, ottava }, warnings };
}

/** O que vai para o Redis (e para o app) de uma entrada. */
const pack = (e, now) => JSON.stringify({ m: e.marks, o: e.ottava, t: now });
function unpack(field, value) {
  const [pc, alt, type, oct] = String(field).split('|');
  let v;
  try { v = JSON.parse(value); } catch (_) { return null; }
  if (!v || typeof v !== 'object') return null;
  return { pc: Number(pc), alt: alt === '1', type, oct: Number(oct), marks: v.m || {}, ottava: v.o || null, t: v.t || 0 };
}

async function listOverrides(store) {
  const h = await store.hgetall(HASH);
  return Object.entries(h || {}).map(([f, v]) => unpack(f, v)).filter(Boolean);
}

module.exports = { suggest, tonicChoices, MOLD, HASH, TYPES, OPEN_STRINGS, keyOf, tonicMidi, hasAlt, tonicSpelling, sequence, seqLength, noteRows, validate, pack, unpack, listOverrides };
