# API: endpoints e ações

> **Gerado automaticamente** por `scripts/gen_docs.js` a partir do código. Não edite à mão: rode `node scripts/gen_docs.js`.
> Cada endpoint é um arquivo em `api/` (uma função da Vercel). O limite do plano Hobby é **12 funções**; arquivos de teste ficam fora do deploy.

Funções hoje: **11 de 12**.

## `/api/account`

```text
POST /api/account: e-mail da conta, SEM senha. O e-mail serve para recuperar o perfil e entrar em outro aparelho.

O perfil continua nascendo sem cadastro (código + segredo do aparelho). Aqui a pessoa pode, se quiser, ligar um e-mail
a ele: o servidor manda um código de 6 dígitos para o e-mail, ela digita no app e pronto. Depois, num aparelho novo,
"Entrar com e-mail" manda outro código e, ao confirmar, este aparelho passa a ser o dono do perfil (o segredo antigo
deixa de valer, como na liberação pelo suporte do painel).

O servidor guarda só um HASH do e-mail (com pepper) e uma versão mascarada para mostrar ("d***@gmail.com"). O código
de 6 dígitos vale 10 minutos, aceita 5 tentativas e só é guardado como hash. Nunca registra o conteúdo do e-mail.

CHAVE DE 25 CARACTERES (sem e-mail, funciona mesmo com o envio de e-mail desligado): o app pede uma chave aleatória
(XXXXX-XXXXX-XXXXX-XXXXX-XXXXX, 125 bits) que o servidor guarda só como hash; num aparelho novo, digitá-la faz o aparelho
virar o dono do perfil (o segredo antigo deixa de valer). Gerar outra chave cancela a anterior.

Ações (todas POST):
  status        { code, secret }                      -> { ok, enabled, linked, hint, hasKey }
  rk_new        { code, secret }                      -> { ok, key }: gera a chave de 25 (a anterior deixa de valer)
  rk_login      { key, secret }                       -> { ok, code, name }: este aparelho (segredo novo) vira o dono
  bind_start    { code, secret, email, lang? }        -> manda o código ao e-mail
  bind_verify   { code, secret, email, otp }          -> liga o e-mail ao perfil
  unbind        { code, secret }                      -> desliga o e-mail do perfil
  login_start   { email, lang? }                      -> manda o código (sempre { ok } para não revelar quem tem conta)
  login_verify  { email, otp, secret, drop?, dn? }    -> { ok, code, name }: este aparelho (segredo novo) entra na conta
  pair_new      { code, secret }                      -> { ok, pair: 'XXXX-XXXX', ttl }: código de 10 min para ligar OUTRO aparelho
  pair_join     { pair, secret, drop?, dn? }          -> { ok, code, name }: o aparelho novo entra na conta (sem e-mail nem chave)
  devices       { code, secret }                      -> { ok, max, devices: [{ id, ou, br, md, dn, c, l, me }] }
  device_remove { code, secret, id }                  -> tira um aparelho da conta (nunca o último)
  device_name   { code, secret, dn }                  -> dá um apelido a ESTE aparelho

APARELHOS: a mesma conta abre em até 5 aparelhos (api/_lib/devices.js). Entrar com e-mail ou chave ADICIONA o aparelho;
com 5 já na conta, responde 422 { error: 'device_limit', max, devices } e o app pergunta qual tirar (repete com drop: id).

Precisa do Upstash Redis e das variáveis de e-mail (MAIL_API_KEY e MAIL_FROM). Sem e-mail configurado: 503 mail_unavailable.
Custo: ~6 comandos por pedido de código, ~8 ao confirmar; só quando a pessoa usa o recurso.
```

