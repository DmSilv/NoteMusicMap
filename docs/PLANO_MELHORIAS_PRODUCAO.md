# Plano de melhorias e preparação para produção (novembro/2026)

> **Só planejamento.** Nenhum código foi alterado para escrever este documento. Tudo abaixo vem da leitura do código atual, dos
> documentos do projeto e de medições feitas com os scripts do próprio repositório. Onde algo depende de regra externa (Google Play,
> bancos, lei) está marcado **"conferir"**: é conhecimento até meados de 2026 e precisa ser reconfirmado antes de decidir.

## 0. Resumo em uma página

| # | Tema | Minha posição | Prioridade | Esforço |
|---|---|---|---|---|
| 1 | Novidades × avisos, modais, animações | **Concordo com ajustes.** Hoje há 3 lugares para Novidades; ficar com 2 (ícone próprio + aviso destacado), tirar do sino. Animação sim, mas leve | Alta | M |
| 2 | Conversa desenvolvedor × usuário | **Já existe a base** (`inbox.js`, "Conversas" no painel). Falta status, etiquetas, histórico por usuário e resposta ligada à pesquisa | Alta | M |
| 3 | UI/UX, cores, textos | **Concordo, com um contraponto:** não suavizar o verde/azul/laranja da afinação (é a leitura rápida). Separar "cor da marca" de "cor de significado" e suavizar só o cromo | Média | M |
| 4 | Agendamento | **Auditar antes de mexer.** Há um risco real e conhecido: aula apagada pode "ressuscitar" entre aparelhos (espelho sem lápides) | Alta (auditoria) | M |
| 5 | Google Play | Viável, mas o aplicativo **ainda não está pronto**: o manifesto de release **não tem permissão de internet**, a assinatura é a de depuração e não há política de privacidade pública | Média, em paralelo | G |
| 6 | Reformular o painel | **Já feito em parte** (5 áreas + Guia). Falta separar Suporte de Administração e dar um "porquê" para cada liberação | Média | M |
| 7 | Chaves de recursos por grupo | **Já existe** por usuário, por % e para todos. Falta **grupo** e um **diagnóstico "por que este usuário vê isto?"** | Alta | M |
| 8 | Central de suporte | Concordo, **sobre a mesma conversa do item 2**, com o usuário podendo abrir pedido, respostas prontas e anexo de diagnóstico | Alta | M |
| 9 | Ficha do aluno | Concordo. O arquivo tem 1.910 linhas; **primeiro separar a ficha em arquivo próprio**, depois reorganizar em 3 blocos | Média | M |
| 10 | Revisão geral das telas | Concordo, **por inventário com nota**, não "tela a tela por intuição" | Média | G (contínuo) |
| 11 | **Acesso e recuperação da conta** (trocar de aparelho sem perder tudo) | **Concordo e é pré-requisito de produção.** E-mail obrigatório para **professor**; para **aluno**, só com responsável quando menor. **Não** enviar a chave por e-mail como regra | **Alta** | M a G |
| 12 | **Página pública de ajuda** (esqueci o e-mail, falar com o suporte, excluir conta) | Concordo; serve também de endereço de exclusão exigido pela Play | Alta | M |
| 13 | **Idade, LGPD e ECA Digital** | **Concordo e é urgente de decidir.** O app é de "provável acesso por menores"; decidir faixa etária, consentimento do responsável e revisão jurídica **antes** do teste fechado | **Alta** | G |
| 14 | **As 11 funções da Vercel** | **São necessárias hoje; sem sobrecarga.** Dá para chegar a 8 (juntar 3 leituras e `errors`) sem risco relevante. O que pesa é a **quantidade de chamadas** (`rev` = 62%), não de funções | Baixa agora | P a M |

**Ordem que recomendo** (detalhe na seção 5): Onda 0 (fundação, **e-mail da conta no ar** e verificação em aparelho real) → Onda 1 (central de novidades + conversa/suporte + **recuperação de conta e página de ajuda**) →
Onda 2 (chaves por grupo + painel Suporte/Administração) → Onda 3 (paleta, ficha do aluno, revisão de telas) → Onda 4 (agenda) → Onda 5
(Play Store). A preparação técnica da Play (Onda 5A) pode começar junto da Onda 2, porque quase tudo nela é independente da interface.

---

## 1. Estado real da aplicação (medido)

| Fato | Valor | Fonte |
|---|---|---|
| Código do app (Dart, `lib/`) | ~34 mil linhas; ~24,8 mil só em `lib/ui/` | `wc -l` |
| Maiores telas | `teacher_page.dart` 1.910 · `profile_page.dart` 993 · `welcome_tour.dart` 790 · `metronome_page.dart` 770 · `widgets.dart` 724 | `wc -l` |
| Funções da Vercel | **11 de 12** (Hobby) | `check_docs.js` |
| Testes automáticos | núcleo 895 · telas 96 · API: um arquivo `*.test.js` por assunto, todos passam | CI local |
| Painel do administrador | 14 telas em **5 áreas + Ajuda** (feito em 17/11) | `web/admin.html` |
| Chaves de recurso | 3 recursos (`acervo`, `aula_online`, `lembrete_escolha`); estados desligado / lista / % / todos; por código | `api/_lib/features.js` |
| Conversa admin ↔ usuário | existe: `cv:th`/`cv:ix`, admin escreve primeiro, usuário responde até 280 letras, limites por dia/hora | `api/_lib/inbox.js`, `lib/ui/dev_chat_sheet.dart` |
| Pesquisas | uma participação = um modal no painel, limite por aparelho, liberar/retirar | `api/_lib/surveys.js` |
| Boletim "Novidades" | rascunho/publicar/ocultar/excluir; aviso único por abertura; ícone com anel; lista em Avisos | `api/news.js`, `lib/ui/news_ui.dart` |
| Android | `applicationId br.app.afina`; versão `1.0.0+1`; **assinatura de depuração** (há um `TODO` no `build.gradle.kts`); permissões: microfone, câmera, tela acesa, vibração; **sem `INTERNET` no manifesto principal** (só nos de depuração e perfil) | `android/app/` |
| Política de privacidade pública | **não existe** como página (`web/` tem `sobre.html`, `curioso.html`, `index.html`) | `web/` |
| Lembretes de aula | só **Web Push** (`lib/platform/web_push_web.dart`); no Android nativo não há equivalente | `lib/platform/` |
| Custo medido por usuário ativo | 387 comandos do Redis, 136 chamadas de função, 16 MB de tráfego por mês | `scripts/simulate_load.js` |

Pontos fortes que o plano **protege**: núcleo em Dart puro testado, API retrocompatível, custo baixo por usuário, Design System com tokens
(`Ds`), tradução português/inglês com verificação automática, painel com registro de ações.

---

## 2. Análise crítica, item por item

Legenda de esforço: **P** (até 1 dia) · **M** (2 a 5 dias) · **G** (mais de uma semana ou contínuo).

### 2.1 Novidades e notificações

**Hoje.** A mesma novidade pode aparecer em **três lugares**: (a) aviso central que sobe sozinho (`showNewsDialog`), (b) ícone na barra
(`NewsBell`, que abre uma folha "Novidades") e (c) uma seção "Novidades" dentro da folha do sino (`NewsTiles` em
`notifications_sheet.dart`). O sino ainda mistura três coisas: **Novidades**, **Dicas** e **Avisos** de aula/tarefa.
O aviso que sobe é um `AlertDialog` fixo no centro. Os avisos de ação (`AppNotice`) são texto livre em `ListTile`, sem tela de detalhe.

**Problema e impacto.** Mistura de assuntos (o que é "preciso fazer algo" × "saiba que mudou") faz a pessoa ignorar tudo; texto longo
fica sem leitura completa nos avisos rápidos (toast); o modal central parece "janela de sistema", não parte do app.

**Concordo com:** separar; dar a cada novidade um espaço próprio; ler texto longo em tela cheia; animação ao remover.

**Contrapontos e ajustes.**
1. **Não criar um 4º lugar.** Recomendo exatamente dois: **sino = tudo que pede ação ou fala só com a pessoa** (aula, tarefa, horário, conversa com o
   desenvolvedor) e **ícone de novidades = central de novidades** (lista com data, título, resumo e "ler"). Tirar "Novidades" de dentro do sino.
   O aviso que sobe sozinho passa a ser **exceção**: só para publicação marcada como "destaque" no painel (hoje toda novidade nova sobe).
2. **Dicas** (cartões de "Informe seu nome", "Instale o app") **não são novidades nem avisos**: viram uma faixa discreta no início
   ("Comece por aqui" já existe) ou ficam no sino numa aba própria "Dicas". Decisão sua (seção 7).
3. **Tela cheia só quando o conteúdo pede.** Criar uma variante de `showDsSheet` com `fullScreen` (usando `DraggableScrollableSheet`,
   que já é parte do Flutter) e usar para: novidade com texto acima de ~280 letras, conversa com o desenvolvedor, relatório. Não transformar
   todo modal em tela cheia: perde o contexto e piora no tablet.
4. **Animações:** usar `Dismissible` + `AnimatedList`/`AnimatedSize` e o "Desfazer" que o app já tem (`undo_snack`). Sem biblioteca nova
   (Lottie, Rive): pesam no pacote web e atrapalham aparelhos fracos. Respeitar "reduzir movimento" (já respeitado em `NewsBell`, `BeatBar`, avisos).
