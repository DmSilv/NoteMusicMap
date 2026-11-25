# Regras de negócio

Cada regra diz **onde mora no código** e **onde está o teste**. Se mudar uma regra, mude o teste junto.

## 1. Identidade e vínculo
- **Perfil anônimo**: `Profile` (`afina_core/identity.dart`) tem `shareCode` (`XXXX-XXXX`), `secret` e apelido opcional. O código tem dígito verificador (7 sorteados + 1); `formatShareCode` valida. Teste: `identity` / `link_status`.
- **Reivindicar o código**: o primeiro `sync` com um segredo vira o dono (`HSETNX u:<código> h <hash>`); depois só quem tem o segredo passa. Segredo errado → 403 genérico (`Este código pertence a outro aparelho.`), sem revelar se o código existe.
- **Vínculo** (`link`/`unlink` em `api/link.js`): bilateral (`ut:` do professor e `us:` do aluno); limite de 300 vínculos por perfil. Ligar o **vínculo online** é opcional e reversível (Minha conta › Vínculo online: Reconectar, Desativar, Ativar). Desativar não apaga nada local.
- **Estado do vínculo em linguagem simples** (`link_status.dart`): `off`, `connecting`, `online`, `offline`, `serverDown`, com o texto "há quanto tempo" e o que fazer.
- **Recuperação**: a *chave de recuperação* (derivada do perfil) leva o perfil a outro aparelho. A **chave curta de 25 caracteres** (gerada em Minha conta › Chave de recuperação, verificada no servidor, sem depender de e-mail) é a chave principal; a longa antiga (`NM1-…`) continua funcionando. Opcionalmente, o **e-mail da conta** (sem senha, código de 6 dígitos) faz o mesmo: o aparelho que entra passa a ser **mais um aparelho da conta** (até **5** ao mesmo tempo; o dono vê a lista em Minha conta › Aparelhos e pode tirar qualquer um; com 5 já na conta, quem entra escolhe qual sai). Só o código de suporte do painel continua trocando tudo: o aparelho novo fica sozinho na conta. Os dois recuperam a identidade e os vínculos; o que ficou só no aparelho (anotações, histórico) não volta.
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
- **Lembrete**: 15 minutos antes por padrão (`kReminderMinutes`); com o recurso `lembrete_escolha` o professor escolhe por aula (seção 15). O servidor agenda no QStash só a **próxima** ocorrência; ao disparar (`/api/remind`) envia Web Push e agenda a seguinte (semanal).
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

## 12. Aula online (link da aula) — liberada por chave
Recurso `aula_online` (aba Recursos do painel; nasce desligado). Com ele ligado para o professor:
1. Cada aula e cada horário livre tem um modo: **Presencial** (padrão) ou **Online**. Online pode ficar **sem link** e o professor põe depois (menu da aula › Adicionar/Editar link da aula); o aluno é avisado da mudança como em qualquer alteração de aula.
2. **Link da sala:** só `https`, sem usuário e senha, sem espaços, com domínio de verdade, até 300 caracteres (mesma regra no app e no servidor). Sites conhecidos (Meet, Zoom, Teams, Whereby, Jitsi) abrem direto; qualquer outro mostra o endereço antes de abrir.
3. **Link padrão do professor** ("Guardar como link padrão" no formulário): aulas online novas já vêm com ele preenchido; um horário livre online publicado sem link usa o link padrão do professor no momento em que o aluno pega.
4. O aluno vê "Aula online", o botão **Entrar** na agenda e **Entrar na aula online** em Meu espaço. O app não cria a sala: o atalho "Criar sala no Meet" abre meet.new.
5. **Compatibilidade:** o modo (`m`: `p` ou `o`) e o link (`l`) são campos novos do horário. App antigo ignora; se um app antigo (ou o recurso desligado) editar uma aula online, o servidor **mantém** o modo e o link que já estavam guardados. O painel de suporte **não mostra** o link da aula.

