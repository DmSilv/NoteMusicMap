# Plano: aula online, controle da agenda, painel admin, tutorial e sucesso

Documento de planejamento (novembro/2026). Nada aqui foi publicado ainda, exceto onde disser "pronto".
Regra de sempre: testar tudo, mostrar no navegador (390×844), API sempre compatível com apps antigos, custo baixo
(Upstash 500 mil comandos/mês, Vercel Hobby, até 12 funções), e só publicar com "Sim, publicar".

## 0. Estado de hoje
- **Momento de sucesso** (pegar horário, marcar aula, enviar tarefa): pronto, 2 commits locais, falta o "Sim, publicar".
- **Tutorial guiado**: desenhado (mecanismo único, nunca obrigatório, "Rever tutoriais" em Ajustes), não começado.
- **Painel admin**: 8 abas, atualização do "agora" a cada 30 s, 5 ações com `confirm()`/`prompt()` do navegador.

## 1. Aula online (link da aula)

### O que existe
`ClassSlot` (professor e aluno) tem: id, aluno, início, duração, repete, cancelados (`x`), observação (`n`), versão (`u`), cancelada (`c`).
O servidor (`api/_lib/agenda.js › cleanSlot`) só deixa passar esses campos. Não há "online" nem link.

### Proposta
- Dois campos novos no horário: **modo** (`m`: `o` online, `p` presencial; ausente = presencial) e **link** (`l`, opcional).
- O professor escolhe o modo ao marcar a aula e ao publicar um horário livre. Online sem link é permitido: o link pode ser
  **adicionado depois** (item "Adicionar/editar link" no menu da aula, sem abrir o formulário inteiro).
- Horário livre online: ao ser pego, a aula nasce online e herda o link do horário (se houver). Depois o professor edita.
- O aluno vê "Online" na aula e, com link, o botão **Entrar na aula** (a partir de 15 min antes; antes disso o link fica
  visível mas mais discreto). Abre pelo navegador (já temos `url_launcher`).
- O app **não cria** a sala do Meet (isso exigiria login do Google). O formulário terá o atalho "Criar sala" que abre
  `meet.new` e o professor cola o link de volta.
- **Segurança do link:** só `https`, sem usuário/senha, de uma lista (Meet, Zoom, Teams, Whereby, Jitsi) mais "Outro site"
  que mostra o endereço antes de abrir. O link só é entregue ao aluno vinculado àquela aula (mesma regra das aulas hoje).

### Compatibilidade (o ponto de maior cuidado)
- App antigo ignora `m` e `l` (mostra a aula normal). Sem quebra.
- **Risco:** professor com app antigo edita uma aula online e o servidor regrava sem `m`/`l`, apagando o link.
  **Solução:** versão nova do app sempre manda `m`; se a requisição vier **sem** a chave `m`, o servidor mantém `m` e `l` antigos.
- Tamanho: +~100 bytes por aula, sem comando novo no Redis. Custo ~0.
- Lembrete (QStash) não muda; pode incluir "(online)" no texto numa segunda fase.

### Testes
`api/agenda.test.js` e `api/avail.test.js`: guardar/limpar `m`/`l`, link inválido recusado, app antigo não apaga o link,
aluno não vinculado não recebe. Núcleo (`dart test`): leitura/gravação do horário com e sem os campos novos.

## 2. O professor tem controle total da agenda? (avaliação)

### Já faz
Marcar (única ou toda semana), editar a regra inteira (dia, hora, duração, repetição, observação), cancelar só uma aula,
cancelar todas, publicar/apagar horário livre, conflito com outras aulas é barrado, aluno é avisado de cada mudança.

### Lacunas encontradas
1. **Remarcar só uma aula** (mudar uma quarta específica de dia/hora): hoje só dá para cancelar aquela data. Falta "Remarcar esta aula".
2. **Trocar horários entre dois alunos**: hoje são duas edições manuais, e a primeira esbarra no conflito da segunda.
3. **Trocar o aluno de uma aula**: no modo editar o aluno aparece fixo.
4. **Férias / pausa**: cancelar um período exige cancelar data por data (limite de 30 cancelamentos por regra).
5. **Pedido do aluno** (pedir troca) não existe; está previsto no roteiro em etapas.
6. **Suspeita de bug a confirmar com teste:** ao editar a hora de uma regra semanal que já tinha datas canceladas, a lista
   de cancelados guarda os horários antigos e pode "ressuscitar" aulas canceladas.

