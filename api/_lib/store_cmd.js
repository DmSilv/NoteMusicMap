// Comandos genéricos do Redis (HyperLogLog, conjuntos ordenados, contadores em hash) para as
// métricas, com um emulador mínimo em memória para os testes. Em produção vai tudo ao Upstash,
// em lote (`/pipeline`): uma ida e volta de rede para vários comandos.
'use strict';

const { hashes } = require('./store');

const sets = new Map(); // PFADD/PFCOUNT (só testes): chave -> Set
const zsets = new Map(); // ZADD...: chave -> Map(membro -> pontos)

function bound(v, dflt) {
  const s = String(v);
  if (s === '-inf') return -Infinity;
  if (s === '+inf' || s === 'inf') return Infinity;
  const n = Number(s);
  return Number.isFinite(n) ? n : dflt;
}

/** Emula o pedaço do Redis que as métricas usam. */
function memCmd(a) {
  const op = String(a[0]).toUpperCase();
  const key = a[1];
  switch (op) {
    case 'PFADD': {
      const s = sets.get(key) || sets.set(key, new Set()).get(key);
      let added = 0;
      for (const m of a.slice(2)) if (!s.has(String(m))) { s.add(String(m)); added = 1; }
      return added;
    }
    case 'PFCOUNT': {
      const u = new Set();
      for (const k of a.slice(1)) for (const m of sets.get(k) || []) u.add(m);
      return u.size;
    }
    case 'ZADD': {
      let i = 2;
      let xx = false;
      if (String(a[i]).toUpperCase() === 'XX') { xx = true; i++; }
      const z = zsets.get(key) || zsets.set(key, new Map()).get(key);
      const member = String(a[i + 1]);
      const had = z.has(member);
      if (xx && !had) return 0;
      z.set(member, Number(a[i]));
      return had ? 0 : 1;
    }
    case 'ZCOUNT': {
      const lo = bound(a[2], -Infinity), hi = bound(a[3], Infinity);
      let n = 0;
      for (const v of (zsets.get(key) || new Map()).values()) if (v >= lo && v <= hi) n++;
      return n;
    }
    case 'ZREMRANGEBYSCORE': {
      const lo = bound(a[2], -Infinity), hi = bound(a[3], Infinity);
      const z = zsets.get(key);
      if (!z) return 0;
      let n = 0;
      for (const [m, v] of [...z]) if (v >= lo && v <= hi) { z.delete(m); n++; }
      return n;
    }
    case 'HINCRBY': {
      const h = hashes.get(key) || hashes.set(key, new Map()).get(key);
      const v = (Number(h.get(String(a[2]))) || 0) + Number(a[3]);
      h.set(String(a[2]), String(v));
      return v;
    }
    case 'INCR': {
      const k = 'incr:' + key;
      const h = hashes.get(k) || hashes.set(k, new Map()).get(k);
      const v = (Number(h.get('v')) || 0) + 1;
      h.set('v', String(v));
      return v;
    }
    case 'EXPIRE':
      return 1;
    case 'HGETALL': {
      const out = [];
      for (const [k, v] of hashes.get(key) || []) out.push(k, v);
      return out;
    }
    default:
      throw new Error('comando não emulado: ' + op);
  }
}

function resetMem() { sets.clear(); zsets.clear(); }

/** Devolve { cmd, pipeline } ligados ao Redis (ou à memória, se permitido). */
function createCmd(cfg, fetchImpl, opts = {}) {
  const useRedis = !!(cfg.redisUrl && cfg.redisToken);
  const headers = () => ({ Authorization: `Bearer ${cfg.redisToken}`, 'Content-Type': 'application/json' });
  return {
    durable: useRedis || !!opts.allowMemory,
    async cmd(args) {
      if (useRedis) {
        const r = await fetchImpl(cfg.redisUrl, { method: 'POST', headers: headers(), body: JSON.stringify(args) });
        if (!r.ok) throw new Error('redis ' + r.status);
        return (await r.json()).result;
      }
      if (!opts.allowMemory) throw new Error('no-redis');
      return memCmd(args);
    },
    /** Vários comandos numa só chamada; devolve os resultados na mesma ordem. */
    async pipeline(list) {
      if (!list.length) return [];
      if (useRedis) {
        const r = await fetchImpl(`${cfg.redisUrl.replace(/\/+$/, '')}/pipeline`, { method: 'POST', headers: headers(), body: JSON.stringify(list) });
        if (!r.ok) throw new Error('redis ' + r.status);
        const j = await r.json();
        return j.map((x) => (x && x.error ? null : x && x.result));
      }
      if (!opts.allowMemory) throw new Error('no-redis');
      return list.map(memCmd);
    },
  };
}

module.exports = { createCmd, resetMem, memCmd };
