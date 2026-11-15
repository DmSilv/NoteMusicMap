# API e dados

> Lista completa de endpoints e ações: [referencia/API.md](referencia/API.md). Chaves do Redis e do armazenamento local: [referencia/DADOS.md](referencia/DADOS.md). Variáveis de ambiente: [referencia/AMBIENTE.md](referencia/AMBIENTE.md). Todas **geradas do código**. Aqui está o **funcionamento**.

## Visão geral
| Função | Para quê | Quem chama | Autenticação |
|---|---|---|---|
| `/api/link` | Vínculo, aulas, tarefas, decisões, agenda, horários livres, notificações | App | Código + segredo do perfil |
| `/api/account` | E-mail da conta, **sem senha**: ligar um e-mail ao perfil e entrar com ele em outro aparelho | App | Código + segredo do perfil (ligar) / só o e-mail + código de 6 dígitos (entrar) |
| `/api/stats` | Estatísticas anônimas (POST do app) e leitura (GET do painel) | App / painel | Aparelho anônimo / chave de admin |
| `/api/errors` | Relatórios de erro do app | App | Nenhuma (anônimo, com limites) |
| `/api/admin` | Painel: indicadores, perfis, bugs, saúde, custos | Painel | Chave de admin (cabeçalho) |
| `/api/remind` | Dispara o lembrete de aula (Web Push) | QStash | Assinatura do QStash |
| `/api/coach`, `/api/ai-status` | Análise por IA com fila | App | Cabeçalho do aparelho + limites |
| `/api/fingering` | Dedilhados do violino corrigidos/incluídos no painel (GET; o app busca 1 vez por abertura; CDN guarda 5 min) | App | Nenhuma (dado público, sem pessoa) |
| `/api/feedback` | Nota do app e pesquisas | App / admin | Aparelho / chave de feedback |

## Autenticação anônima (`/api/link`)
Todo pedido leva `{ code, secret, action, ... }`:
1. `code` precisa ser um texto válido (`XXXX-XXXX`, dígito verificador) e `secret` 64 caracteres hexadecimais.
2. O servidor compara o **hash** do segredo (`sha256("lnk|" + secret)`) com `u:<code>.h`. Se o perfil não existe, o primeiro pedido o cria (limite de perfis novos por origem/dia).
3. Segredo errado → 403 genérico; muitas tentativas → 429.
4. Perfil bloqueado → 403 `blocked`.
5. A cada pedido autenticado o servidor registra atividade (no máximo 1 gravação a cada 6 h por perfil) e **presença** (`pf:on` e campo `pa`, no máximo 1 gravação de 2 comandos a cada 10 min por perfil) para o painel. A conferência usa o perfil que já foi lido, então não custa leitura.

6. **Liberação pelo suporte** (`action: "claim"`, antes da conferência do dono): o aparelho novo manda o código do perfil, um segredo **novo** e o código de suporte de uso único gerado no painel. O servidor guarda só o hash do código (`u:<code>.sc`) e o prazo (`.sx`, 24 h); se conferem, troca o hash do segredo (`.h`) e apaga o código. Só a tentativa errada conta (por origem e por perfil, 10/h por perfil); o aparelho antigo passa a receber 403.

7. **E-mail da conta** (`/api/account`, sem senha): `bind_start` manda um código de 6 dígitos ao e-mail e `bind_verify` o confere e liga o e-mail ao perfil; `login_start`/`login_verify`, num aparelho novo, fazem a mesma prova e então o aparelho novo manda um segredo **novo** que passa a valer (`u:<code>.h`; o aparelho antigo recebe 403, como na liberação pelo suporte), e o e-mail recebe um aviso de "novo acesso". O servidor guarda só o **hash do e-mail** (HMAC com `MAIL_PEPPER`) em `acct:em` (hash do e-mail → código do perfil) e, no perfil, `eh` (esse hash) e `em` (versão mascarada para mostrar: `a***@gmail.com`). O código de 6 dígitos vale 10 min, aceita 5 tentativas, é de uso único e só existe como hash (`acct:otp:<hash do e-mail>`). `login_start` responde igual com ou sem conta (não revela quem tem conta). Limites: 40 pedidos/h por origem, 20 tentativas erradas/h por origem, 5 códigos/h por perfil e por e-mail, 10 pedidos de entrada/h por origem. Perfil com `eh` nunca é apagado pela limpeza de abandonados. Sem `MAIL_API_KEY`/`MAIL_FROM` o recurso fica desligado (`status` devolve `enabled: false`) e o app esconde as telas.

8. **Chave de recuperação de 25 caracteres** (`/api/account`, `rk_new` e `rk_login`, **não depende do e-mail**): `rk_new` (dono do perfil) gera uma chave aleatória `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` (25 símbolos de um alfabeto de 32, 125 bits) e o servidor guarda só o hash: `acct:rk` (hash da chave → código do perfil) e, no perfil, `rk` (esse hash); gerar outra cancela a anterior (5 por hora por perfil). `rk_login` (sem autenticação; manda a chave e um segredo novo) confere o hash e troca o hash do segredo do perfil (`u:<code>.h`): o aparelho novo vira o dono e o antigo recebe 403, como no e-mail e no código de suporte. Tentativas erradas contam por origem (20/h). Perfil com `rk` nunca é apagado pela limpeza de abandonados. `status` devolve também `hasKey`. O painel mostra, na ficha do perfil (`recovery` em `profile_detail`), se a pessoa tem e-mail ligado e/ou chave de 25.

O corpo é limitado (`MAX_BODY` 2 KB; aula 40 KB). Ações de leitura contam em "consultas/h"; ações que mudam dados contam em "alterações/h".