5. **Texto longo em aviso:** regra única: o toast mostra **uma frase de até ~110 letras** (o `check_text.js` já limita) e, se a mensagem é
   maior, o toast ganha o botão "Ler tudo", que abre a folha. Não aumentar o tempo do toast.

**Solução recomendada.** (1) Separar dados: `AppNotice` (ação) × `NewsItem` (novidade) × `Tip` (dica), cada um com seu componente.
(2) Central de Novidades em tela própria (`NewsPage`) com cartão por item e estado lido/não lido por item (já há `news_seen`).
(3) `showDsSheet(fullScreen: true)`. (4) Reescrever o aviso de destaque como folha que sobe de baixo, com imagem opcional.
(5) No painel: campo "destaque" e "ilustração" (emoji ou ícone da lista do app, nunca arquivo enviado: custo e privacidade).

**Dependências:** nenhuma técnica. Casa bem com o item 2 (conversa vira um tipo de item do sino).
**Riscos:** regressão nos avisos de aula/tarefa (críticos para o professor); mexer em `AppNotice` toca sincronização.
Mitigar: não alterar o formato de dados, só a apresentação, e testar `notifications_sheet` com os 5 tipos.
**Testes:** teste de tela para cada tipo; teste de "texto longo abre a folha"; conferir inglês; conferir 390×844 e tablet.
**Esforço:** M.

### 2.2 Comunicação entre desenvolvedor e usuário

**Hoje.** A base **já existe**: o desenvolvedor abre a conversa no painel (aba Conversas), o usuário recebe em Avisos e responde curto; há pedido de
licença para citar o apelido no boletim; limites (10 mensagens do admin por dia por perfil, 6 respostas do usuário por hora, 30 mensagens por conversa).
As respostas da pesquisa têm um modal por participação.

**Lacunas.** Não há: estado da conversa além de aberta/resolvida; etiquetas; busca; ver **todo o histórico de um usuário** (pesquisas
+ conversa + erros) numa tela só; resposta pronta; ponte "responder esta sugestão" a partir do modal da pesquisa (existe em parte via `ref`).

**Contraponto importante.** O usuário **não inicia** conversa (decisão de `inbox.js`, para evitar abuso). Para o suporte (item 8) isso muda:
é preciso um caminho do usuário até você. Proponho **dois tipos de conversa** no mesmo armazenamento: `dev` (você escreve primeiro, como hoje) e
`suporte` (o usuário abre pedido, com limite de 3 por dia e texto até 600 letras).

**Solução.** (1) Linha do tempo por usuário no painel (Pessoas › ficha): conversa, pesquisas, erros do código, aparelhos, recursos ligados.
(2) Estados: nova · em andamento · aguardando usuário · resolvida, com a hora da última mudança. (3) Etiquetas livres limitadas (sugestão, bug, dúvida, elogio).
(4) Botão "Responder" dentro do modal da pesquisa abre a conversa já com o trecho citado.
**Custo (Redis):** a caixa de entrada é lida pelo painel só ao abrir (1 `HGETALL` de até 800 resumos). Etiqueta e estado entram no resumo `cv:ix`
que já existe: 0 comando novo para o usuário. **Riscos:** privacidade (só o dono lê a própria conversa, mantido); crescimento do hash (teto de 800 já existe).
**Testes:** `api/inbox.test.js` (já existe) ganha casos de estado, etiqueta, limite do pedido do usuário e leitura cruzada (um usuário não lê o outro);
teste de tela para a folha de conversa; teste de carga: 800 conversas no painel.
**Esforço:** M.

### 2.3 Interface, cores e textos

**Botão de validação desalinhado na tela de alunos.** Não consegui reproduzir só pela leitura do código; a lista usa `AppCard` com
`padding: fromLTRB(14, 12, 6, 12)` (6 à direita por causa do menu de três pontos) e uma faixa de números no topo (`_summaryStrip`) com chips de alturas diferentes.
Plano: **reproduzir com o semeador de testes** (`seed_v`), tirar captura em 390×844 e 360×640, medir; suspeitos: chip clicável vs. chip fixo na `_summaryStrip`,
e a etiqueta "N para validar" dentro do `Wrap`. Esforço P, **depois** de reproduzir.

**Cores.** Dados medidos:
- `AppColors.accent` **é igual** a `AppColors.inTune` (verde `#1FE68F` no escuro). Usado 207 vezes como cor da marca/botões e 47 como "afinado".
  A mesma cor diz "este é o botão principal" **e** "esta nota está afinada".
- 146 usos de `withValues(alpha: …)`: muitos cartões usam **verde com transparência sobre fundo escuro**, que fica verde-sobre-verde (o ponto
  de leitura difícil que você descreveu).
- 26 cores fixas (`Color(0x…)`) fora de `theme.dart`, o que quebra a regra do Design System.
- Há um segundo verde (`inTuneBright`) usado só em 2 lugares.

**Contraponto.** Não suavizar tudo. Na afinação, **verde = afinado, azul = baixo, laranja = alto** é leitura de relance; suavizar isso piora o
instrumento. A proposta é **separar duas famílias**:
1. **Marca/ação (`primary`)**: um verde-água mais calmo e menos saturado, para botões, abas, seleção e ícones. Pode ser mais suave.
2. **Significado (`inTune`/`flat`/`sharp`)**: continuam vivos, só aparecem na afinação, nas notas, nos resultados e nos alertas.
3. **Superfícies:** cartões em tom neutro; destaque por **borda fina** e ícone, não por fundo verde translúcido.

**Passos:** (a) auditoria de contraste automática (razão ≥ 4,5:1 texto, ≥ 3:1 componentes) de todos os pares texto/fundo do tema claro e escuro, em script;
(b) criar o token `primary` (valor inicial igual ao atual, para não mudar nada); (c) migrar usos em lotes por tela, com captura antes/depois; (d) trocar o valor
do `primary` e das superfícies; (e) eliminar as 26 cores fixas. **Riscos:** muita superfície de mudança (207 usos) → fazer por lotes pequenos e com testes de tema
(`theme_light_test` já existe). **Esforço:** M.

**Textos e visual.** O `check_text.js` limita a **19** textos longos; a meta deve ser reduzir esse teto aos poucos (19 → 15 → 12), não criar regra nova.
Para "mais visual e lúdico": preferir **ícone + palavra curta + exemplo** em vez de parágrafo; usar os componentes que já existem (`DsIconBadge`, `DsNavRow`,
`DsCardTitle`). Sem ilustrações novas pesadas (custo de pacote web).

### 2.4 Agendamento (professor e aluno)

**Mapa do que existe.** Professor: `agenda_page`, `slot_form_page`, `open_slots_page`, `agenda_sheets`, `agenda_calendar`, `agenda_actions`.
Aluno: `my_agenda` (dentro de `hub_section`/`agenda_page`), "Pegar horário", `my_lessons_page`. Núcleo: `agenda.dart`, `open_slots.dart`, `class_rules.dart`,
`absence.dart`, `lesson_week.dart`. Servidor: `sched`, `sched_put`, `avail_put`, `avail_take`, `picks`, `lesson(s)` em `api/link.js`; lembretes em `api/remind.js`.

**Lacunas já registradas** em `PLANO_AULA_ONLINE_AGENDA_ADMIN.md` §2 (remarcar só uma aula, trocar horários entre alunos, trocar o aluno, pausa/férias, pedido
do aluno) e em `PLANO_PROXIMOS_PASSOS.md` (pedido de troca, falta/reposição, visão semanal em grade). **Eu não consegui confirmar, só pelo código, quais já foram
entregues**: a auditoria abaixo começa por isso.

**Conflitos e riscos que encontrei na leitura.**
1. **Espelho entre aparelhos sem lápides** (`AG`/`OS` em `mirror.dart`): se o professor apaga uma aula no aparelho A enquanto o B tem outra mudança na agenda, a junção
   pode **trazer a aula de volta**. Está registrado como "limite conhecido" em `11_HISTORICO.md`. Com agenda isso é grave (aluno recebe aula cancelada).
2. **Duas noções de "aula"**: a agenda (`sched`, horário marcado) e o diário (`lesson`, o que aconteceu); a ligação entre elas depende de regras em `class_rules`.
   Sem uma tabela de estados única, "falta", "reposição" e "remarcada" ficam espalhadas.
3. **Lembretes só na web** (Web Push). No Android nativo (item 5) não há lembrete: a agenda perde metade do valor se o app for nativo.
4. A suspeita já anotada: editar a hora de uma regra semanal com datas canceladas pode "ressuscitar" aulas (confirmar com teste).

**Solução em duas etapas.**
- **Etapa A: auditoria (não mexe no app).** Matriz de cenários *professor × aluno × aparelho × conexão*: marcar única, marcar semanal, remarcar uma, cancelar uma,
  cancelar todas, pausa, pegar horário (dois alunos ao mesmo tempo), trocar horários, duas pessoas no mesmo horário, dois aparelhos do mesmo professor, offline e volta.
  Cada cenário ganha um teste (há `agenda.test.js`, `agenda_control.test.js`, `avail.test.js` e o `smoke.js` como base).