| Ação / tipo | Descrição (comentário do código) |
|---|---|
| `notice` | — |
| `devices` | Teto de pedidos por origem (barato: 1 comando). A consulta de aparelhos já é do dono (segredo) e tem o teto por perfil: não gasta o teto da origem (a tela de adicionar consulta a cada 10 s). |
| `status` | status |
| `device_remove` | — |
| `device_name` | — |
| `pair_new` | ligar outro aparelho com um código de 10 minutos (sem e-mail e sem chave) O aparelho que já está na conta gera o código (pair_new) e o aparelho novo o digita (pair_join). Uso único, 5 tentativas, 10 minutos, só o hash fica guardado. |
| `pair_join` | — |
| `rk_new` | chave de recuperação de 25 caracteres (não depende de e-mail) |
| `rk_login` | — |
| `unbind` | desligar o e-mail |
| `bind_start` | ligar o e-mail ao perfil |
| `bind_verify` | — |
| `login_start` | entrar com e-mail em outro aparelho |
| `login_verify` | — |

## `/api/admin`

```text
/api/admin: painel do administrador (indicadores e gestão de perfis anônimos).

 POST { action, ... } com "Authorization: Bearer <chave de admin>". Ações:
  kpis                       indicadores (total, ativos x inativos, professores, crescimento, retenção)
  list {offset?, q?, by?}    perfis, do mais recente ao mais antigo (busca por trecho do código; by:'name' busca pelo apelido nos 100 mais recentes)
  detail {code}              um perfil: papel, vínculos, volume de dados, tempo de uso (14 dias) e ficha do aparelho (NUNCA o segredo)
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
 costs                      comandos do Redis no mês (estimativa) e o que foi medido nos últimos 30 dias (measured)
 cost_report {users,fx,basis,commercial,m}  quanto custa manter a plataforma hoje e para N usuários (conta pura, 0 comandos no Redis)
 funnel                     ativação: quantos perfis fizeram cada coisa pela primeira vez (vincular, marcar aula, enviar tarefa…)
 agenda_pair {code, other}  compara a agenda do professor (code) com a que o aluno (other) recebeu: o que falta ou sobra
 Recursos liberados aos poucos (docs/PLANO_AULA_ONLINE_AGENDA_ADMIN.md, seção 6):
  features                   um cartão por recurso: estado, % e quem está na lista
  feature_set {id, mode, pct?}        off | list | pct | all
  feature_grant {id, code, students?} libera um código (e, se students, os alunos vinculados a ele)
  feature_revoke {id, code, students?} tira da lista
 Boletim do app ("Novidades"; ver api/_lib/news.js):
  news_list                  todas as publicações (rascunho, publicadas, ocultas) e as sugestões prontas ainda não usadas (1 comando)
  news_save {id?, t, b, te?, be?, k?}  cria um rascunho (sem id) ou altera o texto (com id)
  news_state {id, st}        draft | live (publica) | off (oculta; continua no histórico)
  news_delete {id}           exclui de vez
Pesquisas do app (ver api/_lib/surveys.js):
  survey                     participações (uma por envio, com tudo o que a pessoa respondeu) + as pesquisas e o estado de cada uma
  sv_save {id?, t, te?, qs, from?, to?, k?}  cria um rascunho (sem id) ou altera (com id)
  sv_state {id, st}          draft | live (libera; com from/to agenda) | off (encerra; continua no histórico)
  sv_delete {id}             exclui de vez
 Conversas com os usuários (aparecem em Avisos no app; ver api/_lib/inbox.js):
  inbox_list                 caixa de entrada: uma linha por usuário (quem respondeu primeiro), com apelido (1 comando + 1 por página)
  rq_list                    pedidos de suporte (relatos de problema enviados pelos usuários)
  rq_open {code, x}          abre conversa a partir do pedido: você escreve primeiro e o pedido sai da fila
  rq_close {code}            fecha o pedido sem conversa
  inbox_thread {code}        a conversa de um perfil (zera as "não lidas")
  inbox_send {code, x, ref?, ask?}  escreve para o usuário (ref = trecho da sugestão respondida; ask = pede licença para citar o apelido)
  inbox_resolve {code, done} marca como resolvida (ou reabre)
  inbox_delete {code}        apaga a conversa
 Dedilhado do violino (Flesch), editado à mão (docs/07_PAINEL_ADMIN.md):
  fing_list                  o que vem no app (seed) e o que foi corrigido/incluído aqui (1 comando no Redis)
  fing_rows {pc,alt,type,oct} as notas da escala (nome, 8va, corda solta) e o que está salvo para ela (0 ou 1 comando)
  fing_suggest {pc,alt,type,oct} sugestão pelo molde das páginas já lidas (para conferir com o livro; não salva nada)
  fing_save {pc,alt,type,oct,marks,ottava}  salva (vale no lugar da tabela do app); devolve avisos, sem impedir
  fing_delete {pc,alt,type,oct}  apaga a correção daqui (volta ao que vem no app, se houver)

Não há cadastro nem login no app: "usuário" = perfil anônimo (código + apelido). O apelido pertence
ao usuário (volta a cada sincronização), por isso o painel não o edita.
Custo: só quando o admin abre o painel (kpis ~35 comandos; lista de 25 = ~27; detalhe = ~12).
```

