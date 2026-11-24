# Agenda: o que existe, o que falta e como explicar no app

Data: 24/11/2026. Levantamento do código (`packages/afina_core/lib/agenda.dart`, `lib/ui/agenda_*.dart`, `slot_form_page.dart`, `open_slots_page.dart`, `api/link.js`) e das regras em `03_REGRAS_DE_NEGOCIO.md` (seções 4, 5, 12, 13, 15, 16). Só estudo: nada foi alterado no app.

## 1. O que existe hoje

**Modelo.** Uma aula marcada (`ClassSlot`) tem aluno (por código), início, duração (15 a 240 min), se repete toda semana, datas canceladas só naquele dia (`skipped`, até 30), observação, modo (presencial ou online), link da sala, lembrete (`remindMin`) e versão (`updatedMs`). Uma regra semanal é uma entrada só. O servidor guarda até 400 aulas por professor.

**Professor.**
| Ação | Onde | Observação |
|---|---|---|
| Marcar aula (única ou toda semana) | Agenda › Marcar aula | Aluno, dia, hora, duração, observação, modo, link, lembrete |
| Editar, cancelar | Menu da aula | Só antes de começar; trocar o aluno da aula é permitido |
| Remarcar só esta data | Menu da aula | A data vira aula avulsa; o resto da regra continua |
| Trocar horário com outro aluno | Menu da aula | Vale para as próximas 3 semanas |
| Pausar (férias, viagem) | Botão na barra | Até 120 dias por vez; datas canceladas, regra volta depois |
| Aluno faltou | Ficha do aluno e cartão da aula | Falta sem avisar, avisou que não vem, quer remarcar |
| Horários livres | Agenda › Horários livres | Até 100; o aluno pega, quem pega primeiro leva |
| Link padrão da aula online | Formulário da aula | Reaproveitado nos horários livres |
| Conflito | Automático | Duas aulas do professor não se sobrepõem (120 dias à frente) |
| Ajuda | "?" da barra | Tutorial com 2 passos: Marcar aula e Pausar |

**Aluno.**
| Ação | Onde | Observação |
|---|---|---|
| Ver aulas marcadas | Agenda do aluno (calendário do mês e lista do dia) | Só leitura |
| Entrar na aula online | Botão "Entrar" | Aparece quando há link |
| Pegar horário livre | Pegar horário | 60 min de antecedência mínima; 12 aulas por professor; não bate com aula do professor nem (novo) com aula de outro professor dele |
| Lembrete | Automático | Notificação no tempo escolhido pelo professor (recurso liberado por chave) |
| Avisos de mudança | Sino e push | Aula nova, remarcada, cancelada |

**Servidor.** Lembretes por QStash (uma mensagem por aula e ocorrência), trava de horário com `HSETNX`, versão por aula (um pedido atrasado não desfaz o mais novo), aviso `clash` quando o aluno já tem aula com outro professor no mesmo horário.

## 2. Usos reais e como a agenda atende

| Situação | Atende? | Falta |
|---|---|---|
| Professor individual, aula semanal fixa | Sim | |
| Aula avulsa e remarcação de um dia | Sim | |
| Férias e viagem do professor | Sim | |
| Aula online com link | Sim | O app não cria a sala (abre o Meet) |
| Aluno quer cancelar ou remarcar | **Não** | Aluno só vê. Hoje resolve por fora (WhatsApp) |
| Aluno confirma presença ("vou") | **Não** | Professor não sabe se o aluno viu |
| Reposição de aula faltada ou cancelada | Parcial | Remarcar à mão; sem saldo de reposições |
| Aula em grupo ou turma | **Não** | Uma aula tem um aluno só. As turmas existem na lista, mas não na agenda |
| Aluno com dois professores | Sim (agora) | Conflito checado; falta ver as duas agendas juntas com cores |
| Escola com vários professores | Parcial | Cada professor tem a sua agenda; não há visão da escola nem sala compartilhada |
| Fuso horário (aluno em outra cidade ou país) | **Não** | Horários em UTC convertidos para o aparelho; falta mostrar "horário de Brasília" quando os fusos diferem |
| Calendário do celular (Google, Apple) | **Não** | Sem exportar para o calendário (`.ics`) |
| Aula com fim (ex.: até dezembro) | **Não** | A regra semanal não tem data final |
| Aluno desativado | Sim (novo) | Aulas futuras dele continuam na agenda até o professor cancelar |
| Aula experimental ou aula única de teste | Parcial | Sem tipo de aula (experimental, reposição, avulsa) |
| Histórico das aulas dadas e faltas | Parcial | Faltas só no aparelho do professor |

## 3. Decisões que confundem o usuário e onde estão explicadas hoje