## Contadores de novidade (o truque que mantém o custo baixo)
O perfil `u:<code>` guarda carimbos de tempo que mudam quando há novidade:

| Campo | Significa | Muda quando |
|---|---|---|
| `lr` | aulas novas (aluno) | professor publica aula |
| `dr` | tarefas marcadas (professor) | aluno marca "fiz" |
| `kr` | vínculos | link/unlink |
| `sr` | agenda (aluno) | professor marca/muda aula; aluno pega horário |
| `vr` | decisões (aluno) | professor valida/devolve |
| `ar` | horários pegos (professor) | aluno pega horário |
| `sn` | aviso do suporte `{ t, k, x }` (vínculo encerrado, item de agenda apagado) | admin age sobre o perfil; vai junto de `sync` e `rev`, sem comando extra; app antigo ignora |

O app pergunta `rev` (devolve os contadores **sem comando extra**, porque o perfil já foi lido na autenticação) a cada ~30 s com o app à frente (esticando até 4× sem novidade; fora de foco não consulta). **Só se um contador mudou** ele baixa a lista (`lessons`, `dones`, `sched`, `verdicts`, `picks`). Disso vem a regra de custo: **não adicionar polling de lista**.

## Convenções ao criar uma ação
- **Aditiva**: ação nova ou campo novo; nunca mudar o formato do que já existe (app antigo precisa continuar funcionando; há teste de compatibilidade).
- **Validar tudo**: ids por regex (`[a-z0-9]{2,40}`), tamanhos, tipos (`normCode` só aceita texto).
- **Limpar texto** (`clean`, `cleanSlot`, `cleanLesson`).
- **Versão**: `u` (updatedMs) nas aulas marcadas — pedido atrasado não desfaz o mais novo.
- **Atômico quando disputado**: `HSETNX` (ex.: pegar horário).
- **Medir custo** e anotar em [CUSTOS_E_REGRESSAO.md](CUSTOS_E_REGRESSAO.md).
- **Erros**: o `catch` do handler chama `serverError(...)` para o erro aparecer no painel de bugs.

## Redis: grupos de chaves
Formato e descrição de cada uma em [referencia/DADOS.md](referencia/DADOS.md). Por família:
- `u:`, `ut:`, `us:`, `ul:`, `sl:`, `ss:`, `ps:`, `av:`, `tk:`, `vd:`, `dn:` — vínculo, aulas, agenda, horários, decisões, notificações.
- `pf:bl` — conjunto dos perfis bloqueados pelo painel (contagem sem varrer).
- `pf:*` — índice de perfis (entrou em, última atividade, papéis) para o painel. `pf:on` guarda o último sinal de vida de cada perfil (online = nos últimos 12 min; quem some há 2 dias sai).
- `st:*` — estatísticas anônimas (HyperLogLog de aparelhos, contadores por dia e por hora).
- `er:*` — relatórios de erro agrupados.
- `adm:log` — últimas ações do administrador.
- chaves de limite (`lnkpull:`, `lnkmut:`, `lnkbad:`, `lnknew:`, `er:rl:`, `er:cap:`) expiram sozinhas.

Tudo é **anônimo**; o código de perfil é a única identificação.

## Recursos por chave e aula online
- A sincronização (`sync`) devolve `ff` (lista de recursos ligados para o perfil) e, com a aula online ligada, `ml` (link padrão do professor). Apps antigos ignoram os dois. `lb`/`lbT` continuam existindo para o acervo.
- Campos novos do horário (aula marcada e horário livre): `m` (`p`|`o`) e `l` (link, só com `m=o`). Nova ação `meet_set {link}` guarda ou limpa (`""`) o link padrão (campo `ml` do perfil); exige o recurso ligado (`403 feature_off`) e recusa link inválido (`400 link_invalid`).
- Campo novo do horário: `r` (minutos antes do aviso: 0, 5, 10, 15, 30, 60, 120 ou 1440; sem `r` = 15), só com o recurso `lembrete_escolha` ligado para o professor; sem ele o servidor ignora e mantém o já guardado. O `r` vai junto da aula para o aluno e é copiado do horário livre para a aula pega.
- Redis: `ff:cfg` (estado de cada recurso), `ff:l:<recurso>` (códigos liberados) e o campo `ff` do perfil.

## Armazenamento local (aparelho)
`SharedPreferences` (no navegador: `localStorage` com prefixo `flutter.`). Lista completa em [referencia/DADOS.md](referencia/DADOS.md). Grupos: ajustes, perfil, alunos e tarefas do professor, sessões, estudo, agenda (`agenda`, `agenda_in`, `open_slots`), vínculo e filas (`done_outbox`, `verdict_outbox`), avisos (`notices`), erros (`error_log`, `report_mode`), estatísticas (`stats_*`), visão do hub (`hub_view`).

## IA (`/api/coach`)
Recebe só um **resumo de números** (nunca áudio) e o tipo de pedido; um roteador escolhe o serviço (Gemini, OpenAI, Claude, Groq, Mistral, OpenRouter — os que tiverem chave), com **fila justa**, limite diário por aparelho e cooldown. Se o serviço corta a resposta (limite de tokens), `finishText` remove a frase pela metade e avisa. Gemini recebe 3× o limite de tokens porque modelos que "pensam" gastam parte dele antes de escrever.

## Estatísticas e relatórios de erro
Ver [07_PAINEL_ADMIN.md](07_PAINEL_ADMIN.md) e [CUSTOS_E_REGRESSAO.md](CUSTOS_E_REGRESSAO.md) (custo por ação).
