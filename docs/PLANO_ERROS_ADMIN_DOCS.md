# Plano: erros no app, monitoramento de bugs no admin, admin melhor e documentação do projeto

Pedido do Daniel (10/11/2026). **Este documento é só o plano; nada foi alterado no app.** Cada pacote abaixo vai separado, com testes, conferência na tela e o "sim" do Daniel antes de publicar.

## O que o levantamento achou
- **O app não tem nenhum tratamento global de erro:** não há `FlutterError.onError`, `runZonedGuarded`, `PlatformDispatcher.onError` nem `ErrorWidget.builder`. Um erro inesperado deixa a tela cinza/vermelha ou parada, sem aviso e sem registro.
- **Erros de ação viram frases soltas** em `say('Não foi possível…')`, cada uma com um texto diferente e sem padrão (ícone, "tentar de novo", código).
- **O servidor só escreve no log da Vercel** (`console.error`): ninguém consegue filtrar, contar nem ver tendência.
- **O painel admin** mostra uso e perfis, mas não erros, não compara períodos e não explica cada número.
- **Documentação:** existe um README (139 linhas) e 5 documentos de planejamento; não há um guia do projeto inteiro (arquitetura, dados, API, regras, operação). São ~32 mil linhas de Dart e ~2,7 mil de API.
- **Limite da Vercel (plano Hobby): 12 funções.** Hoje são 7; um endpoint novo de erros usa a 8ª.

---

## Pacote 1 · Tela e avisos de erro no app
**Objetivo:** o usuário nunca fica diante de uma tela quebrada; sempre vê o que houve, o que fazer e um código para falar com o suporte.

1. **Núcleo testável (`afina_core/errors.dart`):** `AppError` (código, gravidade, mensagem amigável, ação sugerida), `classifyError(exceção)` e um **catálogo único** de códigos e textos em pt-BR (ex.: `NET-01 sem internet`, `NET-02 servidor fora`, `API-04 pedido recusado`, `DATA-01 dados inválidos`, `AUD-01 microfone`, `STO-01 armazenamento`, `APP-00 erro inesperado`).
2. **Captura global:** `FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded` e `ErrorWidget.builder` (um cartão amigável no lugar do widget quebrado, em vez da tela cinza).
3. **Três níveis de aviso, sempre no mesmo formato:**
   - **Crítico:** tela cheia "Algo deu errado" com código (ex.: `E-7K2F`), botões **Tentar de novo**, **Voltar ao início**, **Enviar relatório**.
   - **Falha de ação:** faixa/toast com ícone vermelho, uma frase e **Tentar de novo** (substitui os `say('Não foi possível…')` espalhados; auditar todos).
   - **Conexão:** o selo que já existe (offline/servidor fora), padronizado com o catálogo.
4. **Problemas recentes** (Ajustes › Diagnóstico): últimos 20 erros locais, com hora, código e **Copiar detalhes**.
5. **Testes:** classificação de erros, catálogo (todo código tem texto e ação), limite do histórico, nenhum dado pessoal nas mensagens.

## Pacote 2 · Coleta de bugs e filtro no admin (monitoramento com o máximo de detalhe)
**Coleta (app → servidor), anônima e sanitizada:**
| Campo | Exemplo | Observação |
|---|---|---|
| Impressão digital (fingerprint) | `a91c…` | hash de código + tela + trecho da pilha; agrupa o mesmo bug |
| Código e gravidade | `APP-00`, crítico | do catálogo |
| Mensagem e pilha | 8 primeiros quadros | números, códigos de perfil, nomes, e-mails e tokens são removidos |
| Onde | tela/rota e ação | ex.: `Agenda do professor › Marcar aula` |
| Trilha (breadcrumbs) | últimos 10 eventos | só nomes de telas e ações, **nunca conteúdo** |
| Ambiente | versão/build, plataforma, navegador, PWA/navegador/app, tema, tamanho de tela | |
| Estado | vínculo online (ok/offline/fora), visão (aluno/professor), em aula? | |
| Quem | código do aparelho **embaralhado** (o mesmo da estatística) | sem nome, IP, áudio ou perfil |