- **Etapa B: correções por ordem de dano:** lápides no espelho da agenda → tabela de estados da aula → a lacuna de "remarcar só esta aula" → pedido de troca do aluno →
  visão semanal. Cada uma atrás de chave de recurso (seção 2.7).
**Esforço:** auditoria M; correções G (várias entregas).

### 2.5 Google Play Store

Desenvolvido na seção **3**, por ser o maior item.

### 2.6 Reformulação da área administrativa

**Hoje (já entregue em 17/11):** 5 áreas (Início, Quem usa, Pessoas, Publicar, Saúde e custos) + Ajuda com guia e dúvidas; cada tela tem frase de apoio e
dica; `docs/07_PAINEL_ADMIN.md` tem o mapa.

**O que ainda falta de verdade:**
1. **Separar Suporte de Administração.** Hoje "Pessoas" mistura achar usuário, conversar, liberar recurso e excluir perfil. Proponho **duas portas** no painel:
   **Suporte** (achar usuário, ficha completa do usuário, conversa, erros dele, aparelhos, recursos que ele vê e por quê, ações reversíveis) e
   **Administração** (publicações, recursos globais, custos, sistema, **ações destrutivas** como excluir perfil).
2. **Contraponto:** separar em *papéis com senhas diferentes* só faz sentido quando houver **uma segunda pessoa** atendendo. Hoje há uma só chave (`ADMIN_KEY`).
   Recomendo separar **na tela** agora (organização) e deixar a **chave de suporte limitada** (uma segunda chave que só abre Suporte) como passo opcional, sem custo de refatoração grande.
3. Registro de ações já existe (`LOG`); acrescentar "quem fez" quando houver duas chaves.
**Riscos:** o painel é um arquivo de ~3.000 linhas (`web/admin.html`); qualquer reorganização maior pede **dividir em módulos** antes (ver seção 5, Onda 2).
**Testes:** `admin_design.test.js` (já valida abas, ícones, dicas, frases de apoio) + novo teste "toda ação destrutiva fica só em Administração".
**Esforço:** M.

### 2.7 Controle de funcionalidades e permissões

**Hoje.** `features.js`: estados **off / list / pct / all**, por **código de perfil**; a decisão é do servidor e chega ao app em `ff` sem comando extra; recurso novo = uma linha.
Ligar para um professor pode ligar para os alunos dele (até 200).

**O que falta para o que você pediu:**
- **Para todos / um usuário:** já existe (all e list).
- **Para grupos:** não existe. Proposta: **grupos nomeados** no painel (ex.: "Testadores", "Professores de violino", "Turma do Vinícius") guardados como conjuntos
  (`ff:g:<id>`), e um recurso passa a aceitar `grupos: [...]`. Grupos automáticos úteis sem cadastro: *professores*, *alunos*, *quem tem o app instalado*, *versão do app ≥ X*.
- **Diagnóstico "por que este usuário vê isto?"**: ao abrir a ficha de um usuário, listar cada recurso com **ligado/desligado e o motivo** (chave geral, lista pessoal,
  grupo "X", faixa de %, aluno do professor Y, versão antiga). É o que mais ajuda no suporte (item 8).
- **Regra de precedência clara:** `desligar geral` > `desligado para este usuário` > `ligado para este usuário` > `grupo` > `porcentagem` > `geral`.
**Custo:** a lista de grupos do usuário vai num campo do perfil (`gp`), como `ff`: 0 comando novo na sincronização. **Riscos:** cache de 60 s do estado geral (aceitável,
já documentado); grupos grandes (limitar a 500 por grupo e 20 grupos). **Testes:** `features` ganha tabela de precedência (uma linha por combinação); teste de que app antigo ignora grupos.
**Esforço:** M.

### 2.8 Central de suporte ao usuário

**Concordo, mas sem criar um sistema novo.** Reaproveitar a conversa (2.2) com o tipo `suporte`:
1. **No app:** em Ajustes › "Falar com o suporte" (e em cada aviso de erro: botão "Enviar para o suporte" com o código do erro).
2. **Anexo de diagnóstico, só com consentimento:** versão do app, sistema, aparelho, últimos 5 erros (já sanitizados), recursos ligados. O usuário vê o que vai antes de enviar.
3. **No painel:** fila (nova → em andamento → aguardando → resolvida), busca por código/apelido, e **respostas prontas** com campos (`{apelido}`, `{recurso}`, `{codigo_erro}`),
   que você **edita antes de enviar**. As respostas prontas ficam num arquivo versionado (`api/_lib/support_replies.json`) e podem ser ampliadas no painel numa segunda fase.
4. **Ligações com o que já existe:** erro (`Bugs`) ↔ conversa do mesmo código; pesquisa ↔ conversa; recurso ↔ diagnóstico (2.7).
**Contraponto:** não é um "helpdesk": sem prazo contratual, sem e-mail de resposta, sem anexo de arquivo (custo e privacidade). **Riscos:** abuso (limite por dia, por aparelho e por IP já existe como padrão do projeto);
dado pessoal em texto livre (aviso curto "não escreva senhas" e corte de tamanho). **Custo:** 2 a 4 comandos por mensagem. **Esforço:** M (depende de 2.2).

### 2.9 Ficha do aluno

**Hoje (`StudentPage`, `teacher_page.dart:952`).** De cima para baixo: identidade + instrumento → cartão da aula (`_LessonCard`) → validação (`ValidationCard`) →
entrega (`_deliveryCard`) → tarefas (`_tasks`) → "mais" (desempenho, observações, aulas dadas, em modais). O menu da barra tem **6 itens** (relatório, relatório com IA,
copiar dados, código, renomear, excluir). O arquivo todo tem 1.910 linhas e a ficha divide espaço com a lista de alunos.

**Problemas.** Ordem por "quando foi criado", não por "o que o professor faz agora"; configuração de **entrega** (regra de envio) no meio da página no mesmo peso de tarefa;
itens raros (copiar dados, código) escondidos num menu de 6 itens.

**Proposta de 3 blocos (barra de seleção no topo, como o seletor Aluno | Professor):**
1. **Agora:** próxima aula, o que espera validação, tarefas em aberto, botão grande "Nova tarefa" e "Aluno faltou".
2. **Caminho:** histórico de aulas, desempenho (gráfico pequeno), observações.
3. **Combinados:** instrumento, turma, regra de entrega, código, vínculo, relatório, excluir (dentro de uma folha "Mais").
**Contraponto:** não adicionar abas se o conteúdo couber: se a tela "Agora" tiver menos de ~5 elementos, mantém numa rolagem só. Avaliar com 3 professores reais.
**Pré-requisito técnico:** extrair `StudentPage` e `_LessonCard` para `lib/ui/student_page.dart` (move sem mudar comportamento; os testes atuais protegem).
**Riscos:** a ficha é a tela de maior uso do professor: mudar no escuro. **Mitigação:** chave de recurso `ficha_nova` (liga para você e o Vinícius primeiro). **Esforço:** M.

### 2.10 Revisão geral das telas

Método (para não depender de opinião): **inventário com nota** de 0 a 3 em 5 critérios: texto (palavras na tela), densidade (elementos acima da dobra), toque (alvos ≥ 48 px),
hierarquia (uma ação principal) e consistência com o Design System. Começar pelas telas **maiores e mais usadas**: ficha do aluno, Minha conta (993 linhas), tour de boas-vindas (790),
Metrônomo (770), Ajustes (617), Agenda. Cada tela com nota ≤ 1 em algum critério vira tarefa.
Entregáveis: planilha no repositório (`docs/INVENTARIO_TELAS.md`), reduzir o teto do `check_text.js` aos poucos, capturas antes/depois em 390×844 e tablet.
**Esforço:** G, contínuo e em lotes de 2 a 3 telas por semana, para não misturar com funcionalidade nova.

### 2.11 Avaliação crítica geral (resumo dos contrapontos)

1. **Muita coisa já existe.** Itens 2, 6, 7 e 8 são **evoluções** de peças já entregues; tratar como projeto novo seria retrabalho.
2. **Não suavizar a cor de afinação.** Suavizar só a cor da marca e as superfícies.
3. **Separar Suporte de Administração na tela agora; em senhas só quando houver 2ª pessoa.**
4. **Usuário abrir conversa** é mudança de política (hoje não pode): decidir conscientemente (seção 7).
5. **A agenda exige auditoria antes de novas funções**, por causa das lápides do espelho.
6. **Play Store tem pré-requisitos que não são de interface** (internet no manifesto, assinatura, privacidade, lembretes nativos) e eles demoram mais que as telas.
7. **Público infantil muda as regras** (seção 3.4): se crianças vão usar sozinhas, há exigências da Play (Famílias) e da lei (LGPD, art. 14).

### 2.12 Acesso e recuperação da conta (aluno e professor): auditoria

**Pedido:** garantir que, ao trocar de aparelho, aluno e professor **consigam voltar à própria conta**, mesmo sem senha; ter instruções claras; garantir que
tenham o **e-mail** como forma de recuperar; página de ajuda pública; e controle disso no painel de suporte.

