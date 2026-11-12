// Testes de tela do Flutter (widgets) rodando num pacote isolado: `node scripts/ui_tests.js`
//
// Por quê: o app depende de áudio nativo (flutter_soloud), cujo `flutter test` precisa compilar C++ (Visual Studio no Windows).
// As telas e peças que NÃO dependem de áudio nem de AppState (modal de sucesso, tutorial guiado, design system...) podem ser testadas
// sem isso. Este script lê o que cada teste de test/ui/ importa (`package:afina/...`), copia só esses arquivos para uma pasta temporária
// com um pubspec mínimo e roda `flutter test` lá. Se um teste puxar (direta ou indiretamente) um pacote fora do Flutter, para e diz qual arquivo.
// Roda igual no seu computador e no CI.
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const LIB = path.join(ROOT, 'lib');
const TESTS = path.join(ROOT, 'test', 'ui');
const OK_PACKAGES = new Set(['flutter', 'flutter_test', 'flutter_localizations', 'afina_core']); // afina_core é Dart puro: entra como dependência local
const CORE = path.join(ROOT, 'packages', 'afina_core').replace(/\\/g, '/');

const files = fs.existsSync(TESTS) ? fs.readdirSync(TESTS).filter((f) => f.endsWith('_test.dart')) : [];
if (!files.length) { console.log('Nenhum teste em test/ui.'); process.exit(0); }

const need = new Set(); // caminhos relativos a lib/
const problems = [];
function visit(libRel, from) {
  if (need.has(libRel)) return;
  const abs = path.join(LIB, libRel);
  if (!fs.existsSync(abs)) { problems.push(`${from} importa ${libRel}, que não existe`); return; }
  need.add(libRel);
  const src = fs.readFileSync(abs, 'utf8');
  for (const m of src.matchAll(/^\s*(?:import|export)\s+'([^']+)'/gm)) {
    const u = m[1];
    if (u.startsWith('dart:')) continue;
    if (u.startsWith('package:')) {
      const pkg = u.slice(8).split('/')[0];
      if (pkg === 'afina') visit(u.slice('package:afina/'.length), libRel);
      else if (!OK_PACKAGES.has(pkg)) problems.push(`lib/${libRel} depende do pacote "${pkg}" (precisa de áudio/rede nativa): fora do teste isolado`);
      continue;
    }
    visit(path.posix.normalize(path.posix.join(path.posix.dirname(libRel.replace(/\\/g, '/')), u)), libRel);
  }
}
for (const f of files) {
  const src = fs.readFileSync(path.join(TESTS, f), 'utf8');
  for (const m of src.matchAll(/^\s*import\s+'([^']+)'/gm)) {
    const u = m[1];
    if (u.startsWith('package:afina/')) visit(u.slice('package:afina/'.length), 'test/ui/' + f);
    else if (u.startsWith('package:') && !OK_PACKAGES.has(u.slice(8).split('/')[0])) problems.push(`test/ui/${f} importa ${u}, fora do teste isolado`);
  }
}
if (problems.length) { console.log('Teste de tela isolado não pode rodar:\n - ' + [...new Set(problems)].join('\n - ')); process.exit(1); }

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'afina-ui-'));
try {
  for (const rel of need) { const to = path.join(tmp, 'lib', rel); fs.mkdirSync(path.dirname(to), { recursive: true }); fs.copyFileSync(path.join(LIB, rel), to); }
  fs.mkdirSync(path.join(tmp, 'test', 'ui'), { recursive: true });
  for (const f of files) fs.copyFileSync(path.join(TESTS, f), path.join(tmp, 'test', 'ui', f));
  const sdk = (fs.readFileSync(path.join(ROOT, 'pubspec.yaml'), 'utf8').match(/^\s*sdk:\s*(\^[\d.]+)/m) || [])[1] || '^3.0.0';
  fs.writeFileSync(path.join(tmp, 'pubspec.yaml'),
    `name: afina\npublish_to: none\nenvironment:\n  sdk: ${sdk}\ndependencies:\n  flutter:\n    sdk: flutter\n  flutter_localizations:\n    sdk: flutter\n  afina_core:\n    path: "${CORE}"\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n`);
  console.log(`Teste de tela isolado: ${files.length} arquivo(s) de teste, ${need.size} arquivo(s) do app (${[...need].join(', ')})`);
  const flutter = process.platform === 'win32' ? 'flutter.bat' : 'flutter';
  const get = spawnSync(flutter, ['pub', 'get'], { cwd: tmp, stdio: 'inherit', shell: process.platform === 'win32' });
  if (get.status !== 0) process.exit(get.status || 1);
  const r = spawnSync(flutter, ['test', '--reporter', 'expanded'], { cwd: tmp, stdio: 'inherit', shell: process.platform === 'win32' });
  process.exitCode = r.status === null ? 1 : r.status;
} finally {
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) { /* Windows pode segurar o arquivo */ }
}
