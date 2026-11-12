# Regras de negócio

Cada regra diz **onde mora no código** e **onde está o teste**. Se mudar uma regra, mude o teste junto.

## 1. Identidade e vínculo
- **Perfil anônimo**: `Profile` (`afina_core/identity.dart`) tem `shareCode` (`XXXX-XXXX`), `secret` e apelido opcional. O código tem dígito verificador (7 sorteados + 1); `formatShareCode` valida. Teste: `identity` / `link_status`.
- **Reivindicar o código**: o primeiro `sync` com um segredo vira o dono (`HSETNX u:<código> h <hash>`); depois só quem tem o segredo passa. Segredo errado → 403 genérico (`Este código pertence a outro aparelho.`), sem revelar se o código existe.
- **Vínculo** (`link`/`unlink` em `api/link.js`): bilateral (`ut:` do professor e `us:` do aluno); limite de 300 vínculos por perfil. Ligar o **vínculo online** é opcional e reversível (Minha conta › Vínculo online: Reconectar, Desativar, Ativar). Desativar não apaga nada local.
- **Estado do vínculo em linguagem simples** (`link_status.dart`): `off`, `connecting`, `online`, `offline`, `serverDown`, com o texto "há quanto tempo" e o que fazer.
- **Recuperação**: a *chave de recuperação* (derivada do perfil) leva o perfil a outro aparelho.
- **Bloqueio** (administrador): perfil com `bl=1` recebe 403 `blocked` em todo o vínculo online.

## 2. Papéis e visões
- **Todos começam como aluno**; "Modo professor" é uma capacidade (`profile.teacher`). Não existe conta de professor.
- **Lado de aluno** (`AppState.hasTeacherSide`): tem professor, aula recebida ou agenda marcada por professor.
- **Visões do Meu espaço** (`afina_core/hub_view.dart`, teste `hub_view_test`):
  - Alternador **Aluno | Professor** só para quem tem os dois papéis (`canSwitchHubView`); a escolha é guardada (`hub_view`). Sem escolha → Professor.
  - Cada visão tem seus blocos e ferramentas; **nenhum destino aparece duas vezes na mesma tela**, e a visão do aluno nunca mostra destino do professor (e vice-versa). No máximo 2 blocos.
  - Avisos do hub filtram por visão (`kNoticeKindsByView`); o sino mostra todos.
- **Destaque** (`hub.dart`): ongoing (aula em andamento) → soon (≤15 min) → next → none → noTeacher. Os botões do destaque **não repetem** a agenda: levam à ficha da aula ou ajudam a começar.

## 3. Tarefas, "fiz" e status oficial
O **professor é a fonte oficial** do status. O aluno só **sinaliza**.
1. Professor encerra a aula (`lesson`) → tarefas vão ao aluno (`lr` do aluno muda).
2. Aluno marca "fiz" (`done`, guardado em `dn:<professor>`; `dr` do professor muda). Localmente: `lessonTasksDone`.
3. Professor vê em "para validar" (`awaitsValidation` = marcada e não concluída) e decide:
   - **Validar** (`Verdict.ok`) → `done = true`.
   - **Devolver** (`Verdict.back`) → tira a marca; a tarefa volta a pendente; o servidor também derruba o "fiz" do aluno (senão ela voltaria sozinha).
4. A decisão vai ao aluno (`verdict` → `vd:<aluno>`, `vr` muda; o aluno busca `verdicts`). No aluno (`studentTaskState`): `pending`, `claimed` (aguardando o professor), `validated`, `returned`. Marcar de novo uma devolvida remove a decisão antiga localmente.
- **Resumo ao começar a aula** (`summarizeTasks`): para validar · pendentes · concluídas; **nunca bloqueia** a aula.
- Onde: `afina_core/task_status.dart`, `teacher.dart` (`applyClaims`, `validateTask`), `app_state.dart` (`validateAssignment`, `pullVerdicts`, `flushVerdicts`). Testes: `task_status_test`, `lesson_test`, `api/link.test.js`.

