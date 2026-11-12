// O painel segue o mesmo design system do app: `node --test api/admin_design.test.js`
// (cores iguais às de lib/ui/theme.dart, escala de espaço, abas com ícone, frase de apoio em todo título, movimento que se desliga).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'web', 'admin.html'), 'utf8');
const theme = fs.readFileSync(path.join(root, 'lib', 'ui', 'theme.dart'), 'utf8');
const css = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));
const markup = html.slice(html.indexOf('<body>'), html.indexOf('<script>'));

const cssVar = (name) => {
  const m = css.match(new RegExp(`--${name}:\\s*(#[0-9a-fA-F]{6})`));
  return m ? m[1].toLowerCase() : null;
};
const appDark = (getter) => {
  const m = theme.match(new RegExp(`static Color get ${getter} => dark \\? const Color\\(0xFF([0-9A-Fa-f]{6})\\)`));
  return m ? '#' + m[1].toLowerCase() : null;
};

test('as cores do painel são as do app (tema escuro)', () => {
  const pares = { bg: 'bg', surface: 'surface', surface2: 'surface2', outline: 'outline', text: 'text', dim: 'textDim', accent: 'inTune', 'accent-ink': 'onAccent', flat: 'flat', sharp: 'sharp' };
  for (const [v, g] of Object.entries(pares)) {
    assert.ok(appDark(g), `cor ${g} não encontrada em theme.dart`);
    assert.equal(cssVar(v), appDark(g), `--${v} do painel deve ser igual a ${g} do app`);
  }
});

test('a escala de espaço é a do app (4, 8, 12, 16, 20, 24, 32) e os raios são 20 e 12', () => {
  for (const n of [4, 8, 12, 16, 20, 24, 32]) assert.match(css, new RegExp(`--s${n}:\\s*${n}px`), `falta --s${n}`);
  assert.match(css, /--r-card:\s*20px/);
  assert.match(css, /--r-ctl:\s*12px/);
});

test('as abas têm ícone, nome e uma dica do que mostram', () => {
  const nav = markup.slice(markup.indexOf('<nav class="tabs"'), markup.indexOf('</nav>'));
  const botoes = nav.match(/<button data-tab="[^>]+>[\s\S]*?<\/button>/g) || [];
  assert.equal(botoes.length, 9, 'são 9 abas');
  for (const b of botoes) {
    assert.match(b, /<use href="#i-[a-z]+"/, 'cada aba tem ícone');
    assert.match(b, /title="[^"]{12,}"/, 'cada aba tem uma dica');
    assert.match(b, /<span>[^<]+<\/span>/, 'cada aba tem nome');
  }
  for (const id of botoes.map((b) => b.match(/data-tab="(\w+)"/)[1])) assert.ok(markup.includes(`id="tab-${id}"`), `falta a seção da aba ${id}`);
});

test('todo título de seção explica, numa frase simples, o que a seção mostra', () => {
  const h2s = [...markup.matchAll(/<h2[^>]*>[\s\S]*?<\/h2>\s*(<p class="lead">)?/g)];
  assert.ok(h2s.length >= 35, 'esperava os títulos do painel');
  const sem = h2s.filter((m) => !m[1]).map((m) => m[0].replace(/<[^>]+>/g, '').trim().slice(0, 50));
  assert.deepEqual(sem, [], 'títulos sem frase de apoio (<p class="lead">)');
});

test('movimento e tema: respeita "reduzir movimento" e usa o esquema escuro do navegador', () => {
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(css, /color-scheme:\s*dark/);
  assert.match(css, /\.enter \.bar/, 'barras crescem ao entrar na aba');
  assert.match(html, /MutationObserver/, 'números contam até o valor');
});

test('alvos de toque: botões e campos têm pelo menos 40 px', () => {
  assert.match(css, /--tap:\s*44px/);
  assert.match(css, /button \{[^}]*min-height:\s*40px/);
  assert.match(css, /input:not\(\[type=checkbox\]\)[^{]*\{[^}]*min-height:\s*var\(--tap\)/);
});