| Ação / tipo | Descrição (comentário do código) |
|---|---|
| `whoami` | — |
| `kpis` | Indicadores |
| `list` | Lista |
| `detail` | Detalhe |
| `block` | Bloquear / liberar |
| `delete` | Excluir |
| `indicators` | Indicadores de saúde do uso Custo: 3 comandos + 7 leituras (um hash por dia). Só quando o admin abre ou toca em Atualizar. |
| `library` | Acervo e Repertório (professores de teste) |
| `library_hide` | — |
| `visitors` | Visitantes (quem usa sem cadastro): divulgação e engajamento Custo: ~35 comandos por abertura da aba (7 dias de contadores + abas de hoje + 4 contagens). |
| `cost_report` | Limpa agora os perfis abandonados (sem vínculo, sem dados e parados há 60 dias). Até 30 por toque. Quanto custa manter a plataforma (conta pura: não consulta o Redis) |
| `funnel` | Funil de ativação (primeira vez de cada perfil) |
| `agenda_pair` | Suporte: compara a agenda do professor com a que o aluno recebeu |
| `features` | Recursos liberados aos poucos |
| `feature_set` | — |
| `feature_grant` | — |
| `group_list` | Grupos de recursos e diagnóstico |
| `group_save` | — |
| `group_delete` | — |
| `group_member` | — |
| `feature_groups` | — |
| `feature_why` | — |
| `news_list` | Boletim do app (Publicações) |
| `news_save` | — |
| `inbox_list` | Conversas com os usuários |
| `rq_list` | — |
| `rq_close` | — |
| `rq_open` | — |
| `inbox_thread` | — |
| `inbox_send` | — |
| `inbox_resolve` | — |
| `inbox_delete` | — |
| `news_state` | — |
| `news_delete` | — |
| `fing_list` | — |
| `fing_rows` | — |
| `fing_suggest` | — |
| `fing_save` | — |
| `fing_delete` | — |
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
| `survey` | Bugs (relatórios de erro do app) Respostas da pesquisa rápida e notas do app, uma por linha: quando, de quem (perfil), qual aparelho, o que respondeu. As antigas só têm o aparelho embaralhado; o app manda a identificação do perfil na próxima abertura e aí elas ganham dono. |
| `sv_save` | — |
| `sv_state` | — |
| `sv_delete` | — |
| `bugs` | — |
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
| `survey` | — |
| `identify` | — |

## `/api/fingering`

```text
GET /api/fingering: dedilhados do violino que o administrador corrigiu ou incluiu (ver _lib/fingering.js).
Público e sem dado pessoal. O app busca uma vez por abertura; a CDN guarda a resposta por 5 minutos, então o Redis
quase não é tocado (no máximo 1 comando a cada 5 minutos por região). O que vem daqui vale no lugar da tabela do app.
```

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
  msg_get / msg_put / msg_ok -> conversa particular com o administrador: ler, responder curto, aceitar ou recusar ser citado no boletim
  dones    -> PROFESSOR busca o que os alunos marcaram como feito (e a revisão dr no sync)