**Como é hoje (lido no código):**
- O perfil **nasce sem cadastro**: um **código** (ex.: `K7QM-4TXK`) e um **segredo** guardado só no aparelho (`api/_lib/devices.js`). **Não há senha.**
- Formas de voltar numa conta já existente (`api/account.js`, `lib/ui/join_account_page.dart`, porta "Já tenho conta" no tour):
  1. **Outro aparelho da conta** gera um código de pareamento de 10 minutos (QR ou texto) em Minha conta › Aparelhos; até **5 aparelhos**.
  2. **E-mail:** o servidor manda um código de 6 dígitos; vale 10 minutos, 5 tentativas.
  3. **Chave de recuperação** de 25 caracteres, mostrada ao usuário (marca vermelha no avatar e a linha "Você ainda não guardou a sua chave" enquanto não foi vista).
  4. **Suporte:** o painel libera o perfil para um aparelho novo mediante o **código de suporte** que a pessoa gera.
- **O e-mail está desligado hoje na prática:** o recurso só aparece (`emailEnabled`) quando a Vercel tem `MAIL_API_KEY` e `MAIL_FROM` e o domínio de envio está verificado.
  Esse passo ainda está pendente (anotado desde a entrega do e-mail da conta). **Sem ele, "e-mail obrigatório" é impossível.**
- O **espelho entre aparelhos** só trabalha com **2 ou mais aparelhos** na conta. **Professor com um aparelho só que o perde, perde as fichas** (o servidor guarda os vínculos e as aulas
  publicadas, não o caderno todo). O botão "Copiar dados" é manual.

**Cenários em que a pessoa fica perdida (o que você descreveu):**
| Cenário | Hoje | Resultado |
|---|---|---|
| Aluno troca de celular, **sem** e-mail, sem chave, sem o aparelho antigo | só o suporte pode ajudar | cria perfil novo; o professor precisa vincular de novo; **histórico de estudo some** |
| Professor troca de celular com **um** aparelho e sem e-mail/chave | idem | **perde alunos e anotações locais** |
| Criança (sem e-mail próprio) perde o aparelho | idem | depende de um adulto |
| Pessoa tem e-mail ligado, mas **não recebe o código** (spam, domínio não verificado) | não há tela de ajuda | sem saída sozinha |
| Pessoa **esqueceu a senha do e-mail** | o app não tem senha, mas o e-mail é a chave | precisa recuperar o e-mail no provedor; hoje **nada explica** |
| Alguém tenta se passar por outra pessoa | liberação exige o código de suporte da pessoa | seguro, mas sem roteiro de verificação para o suporte |

**Contraponto à ideia "e-mail obrigatório e enviar os valores de acesso":**
1. **Professor: concordo em tornar obrigatório** ter pelo menos **um método de recuperação** antes de vincular o primeiro aluno (e-mail, ou chave confirmada). Ele guarda dados de outras pessoas.
2. **Aluno: obrigatório só quando o app puder pedir com segurança.** Para criança, o e-mail certo é o **do responsável** (seção 2.13); exigir e-mail próprio de menor entra em conflito com minimização de dados.
   Alternativa para o aluno: **"o professor também resolve"**: o professor pode trocar o código do aluno na ficha (já existe "Código do aluno") para religar a ficha dele ao perfil novo.
3. **Não enviar a chave de 25 caracteres por e-mail como regra.** O e-mail de boas-vindas deve levar: **o código da conta**, **como recuperar** (link para a página de ajuda) e **o que fazer se perder tudo**.
   Quem controla o e-mail já consegue entrar pelo código de 6 dígitos; mandar a chave **a deixa guardada na caixa de entrada para sempre**. Oferecer "Enviar minha chave para o meu e-mail" só como **opção**, com aviso.
4. O que é **obrigatório de fato** é a pessoa **provar que sabe voltar** antes de precisar: pedir, uma vez, para **testar a recuperação** ("digite os 4 primeiros caracteres da chave" ou "confirme o código enviado ao e-mail").

**Solução recomendada (por camadas):**
1. **Pré-requisito de produção:** configurar o provedor de e-mail e o domínio (SPF/DKIM) e monitorar entrega (envios, falhas, devolvidos) no painel.
2. **Etapa "Proteja sua conta" no cadastro do professor** (já existe o cadastro em 3 passos): e-mail + código de confirmação, ou chave com confirmação; só então "Adicionar aluno". Para o aluno, aparece depois do 1º vínculo, e para menor pede o e-mail do responsável.
3. **Tela "Perdi meu acesso / troquei de aparelho"**, em passos, na ordem mais fácil: (a) tenho o aparelho antigo → pareamento; (b) tenho e-mail → código; (c) tenho a chave; (d) nada disso → pedir ajuda ao suporte (formulário curto + roteiro).
4. **E-mail de boas-vindas e de segurança** (ao ligar o e-mail, ao gerar chave nova, ao entrar num aparelho novo, ao tirar um aparelho): código da conta, quais aparelhos, "não foi você? toque aqui". Já existe aviso por e-mail ao entrar num aparelho novo; ampliar e traduzir.
5. **Professor com um aparelho só:** cópia segura das fichas no servidor **também com 1 aparelho** quando houver e-mail (hoje só com 2+). Custo: as seções do espelho já são pequenas; medir comandos (seção 2.14).
6. **Painel › Suporte (seção 2.6):** na ficha do usuário: tem e-mail? (mascarado), tem chave?, quantos aparelhos, último acesso, quando foi o último e-mail enviado/devolvido; **fila de risco**: professores com alunos e **sem** método de recuperação; **roteiro de verificação de identidade** antes de liberar (conferir o código de suporte, o nome do professor/responsável, um dado que só a pessoa saberia, e registrar no log); métrica no Início: **% de professores com recuperação ativa** (meta: 90%).

**Riscos:** e-mail que não chega (principal); engenharia social no suporte; atrito no cadastro (professores desistirem). Mitigar com teste de entrega antes de tornar obrigatório e com um "agora não" **só para o aluno**, nunca para o professor.
**Testes:** matriz com os 6 cenários acima, em aparelho real, cronometrando o tempo até voltar; teste com 3 pessoas (um adulto, um adolescente, um responsável por criança); testes de API de `login_start`/`login_verify`/`rk_login`/`pair_join` já existem e ganham os casos de limite de aparelhos e de e-mail inexistente.
**Esforço:** M (G se incluir a cópia com 1 aparelho).

### 2.13 Idade, LGPD e Google Play: o que o app precisa decidir

**Pesquisa feita nesta análise (fontes na seção 10; conferir com advogado):**
- **ECA Digital (Lei 15.211/2025)** entrou em vigor em **17/03/2026**; regulamentada por decretos de 18/03/2026. Vale para **produtos e serviços de TI direcionados a crianças e adolescentes ou de "provável acesso"
  por eles**, incluindo aplicativos e plataformas educacionais. **Autodeclaração isolada de idade não basta** para o que exige verificação. Pontos citados: menores de 12 sem conta em redes sociais; 12 a 15
  com conta vinculada a um responsável; supervisão parental para menores de 16; sem publicidade comportamental para menores de 18; vedação de "padrões obscuros" (rolagem infinita, autoplay, notificações de apelo emocional);
  **avaliação de impacto** antes de lançar funções acessíveis por menores. Sanções: advertência, multa de até 10% do faturamento (teto de R$ 50 milhões por infração) e suspensão. Fiscaliza a **ANPD**.
  Uma fonte descreve **fases**: lojas e sistemas até junho/2026, jogos/redes/marketplaces entre agosto e novembro/2026 e **fiscalização efetiva a partir de janeiro de 2027** (conferir cronograma oficial).
- **LGPD, art. 14:** tratamento de dados de **criança** (até 12 anos incompletos) exige **consentimento específico de um dos pais ou do responsável**, e o aviso deve ser claro.
- **Google Play, Políticas para Famílias:** valem se **crianças são um dos públicos-alvo** (inclusive "público misto"). Exigem: declarar a faixa etária na ficha, ficha de **Segurança dos dados** e **classificação de conteúdo (IARC)** coerentes, política de privacidade fiel, sem
  identificadores de publicidade em apps só para crianças, SDKs adequados, e obedecer COPPA/LGPD. Recursos sociais com desconhecidos não podem ter crianças como público.
- **Play Age Signals API** (beta): devolve a **faixa etária** do usuário (padrão 0–12, 13–15, 16–17, 18+) e se é conta supervisionada; está retornando sinais para o **Brasil desde 17/03/2026** e deve expandir ao mundo até o fim de 2026; integração **opcional**; os dados só podem
  servir para dar **experiências adequadas à idade dentro do próprio app**.
- **Play, exclusão de conta:** apps que permitem criar conta devem oferecer **exclusão dentro do app** e **um endereço web** informado na ficha de Segurança dos dados; a exclusão da conta apaga os dados associados.

**Onde o Notemusic se encaixa:** é **ensino de música**, com alunos de todas as idades, **sem anúncios, sem perfilamento, sem rede social aberta, sem rolagem infinita**. É "serviço de provável acesso por menores" e tem pontos de dado pessoal:
nome/apelido, **foto**, vínculo com professor, **conversa com o suporte**, e-mail, aparelho/versão. O risco **não é de conteúdo**, é de **dados de menores e de consentimento**.

