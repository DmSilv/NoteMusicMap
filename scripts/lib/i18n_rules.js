// Regras de "este texto é para a pessoa ler?" usadas pelo codemod e pela checagem de idiomas.
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const DIRS = [path.join(ROOT, 'lib'), path.join(ROOT, 'packages', 'afina_core', 'lib')];
// Arquivos que não entram: o próprio sistema de idiomas e os dicionários.
const SKIP_FILE = /[\\/](i18n[^\\/]*\.dart|i18n[\\/].*)$/;

function dartFiles() {
  const out = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.dart') && !SKIP_FILE.test(p) && !e.name.endsWith('.g.dart')) out.push(p);
    }
  };
  DIRS.forEach(walk);
  return out;
}

// Iguais nos dois idiomas: não precisam de tradução.
const NEUTRAL = new Set(['Hz', 's', 'ms', 'min', 'h', 'dB', 'BPM', 'OK', 'x', 'pts', 'cents', '°', '%', 'A4']);
// Palavras minúsculas que aparecem na tela (dias, meses, estados...). Só viram tradução se a linha não for chave de código.
const VISIBLE = new Set(['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado',
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  'hoje', 'agora', 'ontem', 'dia', 'dias', 'aula', 'aulas', 'tarefa', 'tarefas', 'aluno', 'alunos', 'professor', 'professores',
  'afinada', 'afinadas', 'grave', 'aguda', 'suba', 'bastante', 'nota', 'notas', 'oitava', 'oitavas', 'forte', 'fraco', 'mudo', 'médio',
  'atrasada', 'validada', 'refazer', 'descendo', 'subindo', 'melodia', 'acordes', 'pendente', 'pendentes', 'cadastrados', 'encerrada',
  'vinculado', 'vinculados', 'vai', 'baixo', 'baixas', 'altas', 'alto', 'normal', 'desligado', 'ligado']);
// Linhas em que a palavra é chave de código (consulta, id de papel, comparação...).
const ID_LINE = /\b(want|checkStudent|markTab|read|contains|startsWith|endsWith|kind|role|Key|case|switch|jsonDecode|firstWhere)\b|q\[|\['[a-z]+'\]|== *'|' *==/;

const LETTER = /[A-Za-zÀ-ÿ]/;

function prevSignificant(s, i) {
  let j = i - 1;
  while (j >= 0 && /\s/.test(s[j])) j--;
  return j;
}
function nextSignificant(s, i) {
  let j = i;
  while (j < s.length && /\s/.test(s[j])) j++;
  return j;
}

/** Decide se o grupo [g] (com texto [key]) é texto de tela. Devolve null (traduzir) ou o motivo de pular. */
function skipReason(s, g, key) {
  const lineStart = s.lastIndexOf('\n', g.start - 1) + 1;
  const before = s.slice(lineStart, g.start);
  if (/^\s*(import|export|part|library)\b/.test(before)) return 'diretiva';
  if (g.lits.some((l) => l.raw)) return 'raw/regex';
  const flat = key.replace(/\{\d+\}/g, '');
  if (!LETTER.test(flat)) return 'sem letras';
  const p = prevSignificant(s, g.start);
  const prev2 = s.slice(Math.max(0, p - 12), p + 1);
  if (/(==|!=)$/.test(prev2) || /\bcase$/.test(prev2) || /\bis$/.test(prev2)) return 'comparação/case';
  const nx = nextSignificant(s, g.end);
  const nextTwo = s.slice(nx, nx + 2);
  if (nextTwo === '=>') return 'padrão =>';
  if (/^(==|!=)/.test(nextTwo)) return 'comparação';
  if (s[nx] === ':' && !(s[p] === '?' && s[p - 1] !== '?')) return 'chave de mapa';
  const ctx = s.slice(Math.max(0, g.start - 60), g.start);
  if (/(debugPrint|\bprint|Exception|StateError|ArgumentError|FormatException|UnsupportedError|\bassert|UnimplementedError)\s*\(\s*$/.test(ctx) || /\bthrow\s+$/.test(ctx)) return 'erro de desenvolvedor';
  if (/Key\(\s*$/.test(ctx)) return 'ValueKey';
  if (/(?:getString|setString|getInt|setInt|getBool|setBool|getDouble|setDouble|remove|containsKey|getStringList|setStringList)\s*\(\s*$/.test(ctx)) return 'chave de prefs';

  const hasPh = /\{\d+\}/.test(key);
  const words = key.replace(/\{\d+\}/g, ' ').trim();
  const hasSpace = /\s/.test(words);
  const accent = /[À-ÿ]/.test(words);
  if (/^\w+:\/\//.test(words) || /^\/[\w\/\-.]*$/.test(words)) return 'url/caminho';
  if (NEUTRAL.has(words)) return 'neutro';
  if (/^[A-Z]{1,5}-d{1,3}$/.test(words)) return 'código de erro';
  if (!hasSpace && !accent) {
    if (/^[A-Z0-9_#♯♭]+$/.test(words)) return 'sigla/nota';
    const lower = /^[a-z][a-z0-9_\-./:#@?&=%+]*$/.test(words);
    if (lower && !hasPh) {
      const lineEnd = s.indexOf('\n', g.end);
      const line = s.slice(lineStart, lineEnd < 0 ? s.length : lineEnd);
      if (VISIBLE.has(words) && !ID_LINE.test(line)) return null;
      return 'identificador';
    }
  }
  return null;
}

module.exports = { ROOT, dartFiles, skipReason };
