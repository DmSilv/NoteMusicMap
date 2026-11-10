#!/usr/bin/env node
// Gera as partes da documentação que vêm direto do código (para nunca ficarem velhas):
//   docs/referencia/ARQUIVOS.md  mapa de todos os arquivos, com a descrição do cabeçalho de cada um
//   docs/referencia/API.md       endpoints e ações da API (com o comentário de cada ação)
//   docs/referencia/DADOS.md     chaves do Redis e do armazenamento local do app
//   docs/referencia/ERROS.md     catálogo de códigos de erro
//   docs/referencia/AMBIENTE.md  variáveis de ambiente lidas pelo servidor
//
// Uso:  node scripts/gen_docs.js           (escreve os arquivos)
//       node scripts/gen_docs.js --check   (falha se a documentação gerada estiver desatualizada)
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'docs', 'referencia');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8').replace(/\r/g, '');
const exists = (p) => fs.existsSync(path.join(ROOT, p));

function walk(dir, filter) {
  const out = [];
  const abs = path.join(ROOT, dir);
  if (!fs.existsSync(abs)) return out;
  for (const e of fs.readdirSync(abs, { withFileTypes: true })) {
    const rel = `${dir}/${e.name}`;
    if (e.isDirectory()) out.push(...walk(rel, filter));
    else if (filter(rel)) out.push(rel);
  }
  return out.sort();
}

const HEADER = (title, how) => `# ${title}\n\n> **Gerado automaticamente** por \`scripts/gen_docs.js\` a partir do código. Não edite à mão: rode \`node scripts/gen_docs.js\`.\n> ${how}\n\n`;

// ---------------------------------------------------------------- descrições dos arquivos
/** Primeira descrição útil do arquivo: o 1º bloco de comentário de documentação (///) ou o cabeçalho (//). */
const OVERRIDES = {
  'lib/app_state.dart': 'Estado central do app (ChangeNotifier): afinador, metrônomo, grade, estudo, perfil, alunos, aulas, agenda, horários livres, avisos, erros, vínculo online e preferências. Quase toda tela lê e escreve aqui.',
  'lib/ai/coach_ai.dart': 'Análise por IA: pede ao servidor (`/api/coach`) um resumo, relatório ou plano a partir de números de afinação (nunca áudio), com fila, limite diário e endereço base da API (`kApiBase`).',
  'lib/audio/audio_out.dart': 'Saída de áudio (SoLoud): tom de referência, metrônomo por amostra exata, sinos e o Pedal (notas sustentadas, até 4 vozes).',
  'lib/audio/pitch_source.dart': 'Entrada de áudio: microfone (`record`) alimentando o detector de altura, com o quadro de análise (nota, tempo e nível do sinal).',
  'lib/link/link_service.dart': 'Cliente da API de vínculo (`/api/link`): vincular, aulas, tarefas feitas, decisões do professor, agenda, horários livres e notificações. Fala só com o servidor do app.',
  'lib/ui/error_ui.dart': 'Telas e blocos de erro: tela crítica (APP-99), cartão amigável no lugar de bloco que quebrou e a lista "Problemas recentes".',
  'lib/ui/grid_cell.dart': 'Um quadrado da grade de entonação (nota, cor da última vez, brilho e contagem).',
  'lib/ui/metronome_page.dart': 'Aba Metrônomo: andamento, compasso, subdivisão, som, tap tempo e modo desafio.',
  'lib/ui/settings_page.dart': 'Ajustes: aparência, afinação, microfone, metrônomo, grade, estudo, permissões e privacidade, conta, sobre e diagnóstico (problemas recentes e envio de relatórios).',
  'lib/ui/teacher_page.dart': 'Tela Alunos do professor (lista, novo aluno, QR, importar, métodos, senha) e a ficha do aluno (aula, tarefas, validação, observações, relatórios).',
  'lib/ui/tuner_page.dart': 'Aba Afinador: cordas soltas, cromático e Pedal; ponteiro, desvio, frequência, Lá de referência e tônica.',
  'lib/ui/widgets.dart': 'Peças comuns de interface: cartões, seleção de opções, folha de ajuda ("?") e textos de ajuda em um lugar só.',
  'lib/ui/install_banner.dart': 'Faixa "Instale o Notemusic no celular" (só no navegador, enquanto não instalou).',
  'lib/ui/my_lessons_page.dart': 'Minhas aulas (aluno): aulas e tarefas recebidas do professor, com o status oficial (validada, aguardando, refazer) e o botão de treinar.',
  'lib/ui/notifications_sheet.dart': 'Central de avisos (sino): lista todos os avisos, marca como lidos, limpa e leva ao lugar certo conforme o tipo.',
  'lib/ui/open_slots_page.dart': 'Horários livres do professor (publicar e apagar) e "Pegar horário" do aluno.',
  'lib/ui/ref_a_dialog.dart': 'Diálogo do Lá de referência (415 a 443 Hz e valor livre).',
  'lib/ui/share_sheet.dart': 'Compartilhar o app (QR, copiar link, enviar) e o convite do professor.',
  'lib/ui/slot_form_page.dart': 'Formulário de aula marcada (aluno, dia, hora, duração, repetir, observação) com as regras de horário.',
  'lib/ui/smooth_color.dart': 'Transição suave de cor para os quadrados da grade e do ponteiro.',
  'lib/ui/student_identity.dart': 'Selo do vínculo online e campo do código do aluno, na ficha e na lista.',
  'lib/ui/task_form_page.dart': 'Formulário de tarefa (escala, arpejo, método e lição, repertório ou outra) com observações.',
  'lib/ui/grid_widgets.dart': 'Peças da aba Grade: seletor de oitavas, teclado de uma oitava e legendas.',
  'lib/platform/hard_reset.dart': 'Apagar tudo e recarregar o app (botão "Apagar tudo e recomeçar"): escolhe a versão da web ou a de celular (importação condicional).',
  'lib/platform/web_install.dart': 'Instalar o app na tela inicial (PWA): detecta se já está instalado e abre o convite de instalação; escolhe a versão web ou a de celular.',
  'lib/platform/web_push.dart': 'Notificações do navegador (Web Push): permissão, inscrição e suporte; escolhe a versão web ou a de celular.',
  'lib/platform/web_vibrate.dart': 'Vibração no navegador (batida do metrônomo e exercícios); escolhe a versão web ou a de celular.',
  'packages/afina_core/lib/afina_core.dart': 'Ponto de entrada do núcleo: reexporta todos os módulos de `packages/afina_core/lib`.',
  '.vercelignore': 'Arquivos que NÃO vão para a Vercel (testes da API), para ficar abaixo do limite de 12 funções do plano Hobby.',
};