**Regras de custo e proteção:**
- O app envia o mesmo bug **no máximo 1 vez a cada 10 min**; limite no servidor por aparelho/hora; tamanho máximo do pacote; **chave de desligar** (`ERRORS_ENABLED`) para cortar tudo sem publicar.
- Custo estimado: ~7 comandos do Redis por evento novo e ~3 por repetição; com teto de eventos por dia, fica abaixo de 2% da cota mensal gratuita (será medido e documentado).
- **Erros do servidor também entram** (falhas 5xx, Redis fora, timeout da IA), com o mesmo formato.
- Endpoint novo `api/errors.js` (8ª função de 12). Nenhuma biblioteca nova.

**Admin → aba "Bugs":**
- **Lista agrupada por bug** com: gravidade, contagem, aparelhos afetados (distintos), primeira e última vez, versões afetadas, mini-gráfico dos últimos 14 dias.
- **Filtros:** período · gravidade · versão · plataforma/navegador · tela · código · status (novo, visto, resolvido, ignorado, reaberto) · busca por texto.
- **Detalhe:** pilha, trilha de eventos, ambiente, últimas 10 ocorrências, distribuição por versão/plataforma.
- **Ações:** marcar como resolvido, ignorar, reabrir, anotar. Se um bug "resolvido" aparecer numa versão **mais nova**, vira "reaberto" sozinho.
- **Sinais no topo do painel:** "novo bug crítico", "pico de erros nas últimas 2 h", "taxa de erro por sessão".
- **Testes de API:** sanitização, deduplicação, limites, filtros, mudança de status, reabertura, desligar pela chave, nada de dado pessoal salvo.

## Pacote 3 · Admin mais preciso e lúdico
**Precisão**
- Separar e **definir** cada número (aparelhos × perfis × ativos), com "?" explicando a conta e a margem (a contagem de aparelhos usa HyperLogLog, erro de ~1%).
- **Comparação com o período anterior** (▲ ▼ %) em todos os cartões; "dados de hoje são parciais"; horário da última atualização; fuso explícito.
- **Funil:** instalou → abriu → ligou o vínculo → 1ª aula → 1ª tarefa validada.
- **Retenção em grade** (D1, D7, D30 por semana de entrada) e **uso por hora e dia da semana** (mapa de calor).
- **Painel de custos:** comandos do Redis estimados no mês × cota de 500 mil, por tipo de ação, com barra de orçamento (ligado à regra de escalabilidade).
- **Saúde da API:** taxa de erro e respostas lentas por endpoint.

**Lúdico**
- Cabeçalho com **semáforo de saúde** (online agora, erros, API) e saudação do dia.
- Cartões com ícones, **contadores animados** e mini-gráficos; **medalhas e marcos** ("100 perfis", "7 dias sem bug crítico", "primeira aula pegada por aluno").
- Abas: **Visão geral · Uso · Professores e alunos · Bugs · Perfis · Custos**; funciona bem no celular e no computador, claro e escuro.
- Tudo em `textContent` (sem HTML injetado), como hoje.

## Pacote 4 · Documentação do projeto inteiro (feito por último, com tudo pronto)
Pasta `docs/` em pt-BR, Markdown, com **índice e mapa** no começo:
1. **LEIA_PRIMEIRO:** o que é o app, quem usa, glossário (vínculo, visão, horário livre…), como rodar, testar e publicar.
2. **Arquitetura:** camadas (app Flutter, `afina_core`, API serverless, Redis, QStash, Web Push, Vercel) com diagramas Mermaid.
3. **App e núcleo:** cada pasta e arquivo com sua responsabilidade; cada módulo do núcleo com suas regras e testes.
4. **API:** cada endpoint, ação, corpo, resposta, erros, limites e **custo em comandos do Redis**.
5. **Dados:** todas as chaves locais (`SharedPreferences`) e todas as chaves do Redis, com formato e quem escreve/lê.
6. **Regras de negócio:** vínculo, tarefas e status, agenda, horários livres, avisos, visões Aluno/Professor, erros.
7. **Segurança e privacidade:** guardrails, CSP, o que é coletado e o que nunca é.
8. **Operação:** variáveis de ambiente (sem valores), limite de 12 funções, deploy e **rollback**, monitoramento, custos.
9. **Testes:** como rodar, estratégia, matriz de botões, roteiro de regressão.
10. **Decisões (ADRs):** por que sem login, por que anônimo, por que "primeiro a pegar", por que o professor é a fonte do status etc.
11. **Guia de manutenção:** receitas passo a passo (adicionar ação na API, tela, regra no núcleo, código de erro), checklist de publicação e **armadilhas conhecidas** (ex.: testes ficam fora do deploy; cada arquivo de `api/` conta como função).
12. **Catálogo de erros** (gerado do código) e **histórico** (etapas e pacotes publicados).