**Recomendação (a validar com advogado):**
1. **Declarar na Play "para todos os públicos, com uso supervisionado"** e tratar o app como **público misto** (por isso a política de Famílias passa a valer); **não** declarar "só crianças".
2. **Faixa etária por seleção neutra** (menos de 12 · 12 a 15 · 16 a 17 · 18 ou mais) na primeira vez, **sem pedir data de nascimento**; no Android, **confirmar com o Play Age Signals** quando disponível (só para adequar a experiência).
3. **Experiência por faixa** (a mesma tela, menos coisas):
   - **Menos de 12:** sem foto, sem conversa com o suporte, **apelido** em vez de nome, **e-mail do responsável** (consentimento), vínculo só com o professor que o responsável aceitou.
   - **12 a 15:** foto desligada por padrão; conversa com o suporte **ligada ao e-mail do responsável**; "conta vinculada a responsável".
   - **16 e mais:** como hoje, com as proteções gerais.
4. **Professor que cadastra aluno menor** declara, num aceite simples, que **tem autorização do responsável** (registro do aceite e da data).
5. **Documentos:** política de privacidade com **seção para menores e para responsáveis**, **termos de uso**, **encarregado (DPO) com e-mail de contato**, **relatório de impacto simplificado** (o que coleta, para quê, por quanto tempo, quem acessa), **política de retenção e exclusão**.
6. **Auditoria de SDKs** para a política de Famílias: conferir `mobile_scanner` (leitura de QR), `speech_to_text`, `share_plus`, `url_launcher`, `image_picker`, `vibration`, `record` quanto a identificadores de publicidade, rede e permissões declaradas.
7. **Sem SDK de anúncio e sem análise de comportamento** (já é o caso; deixar **escrito** como compromisso do produto).

**Contrapontos:** pedir faixa etária a todos **aumenta o atrito**; por isso só **uma pergunta**, sem teclado, e o texto explica o porquê ("para ajustar o app"). Verificação rígida de idade **não** parece exigida
para um app sem conteúdo restrito, mas **só um advogado pode confirmar**. Se a faixa etária mudar o que a pessoa vê, é preciso **teste de usabilidade com crianças acompanhadas**, não só leitura de regra.
**Dependências:** conta com e-mail (2.12) para o consentimento do responsável; página de ajuda e privacidade (2.12/3.1); chave `faixa_etaria` (2.7) para liberar aos poucos.
**Testes:** matriz faixa × recurso (foto, conversa, e-mail, vínculo, relatório) com teste automático de que cada faixa **não** vê o que não deve; revisão jurídica antes do teste fechado.
**Esforço:** G (inclui jurídico).

### 2.14 As 11 funções da Vercel: são necessárias? Há sobrecarga?

**Resposta curta:** as 11 **fazem sentido hoje**, **nenhuma está sobrecarregada pelo número de arquivos**, e dá para **chegar a 8** sem risco relevante quando for preciso. O que realmente pesa **não é o número de funções, é o número de chamadas**.

*Importante:* o limite de 12 do plano Hobby conta **arquivos em `api/`** (fora de `_lib/`). Funções que ficam juntas num arquivo **não** viram uma só função na prática de carga: o que muda é **onde cada pedido executa**.

| Função | Linhas | Papel | Tráfego (simulação) | Pode juntar? |
|---|---|---|---|---|
| `link` | 941 | vínculo, agenda, aulas, tarefas, espelho, foto (hot path) | **~74% das chamadas** | **Não.** É o caminho quente; juntar outra coisa aumenta a carga a frio |
| `stats` | 230 | abertura, batida, eventos; leitura do painel | ~23% | **Não** (segundo caminho quente) |
| `remind` | 118 | alvo do QStash, lembrete de aula | ~2,5% | Não: é chamado por outro serviço, com assinatura própria |
| `coach` | 200 | IA com fila, **timeout de 60 s** (`vercel.json`) | baixo | **Não:** a configuração de tempo é por função |
| `account` | 431 | e-mail, chave, pareamento, aparelhos | baixo | Não: depende de `link` e e-mail; ficaria na rota quente |
| `admin` | 1.252 | painel (22 módulos) | baixíssimo (só você) | Não: grande demais e exige chave própria |
| `feedback` | 225 | nota/pesquisa/identify | baixo | Possível com `errors`/`stats`, ganho pequeno |
| `errors` | 63 | relatório de erro | baixo | **Sim**, para dentro de `stats` (ambos anônimos, `POST`) |
| `news` | 38 | boletim publicado (GET, cache de 5 min na CDN) | quase zero (CDN) | **Sim** |
| `fingering` | 36 | dedilhado (GET, cache 5 min) | quase zero (CDN) | **Sim** |
| `ai-status` | 40 | estado da IA (GET) | baixo | **Sim** |

**Proposta, só se precisar de vagas:** criar **um** arquivo público de leitura (`api/pub.js`) com `?k=news|fingering|ai`, e mover `errors` para dentro de `stats`.
Resultado: 11 → **8 funções**. **Sem quebrar apps antigos:** manter os endereços atuais com **`rewrites` no `vercel.json`** (`/api/news` → `/api/pub?k=news`); rewrites **não** contam como função.
**Impacto esperado:** baixo: são rotas pequenas, de leitura, com cache de CDN; **não tocam** `link` nem `stats` quentes. **Riscos:** (1) uma falha no arquivo comum derruba as três leituras (mitigar com testes e com `try/catch` por parte);
(2) a chave de cache da CDN passa a depender do parâmetro `k` (conferir o cabeçalho `Cache-Control` por parte); (3) o painel usa `api/stats` com autenticação: separar claramente o `POST` anônimo do `GET` do painel.
**Não vale a pena** juntar `account`, `admin`, `coach` ou `remind`.

**O que realmente pode sobrecarregar (e merece atenção antes de crescer):**
- A consulta barata **`rev`** é **~62%** de todas as chamadas (25.104 de 40.785 na simulação de 300 usuários). Já tem espaçamento adaptativo; ainda dá para **esticar mais o intervalo** quando nada muda e **juntar a "batida" (`beat`, 15%)** com o `rev` (uma chamada em vez de duas) para cortar **até ~15% das chamadas**.
- Em **10 mil usuários ativos** a simulação aponta ~1,36 milhão de chamadas/mês, **acima** do 1 milhão incluído no Pro: o excesso custa centavos (US$ 0,60 por milhão), então **não é risco de queda, é de custo pequeno**.
- No Hobby, **conferir o limite real de invocações** do plano (fontes divergem entre 100 mil e 1 milhão) e olhar no painel da Vercel (Observability) **chamadas, erros, duração p95 e partidas a frio por função**. **Não consegui consultar a conta da Vercel**: este é um dado a ler por você (ou me dar acesso a um print).
**Como medir (sem mudar nada):** aba Custos do painel (chamadas dos últimos 30 dias, já medidas), `scripts/simulate_load.js` antes/depois, e os logs de função da Vercel.
**Esforço:** juntar as leituras P/M; otimizar `rev`/`beat` M. **Prioridade:** baixa agora, **média antes de abrir ao público da Play**.

### 2.15 Página pública de ajuda (documentação para o usuário)

**Pedido:** uma página que ajude com dúvidas gerais ("esqueci a senha do meu e-mail e agora?", "como falo com o suporte?").

**Proposta:** `web/ajuda.html` (estática, no mesmo visual do site, em português e inglês), com **link dentro do app** (Ajustes › Ajuda e suporte, tela de "Perdi meu acesso", rodapé do e-mail) e **na ficha da Play**.
Também serve de **endereço web de exclusão de conta** exigido pela Play (seção própria, com âncora), e de apoio para responsáveis.

**Conteúdo mínimo (perguntas reais, respostas curtas, com passo a passo):**
1. **Troquei de celular, como entro na minha conta?** (os 4 caminhos da seção 2.12, com imagens do app)
2. **Perdi a chave e não tenho e-mail ligado.** O que fazer e quando falar com o suporte.
3. **Não recebi o código no e-mail** (spam, endereço digitado errado, tempo de 10 minutos, pedir de novo).
4. **Esqueci a senha do meu e-mail.** O Notemusic **não tem senha**; quem controla o e-mail controla a conta; **recupere o e-mail no próprio provedor** (Google, Outlook, Yahoo: link oficial de cada um) e volte.
5. **Como falar com o suporte** (canal, horário, o que informar: código da conta, aparelho, o que aconteceu; **nunca** enviar chave nem código de 6 dígitos).
6. **Sou aluno: meu professor pode me ajudar?** (religar a ficha pelo código).
7. **Sou responsável por uma criança:** o que é coletado, como dar ou retirar consentimento, como excluir os dados (ligação com 2.13).
8. **Apagar minha conta e meus dados** (no app e por esta página).
9. **O app não abre / a foto não carrega / o microfone não funciona** (guia curto por aparelho).
10. **Privacidade e termos** (links).

**Regras de redação:** frases curtas, vocabulário simples (de criança a adulto), uma pergunta por bloco recolhível, botão "Falar com o suporte" no fim de cada resposta.
**Mantê-la viva:** cada pergunta nova que chegar ao suporte vira candidata a entrar aqui (campo "virou FAQ" na conversa de suporte, seção 2.8). **Canal de contato:** definir um e-mail de suporte dedicado (precisa de domínio próprio; hoje o site é `notemusicmap.vercel.app`): **decisão sua** (seção 7).
**Testes:** link verificado no CI (`check_docs`-like para `web/`), leitura em celular, versão em inglês, e teste com 3 pessoas tentando recuperar a conta **só com a página**.
**Esforço:** M (conteúdo é o maior trabalho).