## 13. Controle da agenda do professor (remarcar, trocar, pausar)
Tudo no menu de cada aula da agenda e no botão de pausa da barra, sempre com confirmação que diz quem é avisado. As regras ficam em `packages/afina_core/lib/agenda.dart` (`planMoveOccurrence`, `planSwap`, `planPause`, `validatePlan`) e valem **de uma vez só**: se uma das mudanças não couber (choque com outra aula, horário no passado, limite de datas canceladas), **nada muda**.
1. **Remarcar só esta aula** (regra semanal): aquela data é cancelada e nasce uma aula avulsa no horário novo, com o mesmo aluno, duração, observação, modo, link e lembrete. Numa aula avulsa, "Editar" já muda o horário.
2. **Trocar horário com outro aluno:** cada aula vai para o horário da outra (a duração de cada uma continua a sua); aulas de regra semanal viram avulsas só naquela data. Mesma aula ou mesmo aluno é recusado. Vale para as aulas das próximas 3 semanas.
3. **Pausar** (férias, viagem): as datas do período são canceladas nas regras semanais (que voltam depois) e as aulas avulsas do período são canceladas. No máximo 120 dias por vez e até 30 datas canceladas por regra.
4. **Trocar o aluno de uma aula:** em Editar, com 2 ou mais alunos, o campo Aluno pode ser trocado; o servidor tira a aula do aluno anterior e ele é avisado.
5. **Correção:** ao mudar o dia ou a hora de uma regra semanal, as datas já canceladas acompanham a mudança (antes guardavam o horário antigo e a aula cancelada podia voltar a aparecer).

## 14. Tutoriais e "Comece por aqui"
1. **Nunca obrigatórios.** Nada abre sozinho na primeira vez e tudo tem "Pular". Só aparecem para o professor (o aluno não vê o cartão).
2. **Comece por aqui** (Meu espaço, visão de professor): três passos, calculados do que já existe no aparelho: vincular um aluno (vínculo ativo), marcar uma aula, passar uma tarefa. Mostra o progresso, leva a cada passo, some sozinho quando tudo foi feito e pode ser escondido ("Esconder"). Lógica pura em `packages/afina_core/lib/start_checklist.dart`.
3. **Ver como funciona:** tutorial com a tela escura e um buraco no botão (`lib/ui/tour/tour.dart`): Comece por aqui, Agenda completa, Horários livres, Seus alunos. Na agenda do professor, o "?" da barra mostra Marcar aula e Pausar aulas. Se um botão não estiver na tela, o passo é pulado.
4. **Só no aparelho:** o que foi visto/escondido fica em `tours_seen` e `start_hidden` (nada vai ao servidor, custo zero). Ajustes › Sobre o app › **Rever tutoriais** zera os dois.

## 15. Lembrete escolhido pelo professor — liberado por chave
Recurso `lembrete_escolha` (aba Recursos; nasce desligado). Com ele ligado para o professor, o formulário de **Marcar aula** e o de **Novo horário livre** ganham o campo **Lembrete para os dois** (um modal com as opções):
1. **Opções** (`kRemindOptions` no núcleo = `REMIND_OPTIONS` no servidor; um teste confere que são iguais): sem lembrete, 5, 10, **15 (padrão)**, 30 minutos, 1 hora, 2 horas e 1 dia antes. Qualquer outro valor é ignorado.
2. **Vale para os dois:** o professor e o aluno recebem o aviso no tempo escolhido para aquela aula (o aluno não escolhe). Em horário livre, a aula que nasce quando o aluno pega herda a escolha. Remarcar só um dia mantém a escolha na aula avulsa.
3. **Última escolha:** o app lembra a última antecedência usada (neste aparelho) como ponto de partida das aulas novas. Ao editar, mostra a antecedência que a aula realmente tem.
4. **Sem lembrete (0):** nada é agendado no QStash para aquela aula.
5. **Texto da notificação:** montado no aparelho (`web/sw.js`) pelo tempo que realmente falta: "Aula em 30 minutos", "Aula em 2 horas", "Aula amanhã" (um aviso agendado para já, porque a aula está perto, não mente o tempo).
6. **Compatibilidade:** campo novo `r` (minutos) no horário. Sem `r` vale 15, como sempre. Sem a chave, o servidor ignora o `r` que chegar e **mantém** o que já estava guardado; app antigo editando uma aula também mantém. Voltar a 15 com o recurso ligado grava `r=15` (não ressuscita um valor antigo). Mudar a escolha troca o `u` da aula, então o aviso antigo já agendado é ignorado quando disparar.
7. **Custo:** zero comandos a mais no Redis; no máximo uma mensagem no QStash por aula e ocorrência, como antes (menos, se for "sem lembrete").

