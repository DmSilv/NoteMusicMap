# Estudo: vínculo professor ↔ aluno (hoje, falhas e proposta)

Data: 23/11/2026. Estudo que originou as mudanças A e B (feitas depois, ainda não publicadas; ver `11_HISTORICO.md`). Base: `api/link.js`, `api/_lib/unlink.js`, `lib/app_state.dart`, telas do aluno e do professor.

## 1. Como funciona hoje

**Modelo.** O vínculo é um par (professor, aluno) gravado nos dois lados: `ut:<prof>` (alunos do professor) e `us:<aluno>` (professores do aluno). Não há limite de professores por aluno nem de alunos por professor (exceto 300 vínculos e, com o recurso ligado, 3 alunos no plano grátis).

**Estados que o app conhece.** Do lado do professor, cada aluno tem `linkState`: `null` (só local), `pending` (aguardando), `active`, `ended`. Do lado do aluno há `myTeachers` (ativos) e `formerTeachers` (arquivo local de quem encerrou).

**Quem cria.** Quem lê o QR ou digita o código cria o vínculo; vale para os dois sem aceite do outro. Reencontrar um ex-aluno restaura o histórico ("voltou a ser seu aluno").

**Quem encerra.** Qualquer um, a qualquer hora, sem aviso prévio e sem aceite. O servidor apaga em `unlinkPair`: aulas, aulas marcadas, tarefas marcadas como feitas, horários pegos e decisões do professor. Cada lado guarda uma cópia local (o professor mantém a ficha, o aluno arquiva em `formerTeachers`).

**O que o professor pode fazer com um aluno hoje:** editar, começar aula, **excluir aluno**, **encerrar vínculo**. Não existe **desativar/pausar**.

## 2. Mais de um professor: como a ferramenta se comporta

| Área | Comportamento com 2+ professores | Avaliação |
|---|---|---|
| Aulas e tarefas | Chegam de todos; cada uma guarda `teacherCode` e `teacherName`. Mesmo id de aula em dois professores não colide (testado). | Bom |
| Desvincular um | Só as aulas daquele professor somem; o arquivo local guarda o histórico. | Bom |
| Agenda do aluno | Mostra o nome do professor em cada aula marcada. | Bom |
| Pegar horário | Tem seletor de professor, mas **abre sempre no primeiro da lista** (`myTeachers.first`), não no último nem no mais recente. | Fraco |
| Conflito de horário | O servidor só confere o conflito **dentro da agenda do professor**. O aluno pode pegar o mesmo horário com dois professores e ninguém é avisado. | **Falha** |
| Resumo de estudo | Um único resumo por aluno (`sh:<aluno>`) e **todos os professores vinculados o leem**. Não dá para compartilhar só com um. | **Falha de privacidade/controle** |
| Início/hello | Com 2 ou mais mostra "N professores" sem nomes. | Pobre |
| Acervo (links) | Abre por professor (`teacher:`), bom. | Bom |
| Notificações | Falam o nome do professor na aula; lembretes são por aula. | Bom |
| `myTeacherCode` | Devolve o **último** da lista; nada o usa hoje (resíduo). | Limpar |
| Limite grátis | O limite conta vínculos do **professor**; ter vários professores não afeta o aluno (aluno sempre grátis). | Bom |

## 3. Falhas do fluxo de "desativar"

1. **Sem meio-termo.** Para tirar um aluno da rotina o professor só tem "Encerrar vínculo" (rompe os dois lados e apaga as aulas do aluno no servidor) ou "Excluir".
2. **Vaga do plano grátis.** O limite conta todo vínculo; o aluno que parou de ter aula ocupa uma das 3 vagas até o vínculo ser encerrado.
3. **O aluno não sabe o motivo.** Ao ser encerrado ele só vê "X encerrou o vínculo com você", sem diferença entre "pausou" e "terminou".
4. **Reativar depende do reencontro.** O professor "reenvia" abrindo a ficha; não há botão claro de voltar.
5. **Sem confirmação nos dois lados** para criar o vínculo: quem lê o QR vincula o outro sem aceite (decisão antiga, vale rever com aluno menor de idade).

## 4. Proposta (ordem de valor)

**A. Desativar aluno (professor).** Novo estado `paused` guardado no vínculo (um campo no valor do hash `ut:<prof>`), sem apagar nada.
- O aluno vai para uma seção "Inativos" da lista e some das escolhas do dia (começar aula, agendar, enviar tarefas).
- Não conta no limite grátis (o servidor conta só vínculos `active`).
- O aluno vê "Aulas pausadas por {professor}" em vez de "encerrou"; mantém o histórico e as tarefas; não recebe aula nova nem lembrete.
- Botão "Reativar": volta ao estado ativo; se estourar o limite grátis, oferece o Pro.
- Compatibilidade: app antigo ignora o campo e trata como ativo (o servidor continua devolvendo as listas atuais).

**B. Aluno com vários professores.**
1. Pegar horário abre no professor com aula mais próxima; mostrar o nome do professor em destaque.
2. Avisar conflito entre professores: ao pegar horário, o servidor confere `SS(me)` (as aulas do próprio aluno) e responde `student_conflict`.
3. Resumo de estudo **por professor**: chave `sh:<aluno>:<prof>` ou lista de professores permitidos; interruptor em Perfil › Meus professores.
4. Início com os nomes ("Ana e Bruno") e a próxima aula de cada.
5. Remover `myTeacherCode` (não usado).

**C. Segurança e clareza do vínculo.**
- Mostrar quem criou o vínculo e quando; aviso ao aluno quando um professor o adiciona (já existe nota no sino).
- Encerrar com motivo opcional ("terminei o curso", "pausa") visível ao outro lado.

## 5. Fluxos (resumo para validar)

```
Criar:    QR/código -> vínculo ativo nos dois lados -> aviso ao outro (sino + push opcional)
Pausar:   professor "Desativar" -> estado paused -> some das ações; aluno vê "pausado"; vaga grátis liberada
Reativar: professor "Reativar" -> checa limite grátis -> active (ou convite ao Pro)
Encerrar: qualquer lado -> apaga aulas/horários no servidor; cada lado guarda cópia local; religar restaura
Vários:   cada ação carrega o código do professor; o aluno escolhe com quem agenda; conflito avisa
```

## 6. Esforço e testes

- A (desativar): servidor `link.js` (estado e contagem do limite), app (ficha do aluno, lista com seção Inativos, tela do aluno), i18n, docs. Testes: estado, limite, app antigo, reativar com limite cheio.
- B.2 e B.3: servidor e testes de conflito/privacidade; B.1 e B.4 só app.
- Nada disso aumenta custo de Redis de forma relevante: o estado cabe no campo que já existe e o conflito usa um `hgetall` que o fluxo já faz.
