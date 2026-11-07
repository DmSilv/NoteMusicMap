'use strict';
// Contadores, estado de saúde e fila. Usa o Upstash Redis (REST) quando configurado,
// para valer entre TODAS as instâncias da Vercel; senão cai para a memória da instância.

const memory = new Map(); // chave -> { v, exp }

function memGet(key, now = Date.now()) {
  const c = memory.get(key);
  if (!c || c.exp <= now) return null;
  return c.v;
}
function memSet(key, v, ttlMs, now = Date.now()) {
  if (memory.size > 5000) for (const [k, c] of memory) if (c.exp <= now) memory.delete(k);
  memory.set(key, { v, exp: now + ttlMs });
}

// Reserva atômica de horário (GCRA): slot = max(agora, ultimo + intervalo).
const LUA_CLAIM = `
local last = tonumber(redis.call('GET', KEYS[1]) or '0')
local now = tonumber(ARGV[1])
local slot = math.max(now, last + tonumber(ARGV[2]))
redis.call('SET', KEYS[1], tostring(slot), 'PX', tonumber(ARGV[3]))
return tostring(slot)
`;

function createStore(cfg, fetchImpl, clock = Date.now) {
  const useRedis = !!(cfg.redisUrl && cfg.redisToken);

  async function redis(cmd) {
    const r = await fetchImpl(cfg.redisUrl, {
      method: 'POST',
      headers: { Authorization: `Bearer ${cfg.redisToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(cmd),
    });
    if (!r.ok) throw new Error('redis ' + r.status);
    return (await r.json()).result;
  }

  return {
    redis: useRedis,

    /** Soma 1 na chave (expira em [ttlSec]); devolve o novo valor e o tempo restante. */
    async incr(key, ttlSec) {
      if (useRedis) {
        try {
          const n = Number(await redis(['INCR', key]));
          if (n === 1) await redis(['EXPIRE', key, String(ttlSec)]);
          const ttl = Number(await redis(['PTTL', key]));
          return { n, ttlMs: Math.max(0, ttl) };
        } catch (_) { /* cai para a memória */ }
      }
      const now = clock();
      const cur = memGet(key, now);
      if (cur == null) {
        memSet(key, { n: 1, exp: now + ttlSec * 1000 }, ttlSec * 1000, now);
        return { n: 1, ttlMs: ttlSec * 1000 };
      }
      cur.n += 1;
      return { n: cur.n, ttlMs: Math.max(0, cur.exp - now) };
    },

    async get(key) {
      if (useRedis) {
        try { return await redis(['GET', key]); } catch (_) { /* memória */ }
      }
      return memGet(key, clock());
    },

    async set(key, value, ttlSec) {
      if (useRedis) {
        try { await redis(['SET', key, String(value), 'EX', String(ttlSec)]); return; } catch (_) { /* memória */ }
      }
      memSet(key, String(value), ttlSec * 1000, clock());
    },

    /** Último horário reservado nesta fila (0 se vazia). */
    async lastSlot(key) {
      const v = await this.get(key);
      return Number(v) || 0;
    },

    /** Reserva o próximo horário livre da fila [key]. */
    async claimSlot(key, now, intervalMs, ttlMs = 600000) {
      if (useRedis) {
        try {
          return Number(await redis(['EVAL', LUA_CLAIM, '1', key, String(now), String(intervalMs), String(ttlMs)]));
        } catch (_) { /* memória */ }
      }
      const last = Number(memGet(key, now)) || 0;
      const slot = Math.max(now, last + intervalMs);
      memSet(key, String(slot), ttlMs, now);
      return slot;
    },
  };
}

module.exports = { createStore, memory };
