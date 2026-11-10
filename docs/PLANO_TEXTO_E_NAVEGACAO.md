# Plano: validar botões, enxugar textos e melhorar a navegação

Pedido do Daniel (10/11/2026): validar botões, tirar texto da tela (passar para modais "?"), e criar um fluxo de navegação em que o usuário não se perca. **Este documento é só o plano; nada foi alterado no app.**

## O que o levantamento achou
**Navegação**
- A barra de cima tem **5 ícones em todas as abas** (tema, compartilhar, avisos, perfil, ajustes), além das 4 abas de baixo.
- O mesmo destino tem vários caminhos: Perfil e Ajustes estão na barra **e** em "Ferramentas"; a Agenda do professor abre pelo destaque, pelo bloco, pela ferramenta **e** por um ícone na Área do professor.
- O professor tem duas "casas": **Meu espaço** (hub) e **Área do professor** (tela de 1.656 linhas), com listas e ações repetidas.
- Perfil tem duas abas internas (Perfil / Professor) dentro de uma tela que já é aberta por um ícone de barra.
- O hub abre 17 telas diferentes; não há trilha ("onde estou") nas telas fundas (Aluno → Tarefa → Nova tarefa).

**Texto**
- Já existe o padrão certo: `HelpButton` ("?") + `showInfoSheet`, mas só é usado no Afinador e nos Ajustes.
- Textos longos soltos na tela (mais de 110 caracteres): Ajustes 15, widgets comuns 14, Guia de afinação, Área do professor, Perfil e Grade 3 cada; as telas novas (Horários livres, faixas de agenda, resumo) também têm parágrafos.

**Botões**
- Verificação estática: nenhum botão com ação vazia ou `null`.
- Isso **não prova** que cada botão leva ao lugar certo; falta o teste em tela (Fase 0).

## Fase 0 · Validar os botões (antes de mexer em qualquer coisa)
1. Montar a **matriz de botões** (`docs/MATRIZ_BOTOES.md`): tela × botão × resultado esperado, por papel (aluno, professor, os dois).
2. Percorrer tudo no Chrome em tamanho de celular, com dados de teste, anotando: funciona / leva ao lugar errado / não responde / texto confuso.
3. Corrigir os defeitos achados (um commit só) e guardar a matriz como roteiro de regressão.

## Fase 1 · Navegação (proposta)
Regra de ouro: **cada ação tem um caminho principal e no máximo 3 toques a partir de "Meu espaço".**
1. **Barra de cima enxuta:** só **Avisos** (sino) e **Eu** (perfil). Tema vai para Ajustes; Compartilhar vai para Perfil e para o convite no hub; Ajustes abre de dentro de "Eu".
2. **"Eu"** vira a casa da conta: Perfil, Vínculo online, Professor(es), Ajustes, Compartilhar, Chave de recuperação. Sai a aba "Professor" duplicada: o conteúdo vira seção da mesma tela.
3. **Meu espaço** vira o único lançador de tarefas, em blocos por assunto: **Hoje** (destaque), **Aulas** (agenda do professor / do aluno, horários livres, pegar horário), **Alunos e tarefas** (para validar, tarefas, alunos), **Ferramentas** (metrônomo, escalas). Sem repetir o mesmo destino em três lugares.
4. **Área do professor** deixa de ser uma segunda casa: vira "Alunos" (lista + ficha) e "Relatórios", abertas pelo hub.
5. **Padrão de tela:** título curto com o papel quando importa ("Agenda do aluno"), botão voltar sempre, um "?" no canto, **uma ação principal** (botão fixo ou "+"). Telas fundas mostram a trilha curta ("Marina › Nova tarefa").
6. **Voltar com sentido:** terminou uma ação (marcar aula, passar tarefa, pegar horário) → volta para onde começou, com a confirmação em uma linha.
7. **Fluxos-modelo** (cada um ≤ 3 toques a partir de Meu espaço, testados nos dois papéis): marcar aula · passar tarefa · validar tarefa · começar aula · pegar horário · vincular aluno/professor · ver avisos.