| Decisão | Opções que o app oferece | Explicação hoje |
|---|---|---|
| Aula de um dia: cancelar, remarcar ou trocar? | Cancelar, Remarcar só esta, Trocar com outro aluno | Só o texto da confirmação |
| Parar as aulas: pausar, desativar o aluno ou encerrar o vínculo? | 3 caminhos diferentes | Texto de cada diálogo, mas nada compara os três |
| Marcar eu ou deixar horários livres? | Marcar aula, Horários livres | Passos do tutorial do professor |
| Aula única ou toda semana? | Interruptor "toda semana" | Tutorial |
| Online ou presencial? Link agora ou depois? | Modo no formulário | Texto do formulário |
| Aluno faltou: sem avisar, avisou ou quer remarcar? | 3 botões | Texto da folha |
| Aluno: o que posso fazer na agenda? | Nada além de ver e pegar horário | **Nada explica** que o aluno não remarca sozinho |

O professor tem tutorial ("?"). **O aluno não tem nenhum**, e é ele que mais se perde ("e se eu não puder ir?").

## 4. Proposta (ordem de valor, custo e risco)

**Etapa 1. Explicar o fluxo dentro do app (sem servidor, sem custo).**
1. "Como funciona" também na agenda do aluno: o que o professor marca, como pegar horário, o que acontece quando o professor muda ou cancela, como entrar na aula online.
2. Um guia de decisão no professor ("Parar as aulas?": Pausar = período curto e todos; Cancelar uma data = um dia; Desativar aluno = ele sai do dia a dia e não conta no limite; Encerrar vínculo = fim da relação). Um modal curto, aberto por um "Qual escolher?" nos três lugares onde essas ações aparecem.
3. Texto fixo no calendário vazio explicando o próximo passo (professor: "Marque a primeira aula"; aluno: "Peça ao professor ou pegue um horário livre").
4. Atualizar os tutoriais (Rever tutoriais) com os passos novos.

**Etapa 2. Pedidos do aluno (servidor pequeno).**
1. **Pedir para remarcar ou avisar que não vai** (uma ação no cartão da aula do aluno). O professor recebe o pedido no sino e na agenda, e decide: aceitar (abre o remarcar já com o aluno) ou recusar com uma frase. Nada muda sozinho.
2. **Confirmar presença** ("Vou" / "Não vou") com um toque; o professor vê na agenda.
3. Custo estimado: 1 campo por aula no servidor e 1 aviso por pedido; sem consulta nova, no mesmo ciclo de sincronização já existente.

**Etapa 3. Calendário e fuso.**
1. Botão "Adicionar ao calendário do celular" (`.ics` gerado no aparelho, sem servidor).
2. Mostrar o fuso quando o aluno e o professor estão em fusos diferentes ("Seg 19:00, horário de Brasília").
3. Data final opcional para a aula semanal.

**Etapa 4. Mais usos.**
1. Aula em grupo (uma aula, vários alunos, ligada a uma turma). É a maior mudança: afeta conflito, lembretes e lista.
2. Tipos de aula (experimental, reposição, avulsa) e saldo de reposições.
3. Visão de escola (várias professoras vendo a agenda umas das outras).
4. Ao desativar um aluno, perguntar se cancela as aulas futuras dele.

## 5. Ordem sugerida

1. **Etapa 1 inteira** (resolve "o usuário não se perde nas decisões" e é seguro de publicar).
2. **Etapa 2** (fecha o buraco principal: o aluno falar com o professor sem sair do app).
3. **Etapa 3** (calendário do celular é o que mais pedem; fuso importa para aulas online).
4. **Etapa 4** só depois de ouvir professores reais (Thamires, Djavan, Felipe, Helena, Renata): aula em grupo e escola dependem de como eles trabalham.

## 6. Riscos e cuidados

- A agenda está em produção: tudo novo na API tem de ser retrocompatível (campos opcionais, app antigo ignora).
- Pedidos do aluno precisam de limite por hora (anti-abuso) e de teste de segurança como os do pagamento.
- Texto novo no app vai com tradução em inglês (`tr()`), e cada tela com o design system (modal para configuração, aviso no sino).
- Os números do servidor usados nas explicações (60 min, 12 aulas, 120 dias, 100 horários, 400 aulas) devem sair das mesmas constantes, para o texto não mentir se o limite mudar.

## 7. Revisão: quem manda na agenda (princípio do Daniel, 24/11/2026)

**Princípio.** O professor tem o controle. O aluno informa e pede, mas **nada que o aluno faz muda a agenda do professor sem o professor decidir**. Motivo: aluno que mexe sem querer (ou sem saber) bagunça a agenda, e o professor ainda está aprendendo o sistema. A única exceção que existe hoje é pegar um horário que o próprio professor deixou livre, e mesmo ela precisa de freios.

### 7.1 Quem pode o quê hoje (código atual)

| Ação | Professor | Aluno | Até quando | Desfazer |
|---|---|---|---|---|
| Marcar, editar, cancelar aula | Sim | Não | Editar e cancelar até a aula começar; em andamento só ajusta | Não há "Desfazer": só refazer à mão |
| Remarcar, trocar, pausar | Sim, com confirmação que diz quem é avisado | Não | Antes da aula | Não há |
| Abrir horário livre | Sim (até 100) | Não | | Apagar o horário |
| **Pegar horário livre** | | **Sim, na hora, sem o professor aprovar** | Até 60 min antes; até 12 aulas por professor | **O aluno não desfaz**; só o professor cancela |
| Horário livre semanal | | Quem pega **fica toda semana** | | Só o professor cancela |
| Ver aula e entrar na sala | | Sim (só leitura) | | |
| Avisar que não vai | Professor registra a falta | **Não existe** | | |