---

## 3. Planejamento para publicar na Google Play

### 3.1 Estado atual e lacunas (verificado no código)

| Item | Estado | Ação |
|---|---|---|
| Permissão de internet | **Falta** no `AndroidManifest.xml` principal (só existe em `debug` e `profile`). Um app de **release** sem ela **não acessa a API** | Acrescentar `INTERNET` (e `ACCESS_NETWORK_STATE`, se o app for checar conexão). Conferir com o AAB final |
| Assinatura | `signingConfig = debug` (com `TODO`) | Criar **upload keystore**, guardar fora do repositório, usar **Play App Signing** |
| `applicationId` | `br.app.afina` (nome antigo do projeto) | **Definir o definitivo antes da 1ª publicação**: depois não muda. Sugestão: `br.app.notemusic` (decisão sua) |
| Versão | `1.0.0+1` | Regra: `versionCode` sempre sobe; `versionName` visível. Ligar ao `kBuildId` do CI |
| API alvo | segue o Flutter (compileSdk 36) | Conferir a exigência vigente da Play (API alvo recente) e a de **páginas de 16 KB** nas bibliotecas nativas (microfone, câmera/QR, vibração) |
| Ícone/ícone adaptável | pastas `mipmap-*` existem | Conferir ícone adaptável (camada de fundo/primeiro plano) e ícone de 512 px |
| Política de privacidade | **sem página pública** | Escrever e publicar em `web/privacidade.html` (base: `docs/05_SEGURANCA_E_PRIVACIDADE.md`) |
| Exclusão de conta/dados | existe "Apagar tudo" no app | A Play exige exclusão **no app e um endereço web**, informado na ficha de Segurança dos dados; a exclusão apaga também os dados associados. Pode ser uma **seção com âncora** na página de ajuda (2.15) ou na política de privacidade |
| Lembretes | só Web Push | Ver 3.3 (notificações nativas) |
| Links que abrem o app (`?aluno=`, `?pair=`, `?professor=`) | funcionam no navegador | Para abrir **o app instalado**, configurar *App Links* (`assetlinks.json`) |
| Câmera/microfone/foto | declaradas; pedido em tempo de uso | Escrever as justificativas na ficha "Segurança dos dados" |

### 3.2 Requisitos da loja (conferir antes de agir)

1. **Conta de desenvolvedor:** o projeto registra que já existe. **Conferir** se é pessoal ou de organização e **a data de criação**. Segundo a ajuda oficial da Play, contas **pessoais criadas depois de 13/11/2023** precisam de **teste fechado com pelo menos 12 testadores inscritos continuamente por 14 dias** antes de pedir o acesso à produção (teste aberto não conta; contas de organização ficam fora dessa regra e exigem verificação de empresa, com CNPJ). Se a conta é anterior a essa data, não se aplica.
2. **Pacote:** AAB (`flutter build appbundle`), não APK.
3. **Ficha "Segurança dos dados":** o app envia ao servidor apelido, código, aulas, tarefas, foto (só se a pessoa escolher mostrar), hash do e-mail, versão/sistema do aparelho; **o áudio é analisado no
   aparelho e não é enviado** (isso precisa estar claro e verdadeiro).
4. **Classificação de conteúdo e público-alvo:** ver 3.4.
5. **Ficha da loja:** título, descrição curta e longa em pt-BR e inglês, ícone 512, imagem de destaque 1024×500, capturas de celular e de tablet.
6. **Teste interno → fechado → produção**, nessa ordem; usar o canal de feedback do próprio app.

### 3.3 Web e mobile juntos: compatibilidade e manutenção

- **Uma base de código só.** Há 13 arquivos com `kIsWeb` e uma pasta `lib/platform/` com pares `*_web.dart`/stub (boa prática já em uso: `web_push`, `web_install`,
  `web_file_pick`, `hard_reset`). Manter: **nenhum código de web fora de `lib/platform/` e dos arquivos `*_web.dart`**.
- **API compartilhada** (`/api/*`): precisa continuar **retrocompatível por mais tempo**, porque a versão da loja só atualiza com revisão e o usuário pode ficar semanas numa versão antiga.
  Regra nova: **janela de compatibilidade de 90 dias** e um campo de "versão mínima" que o servidor pode devolver para mostrar "atualize o app" (a Play tem atualização dentro do app).
- **Atualização:** web atualiza na hora; Android depende da loja. Isso aumenta a importância das **chaves de recurso** (2.7): ligar por versão.
- **CI:** hoje compila só a web. Acrescentar um job que roda `flutter analyze` e `flutter build appbundle --release` (sem publicar) a cada envio, e a conferência do manifesto (internet presente, `applicationId` esperado).
- **Notificações nativas:** o lembrete de aula usa Web Push. No Android, **Firebase Cloud Messaging** (gratuito) ou notificações locais agendadas. Recomendo **notificação local agendada** para a aula
  (não depende de servidor e funciona sem internet) e FCM só para avisos novos. Exige o plugin correspondente e a permissão de notificação do Android 13+.
- **Armazenamento e microfone:** o desempenho do detector de altura em aparelhos Android baratos precisa de **teste em 3 aparelhos reais** (baixo, médio, alto) antes do teste fechado.
- **Diferenças de interface:** botão Voltar do Android (tratado em `HomeShell`), notch/teclado, tablet e dobráveis, "reduzir movimento".

### 3.4 Público, idade e privacidade (resumo; o detalhe está em 2.13)

Você pediu para pensar em "da criança ao adulto" e em alinhar o app às diretrizes da Play e à LGPD. A pesquisa desta análise (seção 10) mostra:
- A **Play** aplica as **Políticas para Famílias** quando **crianças são um dos públicos-alvo** (inclusive público misto): exige declarar faixa etária, ficha de Segurança dos dados e classificação de conteúdo coerentes, privacidade fiel e conformidade com a lei local.
- O **ECA Digital** (em vigor desde 17/03/2026) alcança apps de **provável acesso por menores**, exige mais que autodeclaração onde há verificação, pede responsável para 12 a 15 anos, supervisão para menores de 16 e **avaliação de impacto**; fiscalização efetiva anunciada para 2027 (conferir).
- A **LGPD, art. 14** pede **consentimento específico do responsável** para dados de crianças.
- A Play oferece a **Play Age Signals API** (faixas 0–12, 13–15, 16–17, 18+; Brasil desde 17/03/2026; opcional; só para adequar a experiência).

**Decisão recomendada:** declarar **"para todos os públicos, uso supervisionado"**; faixa etária por **seleção neutra**; experiência reduzida por faixa; **consentimento do responsável** pelo e-mail; **aceite do professor** ao cadastrar menor; documentos e **revisão jurídica antes do teste fechado**. Isto é recomendação técnica, **não aconselhamento jurídico**.

### 3.5 Custos e sustentabilidade (números do próprio modelo `api/_lib/cost_model.js`)

Consumo medido por usuário ativo no mês: **387 comandos**, **136 chamadas**, **3,4 lembretes**. Projeção (câmbio R$ 5,50; preços de tabela de 12/11/2026, **conferir**):

| Usuários ativos/mês | Sem receita (Hobby) | Com receita (Vercel Pro obrigatório) |
|---|---|---|
| 100 | R$ 0 | R$ 110 |
| 1.000 | R$ 0 | R$ 110 |
| 5.000 | R$ 16 | R$ 126 |
| 10.000 | R$ 149 | R$ 149 |

Leituras importantes:
1. **O plano Hobby da Vercel é só para uso não comercial.** No dia em que houver cobrança, anúncio ou assinatura, é preciso o **Pro (US$ 20/mês ≈ R$ 110)**. É o **primeiro custo fixo real**.
2. O Redis (Upstash) fica grátis até ~1.290 usuários ativos (500 mil comandos ÷ 387) e custa centavos por usuário depois.
3. O limite de **12 funções** é do plano Hobby; no Pro o limite muda (**conferir** o valor vigente), o que pode aliviar a arquitetura (hoje 11 de 12).
4. Custos que **não estão no modelo**: IA (Gemini/outros), e-mail da conta (provedor + domínio), domínio próprio, imposto e taxa de pagamento, tempo de suporte.
5. **Ponto de equilíbrio simples:** com assinatura de **R$ 9,90/mês**, descontadas as taxas, **cerca de 13 a 15 assinantes** cobrem o Pro; o custo por usuário ativo é de R$ 0,01 a R$ 0,11.

### 3.6 Monetização e pagamentos (opções e regras)

**Princípio:** o app é, ao mesmo tempo, **ferramenta de estudo** e **ferramenta de gestão de aulas**. Cada um tem regra diferente.

