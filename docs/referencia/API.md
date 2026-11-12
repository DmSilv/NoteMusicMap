# API: endpoints e ações

> **Gerado automaticamente** por `scripts/gen_docs.js` a partir do código. Não edite à mão: rode `node scripts/gen_docs.js`.
> Cada endpoint é um arquivo em `api/` (uma função da Vercel). O limite do plano Hobby é **12 funções**; arquivos de teste ficam fora do deploy.

Funções hoje: **8 de 12**.

## `/api/admin`

```text
/api/admin: painel do administrador (indicadores e gestão de perfis anônimos).

 POST { action, ... } com "Authorization: Bearer <chave de admin>". Ações:
  kpis                       indicadores (total, ativos x inativos, professores, crescimento, retenção)
  list {offset?, q?, by?}    perfis, do mais recente ao mais antigo (busca por trecho do código; by:'name' busca pelo apelido nos 100 mais recentes)
  detail {code}              um perfil: papel, vínculos, volume de dados (NUNCA o segredo)
  block / unblock {code}     impede / libera o vínculo online do perfil
  delete {code, confirm}     apaga os dados e vínculos do perfil (confirm tem que ser o código)
  bugs {days,sev,status,ver,plat,code,q,offset}  bugs agrupados (relatórios de erro do app), com filtros
  bug {fp}                   um bug: pilha, trilha, ambiente, últimas ocorrências, tendência
  bug_status {fp,status,note?}  marca como seen | resolved | ignored | new (e anota)
  system                     banco (teste de conexão, tamanho), servidor (versão, erros), variáveis configuradas e limites
  log                        últimas ações do administrador
 Suporte (tudo registrado no log e avisado ao usuário no app):
  unlink {code, other, as}   encerra um vínculo; "as" é o papel de {code}: teacher | student
  agenda {code}              agenda do perfil: aulas que marcou, horários livres, aulas que recebeu
  agenda_del {code, kind, id, other?}  apaga um item travado (kind: class | avail | mine; mine pede other = professor)
  support_code {code}        gera o código de uso único (24 h) para liberar a conta em outro aparelho
  support_cancel {code}      cancela o código pendente
  indicators                 saúde do uso: notificações negadas, versões antigas, cota de IA, bloqueados, online
  push {op}                  avisos de bug grave neste navegador: status | sub {sub} | unsub {endpoint} | test
  presence                   quem está online agora (sinal nos últimos 12 min) e quem esteve há pouco
 Recursos liberados aos poucos (docs/PLANO_AULA_ONLINE_AGENDA_ADMIN.md, seção 6):
  features                   um cartão por recurso: estado, % e quem está na lista
  feature_set {id, mode, pct?}        off | list | pct | all
  feature_grant {id, code, students?} libera um código (e, se students, os alunos vinculados a ele)
  feature_revoke {id, code, students?} tira da lista

Não há cadastro nem login no app: "usuário" = perfil anônimo (código + apelido). O apelido pertence
ao usuário (volta a cada sincronização), por isso o painel não o edita.
Custo: só quando o admin abre o painel (kpis ~35 comandos; lista de 25 = ~27; detalhe = ~12).
```

| Ação / tipo | Descrição (comentário do código) |
|---|---|
| `kpis` | Indicadores |
| `list` | Lista |
| `detail` | Detalhe |
| `block` | Bloquear / liberar |
| `delete` | Excluir |
| `indicators` | Indicadores de saúde do uso Custo: 3 comandos + 7 leituras (um hash por dia). Só quando o admin abre ou toca em Atualizar. |
| `library` | Acervo e Repertório (professores de teste) |
| `library_hide` | — |
| `visitors` | Visitantes (quem usa sem cadastro): divulgação e engajamento Custo: ~35 comandos por abertura da aba (7 dias de contadores + abas de hoje + 4 contagens). |
| `features` | Limpa agora os perfis abandonados (sem vínculo, sem dados e parados há 60 dias). Até 30 por toque. Recursos liberados aos poucos |
| `feature_set` | — |
| `feature_grant` | — |
| `sweep` | — |
| `push` | Avisos de bug grave neste navegador |
| `presence` | Presença: perfis com vínculo ligado e o app à frente |
| `unlink` | Suporte: encerrar um vínculo |
| `agenda` | Suporte: agenda do perfil |
| `agenda_del` | Suporte: apagar item de agenda travado |
| `avail` | — |
| `class` | — |
| `mine` | — |
| `support_code` | Suporte: código para liberar a conta em outro aparelho |
| `support_cancel` | — |
| `bugs` | Bugs (relatórios de erro do app) |
| `health` | Saúde (semáforo do painel) |
| `system` | Sistema: banco, servidor, variáveis e limites Custo: 3 comandos de teste + 14 leituras de erros (só quando o admin abre a aba Sistema). |
| `costs` | Custos (estimativa de comandos do Redis) |
| `bug` | — |
| `bug_status` | — |
| `log` | — |

