# Operação

## Onde as coisas estão
| O quê | Onde |
|---|---|
| Código | GitHub `DmSilv/NoteMusicMap`, ramo `main` |
| Site e funções | Vercel, projeto `notemusicmap` → https://notemusicmap.vercel.app |
| Banco | Upstash Redis (REST) |
| Lembretes | Upstash QStash |
| Painel | https://notemusicmap.vercel.app/admin |

## Deploy
- **Automático**: todo `git push` no `main` dispara o deploy na Vercel. O build (`scripts/vercel_build.sh`) baixa o **Flutter 3.47.9** (versão fixa), roda `flutter build web --release --dart-define=BUILD_ID=<sha> --dart-define=CONTACT_EMAIL=...` e grava `build/web/build-id.txt`.
- A versão do app mostrada nas estatísticas e nos relatórios de erro é o início do **commit** (`BUILD_ID`, 7 caracteres); `dev` em build local.
- Preset da Vercel: **Other** (o `vercel.json` define build e pasta de saída `build/web`).
- **Depois do push não se espera o deploy** (regra do dono): segue-se para a próxima tarefa; só se confere se houver problema.
- Se o `git push` ficar lento, rode-o em segundo plano e confira depois (`git status -sb` deve mostrar `main...origin/main` sem `ahead`).

## Limites que mordem
1. **12 funções na Vercel Hobby.** Cada arquivo em `api/` (fora de `_lib/`) conta, **inclusive `*.test.js`**. Os testes ficam fora do deploy via `.vercelignore`. Hoje: 8 funções (`admin`, `ai-status`, `coach`, `errors`, `feedback`, `link`, `remind`, `stats`). Antes de criar um endpoint: `ls api/*.js | grep -v test | wc -l`. Se encostar em 12, **dobre ações dentro de um endpoint existente** (como `kpis`/`bugs` dentro de `admin`).
2. **500 mil comandos/mês no Upstash (gratuito).** Veja a aba Custos. Regras: nada de polling de lista, ações novas medem custo, tetos e limites por perfil.
3. **QStash**: uma mensagem por vez (o próximo lembrete).

## Variáveis de ambiente (Vercel › Settings › Environment Variables)
> Os **valores nunca ficam no repositório nem no chat.** A lista exata lida pelo código está em [referencia/AMBIENTE.md](referencia/AMBIENTE.md).

| Variável | Obrigatória? | Para quê |
|---|---|---|
| `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` (ou, pela integração da Vercel, `KV_REST_API_URL`, `KV_REST_API_TOKEN`) | **Sim** para vínculo, painel e erros | Banco |
| `ADMIN_KEY` | Recomendada | Chave do painel (cai em `FEEDBACK_ADMIN_KEY` se faltar) |
| `FEEDBACK_ADMIN_KEY` | Opcional | Leitura do painel de feedback (e fallback do painel) |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` | Para lembretes e para os avisos de bug grave do admin | Web Push (gerar com `node scripts/gen_vapid.js`; a privada nunca vai ao chat) |
| `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY`, `QSTASH_URL` | Para lembretes | Agendamento e verificação de assinatura |
| `APP_BASE_URL` | Opcional | Endereço público (padrão `https://notemusicmap.vercel.app`) |
| `VERCEL_GIT_COMMIT_SHA`, `VERCEL_ENV`, `VERCEL_REGION` | Automáticas (a Vercel preenche) | A aba Sistema do painel mostra a versão publicada, o ambiente e a região |
| `geminiAPI`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GROQ_API_KEY`, `MISTRAL_API_KEY`, `OPENROUTER_API_KEY` | Pelo menos uma para a IA | Chaves dos serviços de IA (as que existirem ficam ativas) |
| `AI_PROVIDERS`, `AI_RPM`, `AI_RPM_<ID>`, `AI_RPD`, `AI_USER_DAILY`, `AI_COOLDOWN_S`, `AI_MAX_WAIT_MS`, `AI_TICKET_SECRET`, `GEMINI_MODEL` | Opcionais | Afinar a IA (quais, limites, fila, modelo) |
| `ERRORS_DISABLED`, `ERRORS_DAILY_CAP` | Opcionais | Desligar/limitar relatórios de erro |
| `CONTACT_EMAIL` | Opcional (build) | E-mail mostrado na política de privacidade |
| `FLUTTER_VERSION` | Opcional (build) | Muda a versão do Flutter do build (padrão 3.47.9) |

Mudou uma variável? É preciso um **novo deploy** para valer.

## Rollback
1. **Vercel**: Deployments › escolher o deploy anterior bom › *Promote to Production* (instantâneo).
2. **Git**: `git revert <commit>` e `git push` (gera um deploy novo).
3. **Só relatórios de erro**: `ERRORS_DISABLED=1` (+ novo deploy) corta a coleta sem mexer em código.
Dados no Redis não precisam de rollback: as mudanças da API são **aditivas**.

## Monitoramento do dia a dia
- Abra `/admin`: semáforo no topo, aba **Bugs** (novos/graves/reabertos), aba **Custos** (% do plano).
- E-mail da Vercel avisa deploy que falhou.
- Aba Uso › "Online agora" mostra se há gente usando.

## Incidentes (receitas)
| Sintoma | O que fazer |
|---|---|
| E-mail da Vercel: *"Não mais que 12 Funções Serverless"* | Contar `api/*.js` (sem `_lib`); garantir `.vercelignore` com `api/*.test.js`; juntar endpoints se preciso. Enquanto falha, a produção segue na **última versão que compilou**. |
| Custos perto de 100% do plano | Aba Custos mostra o maior item. Se for polling: aumentar o intervalo no app (`app_state.dart`); se for erros: `ERRORS_DISABLED=1` e/ou baixar `ERRORS_DAILY_CAP`. |
| Pico de erros / semáforo vermelho | Aba Bugs ordenada por recência; abrir o bug (pilha + trilha + versão); se for da versão nova, rollback na Vercel. |
| Aviso de bug grave não chega ao admin | Aba Bugs › cartão "Avisos de bug grave": se disser "indisponível", faltam as VAPID; se estiver "desativado", ative neste navegador e use "Enviar teste". |
| Lembretes não chegam | `POST /api/link {action:'push_key'}` deve devolver `enabled: true`; conferir `VAPID_*` e `QSTASH_*`; no iPhone o app precisa estar instalado na tela inicial. |
| IA não responde | `GET /api/ai-status` (quais serviços estão ativos); conferir chaves; fila cheia devolve 429 com `retryAfterMs`. |
| Painel diz "chave inválida" | Conferir `ADMIN_KEY`/`FEEDBACK_ADMIN_KEY`; redeploy depois de mudar. |
| Usuário vê versão antiga | Ajustes › Sobre › "Atualizar o app" (ou "Apagar tudo e recomeçar" em último caso); o service worker pode manter cache. |
| Perfil abusivo | `/admin` › Pessoas › abrir o perfil › **Bloquear** (ou excluir dados). |

## Rotinas
- **A cada pacote publicado:** conferir o e-mail da Vercel e, se possível, a aba Bugs depois de algumas horas.
- **Mensal:** olhar a aba Custos e o crescimento de perfis; revisar dependências do Flutter se necessário.
- **Quando a `ADMIN_KEY` própria existir:** remover o *fallback* para `FEEDBACK_ADMIN_KEY` em `api/_lib/config.js`.
- **CSP:** já está em modo bloqueio. Se uma tela quebrar depois de um deploy e o console do navegador falar em "Content Security Policy", volte o cabeçalho para `Content-Security-Policy-Report-Only` em `vercel.json`.