## Fase 2 · Dieta de texto
Regras:
- **Título:** até 3 palavras. **Apoio:** 1 linha (cerca de 80 caracteres). **Explicação** além disso vai para o "?" (`HelpButton`).
- Parágrafo introdutório de tela → vira "?" no título ou no cabeçalho da seção.
- Botões com verbo curto ("Marcar aula", "Pegar", "Validar"); sem frases.
- Confirmações e erros: uma frase.
Execução:
1. Criar `SectionHeader(título, ajuda:)` (título + "?") e centralizar os textos de ajuda em `Help` (um lugar só).
2. Ordem por impacto: Área do professor/Alunos → Perfil e Vínculo → Ajustes → Hub e agendas → Horários livres → formulários (tarefa, aula) → Grade/Escalas.
3. **Trava automática:** script `scripts/check_text.js` que falha se houver texto fixo de tela acima do limite fora dos arquivos de ajuda (roda junto com os testes).

## Fase 3 · Verificação e publicação
- Cada fase vai separada, com testes (núcleo, API, analyze), conferência no Chrome em celular e tela larga, **e o seu "sim" antes de publicar**.
- O roteiro manual de `docs/CUSTOS_E_REGRESSAO.md` passa a incluir a matriz de botões.

## Ordem sugerida e riscos
1. Fase 0 (validar) → 2. Fase 1 (navegação) → 3. Fase 2 (texto), porque mover telas muda onde os textos moram.
- **Risco:** mexer na barra de cima muda hábitos de quem já usa. Mitigação: o sino e o perfil ficam no mesmo lugar; o tema e o "Compartilhar" continuam a um toque de "Eu".
- **Sem mudança de API ou dados:** é só interface; rollback é `git revert`.

---

# Acréscimo (10/11/2026): espaçamento e guardrails de segurança

## Espaçamento
Hoje cada tela define seus próprios valores; no celular vê-se aperto e ritmo irregular (ex.: cartões do Afinador colados, faixas sem respiro, grade de ferramentas).
1. **Escala única** em `theme.dart`: `Space.xs 4 · s 8 · m 12 · l 16 · xl 24`; margem lateral da página 16; entre cartões 12; entre seções 24; alvo de toque mínimo 44 px.
2. Widgets padrão (`PageBody`, `SectionGap`, `AppCard`) usando só essa escala; trocar os números soltos nas telas, uma tela por vez, na ordem: Meu espaço → Agendas → Perfil → Alunos/Ficha → Formulários → Afinador/Metrônomo/Grade.
3. Conferir no Chrome em **360, 390 e 768 px**, claro e escuro, antes de pedir publicação.
4. Sem mudar comportamento: só espaçamento. (Preciso saber quais telas mais incomodam para começar por elas.)

## Guardrails de segurança
**No app**
1. **Ações irreversíveis sempre com confirmação padronizada** (excluir aluno, desvincular, apagar dados, limpar avisos, trocar aparelho): um único diálogo com texto do que será perdido; auditar todas as telas.
2. **Toda entrada de texto passa pelo filtro** (`cleanText`, limites e caracteres invisíveis): auditar campos sem filtro e a importação de dados colados (limite já existe).
3. **Convites, QR e links:** validar formato e dígito verificador, ignorar parâmetros desconhecidos e **sempre confirmar antes de vincular** ("Vincular a Fulano?").
4. **Duplo toque:** botões que chamam o servidor (publicar, pegar horário, validar) travam enquanto enviam.
5. **Segredos:** nunca em log, compartilhamento ou mensagem de erro; chave de recuperação com aviso claro.
6. **IA do coach:** limite de tamanho, taxa e custo por perfil; texto do usuário nunca vira instrução do sistema.