| Opção | O que é | Regra da Play (conferir) | Minha avaliação |
|---|---|---|---|
| **A. Plano Pro do professor** (mais turmas, relatórios com IA, acervo, lembretes) | assinatura mensal/anual | Conteúdo/serviço **digital consumido no app** vendido num app da Play deve usar o **Google Play Billing**. Segundo o blog oficial de junho/2026, a taxa de serviço **começa em 10% no primeiro US$ 1 milhão por ano, inclusive em assinaturas**; programas de cobrança alternativa/links externos reduzem a taxa, mas **não confirmei que valem no Brasil** (conferir no Play Console) | **Melhor candidata.** Receita recorrente, público que já paga aulas |
| **B. Gratuito com limite** (ex.: até N alunos) | funil para o Pro | Sem pagamento aqui | Recomendado como porta de entrada |
| **C. Pagamento do aluno ao professor** (mensalidade, aula avulsa) | serviço real, fora do app | Serviços **físicos/presenciais** podem usar meio externo; **mas** se o app **processar** o dinheiro entre pessoas, vira meio de pagamento/intermediação, com exigências do Banco Central e do PSP | **Não recomendo processar dinheiro.** Começar só com **registro manual** ("pago/pendente") e link do Pix do próprio professor |
| **D. Doação/apoio** | contribuição voluntária | Na Play, doações dentro do app também passam por regras de billing (conferir) | Possível pela web (Pix), fora do app Android |
| **E. Anúncios** | AdMob | Incompatível com público infantil (3.4) e com a identidade "de músico para músico" | **Não recomendo** |

**Pagamento online (web) e pela Play, convivendo.** Para o mesmo plano Pro:
- **Android (Play):** compra pelo Play Billing.
- **Web:** checkout com **Pix e cartão** (Mercado Pago, Stripe ou Asaas; escolher pelo menor custo e pela facilidade de Pix recorrente).
- **Direitos do usuário** (`entitlement`) ficam **no servidor**, ligados à **conta com e-mail** (que já existe como recurso, hoje invisível até configurar provedor e domínio), e **não** à loja.
  Assim, quem paga pelo site e usa no Android continua Pro. **Cuidado:** a Play restringe **direcionar** o usuário Android a pagar fora do app (conferir o programa vigente no Brasil).
- Para não construir tudo à mão, avaliar um intermediário de assinaturas (por exemplo RevenueCat, que une Play Billing e web; conferir preço) **ou** começar com **Play Billing só no Android + checkout web separado**
  e unir depois.
- **Dependências:** conta com e-mail ativa → entitlement no servidor → chave de recurso "plano Pro" (2.7) → telas de plano → política de reembolso e termos → nota fiscal/MEI ou CNPJ (**conferir com contador**).

### 3.7 Melhorias necessárias antes de publicar (lista)

Técnicas: internet no manifesto; assinatura e `applicationId`; CI do AAB; notificações nativas; App Links; teste em aparelhos reais; revisão de tamanho do app e do tempo de abertura.
De produto: central de suporte (2.8) antes de abrir ao público; tela "Sobre/privacidade/termos" dentro do app; fluxo para menores; reduzir a dependência de "Chave de recuperação" para quem não entende (e-mail é caminho melhor).
De operação: política de retenção/exclusão; plano de resposta a incidente; painel de alertas (já previsto); monitor de custo por versão.

---

## 4. Dependências entre as melhorias

```
Auditoria da agenda (2.4A) ──► lápides no espelho ──► qualquer divulgação do "multiaparelho" e a Play
Token "primary" (2.3)      ──► ficha do aluno (2.9) ──► revisão geral (2.10)
Conversa tipo suporte (2.2/2.8) ──► diagnóstico por usuário (2.7) ──► Suporte × Administração (2.6)
Chaves por grupo (2.7)     ──► lançar ficha nova, plano Pro e Play em etapas
Manifesto/assinatura/privacidade (3.1) ──► teste interno ──► teste fechado ──► produção
Conta com e-mail ativa ──► entitlement no servidor ──► plano Pro (3.6)
Notificação nativa (3.3)   ──► lembretes da agenda no Android
E-mail da conta no ar (domínio + provedor) ──► e-mail obrigatório do professor ──► consentimento do responsável (2.13)
Decisão de faixa etária (2.13) ──► foto/conversa por faixa ──► ficha da Play (público-alvo, Segurança dos dados)
Página de ajuda (2.15) ──► endereço de exclusão de conta ──► ficha da Play
```

## 5. Etapas (ondas), critérios de "pronto" e testes

**Regras de sempre:** testar tudo antes; mostrar no navegador em 390×844 e tablet; API retrocompatível; custo baixo (medir comandos); texto novo com `tr()` e inglês; recurso novo atrás de chave;
**só publicar com o "Sim, publicar".**

### Onda 0: fundação e verificação em aparelho real (1 semana)
- Testar em **Chrome do Android** (Voltar, foto de perfil, microfone, escala guiada sem escorregar) e iPhone; anotar o que falha.
- Reproduzir e corrigir o **alinhamento do botão de validação** (2.3).
- Auditoria da agenda: matriz de cenários e testes que falham hoje (2.4A).
- Inventário de telas (2.10): primeira planilha, só medir.
- **E-mail da conta no ar:** provedor, domínio, SPF/DKIM, teste de entrega e painel de envios/falhas (pré-requisito da seção 2.12).
- **Decisões de idade** (2.13) e de contato do suporte (2.15) tomadas; **pergunta ao advogado** enviada (lista na seção 7).
- **Leitura da Vercel** (2.14): chamadas, erros, p95 e partidas a frio por função, num print.
- **Pronto quando:** lista de falhas reais em aparelho; matriz da agenda escrita; captura do alinhamento antes/depois; e-mail entregando em Gmail, Outlook e Yahoo.

### Onda 1: Novidades e conversa (2 semanas)
- Central de Novidades separada do sino; folha em tela cheia; avisos longos com "Ler tudo"; animações com `Dismissible` (2.1).
- Conversa com tipos `dev` e `suporte`, estados, etiquetas, histórico por usuário, respostas prontas editáveis (2.2, 2.8).
- **Recuperação de conta** (2.12): etapa "Proteja sua conta" no cadastro do professor, tela "Perdi meu acesso", e-mails de boas-vindas/segurança, fila de risco e roteiro de verificação no painel.
- **Página de ajuda pública** (2.15) com link no app e seção de exclusão de conta.
- **Pronto quando:** 5 tipos de aviso testados; conversa dos dois tipos testada na API e na tela; custo em comandos medido e dentro do orçamento; **3 pessoas recuperam a conta só com a página e o app**; 90% dos professores de teste com recuperação ativa.

### Onda 2: Chaves por grupo, diagnóstico e painel Suporte/Administração (2 semanas)
- Grupos e precedência, "por que vê isto?" (2.7). Dividir `admin.html` em módulos, depois separar Suporte e Administração (2.6).
- **Pronto quando:** tabela de precedência 100% testada; painel com as duas portas e ações destrutivas só em Administração.
- **Funções da Vercel** (2.14): só se faltar vaga, juntar `news`/`fingering`/`ai-status` em `pub` e `errors` em `stats`, com `rewrites`; e otimizar `rev`/`beat`.
- *Em paralelo (3A):* manifesto com internet, assinatura, `applicationId`, política de privacidade e exclusão de conta na web, CI do AAB.

### Onda 3: Paleta, ficha do aluno e revisão de telas (3 a 4 semanas, em lotes)
- Auditoria de contraste e token `primary`; migração por lotes; eliminar cores fixas (2.3).
- Extrair e reorganizar a ficha do aluno atrás da chave `ficha_nova` (2.9).
- Revisão por inventário, 2 a 3 telas por semana (2.10).
- **Pronto quando:** contraste ≥ 4,5:1 nos dois temas; ficha nova ligada para você e para o Vinícius sem erro por 1 semana; teto de textos longos menor.

### Onda 4: Agenda (3 a 5 semanas)
- Lápides no espelho; tabela de estados; remarcar só esta aula; pedido de troca do aluno; visão semanal (2.4B). Notificação nativa de lembrete já na Onda 5A.
- **Pronto quando:** cada cenário da matriz tem teste verde; 3 aulas reais de professor e aluno usadas por 1 semana sem erro no painel.

### Onda 5: Play Store
- **5A (técnico, desde a Onda 2):** AAB assinado, notificações nativas, App Links, aparelhos reais, política e exclusão.
- **5B (conformidade):** ficha de Segurança dos dados, classificação (IARC), **público-alvo e faixa etária**, política de Famílias (auditoria de SDKs), exclusão de conta, **Play Age Signals** (opcional), **ECA Digital/LGPD** e **revisão jurídica**; faixa etária e consentimento do responsável implementados (2.13).
- **5C (teste):** interno (você + 3 pessoas) → **fechado** com professores e alunos reais por pelo menos 14 dias (conferir mínimo vigente) → produção.
- **5D (receita, só depois do teste fechado):** plano Pro (3.6), Vercel Pro, checkout web, entitlement.
- **Pronto quando:** 14 dias de teste fechado sem erro grave; custo por usuário real medido; privacidade e termos revisados.

