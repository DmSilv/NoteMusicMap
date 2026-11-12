// Leitor mínimo de textos de código Dart, usado pelo codemod de tradução e pela checagem de idiomas.
// Acha cada "grupo" de textos (literais vizinhos como 'a' 'b' viram um só), separa o que é texto do que é `$x` / `${expr}`,
// e ignora comentários. Não é um parser completo de Dart: só o que precisamos para achar e trocar literais.
'use strict';

const IDENT = /[A-Za-z0-9_]/;
const IDENT_START = /[A-Za-z_]/;

/** Pula comentários e espaços a partir de i; devolve o novo índice. */
function skipTrivia(s, i) {
  for (;;) {
    while (i < s.length && /\s/.test(s[i])) i++;
    if (s[i] === '/' && s[i + 1] === '/') { while (i < s.length && s[i] !== '\n') i++; continue; }
    if (s[i] === '/' && s[i + 1] === '*') {
      let depth = 1; i += 2;
      while (i < s.length && depth > 0) {
        if (s[i] === '/' && s[i + 1] === '*') { depth++; i += 2; } else if (s[i] === '*' && s[i + 1] === '/') { depth--; i += 2; } else i++;
      }
      continue;
    }
    return i;
  }
}

/** Há um literal de texto começando em i? Devolve {start, raw, quote} ou null (start inclui o prefixo r). */
function stringStartAt(s, i) {
  let j = i, raw = false;
  if (s[j] === 'r' && (s[j + 1] === "'" || s[j + 1] === '"') && !(i > 0 && IDENT.test(s[i - 1]))) { raw = true; j++; }
  if (s[j] !== "'" && s[j] !== '"') return null;
  const q = s[j];
  const triple = s[j + 1] === q && s[j + 2] === q;
  return { start: i, raw, quote: triple ? q + q + q : q, bodyStart: j + (triple ? 3 : 1) };
}

/** Lê um literal que começa em i. Devolve {end, parts:[{t:'text',v}|{t:'expr',code,form:'simple'|'block'}], raw, quote}. */
function readString(s, i) {
  const st = stringStartAt(s, i);
  if (!st) return null;
  const parts = [];
  let j = st.bodyStart, buf = '';
  const q = st.quote;
  const flush = () => { if (buf) { parts.push({ t: 'text', v: buf }); buf = ''; } };
  for (;;) {
    if (j >= s.length) throw new Error('texto sem fim perto de ' + JSON.stringify(s.slice(i, i + 40)));
    if (s.startsWith(q, j)) { j += q.length; break; }
    const c = s[j];
    if (!st.raw && c === '\\') { buf += c + s[j + 1]; j += 2; continue; }
    if (!st.raw && c === '$') {
      if (s[j + 1] === '{') {
        flush();
        let depth = 1, k = j + 2;
        while (k < s.length && depth > 0) {
          const sub = stringStartAt(s, k);
          if (sub) { k = readString(s, k).end; continue; }
          if (s[k] === '{') depth++; else if (s[k] === '}') depth--;
          k++;
        }
        parts.push({ t: 'expr', code: s.slice(j + 2, k - 1), form: 'block' });
        j = k; continue;
      }
      if (IDENT_START.test(s[j + 1] || '') && s[j + 1] !== '$') {
        flush();
        let k = j + 1; while (k < s.length && /[A-Za-z0-9_]/.test(s[k])) k++;
        parts.push({ t: 'expr', code: s.slice(j + 1, k), form: 'simple' });
        j = k; continue;
      }
    }
    buf += c; j++;
  }
  flush();
  return { start: i, end: j, parts, raw: st.raw, quote: q };
}

/** Acha os grupos de literais do arquivo (não entra nas interpolações: quem precisar chama de novo com o código da expressão). */
function findGroups(s) {
  const groups = [];
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    if (c === '/' && s[i + 1] === '/') { while (i < s.length && s[i] !== '\n') i++; continue; }
    if (c === '/' && s[i + 1] === '*') { i = skipTrivia(s, i); continue; }
    const st = stringStartAt(s, i);
    if (st) {
      const first = readString(s, i);
      const lits = [first];
      let end = first.end;
      for (;;) {
        const k = skipTrivia(s, end);
        if (k > end && stringStartAt(s, k) || (k === end && stringStartAt(s, k))) { const nx = readString(s, k); lits.push(nx); end = nx.end; } else break;
      }
      groups.push({ start: i, end, lits });
      i = end; continue;
    }
    i++;
  }
  return groups;
}

const ESC = { n: '\n', t: '\t', r: '\r', b: '\b', f: '\f', v: '\v' };

/** Valor real do texto: resolve as barras (n, t, aspas, cifrão, uXXXX, u{...}, xHH). */
function cook(v) {
  return v.replace(/\\(u\{([0-9a-fA-F]+)\}|u([0-9a-fA-F]{4})|x([0-9a-fA-F]{2})|[\s\S])/g, (m, a, b, c, d) => {
    if (b) return String.fromCodePoint(parseInt(b, 16));
    if (c) return String.fromCharCode(parseInt(c, 16));
    if (d) return String.fromCharCode(parseInt(d, 16));
    return ESC[a] !== undefined ? ESC[a] : a;
  });
}

/** Escreve [text] como literal Dart com aspas simples. */
function emit(text) {
  return "'" + text.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n').replace(/\t/g, '\\t').replace(/\r/g, '\\r') + "'";
}

/** Junta as partes dos literais de um grupo: texto real com {0},{1} no lugar das interpolações (e as expressões, na ordem). */
function groupKey(g) {
  let key = '', n = 0; const args = [];
  for (const lit of g.lits) for (const p of lit.parts) {
    if (p.t === 'text') key += lit.raw ? p.v : cook(p.v); else { key += '{' + n++ + '}'; args.push(p.code); }
  }
  return { key, args };
}

module.exports = { skipTrivia, stringStartAt, readString, findGroups, groupKey, cook, emit };