**Onde o princípio já é quebrado:** pegar horário é a única ação do aluno que **cria** aula, e hoje é imediata, sem aprovação, sem desfazer e (se semanal) permanente. Um toque errado vira uma aula toda semana na agenda do professor, e só ele consegue tirar.

### 7.2 Regras propostas (o que o aluno nunca faz, e o que pode fazer)

1. **O aluno nunca edita, cancela, remarca ou apaga uma aula.** Só o professor.
2. **O aluno só "avisa" ou "pede".** Um aviso é uma mensagem, não uma mudança. A aula continua exatamente como está até o professor decidir.
3. **Cada aviso do aluno tem opções prontas, sem texto livre** (menos erro, nada de conversa): "Não vou conseguir ir nesta aula", "Queria remarcar esta aula", "Cheguei atrasado(a)". Duas confirmações: um diálogo que diz o que será enviado e a quem, e um "Desfazer" por alguns segundos.
4. **O professor decide com um toque** em cada aviso: *Ok, registrei falta justificada* / *Remarcar* (abre o remarcar já com o aluno) / *Ignorar*. Sem decisão, o aviso some sozinho depois da aula.
5. **Freios no aviso:** um aviso aberto por aula; no máximo 3 por dia por aluno; o professor pode **silenciar os avisos de um aluno** (ou de todos) nas configurações.
6. **Avisos em cima da hora** (menos de 24 h) aparecem marcados "em cima da hora", para o professor não tratar igual a um aviso com antecedência.
7. **Professor sempre no comando do que o aluno pode pegar:**
   - cada horário livre ganha a opção **"Confirmo antes"**: o aluno faz um *pedido* e o professor aceita ou recusa (padrão continua automático para não mudar o que já funciona; o professor escolhe por horário);
   - em horário livre semanal, o padrão passa a pedir confirmação (compromisso toda semana não deve sair de um toque);
   - o professor pode **desligar o "pegar horário" de um aluno** específico;
   - o aluno que pega ganha um **desfazer curto (10 min)** enquanto o horário ainda não passou de "pegou há pouco", e o professor também pode desfazer.
8. **Confirmação de presença ("vou"):** tirar da proposta. É ruído para o professor e mais um botão para o aluno apertar errado. Fica só como opção que o **professor liga** nas configurações (desligada por padrão).
9. **Tudo que mexe na agenda fica em um histórico da aula, visível só para o professor** ("o aluno avisou que não vai", "você remarcou", "o aluno pegou o horário"), para ele entender o que aconteceu sem depender de memória.

### 7.3 Proteções para o próprio professor (ele ainda está aprendendo)

- **Desfazer** logo depois de cancelar, remarcar, trocar ou pausar (hoje não existe). É a proteção mais valiosa para quem tem medo de errar.
- Confirmações que dizem em palavras o que muda e quem é avisado (já existem; manter).
- Ao **desativar um aluno**, perguntar se cancela as aulas futuras dele (hoje elas continuam na agenda).
- Conflitos e choques sempre explicados em uma frase, nunca só bloqueados.

### 7.4 Proposta reorganizada

| Etapa | Conteúdo | Risco |
|---|---|---|
| 1 | Explicar no app: "Como funciona" do aluno (com o que ele pode e o que não pode fazer), guia "Qual escolher?" do professor, textos no calendário vazio | Nenhum (só texto e tutorial) |
| 2 | **Controle do professor primeiro:** Desfazer nas ações da agenda; "Confirmo antes" nos horários livres (semanais confirmam por padrão); desligar "pegar horário" por aluno; perguntar das aulas futuras ao desativar | Baixo (professor só ganha controle) |
| 3 | **Avisos do aluno:** "Não vou / Queria remarcar" com opções prontas, decisão do professor em 1 toque, freios e silenciar | Médio: servidor novo, limites por hora, testes de segurança |
| 4 | Calendário do celular (`.ics`, só leitura para o aluno), fuso, data final da semanal (só o professor) | Baixo |
| 5 | Depois de ouvir professores reais: aula em grupo, tipos de aula, visão de escola | Alto |

**Mudança em relação à proposta anterior:** a Etapa 2 antiga (pedidos do aluno) virou a 3, e agora vem **depois** de dar mais controle ao professor. Saiu o "confirmar presença" como padrão.

## 8. Situação (24/11/2026)
Feitas as etapas 1 a 4 da seção 7.4 (explicações, controle do professor, avisos do aluno, calendário e fuso) e o cartão da conta. Regras em `03_REGRAS_DE_NEGOCIO.md` seção 19. **Fica para depois de ouvir professores reais:** aula em grupo, tipos de aula (experimental, reposição) e visão de escola.
