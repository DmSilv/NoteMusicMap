// Envolve em tr('...') os textos em português que a pessoa lê (ferramenta de uma vez só, mantida para consulta).
//   node scripts/i18n_codemod.js            -> mostra o que mudaria (resumo)
//   node scripts/i18n_codemod.js --apply    -> grava as mudanças
// Regras do que é texto de tela: scripts/lib/i18n_rules.js. Depois de aplicar, o analisador do Dart acusa os `const` que
// passam a chamar tr(); `node scripts/i18n_fix_const.js` tira esses `const`.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { findGroups, groupKey, emit } = require('./lib/dart_strings');
const { ROOT, dartFiles, skipReason } = require('./lib/i18n_rules');

const APPLY = process.argv.includes('--apply');
const EXCLUDE = new Set(fs.existsSync(path.join(__dirname, 'i18n_exclude.json')) ? JSON.parse(fs.readFileSync(path.join(__dirname, 'i18n_exclude.json'), 'utf8')) : []);

/** Transforma o código [code], devolvendo o novo código e quantos textos mudaram. */
function transform(code) {
  const groups = findGroups(code);
  let out = '', pos = 0, count = 0;
  for (const g of groups) {
    out += code.slice(pos, g.start);
    pos = g.end;
    const { key } = groupKey(g);
    const ctx = code.slice(Math.max(0, g.start - 12), g.start);
    const already = /\btr\(\s*$/.test(ctx);
    const why = already || EXCLUDE.has(key) ? 'x' : skipReason(code, g, key);
    // As expressões dentro de ${...} podem ter textos próprios: transforma por dentro primeiro.
    const inner = (src) => { const t = transform(src); count += t.count; return t.code; };
    if (why) {
      // mantém o literal como está, mas olha dentro das interpolações
      let lit = code.slice(g.start, g.end);
      if (g.lits.some((l) => l.parts.some((p) => p.t === 'expr' && /['"]/.test(p.code)))) {
        let rebuilt = '', p0 = g.start;
        for (const l of g.lits) {
          rebuilt += code.slice(p0, l.start); p0 = l.end;
          let seg = code.slice(l.start, l.end);
          for (const p of l.parts) {
            if (p.t !== 'expr' || !/['"]/.test(p.code)) continue;
            const t = inner(p.code);
            if (t !== p.code) seg = seg.replace('${' + p.code + '}', () => '${' + t + '}');
          }
          rebuilt += seg;
        }
        lit = rebuilt;
      }
      out += lit; continue;
    }
    // vira tr('texto {0}', [expr])
    const args = [];
    let k = '', n = 0;
    for (const l of g.lits) for (const p of l.parts) {
      if (p.t === 'text') k += l.raw ? p.v : require('./lib/dart_strings').cook(p.v);
      else { k += '{' + n++ + '}'; args.push(/['"]/.test(p.code) ? inner(p.code) : p.code); }
    }
    count++;
    out += args.length ? `tr(${emit(k)}, [${args.join(', ')}])` : `tr(${emit(k)})`;
  }
  out += code.slice(pos);
  return { code: out, count };
}

function ensureImport(src, rel) {
  const isCore = rel.startsWith('packages/afina_core/lib/');
  const line = isCore ? "import 'i18n.dart';" : "import 'package:afina_core/afina_core.dart';";
  if (isCore ? /import 'i18n\.dart'/.test(src) : /import 'package:afina_core\/afina_core\.dart'(?! as| show| hide)/.test(src)) return src;
  const imports = [...src.matchAll(/^import\s+[^;]+;[^\n]*\n/gm)];
  if (!imports.length) {
    const lib = src.match(/^library[^;]*;\n/m);
    const at = lib ? lib.index + lib[0].length : 0;
    return src.slice(0, at) + (lib ? '\n' : '') + line + '\n' + (lib ? '' : '\n') + src.slice(at);
  }
  const last = imports[imports.length - 1];
  const at = last.index + last[0].length;
  return src.slice(0, at) + line + '\n' + src.slice(at);
}

let total = 0, files = 0;
for (const f of dartFiles()) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  let src = fs.readFileSync(f, 'utf8');
  const crlf = src.includes('\r\n');
  if (crlf) src = src.replace(/\r\n/g, '\n');
  const { code, count } = transform(src);
  if (!count) continue;
  total += count; files++;
  if (APPLY) {
    let res = ensureImport(code, rel);
    if (crlf) res = res.replace(/\n/g, '\r\n');
    fs.writeFileSync(f, res);
  }
}
console.log(`${APPLY ? 'Gravado' : 'Simulação'}: ${total} textos em ${files} arquivos.`);