### Proposta de ordem
Remarcar só esta aula → Trocar horários entre dois alunos → Pausa/férias → trocar aluno da aula → pedidos do aluno.
Tudo com confirmação em modal mostrando quem é avisado.

## 3. Painel admin

### Segurança de clique
- Toda ação que muda algo abre um **modal** (sobe de baixo): o que vai acontecer, quem é afetado, se dá para desfazer.
- Ações perigosas (apagar perfil, encerrar vínculo, apagar item de agenda, liberar conta): **digitar o código** ou **segurar 1,5 s**.
- Botões de ação separados dos de consulta, maiores, com cor própria. Ação concluída gera aviso e entra no registro (`log`).
- Substitui os 5 `confirm()`/`prompt()` atuais e cobre as ações que hoje não confirmam (a conferir uma a uma).

### Tempo real e legibilidade
- Faixa fixa no topo: online agora, aparelhos novos hoje, erros na última hora, bugs abertos; indicador "atualizado há Xs".
- "O que pede atenção" vem primeiro (bug novo, pico de cadastros, lembrete falhando).
- Números animados, esqueletos de carregamento, abas com transição, mesmo estilo do app.
- Custo: atualiza só com a aba visível; antes de encurtar o intervalo (15 s) medir comandos do Redis por consulta.

### Acompanhar professor e aluno (suporte)
Hoje: detalhe com contagens e uma lista de agenda só de leitura (60 itens) + apagar item travado.
Proposta: aba/ficha **"Acompanhar"** por pessoa com:
- última atividade, online agora, aparelhos com notificação, erros recentes dela;
- vínculos (com quem, desde quando, atividade do outro lado);
- agenda completa do professor e do aluno lado a lado (próximas aulas, horários livres, quem pegou, cancelados);
- tarefas enviadas/feitas/pendentes (contagens e títulos, sem conteúdo de estudo);
- ações de suporte com confirmação: cancelar/remarcar aula **em nome** do usuário (ele é avisado), reenviar aviso,
  gerar código de liberação, bloquear.
- Limites de privacidade (decisão): mostrar só o que já está no servidor para o vínculo funcionar; **nunca** áudio, e
  explicar na política de privacidade que o suporte pode ver a agenda e as tarefas para ajudar.

## 4. Tutorial guiado e momento de sucesso
- Tutorial: mecanismo único (`lib/ui/tour/`), nunca obrigatório, convite discreto, "Rever tutoriais" em Ajustes.
  Primeiros: Marcar aula, Horários livres, Nova tarefa, depois aluno (código e Pegar horário). **Os tutoriais devem
  ser feitos depois da aula online e do controle da agenda**, para não ensinar telas que vão mudar.
- Momento de sucesso: estender para vincular, concluir tarefa, remarcar e trocar horários.

## 5. Análise de impacto (antes de mexer)
| Área | Impacto | Cuidado |
|---|---|---|
| API de agenda | campos novos `m`/`l` | servidor mantém os antigos se a chave faltar; testes de app antigo |
| Dados | +~100 B por aula | sem comando novo; limites (400 aulas, 100 horários livres) intactos |
| Custo | painel em tempo real | só com aba visível; medir comandos/consulta; nada de laço rápido |
| Funções Vercel | 12 no limite | tudo entra em `api/link.js` e `api/admin.js` existentes |
| Privacidade | suporte vê agenda/tarefas | atualizar política e docs/05; sem áudio |
| Segurança | link do professor ao aluno | lista de sites + https + mostrar o endereço |
| Apps abertos | cache antigo | já temos service worker por versão; avisar ao atualizar |
| Docs/testes | regras novas | docs/03, 04, 07, 11 e referência; testes de API e núcleo a cada etapa |

## 6. Recursos liberados aos poucos (chaves por professor) — NOVO
Objetivo: lançar cada novidade primeiro para quem você escolher e só depois para todos, sem afetar quem já usa.
Hoje isso é a variável `LIBRARY_TESTERS` da Vercel (só o acervo, precisa de redeploy). Passa a ser uma **aba "Recursos" no painel**.

### Como funciona
- **Lista de recursos no código** (`api/_lib/features.js`): id, nome, descrição, para quem vale (professor, aluno ou os dois).
  Só recursos que existem na lista aparecem no painel (sem erro de digitação). Novo recurso = uma linha nova.
- **Estados por recurso:** Desligado → Só os liberados (lista de códigos) → Parte dos usuários (% fixo, por código) → Todos.
- **Desligar na hora** (chave geral): vale para todos sem publicar nada.
- **Liberar um professor** pode liberar junto os alunos vinculados a ele, quando o recurso é de professor e aluno (ex.: aula online).
- **Quem decide é o servidor.** O app só recebe a lista de recursos ligados para o perfil dele (`ff`, junto da sincronização que já existe)
  e esconde o que não está ligado; mas o servidor também recusa (como o acervo faz hoje com `library_off`).