## 16. Aluno faltou (falta registrada pelo professor)
Só neste aparelho, na ficha do aluno (`Student.absences`, `packages/afina_core/lib/absence.dart`; arquivo antigo sem faltas continua abrindo). O botão **Aluno faltou** fica ao lado de **Começar a aula** na ficha; na agenda aparece **Aluno não veio** no cartão da aula perto da hora (a partir de 15 min antes) e depois dela começar.
1. **Qual aula:** a de hoje mais perto de agora (entre 3 h atrás e 12 h à frente). Sem aula marcada, só registra (no início do dia).
2. **Três caminhos:** *Faltou, sem avisar* (só registra; a aula continua na agenda), *Avisou que não vem* (registra e cancela só a aula de hoje, e o aluno é avisado como em qualquer cancelamento) e *Quer remarcar* (abre o remarcar e só registra se a aula foi mesmo remarcada).
3. **Sem duplicar:** registrar de novo a mesma aula troca o registro. Guarda as 200 mais recentes.
4. **Onde aparece:** "N faltas registradas · última em dd/mm" no cartão **Aula** da ficha, com **Desfazer última** (engano), e uma marca "N faltas" (últimos 60 dias) no cartão do aluno na lista.
5. **Fora do escopo por enquanto:** o aluno não vê as faltas; reposição ainda é remarcar à mão.

## 17. Tela de Alunos
Lista agrupada do mais urgente ao resto: **Aula hoje**, **Para validar** e **Todos os outros** (cada aluno aparece uma vez; sem os dois primeiros grupos, a lista vem sem título). O botão **Novo aluno** é flutuante e sempre visível; **Ler QR**, **Importar**, **Meus métodos e lições** e **Senha desta tela** ficam no menu do topo.

## 18. Metrônomo: volume e "Acelerar aos poucos"
**Volume.** O que se escuta como volume é a **energia** do som, não o pico: um clique curto tem pico alto e energia baixa. Por isso os cinco sons têm corpo mais longo (até ~80 ms), harmônicos acima de 300 Hz (o alto-falante do celular quase não reproduz o grave do "tambor"), uma saturação suave que enche o sinal sem passar de 1,0, e as batidas fracas soam quase tão alto quanto a forte (o "um" continua mais agudo). O volume padrão é o máximo. Medido com `packages/afina_core/tool/metro_loudness.dart` (energia pela curva A): média de **−22,5 dB para −13,1 dB (+9,4 dB, cerca do dobro do que se escuta)**. Testes em `metronome_engine_test.dart` ("volume: o metrônomo soa ALTO") impedem voltar atrás.