## 4. Aulas e agenda
- **Aula marcada** (`ClassSlot`): início, duração (15–240 min), semanal ou única, ocorrências canceladas (`skipped`, até 30), observação, versão (`updatedMs`). Uma regra semanal é **uma** entrada.
- **Conflito** (`findConflict`): duas aulas do professor não podem se sobrepor (olha 120 dias à frente). Aula no passado não pode ser criada.
- **Lembrete**: 15 minutos antes (`kReminderMinutes`). O servidor agenda no QStash só a **próxima** ocorrência; ao disparar (`/api/remind`) envia Web Push e agenda a seguinte (semanal).
- **Fase da aula** (`class_rules.dart`, teste `class_rules_test`): `upcoming`, `soon` (≤15 min), `ongoing`, `finished`.
- **Permissões** (`classPermissions`): aluno só vê. Professor: antes de começar edita e cancela; "em breve" também pode começar; **em andamento** só ajusta; **encerrada** é histórico (sem menu).
- **Agenda visível** (`visibleTeacherSlots`): sem canceladas e sem aulas de aluno que o professor já não tem. Hub e agenda usam a mesma lista (`visibleAgenda`), nunca divergem.
- Duas agendas, com rótulos explícitos: **Agenda do professor** (aulas que ele marca) e **Agenda do aluno** (aulas que o professor marcou para ele).

## 5. Horários livres
- Professor publica `ClassSlot`s como "livres" (`avail_put`, até **100**). O aluno vinculado vê só os que ainda dá para pegar (`avail`) e **pega** (`avail_take`).
- **Primeiro que pegar leva**: trava `HSETNX tk:<professor> <idHorário> <aluno>`; o outro recebe 409 (`slot_taken`/`slot_gone`). A aula nasce nos dois lados e o professor é avisado (`ar` → `picks`).
- **Regras** (`open_slots.dart`, teste `open_slots_test` e `api/avail.test.js`): não pegar horário passado, nem com menos de **60 min** de antecedência, nem que bata com outra aula do professor; **12** aulas por aluno com o mesmo professor.
- Semanal: quem pegar fica com o horário **toda semana** (vira aula semanal). Desvincular libera a trava daquele aluno.
- O professor ainda pode mover/cancelar a aula na agenda.

## 6. Avisos
- Tipos (`kNoticeKinds`): `teacher` (um professor te adicionou), `lesson` (aula/agenda nova), `task` (decisão do professor), `done` (aluno marcou tarefa), `pick` (aluno pegou horário).
- Central de avisos (sino): lista, marca como lidos, limpa, toca → vai ao lugar certo (`openNoticeTarget`). Máximo de 20 guardados.
- Aviso curto no topo (toast) aparece no máximo a cada poucos segundos; repetição do mesmo erro não avisa de novo.

## 7. Erros
- **Catálogo único** (`errors.dart`, [referencia/ERROS.md](referencia/ERROS.md)): cada código tem gravidade, título, frase e ação.
- **Captura**: `FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`, `ErrorWidget.builder` (release). Só a **falha ao abrir** (`APP-99`) vira tela cheia; o resto vira aviso + registro, para um erro pequeno nunca esconder o app.
- **Registro local** (`ErrorLog`, 20 itens; o mesmo problema em sequência vira uma linha com contagem). Código curto `E-XXXX` estável por problema.
- **Higienização** (`sanitizeDetail`): tira códigos de perfil, e-mails, segredos, endereços (fica o domínio), números longos e invisíveis. Tudo no app **e** de novo no servidor.
- **Envio** (`ReportMode`): "Só os graves" (padrão), "Todos os erros" (menos conexão), "Nunca"; o envio manual ("Enviar relatório") sempre existe. Freio: o mesmo problema a cada 10 min, 20 por sessão.
- **Trilha** (`Breadcrumbs`, 10 passos): só nomes fixos de telas e ações, nunca conteúdo.
- **Reabertura**: bug "resolvido" volta a "reaberto" só se vier de uma **versão publicada depois** da correção.