## `/api/ai-status`

```text
GET /api/ai-status: quais serviços de IA estão ativos e quanto se espera na fila.
Nunca devolve chaves; só o necessário para o app mostrar o estado.
```

## `/api/coach`

```text
Função da Vercel: POST /api/coach  (IA com vários serviços e fila)

Recebe um RESUMO de números (nunca áudio) e um tipo de pedido, escolhe o serviço
de IA certo (Gemini, OpenAI, Claude, Groq, Mistral, OpenRouter), respeita o limite
de cada um com uma FILA JUSTA entre aparelhos e devolve o texto em português.
As chaves ficam só nas variáveis de ambiente da Vercel; o app nunca as vê.

  corpo:  { summary, kind?: session_summary|teacher_report|study_plan|question, ticket? }
  200:    { text, provider, label, model, kind, remainingToday? }
  429:    { error: queued|busy|cooldown|user_daily|daily_global, retryAfterMs, ticket?, position? }

Regras (ver api/_lib/): router.js (quem atende cada tipo), queue.js (fila),
store.js (contadores; Upstash Redis opcional), providers.js (adaptadores).

Variáveis: geminiAPI, OPENAI_API_KEY, ANTHROPIC_API_KEY, GROQ_API_KEY,
OPENROUTER_API_KEY, MISTRAL_API_KEY (as que existirem ficam ativas) e opcionais
AI_PROVIDERS, AI_ROUTE_<TIPO>, AI_RPM_<SERVIÇO>, AI_USER_DAILY, AI_COOLDOWN_S,
AI_RPD, AI_MAX_WAIT_MS, AI_TICKET_SECRET, MODEL_<SERVIÇO>_<FAST|SMART>.
```

## `/api/errors`

```text
POST /api/errors: relatório de erro do app (anônimo e sem dados pessoais).

O app manda o que aconteceu (código, tela, detalhe já higienizado, versão, aparelho, trilha de
telas). O servidor higieniza DE NOVO (nunca confia no app), agrupa o mesmo bug por impressão
digital e guarda contadores, aparelhos afetados (distintos), tendência e as últimas ocorrências.
Ninguém lê isto sem a chave de admin (painel `/api/admin`, ações `bugs`).

Proteções: tamanho máximo, limite por aparelho/hora, teto global por dia, chave de desligar
(ERRORS_DISABLED=1) e modo "leve" para bug que já se repetiu demais (ver `_lib/error_store.js`).
Custo no Redis (medido nos testes): ~23 comandos por evento (3 chamadas em lote); modo leve ~16.
```

## `/api/feedback`

```text
POST /api/feedback: nota do app e respostas das pesquisas rápidas (anônimas).
GET  /api/feedback: resumo para o dono do app (exige FEEDBACK_ADMIN_KEY).

Privacidade: guarda só a resposta, a versão e um código do aparelho EMBARALHADO
(hash). Nada de nome, e-mail, IP ou áudio. Sem Redis, as respostas só duram na
memória da instância (e vão para o log da Vercel); com Upstash Redis ficam guardadas.
```

| Ação / tipo | Descrição (comentário do código) |
|---|---|
| `rating` | — |

## `/api/link`

```text
POST /api/link: vínculo entre professor e aluno, registrado dos dois lados.

Quem lê o QR (ou digita o código) do outro cria o vínculo; ele passa a valer
para os dois, e cada um vê o outro na sua lista na próxima atualização.

O servidor guarda: o código de cada perfil, o apelido opcional, um hash do segredo
(para provar que o código é seu), a lista de vínculos com a data e, quando o professor
ENCERRA uma aula, o pacote dela (tarefas e observações daquela aula) para o aluno
vinculado buscar. Nunca áudio, nem o histórico de exercícios.

Ações (todas POST, com { code, secret }):
  sync     -> listas de vínculos e a revisão das aulas (lr)
  link     -> cria o vínculo (role + other)
  unlink   -> desfaz o vínculo (e apaga as aulas desse professor para esse aluno)
  lesson   -> PROFESSOR publica uma aula encerrada para um aluno vinculado { other, lesson }
  lessons  -> ALUNO busca as aulas dos professores a que está vinculado
  done     -> ALUNO avisa que fez (ou desmarcou) uma tarefa de um professor { other, lesson, task, done }
  rev      -> só os contadores de novidade { lr, dr, kr } (1 comando): o app só baixa listas se mudou
  sched_put-> PROFESSOR marca/muda/cancela uma aula { other, slot } e agenda o lembrete (QStash)
  sched    -> ALUNO busca as aulas marcadas pelos professores
  push_key / push_sub / push_unsub -> notificações (Web Push) deste aparelho
  dones    -> PROFESSOR busca o que os alunos marcaram como feito (e a revisão dr no sync)

Precisa do Upstash Redis. Sem ele devolve 503 e o app segue só neste aparelho.
```