**Acelerar aos poucos** (card na tela do metrônomo; ajustes pelo botão **Ajustar**):
1. **Quando aumentar:** por **tempo** (15 s, 30 s, 1 min, 2 min) ou por **compassos** (2, 4, 8, 16). O aumento sempre entra no começo de um compasso.
2. **Quanto aumentar:** +1, +2, +5 ou +10 BPM. **Até quantos BPM:** teto com − e + de 5 em 5 e atalhos (BPM atual +20, +40, +60), limitado a 40–320.
3. **Resumo em frase** antes de começar: "Começa em 100 BPM. A cada 30 segundos sobe 5 BPM, até 140 BPM. Chega lá em cerca de 4 min." Se o teto for menor ou igual ao BPM de partida, o resumo avisa.
4. **Ao vivo:** o BPM grande mostra o que está tocando agora ("partiu de 100"), o card mostra "+10 BPM em 55 s" (ou "no próximo compasso"), uma barra até o próximo aumento e outra até o teto; ao chegar, "Chegou ao teto".
5. A contagem só começa depois da contagem inicial. Mexer no BPM ou nos ajustes com o metrônomo tocando recomeça do BPM da tela. O último jeito escolhido fica no aparelho (padrão: por tempo, a cada 30 s, +5 BPM, teto = BPM + 40).

## 19. Agenda com o professor no comando (24/11/2026)
Princípio: **o professor decide; o aluno informa e pede.** Nada que o aluno faz muda a agenda do professor sem o professor decidir. A única exceção é pegar um horário que o próprio professor deixou livre, e mesmo aí ele escolhe o freio. Estudo e decisões: `docs/AGENDA_ESTADO_E_PLANO.md`.
1. **Quem pode o quê.** Professor: marcar, editar, cancelar, remarcar, trocar, pausar, abrir horários livres e decidir o que cada aluno pode. Aluno: ver, entrar na sala, avisar o professor, pegar ou pedir horário livre (se o professor deixar) e desfazer o que acabou de pegar. O aluno **nunca** edita, cancela ou remarca uma aula.
2. **"Eu confirmo antes"** (campo `cf` do horário livre). Com ele ligado, o aluno faz um **pedido** (`avail_take` com `cv:2`) e o professor aceita ou recusa na agenda (`req_answer`); a aula só nasce na aceitação. O horário semanal já vem com "confirmo antes" ligado no formulário (compromisso toda semana); o avulso vem desligado (quem pega primeiro leva, como antes). No máximo **3 pedidos** esperando por aluno e professor. App antigo recebe `needs_update` e nada é criado. Aceitar um pedido recusa os outros do mesmo horário.
3. **Desfazer do aluno** (`pick_undo`): até **10 minutos** depois de pegar, enquanto o professor não mexeu na aula. O horário volta para a lista e a aula é marcada como cancelada nos dois lados.
4. **"Pegar horário" por aluno** (`pick_allow`, marca `np` no vínculo): o professor desliga para um aluno; ele não vê horários livres (`off`) e `avail_take` responde `pick_off`.
5. **Avisos do aluno** (`warn_put`): "Não vou conseguir ir", "Queria remarcar" ou "Vou me atrasar", com opções prontas (sem texto livre) sobre uma aula real e futura. Um aviso por aula e data, **3 por dia** por aluno. O professor responde com um toque (`warn_answer`): *Falta justificada* (registra a falta na ficha, tipo "avisou"), *Remarcar* (abre o remarcar) ou *Ignorar*. Aviso com menos de 24 h vem marcado "em cima da hora". O professor pode **silenciar** os avisos de todos (`warn_global`) ou de um aluno (`warn_mute`, marca `wm`); o aluno recebe "este professor não recebe avisos por aqui". Aluno pausado não avisa.
6. **Caixas.** Professor: `t_inbox` (pedidos + avisos), consultada quando o contador `ar` muda ou ao abrir a agenda. Aluno: `s_inbox` (respostas), só quando há pedido ou aviso esperando. Respostas ficam 7 dias.
7. **Desfazer do professor.** Cancelar, cancelar uma data, marcar/editar, remarcar, trocar, pausar e cancelar as aulas futuras de um aluno guardam a agenda anterior; um aviso com "Desfazer" aparece por 8 s e o estado vale por 2 min. Restaurar sobe a versão (`u`) para os alunos receberem de volta.
8. **Histórico da agenda** (só no aparelho do professor, até 100 linhas): o que mudou e quem mudou, incluindo pedidos e avisos dos alunos.
9. **Data final** (`e`, só aula semanal, até 5 anos): a última aula é a que começa até essa data (núcleo e servidor calculam igual). **Fuso** (`z`, minutos para o UTC, múltiplo de 15): o app do aluno mostra "No fuso do professor: 19:00 (UTC-3)" quando difere do fuso do aparelho.
10. **Calendário do celular:** arquivo `.ics` gerado no aparelho (`agenda_ics.dart`), sem servidor; baixa na web e compartilha no celular.
11. **Compatibilidade.** `cf`, `z` e `e` são opcionais: app antigo ignora, e se um app antigo editar a aula o servidor **mantém** os valores guardados (o app novo sempre envia `cf` e `e`, com 0 para apagar). Chaves novas: `pq:` (pedidos), `pw:` (avisos), `pa:` (respostas), apagadas ao encerrar o vínculo e ao excluir a conta.
12. **Ao desativar um aluno** o app pergunta se cancela as aulas futuras dele.
13. **Controle do aluno** (ficha › Controle do aluno): dois interruptores, "Pode pegar horários livres" e "Recebo os avisos dele". **Controle da agenda** (Agenda › Controle da agenda): avisos de todos, guia "Qual escolher?", histórico e calendário.
14. **Explicações dentro do app:** "Como funciona a sua agenda" (aluno), "Qual escolher?" (professor: cancelar, remarcar, trocar, pausar, desativar, encerrar) e "Como funciona a sua conta" (Minha conta: código, o que fica no celular, chave, aparelhos). O primeiro vínculo sem chave guardada gera um aviso no sino, uma vez.