## 6. Riscos técnicos

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Agenda: aula cancelada volta (espelho sem lápides) | média | **alto** (aluno vai a aula cancelada) | Onda 0 audita; Onda 4 corrige; aviso de limite até lá |
| Mudar a paleta quebra a leitura da afinação | média | alto | separar `primary` de `inTune`; capturas antes/depois; teste de contraste |
| `AppState` e `teacher_page.dart` grandes demais | alta | médio | extrair por partes antes de reorganizar; testes atuais protegem |
| `admin.html` com ~3 mil linhas | alta | médio | dividir em módulos antes de separar Suporte/Administração |
| App Android sem internet no release | **certa se não corrigir** | **alto** | corrigir no manifesto; conferir no AAB; teste em aparelho |
| Versão antiga na loja falando com API nova | média | alto | janela de compatibilidade de 90 dias; versão mínima no servidor |
| Custo sobe com usuários/lembretes | baixa | médio | aba Custos; limite 60%; modelo de projeção; lembrete local no Android |
| Público infantil sem consentimento | média | alto (lei e loja) | decisão da seção 3.4 e revisão jurídica |
| Abuso na conversa de suporte | média | médio | limites por dia/aparelho/IP; texto curto; sem anexo |
| E-mail da conta não entrega (domínio sem verificação, spam) | alta até configurar | **alto** (pessoa sem saída) | configurar provedor + SPF/DKIM; testar Gmail/Outlook/Yahoo; painel de envios e falhas; só então tornar obrigatório |
| Pessoa perde o único aparelho sem e-mail nem chave | alta | alto | etapa "Proteja sua conta" obrigatória para professor; tela "Perdi meu acesso"; roteiro de verificação no suporte; cópia com 1 aparelho |
| Dados de menores sem consentimento do responsável | média | **alto** (lei e loja) | faixa etária neutra; e-mail do responsável; aceite do professor; revisão jurídica antes do teste fechado |
| Engenharia social para tomar conta de outra pessoa | baixa | alto | roteiro de verificação; liberação só com o código de suporte; aviso por e-mail ao aparelho antigo |
| Limite de 12 funções da Vercel | baixa hoje, certa com crescimento | médio | novas ações em endpoints existentes; no Pro o limite muda (conferir) |

## 7. Decisões que dependem de você

1. **Dicas** (cartões de ajuda) ficam no sino, em faixa "Comece por aqui" ou em aba própria?
2. **Usuário poderá abrir conversa com o suporte?** (muda a política atual de "só o desenvolvedor começa").
3. **Chave de suporte separada** já na Onda 2, ou só a separação na tela?
4. **Nome definitivo do pacote Android** (`applicationId`) e do app na loja.
5. **Público-alvo:** "para todos, uso supervisionado" (recomendado) ou direcionado a crianças?
6. **Monetização:** começar por Pro do professor (A) com limite gratuito (B)? Pagamento entre aluno e professor só como registro manual (C)?
7. **Ficha do aluno nova:** testar primeiro com o Vinícius?
8. **Quem testa** em aparelho real e quais aparelhos Android estão disponíveis?
9. **E-mail obrigatório para o professor** antes de vincular o primeiro aluno? (recomendo sim) E para o aluno: só com responsável quando menor?
10. **Enviar a chave por e-mail?** Recomendo **não** como regra (enviar o código da conta e o passo a passo); só como opção explícita.
11. **Faixa etária por seleção neutra** na primeira vez (recomendo) e **experiência reduzida para menores de 16**?
12. **Canal de suporte**: e-mail dedicado em domínio próprio (precisa comprar domínio), formulário no site, ou conversa dentro do app só?
13. **Aceite do professor** ao cadastrar aluno menor ("tenho autorização do responsável")?
14. **Juntar funções da Vercel** só quando faltar vaga (recomendo) ou já agora?
15. **Cópia das fichas do professor no servidor com 1 aparelho** (hoje só com 2+)? Aumenta custo e exige o consentimento claro de que os dados ficam na nuvem.
16. **Advogado:** quem contratar para revisar privacidade, termos, menores e o relatório de impacto antes do teste fechado?

### Respostas do Daniel (21/11/2026)
1. **Aba própria** para as dicas. 2. Usuário **não abre conversa**: pode **enviar um feedback de problema**, e o Daniel decide se abre conversa ou fecha. 3 e 4: pendentes (explicar). 5. **Para todos** (uso supervisionado). 6. A monetização é **do professor**, com **cota grátis de 2 alunos na agenda**. 7. Ficha nova testada com **Vinícius e Daniel Mingoranse**. 9. **Sim** (e-mail obrigatório ao professor antes do 1º aluno). 10. De acordo: **deixar claro em algum lugar como o fluxo funciona**. 11. **Sem** seleção de idade nem experiência reduzida; só **não pode ser professor quem é menor de idade**. 12. Suporte **dentro do app**. 13. **Não precisa** de aceite do professor. 14. **Juntar funções só quando faltar vaga**. 15 e 16: pendentes (explicar). **Cuidado extra com quem já está cadastrado** (migração sem impacto).

## 8. Como validar cada entrega (resumo)

| Tipo | Como |
|---|---|
| Lógica | `dart test` no núcleo; testes de API (`node --test`) |
| Tela | `node scripts/ui_tests.js`; captura em 390×844, 360×640 e tablet; modo claro e escuro; português e inglês |
| Texto e tradução | `check_i18n.js`, `check_text.js` (reduzir o teto aos poucos) |
| Contraste | novo script de contraste (Onda 3), roda no CI |
| Documentação | `gen_docs.js` e `check_docs.js`; atualizar `11_HISTORICO.md` e o guia do painel |
| Custo | `simulate_load.js` antes/depois; olhar a aba Custos |
| Aparelho real | lista de verificação em Android (Chrome e app) e iPhone; registrar o resultado no `MATRIZ_BOTOES.md` |
| Publicação | só com o "Sim, publicar"; liberar por chave (você → Vinícius → 10% → todos) |

## 9. O que **não** foi verificado nesta análise
- Funcionamento em **celular real** (Android e iPhone): só foi testado no navegador do computador e na emulação do painel.
- Quais lacunas da agenda (2.4) **já foram entregues**: depende de testar o app, não só de ler.
- Regras atuais da Google Play, do Banco Central e da LGPD: conhecimento até meados de 2026; **conferir antes de decidir**.
- O alinhamento do botão de validação (2.3): não reproduzido ainda.
- Preços dos serviços: os de 12/11/2026 que estão em `cost_model.js`.
- **Painel da Vercel** (chamadas, erros, duração e partidas a frio por função): não tenho acesso; a seção 2.14 usa a simulação do repositório.
- **Texto oficial do ECA Digital e dos decretos**: li resumos jurídicos e notícias; o artigo de um dos escritórios não abriu. Conferir os artigos citados e o cronograma de fiscalização.
- **Cobrança alternativa no Brasil** pelo Google: sem página oficial encontrada.
- **SDKs do app** quanto à política de Famílias (`mobile_scanner` e outros): citados para auditoria, **não auditados** ainda.

## 10. Fontes da pesquisa (consultadas em novembro/2026)

**Conferir sempre no texto oficial antes de decidir. Parte vem de resumos de terceiros; o que é de terceiros está dito no texto.**

- Google Play, política para Famílias (resumo do texto oficial): <https://support.google.com/googleplay/android-developer/answer/9893335?hl=en>
- Google Play, público-alvo e conteúdo do app: <https://support.google.com/googleplay/android-developer/answer/9867159>
- Play Age Signals API (documentação oficial): <https://developer.android.com/google/play/age-signals/use-age-signals-api> · notas de versão: <https://developer.android.com/google/play/age-signals/release-notes?hl=pt>
- Play, requisitos de **exclusão de conta**: <https://support.google.com/googleplay/android-developer/answer/13327111>
- Play, **teste fechado** para contas pessoais novas (12 testadores, 14 dias): <https://support.google.com/googleplay/android-developer/answer/14151465?hl=en> (a ajuda oficial; os resumos de terceiros divergem na data de corte, 1º ou 13/11/2023; vale a oficial)
- Play, novas regras de cobrança (taxa a partir de 10% no primeiro US$ 1 milhão, inclusive assinaturas): <https://android-developers.googleblog.com/2026/06/play-expanded-billing.html>
- ECA Digital, resumo jurídico: <https://confidata.com.br/blog/eca-digital-o-que-muda-empresas>; vigência e decretos: <https://www.band.com.br/nacional/sp/o-eca-digital-entra-em-vigor-e-redefine-as-regras-de-protecao-de-menores> · <https://canaltech.com.br/internet/pontos-para-entender-o-eca-digital-que-entra-em-vigor-nesta-terca-17/>
- Análise dos atos normativos do ECA Digital (DPBR): <https://www.dataprivacybr.org/wp-content/uploads/2026/03/DPBR_20260324_Analise-dos-atos-normativos-de-implementacao-do-ECA-Digital.pdf>
- Play e ECA Digital: <https://www.tecmundo.com.br/produto/414920-google-atualiza-play-store-com-base-no-eca-digital-entenda-o-que-muda.htm>
- Cobrança alternativa no Brasil (fontes de terceiros, **inconclusivas**): <https://www.pagbrasil.com/blog/markets/gaming/google-play-alternative-billing-in-brazil-a-guide-to-d2c-monetization-on-android/>

**Não consegui abrir** (acesso negado): o artigo do escritório Machado Meyer sobre o ECA Digital; por isso o resumo do ECA usa a consultoria Confidata e a imprensa. **Não encontrei**
uma página oficial do Google sobre cobrança alternativa **no Brasil**: a regra de pagamento da seção 3.6 está marcada "conferir".