| Ação / tipo | Descrição (comentário do código) |
|---|---|
| `lesson` | Só 'lesson' pode ser grande; os demais pedidos têm ~200 bytes. |
| `claim` | Liberação pelo suporte: o aparelho novo prova que tem o código de uso único gerado no painel e passa a ser o dono do perfil (o segredo antigo deixa de valer). Só a tentativa errada conta. |
| `sync` | — |
| `rev` | Consulta barata: o perfil já foi lido na autenticação, então não custa nenhum comando a mais. lr = aulas novas, dr = tarefas marcadas pelos alunos, kr = vínculos mudaram. |
| `avail` | O ALUNO vê os horários disponíveis de um professor a que está vinculado (só os que ainda dá para pegar). |
| `picks` | O PROFESSOR vê as aulas que os alunos pegaram (para entrarem na agenda dele). |
| `verdicts` | O ALUNO busca o que o professor decidiu (validou ou devolveu) sobre as suas tarefas. |
| `dones` | O PROFESSOR busca o que os alunos marcaram como feito (só dos alunos ainda vinculados). |
| `push_key` | Lembretes: o app pergunta se o servidor está pronto para enviar notificações. |
| `sched` | O ALUNO busca as aulas marcadas pelos professores a que ainda está vinculado. |
| `lessons` | O aluno busca as aulas dos professores a que ainda está vinculado. |
| `lib_list` | Acervo e Repertório (só links): leitura. O professor vê tudo; o aluno vê o que é para ele |
| `lib_put` | Acervo: o PROFESSOR liberado cadastra, muda ou apaga; o ALUNO denuncia |
| `lib_del` | — |
| `lib_report` | — |
| `push_sub` | Notificações: inscrição do navegador deste aparelho |
| `push_unsub` | — |
| `avail_put` | Horários disponíveis: o PROFESSOR cria, muda ou apaga |
| `avail_take` | O ALUNO pega um horário disponível: o primeiro que pega leva |
| `sched_put` | Agenda: o PROFESSOR marca, muda ou cancela uma aula (e agenda o lembrete) |
| `done` | O ALUNO marca (ou desmarca) como feita uma tarefa que recebeu de um professor vinculado. |
| `verdict` | O PROFESSOR decide sobre uma tarefa de um aluno vinculado: 'ok' valida, 'back' devolve, vazio apaga a decisão. O aluno vê isso como o status oficial. |
| `link` | — |
| `unlink` | — |

## `/api/remind`

```text
POST /api/remind: chamado pelo QStash 15 minutos antes de uma aula. Envia a notificação ao
professor e ao aluno (Web Push) e agenda o lembrete da próxima aula (se a aula é semanal).

Só aceita mensagens que o próprio servidor criou: assinatura própria (HMAC com um segredo
derivado da chave do QStash) e, se as chaves de assinatura estão configuradas, o JWT do QStash.
Mensagem velha (aula mudada, cancelada, dia pulado, vínculo desfeito) é ignorada.
```

## `/api/stats`

```text
/api/stats: métricas ANÔNIMAS de uso do app.

 POST (o app, sem chave): { t: 'open'|'beat', id, d?: { pl, in, v, o?, x?: { os, sc, lg, th, tc, mic, nt } }, tabs?: [...] }
       id = código aleatório do aparelho (NÃO é o código de professor/aluno). Nada de IP,
       nome, áudio ou o que a pessoa toca é guardado.
 GET  (só o admin, com "Authorization: Bearer <chave>"): ?part=live (online agora) ou ?part=full.

Custo no Redis por aparelho por dia: ~10 comandos ao abrir (4 quando já abriu hoje) e 1 por
batida (a cada ~5 min, só com o app à frente). Nenhum comando lê listas grandes.
```

| Ação / tipo | Descrição (comentário do código) |
|---|---|
| `beat` | — |