Precisa do Upstash Redis. Sem ele devolve 503 e o app segue só neste aparelho.
```

| Ação / tipo | Descrição (comentário do código) |
|---|---|
| `lesson` | Só 'lesson' pode ser grande; os demais pedidos têm ~200 bytes. |
| `claim` | Liberação pelo suporte: o aparelho novo prova que tem o código de uso único gerado no painel e passa a ser o dono do perfil (o segredo antigo deixa de valer). Só a tentativa errada conta. |
| `sync` | — |
| `cloud_set` | cópia na nuvem com 1 aparelho (chave copia_nuvem + aceite da pessoa) cloud_set { on: true\|false } -> liga (aceite) ou desliga; desligar apaga a cópia do servidor se a conta tem 1 aparelho só. |
| `mi_list` | mi_get { secs: [...] }  -> { mitems: { seção: { u, d } } } mi_put { sec, u, d }    -> grava a seção (versão mais antiga que a guardada é ignorada) mi_del { sec, u }       -> marca a seção como apagada |
| `mi_put` | — |
| `mi_get` | — |
| `photo_put` | foto do perfil (só aparece para quem está vinculado e só se a pessoa escolheu mostrar) photo_put { photo }  -> guarda (ou, vazia, apaga) a foto e avisa quem está vinculado (a versão "pv" vai em cada vínculo) photo_get { other }  -> a foto de quem está vinculado a você (nunca a de um desconhecido) |
| `photo_get` | — |
| `rev` | Consulta barata: o perfil já foi lido na autenticação, então não custa nenhum comando a mais. lr = aulas novas, dr = tarefas marcadas pelos alunos, kr = vínculos mudaram. |
| `rq_put` | msg_put { x }   -> resposta curta (só depois de o administrador escrever; limites por hora e por sequência) msg_ok { yes }  -> aceita ou recusa ser citado pelo apelido no boletim rq_put { x, v?, p? } -> relato de problema para o administrador (não abre conversa; ele decide abrir ou fechar) |
| `msg_get` | — |
| `msg_put` | — |
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
| `meet_set` | Link padrão da aula online do professor (vale para os horários livres sem link) |
| `sched_put` | Agenda: o PROFESSOR marca, muda ou cancela uma aula (e agenda o lembrete) |
| `done` | O ALUNO marca (ou desmarca) como feita uma tarefa que recebeu de um professor vinculado. |
| `verdict` | O PROFESSOR decide sobre uma tarefa de um aluno vinculado: 'ok' valida, 'back' devolve, vazio apaga a decisão. O aluno vê isso como o status oficial. |
| `link` | — |
| `unlink` | — |

## `/api/news`

```text
GET /api/news: o boletim publicado (ver _lib/news.js). Público e sem dado pessoal.
O app busca uma vez por abertura; a CDN guarda a resposta por 5 minutos, então o Redis quase não é tocado
(no máximo 1 comando a cada 5 minutos por região). Ocultar ou excluir no painel chega aos aparelhos em até ~5 minutos.
```

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

 POST (o app, sem chave): { t: 'open'|'beat'|'ev', id, d?: { pl, in, v, o?, x?: { os, sc, lg, th, tc, mic, nt } }, tabs?: [...] }
       'ev' = evento de ativação ("primeira vez"): { t: 'ev', id, e: 'tuned'|..., o?: origem }
       id = código aleatório do aparelho (NÃO é o código de professor/aluno). Nada de IP,
       nome, áudio ou o que a pessoa toca é guardado.
 GET  (só o admin, com "Authorization: Bearer <chave>"): ?part=live (online agora) ou ?part=full.

Custo no Redis por aparelho por dia: ~10 comandos ao abrir (4 quando já abriu hoje) e 1 por
batida (a cada ~5 min, só com o app à frente). Nenhum comando lê listas grandes.
```

| Ação / tipo | Descrição (comentário do código) |
|---|---|
| `ev` | — |
| `beat` | — |