## 20. Treinador (IA) fechado até a pessoa estudar (24/11/2026)
O treinador (Gemini, ChatGPT e os outros serviços do servidor) custa e tem limite grátis, então não abre para quem acabou de entrar.
1. **Abre com 60 minutos de estudo somados** (`coachGate`, `kCoachUnlockMinutes` em `packages/afina_core/lib/coach_gate.dart`): vale qualquer ferramenta do app (afinador, escalas, metrônomo, grade). Antes disso o cartão "Seu treinador" mostra "Estude mais N min" e a aba Treinador mostra a barra de progresso e as **Dicas de hoje** (calculadas no aparelho, sem IA). Quem já tinha plano, histórico ou resposta guardados continua com o treinador aberto.
2. **Relatório do professor com IA** (ficha do aluno) só com **3 sessões** de exercício do aluno (`kReportMinSessions`).
3. **Perguntas que giram, sem texto livre.** O banco tem 21 perguntas em 4 temas (escalas, afinação, rotina, aula). O app mostra **3 por dia**: as mesmas no mesmo dia, outras no dia seguinte, evitando as feitas nos últimos pedidos e misturando temas. Sem exercícios gravados não oferece as de "as minhas notas"; sem professor não oferece as de aula (`pickCoachQuestions`).
4. **O servidor só aceita pergunta da lista.** O app manda o `qid`; o servidor monta o texto (`api/_lib/coach_questions.js`) e descarta qualquer pergunta que veio no resumo. Pergunta fora da lista é recusada (400). Apps antigos continuam funcionando só com as 3 perguntas antigas. Um teste confere que os ids do servidor e do app são os mesmos.
5. **Escopo fechado nos prompts** (todos os tipos): só estudo de instrumento de arco; assunto de fora, pedido para mudar regras, revelar instruções ou assumir outro papel faz a IA responder só `FORA_DO_ESCOPO`, e o servidor devolve 422 com uma explicação (o pedido já conta no limite). Sem links, sem código, sem dados pessoais, sem diagnóstico de dor ou lesão. A resposta ainda passa por uma limpeza que tira links e blocos de código.
6. **Limites que continuam:** 5 pedidos por dia por aparelho, intervalo entre pedidos, limite global do dia e fila.