- **App antigo** ignora `ff` e continua como está; recursos novos nunca ligam sozinhos num app que não os conhece.
- **Acervo** vira o primeiro recurso da lista (`acervo`), importando os códigos de `LIBRARY_TESTERS` (a variável continua valendo como ponto de partida).

### Custo e armazenamento
- Por perfil: um campo a mais (`ff`) no hash que a sincronização **já lê** → 0 comando novo por sincronização.
- Estado geral dos recursos: 1 chave pequena, guardada em memória da função por 60 s → ~1 comando por minuto por instância.
- Lista de liberados por recurso: um conjunto no Redis só para o painel listar e contar (escrita só quando você libera).

### No painel (aba Recursos)
Cartão por recurso com estado, quantos liberados, botões **Liberar para um código**, **Liberar parte (%)**, **Liberar para todos**, **Desligar**.
Todas as ações passam pela confirmação em modal; "Todos" e "Desligar" exigem digitar o nome do recurso. Cada mudança entra no registro
(quem, quando, antes/depois). Cada cartão mostra também o uso: quantos liberados abriram o recurso nos últimos 7 dias (só contagem).

### Funil de liberação sugerido
1. Você (teste) → 2. professor de teste (Vinícius) → 3. 5 a 10% → 4. 50% → 5. todos. Em cada passo olhar bugs e erros do painel antes de subir.

## 7. Verificação automática e segurança no GitHub — NOVO
O GitHub já roda um CI a cada envio (análise, testes do núcleo e build web). Mudanças feitas agora:
- **CI completo:** passa a rodar também **todos os testes da API (236)** e as conferências de documentação e de texto
  (antes só rodava os da IA).
- **Varredura de segurança (CodeQL):** a cada pull request, a cada envio e uma vez por semana; resultado em GitHub › Security.
- **Dependabot:** abre pull request semanal quando sai versão nova de pacote ou ação, inclusive correção de segurança.
- **Do seu lado, em GitHub › Settings** (o repositório é público, então é grátis): ligar **Secret scanning** e **Push protection**
  (barra o envio de senha ou chave por engano), e **proteger o ramo `main`** exigindo o CI verde antes de juntar um pull request.
- **Teste de fumaça (feito):** `node scripts/smoke.js --web` roda no CI a cada envio (fluxos da agenda, aula online, painel e abertura do app no Chrome).
Observação: o CI **não bloqueia** a Vercel (ela publica ao receber o envio). Por isso a regra de só publicar após o "Sim" continua.

## 8. Ordem de execução (atualizada)
1. Publicar o **momento de sucesso** — feito.
2. **Verificação no GitHub** (CI completo, CodeQL, Dependabot) — pronto para envio.
3. **Admin: confirmação em modal** nas ações + registro de ações.
4. **Recursos por professor** (chaves no painel) — antes da aula online, para ela já nascer atrás de uma chave.
5. **Aula online** com **link padrão do professor** ("Meu link de aula online", cada aula já nasce com ele) e link por aula editável; liberada por chave.
6. **Controle da agenda** (remarcar só esta aula, trocar horários, pausa/férias, corrigir a suspeita dos cancelados antigos); depois falta/reposição e pedido de troca do aluno.
7. **Admin: Acompanhar** — começa pelo **funil de ativação** (gerou código → vinculou → 1ª aula → 1ª tarefa), agendas lado a lado, ações de
   suporte com motivo escrito, **alertas** (erro crítico, pico de cadastros, lembrete falhando) e tempo real + design.
8. **Tutoriais** como checklist "Comece por aqui" (vincular aluno, marcar aula, passar tarefa) mais os destaques com tela escura.
Cada etapa: testar, mostrar no navegador, documentar, e só então pedir o "Sim, publicar".

## 9. Decisões abertas
1. Link da aula: lista de sites (Meet, Zoom, Teams, Whereby, Jitsi) ou aceitar qualquer https? (recomendado: lista + "Outro site")
2. Horário livre: o professor define online/presencial no horário, ou o aluno escolhe ao pegar? (recomendado: o professor define)
3. Suporte do admin: pode remarcar/cancelar aula em nome do usuário, ou só ver? (recomendado: pode, com confirmação e aviso ao usuário)
4. Intervalo do "agora" no admin: 15 s (recomendado) ou manter 30 s.