function describe(rel) {
  if (OVERRIDES[rel]) return OVERRIDES[rel];
  const text = read(rel);
  const lines = text.split('\n');
  const isDart = rel.endsWith('.dart');
  const isJs = rel.endsWith('.js') || rel.endsWith('.mjs');
  const grab = (re, strip) => {
    for (let i = 0; i < lines.length; i++) {
      if (!re.test(lines[i])) continue;
      const block = [];
      while (i < lines.length && re.test(lines[i])) { block.push(lines[i].replace(strip, '').trim()); i++; }
      const t = block.filter((x) => x && !/^(eslint|ignore|use strict)/i.test(x)).join(' ').replace(/\s+/g, ' ').trim();
      if (t) return t;
    }
    return '';
  };
  let d = '';
  if (isDart) d = grab(/^\s*\/\/\//, /^\s*\/\/\/ ?/);
  if (!d && (isJs || isDart)) d = grab(/^\s*\/\/(?!\/)/, /^\s*\/\/ ?/);
  if (!d && rel.endsWith('.html')) { const m = text.match(/<title>([^<]+)<\/title>/); d = m ? `Página HTML: ${m[1]}` : ''; }
  if (!d && rel.endsWith('.sh')) d = grab(/^#(?!!)/, /^# ?/);
  if (!d && rel.endsWith('.json')) d = 'Configuração (JSON).';
  d = d.replace(/\|/g, '\\|');
  if (d.length > 220) d = d.slice(0, 217).replace(/\s+\S*$/, '') + '…';
  if (!d && rel.endsWith('_test.dart')) d = 'Testes do módulo `' + path.basename(rel).replace('_test.dart', '') + '`.';
  return d || '_(sem descrição no cabeçalho)_';
}

function filesDoc() {
  const groups = [
    ['App Flutter (`lib/`)', walk('lib', (p) => p.endsWith('.dart'))],
    ['Núcleo em Dart puro (`packages/afina_core/lib/`)', walk('packages/afina_core/lib', (p) => p.endsWith('.dart'))],
    ['Testes do núcleo (`packages/afina_core/test/`)', walk('packages/afina_core/test', (p) => p.endsWith('.dart'))],
    ['API (funções da Vercel, `api/`)', walk('api', (p) => p.endsWith('.js') && !p.includes('/_lib/') && !p.endsWith('.test.js'))],
    ['Apoio da API (`api/_lib/`, não conta como função)', walk('api/_lib', (p) => p.endsWith('.js') && !p.endsWith('.test.js'))],
    ['Testes da API (ficam fora do deploy via `.vercelignore`)', walk('api', (p) => p.endsWith('.test.js'))],
    ['Site e painel (`web/`)', walk('web', (p) => /\.(html|js|json)$/.test(p) && !p.includes('/icons/'))],
    ['Scripts e configuração', ['vercel.json', '.vercelignore', 'pubspec.yaml', 'scripts/gen_vapid.js', 'scripts/vercel_build.sh', 'scripts/gen_docs.js', 'scripts/check_docs.js'].filter(exists)],
  ];
  let md = HEADER('Mapa de arquivos', 'Cada linha traz a descrição que está no cabeçalho do próprio arquivo. Se uma descrição estiver ruim, melhore o comentário no código.');
  let total = 0;
  for (const [title, files] of groups) {
    if (!files.length) continue;
    md += `## ${title}\n\n| Arquivo | O que faz |\n|---|---|\n`;
    for (const f of files) {
      md += `| \`${f}\` | ${f.endsWith('.yaml') ? 'Dependências e metadados do app Flutter.' : describe(f)} |\n`;
      total++;
    }
    md += '\n';
  }
  return md + `Total: **${total}** arquivos mapeados.\n`;
}

// ---------------------------------------------------------------- API
function apiDoc() {
  let md = HEADER('API: endpoints e ações', 'Cada endpoint é um arquivo em `api/` (uma função da Vercel). O limite do plano Hobby é **12 funções**; arquivos de teste ficam fora do deploy.');
  const files = walk('api', (p) => p.endsWith('.js') && !p.includes('/_lib/') && !p.endsWith('.test.js'));
  md += `Funções hoje: **${files.length} de 12**.\n\n`;
  for (const f of files) {
    const text = read(f);
    const lines = text.split('\n');
    const head = [];
    for (const l of lines) { if (/^\/\//.test(l)) head.push(l.replace(/^\/\/ ?/, '')); else if (head.length) break; }
    md += '## `/' + f.replace(/\.js$/, '') + '`\n\n```text\n' + head.join('\n') + '\n```\n\n';
    const rows = [];
    const seen = new Set();
    lines.forEach((l, i) => {
      const m = l.match(/(?:action|kind)\s*===\s*'([a-z_0-9]+)'/);
      if (!m || seen.has(m[1])) return;
      seen.add(m[1]);
      let c = '';
      for (let j = i - 1; j >= Math.max(0, i - 3); j--) {
        const t = lines[j].trim();
        if (t.startsWith('//')) { c = t.replace(/^\/\/\s*(-+\s*)?/, '').replace(/\s*-+\s*$/, '') + (c ? ' ' + c : ''); } else if (t) break;
      }
      rows.push([m[1], c.replace(/\|/g, '\\|')]);
    });
    if (rows.length) {
      md += '| Ação / tipo | Descrição (comentário do código) |\n|---|---|\n';
      for (const [a, c] of rows) md += `| \`${a}\` | ${c || '—'} |\n`;
      md += '\n';
    }
  }
  return md;
}

// ---------------------------------------------------------------- Dados
function keyLines(rel) {
  const out = [];
  read(rel).split('\n').forEach((l) => {
    const m = l.match(/(?:`|')([a-z]{1,4}:[a-z0-9:_${}.\-]*)(?:`|')[^\n]*?\/\/\s*(.+)$/i);
    if (m) out.push([m[1].replace(/\$\{([^}]+)\}/g, '<$1>'), m[2].trim()]);
  });
  return out;
}

function dataDoc() {
  let md = HEADER('Dados: Redis e armazenamento local', 'Chaves lidas dos comentários do código. Para mudar a descrição de uma chave, edite o comentário na linha onde ela é definida.');
  md += '## Redis (Upstash)\n\nTudo guardado no servidor é anônimo: código de perfil, apelido, datas e o necessário para o vínculo. Nunca áudio, e-mail ou IP.\n\n';
  for (const [rel, title] of [
    ['api/link.js', 'Vínculo, aulas, agenda, tarefas e horários (`api/link.js`)'],
    ['api/_lib/profiles.js', 'Índice de perfis para o painel (`api/_lib/profiles.js`)'],
    ['api/_lib/metrics.js', 'Estatísticas anônimas de uso (`api/_lib/metrics.js`)'],
    ['api/_lib/errors_lib.js', 'Relatórios de erro (`api/_lib/errors_lib.js`)'],
    ['api/admin.js', 'Painel do administrador (`api/admin.js`)'],
  ]) {
    const rows = keyLines(rel);
    if (!rows.length) continue;
    md += `### ${title}\n\n| Chave | Conteúdo |\n|---|---|\n`;
    for (const [k, d] of rows) md += `| \`${k}\` | ${d.replace(/\|/g, '\\|')} |\n`;
    md += '\n';
  }
  // armazenamento local
  const files = walk('lib', (p) => p.endsWith('.dart'));
  const keys = new Map();
  const re = /\b(?:get(?:String|Int|Bool|Double|StringList)|set(?:String|Int|Bool|Double|StringList)|remove)\(\s*'([A-Za-z0-9_]+)'/g;
  for (const f of files) {
    const t = read(f);
    let m;
    while ((m = re.exec(t))) {
      const set = keys.get(m[1]) || new Set();
      set.add(path.basename(f));
      keys.set(m[1], set);
    }
  }
  md += '## Armazenamento local do app (`SharedPreferences`)\n\nNo navegador aparecem no `localStorage` com o prefixo `flutter.`. Tudo fica no aparelho.\n\n| Chave | Arquivos que usam |\n|---|---|\n';
  for (const [k, set] of [...keys.entries()].sort((a, b) => a[0].localeCompare(b[0]))) md += `| \`${k}\` | ${[...set].sort().join(', ')} |\n`;
  md += `\nTotal: **${keys.size}** chaves locais.\n`;
  return md;
}

// ---------------------------------------------------------------- Erros
function errorsDoc() {
  const t = read('packages/afina_core/lib/errors.dart');
  let md = HEADER('Catálogo de erros', 'Lido de `packages/afina_core/lib/errors.dart` (`kErrorCatalog`). Para criar um erro novo, acrescente a entrada lá e rode o gerador.');
  md += '| Código | Gravidade | Título | O que a pessoa lê | Ação |\n|---|---|---|---|---|\n';
  const re = /'([A-Z]+-\d+)':\s*ErrorSpec\(\s*'[^']+',\s*ErrorSeverity\.(\w+),\s*'([^']*)',\s*'((?:[^'\\]|\\.)*)',\s*'([^']*)'\s*\)/g;
  let m, n = 0;
  while ((m = re.exec(t))) {
    md += `| \`${m[1]}\` | ${m[2]} | ${m[3]} | ${m[4].replace(/\\'/g, "'")} | ${m[5]} |\n`;
    n++;
  }
  md += `\nTotal: **${n}** códigos. Gravidade: \`critical\` derruba o app (tela cheia), \`action\` é uma ação que falhou, \`info\` é só aviso de conexão.\n`;
  return md;
}

// ---------------------------------------------------------------- Ambiente
function envDoc() {
  let md = HEADER('Variáveis de ambiente', 'Nomes lidos do código do servidor. **Os valores nunca ficam no repositório**: configure na Vercel (Settings › Environment Variables).');
  const files = [...walk('api', (p) => p.endsWith('.js') && !p.endsWith('.test.js'))];
  const map = new Map();
  for (const f of files) {
    const re = /env\.([A-Z][A-Z0-9_]+)/g;
    let m;
    const t = read(f);
    while ((m = re.exec(t))) (map.get(m[1]) || map.set(m[1], new Set()).get(m[1])).add(path.basename(f));
  }
  md += '| Variável | Lida em |\n|---|---|\n';
  for (const [k, set] of [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]))) md += `| \`${k}\` | ${[...set].sort().join(', ')} |\n`;
  md += `\nTotal: **${map.size}** variáveis. Para o que cada uma faz e quais são obrigatórias, veja \`docs/08_OPERACAO.md\`.\n`;
  return md;
}

// ---------------------------------------------------------------- principal
const OUTPUTS = {
  'ARQUIVOS.md': filesDoc,
  'API.md': apiDoc,
  'DADOS.md': dataDoc,
  'ERROS.md': errorsDoc,
  'AMBIENTE.md': envDoc,
};

function main() {
  const check = process.argv.includes('--check');
  let stale = 0;
  fs.mkdirSync(OUT, { recursive: true });
  for (const [name, fn] of Object.entries(OUTPUTS)) {
    const body = fn();
    const file = path.join(OUT, name);
    const cur = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').replace(/\r/g, '') : '';
    if (cur === body) continue;
    stale++;
    if (check) console.error(`Desatualizado: docs/referencia/${name}`);
    else fs.writeFileSync(file, body);
  }
  if (check) {
    if (stale) { console.error(`\n${stale} arquivo(s) de referência desatualizado(s). Rode: node scripts/gen_docs.js`); process.exit(1); }
    console.log('Documentação gerada está em dia.');
  } else {
    console.log(stale ? `Atualizados ${stale} arquivo(s) em docs/referencia/.` : 'Nada mudou.');
  }
}

if (require.main === module) main();
module.exports = { describe, OUTPUTS };