## 21. Lembrete de estudo automático (25/11/2026) — liberado por chave
Recurso `lembrete_estudo` (aba Recursos; nasce desligado; libere para o **aluno**, por código ou para todos). Fica só entre o sistema e o aluno: **o professor não vê nada** (nem se o aluno abriu o app, nem se recebeu lembrete). Código: `api/_lib/nudge.js`, testes `api/nudge.test.js`.
1. **Quem pode receber:** quem ligou as notificações no aparelho. Quem só ensina não recebe.
2. **Quando:** a conferência é marcada para 2 dias à frente, às **18h** no fuso da pessoa. Na hora, se ela está há cerca de 2 dias sem abrir o app, recebe um lembrete ("Que tal 10 minutos na tarefa de {professor} hoje?", ou sem o nome se há zero ou vários professores).
3. **Quem não precisa não recebe:** usou o app em **3 dias ou mais** na última semana, ou abriu há pouco: nada é enviado.
4. **Freios:** no máximo **2 por 7 dias**; depois de **3 ignorados** o sistema para e só volta a conferir quando a pessoa abrir o app de novo.
5. **Desligar:** interruptor "Lembrete de estudo" no cartão de lembretes (agenda). Vale no servidor (`nudge_set`, campo `ngz`).
6. **Convite na hora certa:** o aluno que já recebeu uma aula e não ligou as notificações vê "Quer um lembrete da tarefa?" no Meu espaço (uma vez; no iPhone explica como instalar o app).
7. **Custo:** uma mensagem no QStash a cada 2 ou 3 dias por pessoa com notificação ligada (o plano grátis tem 1.000 por dia, divididas com os lembretes de aula) e poucos comandos no Redis. Abrir o app com a conferência já marcada não gasta nada. Não há varredura do banco.
8. **Lembrar no WhatsApp (professor):** botão na ficha do aluno com mensagem pronta (tarefas em aberto); abre o WhatsApp e quem escolhe o contato e envia é o professor. Não usa servidor nem notificação.

## 22. WhatsApp do aluno, empurrãozinho e programação (25/11/2026)
Núcleo em `student_reminder.dart` (teste `student_reminder_test`).
1. **Número.** Opcional, preenchido pelo professor na folha "Lembrar" (DDD + número ganha o 55; outro país começa com +). Fica **só no aparelho do professor**: não vai ao servidor, à cópia entre aparelhos, à cópia na nuvem, ao "Copiar dados" nem aos relatórios com IA. Em outro aparelho é preciso digitar de novo.
2. **Aviso ao aluno.** Ao guardar o número de um aluno vinculado, o app manda ao servidor só a **marca** (`contact_note`, campo `wa` no vínculo), e o aluno recebe no sino "{professor} guardou o seu WhatsApp para mandar lembretes de estudo...".
3. **O app não envia WhatsApp sozinho.** Ele escolhe uma mensagem amigável (três opções, com o nome e até três tarefas em aberto), abre a conversa (`wa.me`) e o professor envia. Envio automático pelo WhatsApp exigiria a API paga do WhatsApp Business (empresa verificada, modelos aprovados, número no servidor); não usamos robôs, que quebram as regras do WhatsApp.
4. **"Um empurrãozinho pode ajudar"** (Meu espaço do professor e lista de alunos): usa só o que o professor já vê. Entra quem (a) está num **dia programado**; (b) tem tarefa em aberto há **3 dias** ou mais sem marcar nenhuma nesse período; (c) **compartilha** o estudo e fez menos de **20 min** na semana (a partir de quarta). Não olha se o aluno abriu o app. Desativado fica fora; quem foi lembrado descansa **3 dias**.
5. **Programar:** dias da semana por aluno. No dia, o aluno aparece na lista como "Hoje é dia de lembrar" e o professor recebe um aviso no sino ao abrir o app (uma vez por dia). Não há notificação no celular do professor para isso.