**No servidor**
7. **Cabeçalhos:** adicionar `Content-Security-Policy` (primeiro em modo **somente relatório**, porque o app em produção carrega CanvasKit/WASM e um CSP errado o derrubaria), HSTS e `frame-ancestors`. Só vira obrigatório depois de testado.
8. **Painel admin:** exigir chave **própria** (`ADMIN_KEY`, sem cair na do feedback), registrar tentativas, manter o limite de tentativas, tudo exibido com `textContent` (já é).
9. **API:** exigir `Content-Type` JSON, rejeitar corpo grande e campos inesperados, erro sem detalhes internos, limites por perfil e por origem (já existem; revisar as ações novas).
10. **Testes de guardrail:** entradas malformadas, gigantes, com HTML/script e caracteres invisíveis em todas as ações; garantir que nada vaza (segredo, hash) em respostas.

## Ordem e publicação
Fase 0 validar botões → Fase 1 navegação → Fase 2 textos → **Espaçamento** → **Guardrails** (CSP em somente relatório primeiro). Cada pacote separado, com testes, conferência no Chrome e o seu "sim" antes de publicar.
Observação: guardrails 1, 3, 4 e 9–10 não mudam o visual e podem ir antes de tudo, se preferir segurança primeiro.

---
## Andamento (10/11/2026)
- **Fase 1, pacote 1 (pronto, aguardando publicação):** barra de cima só com **Avisos** e **Eu**; "Eu" (Perfil) ganhou os botões **Ajustes** e **Compartilhar app** no topo (o tema continua em Ajustes › Aparência); Meu espaço sem atalhos repetidos (saíram Perfil, Ajustes e Relatórios das ferramentas); "Para validar" abre direto a ficha do aluno que espera validação (se houver mais de um, a lista de alunos).
- Falta da Fase 1: fundir a "Área do professor" em Alunos + Relatórios, trilha curta nas telas fundas, padrão de tela (título, voltar, "?", ação principal) e retorno ao ponto de partida após cada ação.
- **Fase 1, pacote 2 (pronto, aguardando publicação):** a "Área do professor" virou **Alunos** (título, textos que a citavam e botão "Abrir Alunos" no perfil); o cartão de apresentação e o guia "Como funciona" saíram da tela e foram para o **"?"** da barra; a ficha mostra a trilha curta "Alunos › Marina".
- **Pacote 3 (pronto, aguardando publicação):** tela **Alunos** redesenhada (faixa com "1 aluno · 1 para validar · aulas hoje", cartão do aluno com próxima aula e marcas, ações agrupadas: Novo aluno, Ler QR e Importar lado a lado, Métodos e Senha numa lista); **Minha conta** (antes "Perfil e professor") com margens de 16 e respiro maior entre cartões, abas "Perfil" e "Professor"; títulos coerentes ("Ajustes", "Horários livres", "Minha conta").
- **Resposta da IA:** itálico `*assim*` agora é desenhado (antes aparecia com asteriscos); botão "Copiar resposta" copia com quebras de linha (copiar direto da tela juntava os blocos); o servidor dá mais folga de tokens ao Gemini (modelos que "pensam" cortavam o final) e, se ainda for cortada, remove a frase pela metade e avisa.
- **Pacote 4 (pronto, aguardando publicação): visões Aluno | Professor no Meu espaço.** `hub_view.dart` define a regra única: quem tem os dois papéis vê um alternador **Aluno | Professor** (a escolha fica guardada); quem tem um só não vê alternador. Cada visão tem seus próprios blocos, ferramentas, próxima aula e avisos, e **cada destino aparece uma única vez por tela** (o destaque deixou de repetir "Agenda do aluno/professor": agora só leva à ficha da aula ou ajuda a começar). Testes garantem: sem destino repetido em nenhum estado, sem destino de professor na visão do aluno (e vice-versa), no máximo 2 blocos.