## 8. Entrada de dados (guardrails de texto)
Tudo que a pessoa digita, cola ou lê de QR passa por `input_guard.dart` (`cleanText`, `stripUnsafe`): remove controle e caracteres invisíveis, limita tamanho (`kMaxName` 60, `kMaxTitle` 80, `kMaxLine` 160, `kMaxNote` 500, `kMaxQr` 300…). O servidor repete a limpeza (`cleanSlot`, `cleanLesson`, `sanitize`).

## 9. Limites (resumo)
| O quê | Limite | Onde |
|---|---|---|
| Vínculos por perfil | 300 | `api/link.js` |
| Aulas guardadas por aluno | 60 | `LESSONS_KEPT` |
| Aulas marcadas por professor | 400 | `MAX_SLOTS` |
| Horários livres por professor | 100 | `MAX_AVAIL` |
| Aulas de um aluno com o mesmo professor | 12 | `MAX_PICKS` |
| Antecedência mínima para pegar horário | 60 min | `PICK_LEAD` |
| Marcações/decisões guardadas | 1500 | `DONES_KEPT` |
| Aparelhos com notificação por perfil | 4 | `MAX_DEVICES` |
| Consultas/h por perfil | 240 | `PULLS_PER_HOUR` |
| Alterações/h por perfil | 60 | `MUTATIONS_PER_HOUR` |
| Tentativas erradas/h por origem | 20 | `BAD_AUTH_PER_HOUR` |
| Perfis novos por origem/dia | 100 (aviso no painel acima de 30) | `NEW_PROFILES_PER_DAY`, `NEW_PROFILES_ALERT` |
| Relatórios de erro por aparelho/h · por dia | 10 · 150 (`ERRORS_DAILY_CAP`) | `error_store.js` |

## 10. Quando nasce um cadastro (regra de perfis)
1. **Visitante não cria nada.** Quem só usa as ferramentas tem o código só no aparelho; o vínculo online vem desligado e o servidor não é chamado.
2. **O perfil nasce na primeira chamada do vínculo**, que só acontece com intenção: modo professor (exige apelido e confirmação), ler QR ou digitar código de professor (exige apelido), adicionar aluno com código, ou ligar o vínculo à mão.
3. **Limite por origem:** 100 perfis novos por dia; acima de 30 o painel mostra o aviso "Origens com muitos cadastros" (escola ou igreja com um Wi-Fi só é normal). Barrar é a exceção.
4. **Limpeza:** perfil sem vínculo, sem professor nem aluno, sem horários nem notificações e parado há 60 dias é apagado (`api/_lib/sweep.js`), aos poucos, quando nasce outro perfil, e sob pedido no painel (Saúde do uso › Limpar agora). Quem tem qualquer vínculo ou bloqueio nunca é apagado.

## 11. Acervo e repertório do professor (só links, só teste)
1. **Só links:** título, autor, pasta, endereço e para quem é. O app não guarda nem copia arquivo nenhum (Drive, Dropbox, OneDrive, IMSLP, CPDL e YouTube, só `https`; lista em `api/_lib/library.js` e `packages/afina_core/lib/library.dart`, mantenha as duas iguais).
2. **Liberado por chave:** a aba Recursos do painel (lista de códigos, parte dos usuários ou todos) e, como ponto de partida, os códigos em `LIBRARY_TESTERS` (variável da Vercel; vazio = ninguém). O servidor recusa todo o resto (`library_off`); esconder o botão no app não basta.
3. **Quem vê:** o professor vê tudo; o aluno vinculado vê o que é para todos ou para ele. Vínculo encerrado = acesso encerrado.
4. **Declaração:** cada item só salva se o professor marcar que tem o direito de compartilhar (domínio público, dele ou autorizado).
5. **Denúncia e moderação:** o aluno pode denunciar; no painel (Pessoas › Acervo) o administrador esconde o item dos alunos. Remoção em até 48 h.
6. **Tarefa "Material do professor":** a tarefa carrega só o texto (título e pasta) e o aluno abre o acervo já filtrado; não gasta nada além da própria tarefa.
7. **Limites:** 200 itens por professor, link até 500 caracteres, 40 alunos por item.
