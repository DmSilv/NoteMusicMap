// Acervo e Repertório do professor (só LINKS, nenhum arquivo é guardado aqui).
// O professor cadastra título, autor e o endereço do material (Google Drive, IMSLP, YouTube…); o aluno
// vinculado abre o endereço. Liberado só para quem está em LIBRARY_TESTERS (variável da Vercel).
// A MESMA lista de endereços aceitos existe em packages/afina_core/lib/library.dart: mantenha as duas iguais.
'use strict';

const MAX_ITEMS = 200; // itens por professor
const MAX_TO = 40; // alunos escolhidos por item

// Só endereços https destes sites (evita golpe e link para qualquer lugar). Subdomínios valem.
const HOSTS = [
  'drive.google.com', 'docs.google.com', 'dropbox.com', 'onedrive.live.com', '1drv.ms',
  'imslp.org', 'cpdl.org', 'youtube.com', 'youtu.be',
];

const rng = (a, b) => String.fromCharCode(a) + (b ? '-' + String.fromCharCode(b) : '');
// caracteres invisiveis e de controle (montados por codigo para o arquivo ficar so em ASCII)
const INVISIBLE = new RegExp('[' + [[0xad], [0x200b, 0x200f], [0x2028, 0x202e], [0x2060, 0x2064], [0x2066, 0x2069], [0xfeff]].map(([x, y]) => rng(x, y)).join('') + ']', 'g');
const CONTROL = new RegExp('[' + rng(0, 0x1f) + rng(0x7f, 0x9f) + ']', 'g');
const clean = (v, max) =>
  String(v == null ? '' : v).replace(INVISIBLE, '').replace(CONTROL, ' ').replace(/ {2,}/g, ' ').trim().slice(0, max);

/** Endereço aceito (https e site da lista) ou null. Devolve o endereço limpo. */
function cleanUrl(v) {
  const s = String(v == null ? '' : v).trim();
  if (s.length < 12 || s.length > 500 || /[\s<>"'`\\]/.test(s)) return null;
  let u;
  try { u = new URL(s); } catch (_) { return null; }
  if (u.protocol !== 'https:' || u.username || u.password) return null;
  const host = u.hostname.toLowerCase();
  if (!HOSTS.some((h) => host === h || host.endsWith('.' + h))) return null;
  return u.toString();
}

/**
 * Valida e limpa um item. [normCode] é a função de código do servidor. Devolve { item } ou { error }.
 * Exige a declaração do professor (ok === true).
 */
function cleanItem(raw, now, normCode) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return { error: 'Item inválido.' };
  const id = String(raw.id || '');
  if (!/^[a-z0-9]{2,40}$/.test(id)) return { error: 'Item inválido.' };
  if (raw.ok !== true) return { error: 'declaration', message: 'Confirme que você tem o direito de compartilhar este material.' };
  const t = clean(raw.t, 80);
  if (!t) return { error: 'Falta o título.' };
  const u = cleanUrl(raw.u);
  if (!u) return { error: 'bad_url', message: 'Use um link https do Google Drive, Dropbox, OneDrive, IMSLP, CPDL ou YouTube.' };
  let to = 'all';
  if (Array.isArray(raw.to)) {
    to = [...new Set(raw.to.map((c) => normCode(c)).filter(Boolean))].slice(0, MAX_TO);
    if (!to.length) to = 'all';
  }
  const item = {
    id,
    k: raw.k === 'r' ? 'r' : 'a', // a = acervo (métodos), r = repertório (peças)
    f: clean(raw.f, 40) || 'Geral',
    t,
    a: clean(raw.a, 60),
    u,
    n: clean(raw.n, 300),
    to,
    c: Number.isFinite(Number(raw.c)) && Number(raw.c) > 1577836800000 && Number(raw.c) <= now + 86400000 ? Math.round(Number(raw.c)) : now,
    m: now,
  };
  return { item };
}

/** O aluno [student] pode ver este item? (professor vê tudo; oculto pela moderação nunca aparece ao aluno) */
function visibleTo(item, student) {
  if (item.x) return false;
  return item.to === 'all' || (Array.isArray(item.to) && item.to.includes(student));
}

module.exports = { MAX_ITEMS, MAX_TO, HOSTS, cleanUrl, cleanItem, visibleTo };