**Para a documentação não envelhecer:** `scripts/check_docs.js` falha se existir arquivo de código sem menção na documentação, e gera partes automáticas (lista de endpoints, códigos de erro, chaves do Redis). Entra junto com os testes.

---

## Ordem, esforço e riscos
| # | Pacote | Tamanho | Depende de | Risco |
|---|---|---|---|---|
| 1 | Tela e avisos de erro | médio | — | baixo (só interface e núcleo) |
| 2 | Coleta + admin Bugs | grande | 1 | médio (dados novos no Redis; mitigado por limites e chave de desligar) |
| 3 | Admin preciso e lúdico | grande | 2 | baixo |
| 4 | Documentação | grande | 1–3 | baixo |

Cada pacote: testes (núcleo, API, `flutter analyze`), conferência no Chrome em celular e tela larga, custo medido, e **"sim, publicar" do Daniel**.

## Decisões que preciso do Daniel
1. **Envio de erros:** automático e anônimo (com chave de desligar em Ajustes) **ou** só quando o usuário toca em "Enviar relatório"? *Recomendo:* automático só para erros **críticos** e manual para os demais, com explicação clara em Ajustes.
2. **Alertas:** só no painel (selo de "novo bug crítico") **ou** também um aviso para você (push no seu aparelho, que o app já sabe enviar)? *Recomendo:* painel agora e push depois.
3. **Documentação:** em pt-BR, em Markdown dentro de `docs/` (versionada no Git), como descrito? *Recomendo* sim.

---
## Andamento
- **Pacote 1 (publicado em 10/11/2026):** `afina_core/errors.dart` (catálogo `kErrorCatalog`, `classifyError`, `sanitizeDetail`, `errorShortId`, `ErrorLog`) com 17 testes; captura global (`FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`, `ErrorWidget.builder` amigável em release); falha ao abrir mostra `CriticalErrorPage` (APP-99) com "Tentar de novo" e "Copiar detalhes"; avisos de erro no formato único (ícone + título + código `E-XXXX`, no máximo 1 a cada 8 s, repetição não avisa de novo); Ajustes › Diagnóstico › **Problemas recentes** (lista, detalhe, copiar relatório, limpar); três `say('Não foi possível…')` passaram a `fail(...)` (registrados). Em demo (`DEV_DEMO`) há botões de teste ("Simular erro", "Ver tela de erro crítico").
- **Escolha de projeto:** só a falha ao iniciar derruba para tela cheia; erros inesperados depois disso viram aviso + registro, para um erro pequeno nunca esconder o app inteiro.
- Próximo: **Pacote 2** (coleta e aba Bugs no admin; novo endpoint `api/errors.js`).
- **Pacote 2 (pronto, aguardando publicação):** `api/errors.js` (8ª função de 12) + `api/_lib/errors_lib.js` (higienização igual à do app, impressão digital, chaves `er:*`); admin: ações `bugs` (filtros: período, gravidade, status, versão, plataforma, código, texto), `bug` (detalhe) e `bug_status` (visto/resolvido/ignorado/novo + anotação); reabertura automática só por versão publicada depois da correção; app: `error_report.dart` (modo de envio, trilha de passos, freio, pacote), `ErrorReportService`, seletor "Enviar relatório de erro" em Ajustes › Diagnóstico (Só os graves / Todos / Nunca) e botão "Enviar relatório" no detalhe do problema; aba **Bugs** no painel com resumo, erros por hora, lista com mini-gráfico, detalhe e ações. Custo medido: ~23 comandos por relatório.
