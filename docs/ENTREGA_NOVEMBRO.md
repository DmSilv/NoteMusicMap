# Entrega de novembro/2026: commits prontos para aprovar, um a um

Todos os commits abaixo estão **só no computador** (nada foi enviado). A ordem importa: cada um depende dos anteriores, então
aprove **de cima para baixo**. Um `git push` envia todos os commits até onde você escolher; para enviar só até o commit N, use
`git push origin <hash do commit N>:main`.

Regras seguidas em todos: API compatível com apps antigos, recurso novo atrás de chave (desligado por padrão), custo no Upstash
medido, testes automáticos, conferência no navegador em 390×844 e documentação atualizada. Se algo der errado depois de publicar,
`git revert <hash>` desfaz só aquele commit (cada um é independente na hora de desfazer, do último para o primeiro).

| # | Commit | O que muda para o usuário | Risco | Como desfazer |
|---|---|---|---|---|
| 1 | `fea670b` CI completo, CodeQL e Dependabot | Nada no app. O GitHub passa a rodar todos os testes da API, as conferências de documentação e a varredura de segurança. | Nenhum para os usuários. O CI pode ficar vermelho no GitHub, mas não trava a Vercel. | `git revert` |
| 2 | `806db5c` Painel: confirmação em modal | Só o painel do admin: toda ação que altera algo pede confirmação (segurar 1,5 s ou digitar o código nas ações sem volta). | Só afeta o admin. | `git revert` |
| 3 | `bf50952` Recursos liberados aos poucos | Aba **Recursos** no painel; a sincronização do app traz `ff`. Acervo passa a usar as chaves (LIBRARY_TESTERS continua valendo). Usuários não veem diferença. | Médio-baixo: mexe na sincronização. Apps antigos ignoram `ff`. Sem comando novo no Redis por sincronização do próprio perfil. | `git revert` (volta o acervo à variável) |
| 4 | `d5b13b0` Aula online (atrás da chave `aula_online`) | **Nada muda para ninguém** até você liberar o recurso no painel. Depois: modo online/presencial, link da sala, link padrão e botão Entrar. | Baixo: desligado por padrão; servidor mantém modo e link de app antigo. | Desligar a chave no painel (na hora) ou `git revert` |
| 5 | `2e76d1a` Controle da agenda do professor | Menu da aula: Remarcar só esta aula, Trocar horário com outro aluno; botão Pausar aulas; trocar o aluno ao editar; corrige datas canceladas que "ressuscitavam". | Médio: mexe na agenda de produção. Mudanças aplicadas de uma vez e conferidas antes. Servidor remove a aula do aluno anterior ao trocar de aluno. | `git revert` |
| 6 | `c0a1759` Painel: ativação, comparar agendas e visual | Só o painel: funil de ativação, comparar agenda do professor com a do aluno, "agora há X s", visual. | Baixo: contador novo grava 3 comandos uma única vez por perfil e etapa. | `git revert` |
| 7 | `eb0416b` Tutoriais e Comece por aqui | Cartão **Comece por aqui** no Meu espaço do professor, tutorial com tela escura, "Rever tutoriais" em Ajustes. | Baixo: só no aparelho, opcional, sem servidor. | `git revert` |

## O que foi testado em cada um
- **Automático:** 272 testes da API, 571 do núcleo, análise do Flutter sem avisos e conferência da documentação, no estado final **e em
  cada commit** (veja a tabela de verificação por commit no fim deste arquivo).
- **No navegador (390×844):** modal de confirmação (cancelar, Esc, atraso de 0,7 s, segurar, digitar), aba Recursos (liberar com alunos,
  tirar, desligar, todos, porcentagem), formulário de aula online ligado e desligado, aluno vendo "Entrar na aula online", trocar
  horários entre alunos (o resultado aparece na agenda), cartão Comece por aqui e o tutorial com destaque.

## Antes de publicar (do seu lado)
1. **Commit 3 em diante:** depois de publicar, abra **Painel › Recursos** e confira os dois cartões. `LIBRARY_TESTERS` continua valendo.
2. **Commit 4:** para ligar a aula online só para o Vinícius: Recursos › Aula online › digite o código dele › marque "Incluir os alunos
   vinculados" › Liberar. Depois teste com ele e um aluno. Aumente para 10% e depois todos, olhando os bugs do painel.
3. **No GitHub (uma vez):** Settings › Code security: ligar *Secret scanning* e *Push protection*; Settings › Branches: proteger o `main`.

## O que **não** foi possível testar neste computador
- Teste de tela do Flutter (`flutter test`): falta o compilador do Windows. O CI do GitHub roda análise e testes do núcleo, mas esse teste de tela
  também não faz parte do CI hoje.
- Vibração e abrir o link da sala num celular de verdade; o seletor de datas do Flutter aparece em inglês (o app não tem os textos do Flutter
  em português: pendência antiga, não piorou).
- Lembretes (QStash e VAPID): continuam dependendo das chaves da Vercel; nada nesta entrega muda isso.

## Pendências conhecidas (não bloqueiam)
- Tutorial do aluno ainda não existe (só do professor).
- O funil de ativação só conta a partir da publicação do commit 6.
- Falta/reposição e pedido de troca feito pelo aluno (ideias de próxima etapa em `docs/PLANO_AULA_ONLINE_AGENDA_ADMIN.md`).

## Verificação por commit (cada um conferido em uma cópia limpa do projeto)
| Commit | Testes da API | Testes do núcleo | Análise do Flutter | Documentação |
|---|---|---|---|---|
| fea670b | 236 ok | 552 ok | sem avisos | ok |
| 806db5c | 237 ok | 552 ok | sem avisos | ok |
| bf50952 | 250 ok | 552 ok | sem avisos | ok |
| d5b13b0 | 263 ok | 559 ok | sem avisos | ok |
| 2e76d1a | 267 ok | 568 ok | sem avisos | ok |
| c0a1759 | 272 ok | 568 ok | sem avisos | ok |
| eb0416b | 272 ok | 571 ok | sem avisos | ok |
