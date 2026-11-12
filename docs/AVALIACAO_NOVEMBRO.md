# Avaliação do Notemusic: onde estamos e para onde vamos (12/11/2026)

Esta avaliação mistura **fatos medidos** (códigos, testes, CI, tamanhos) e **minha opinião**. Onde é opinião, digo. Onde não consegui verificar, digo também (seção 9).
Método: li o código e os documentos, rodei todas as verificações, medi tamanhos e custos, consultei o estado do CI pelo GitHub e abri o app em celular simulado (390×844) durante todo o desenvolvimento.

## 1. Em uma página

**Veredito.** O projeto saiu de "afinador" para uma **plataforma pequena de professor e aluno** (vínculo, agenda, tarefas, validação, horários livres, aula online, faltas, acervo, painel de suporte) em cerca de 3 semanas. A **base técnica é saudável e acima da média para um projeto desse tamanho** (regras testadas, API compatível, custo medido, publicação controlada). Os **maiores riscos não são de código: são de dados do professor só no aparelho, de falta de teste em celular real e de falta de dados de uso para guiar as próximas apostas.**

| Dimensão | Situação | Em uma frase |
|---|---|---|
| Regras de negócio (núcleo) | Forte | 7 mil linhas puras e 589 testes: onde o erro custaria mais está mais protegido. |
| API e dados | Forte | 8 de 12 funções, 297 testes, compatível com apps antigos, custo medido. |
| Interface (telas) | Bom, com atenção | Visual evoluiu muito, mas ~26 mil linhas de interface e estado têm só 40 testes de tela e a conferência é manual. |
| Arquitetura do app | Atenção | `AppState` com 4,3 mil linhas e 42 seções virou o ponto único de mudança e de risco. |
| Operação, custo, publicação | Forte | Chaves de recursos, CI verde, painel de custos com projeção, regra "só publica com sim". |
| Segurança e privacidade | Bom, com pendências | Boas práticas e testes de proteção; faltam revisão jurídica e teste de invasão. |
| Dados do professor | **Risco** | Alunos, tarefas, notas e faltas ficam só no aparelho; sem backup automático. |
| Teste em aparelho real | **Risco** | Nenhum celular real testado nesta rodada; o produto depende de microfone e vibração. |
| Acessibilidade | Atenção | Pouco uso de rótulos para leitor de tela (62 pontos) e app desenhado em canvas. |
| Desempenho de carga inicial | Atenção | 4,6 MB de JavaScript (1,4 MB compactado) na primeira abertura. |
| Direção do produto | Atenção | Muita coisa nova, pouco dado de uso lido; falta escolher 3 números para guiar. |

## 2. Onde estamos (números)
| Item | Valor |
|---|---|
| Código do app (Flutter, `lib/`) | ~25,9 mil linhas; 14 arquivos com mais de 500 linhas |
| Núcleo puro (`packages/afina_core`) | ~7,0 mil linhas de código e ~5,9 mil de testes (589 testes) |
| API (Node, `api/`) | ~4,6 mil linhas de código e ~4,8 mil de testes (297 testes) |
| Painel admin e service worker | 1,7 mil e 149 linhas |
| Testes de tela | 40 testes (7 arquivos), só de peças sem áudio nem `AppState` |
| Teste de fumaça (CI) | 13 passos, inclui abrir o app num Chrome sem janela |
| CI no GitHub (consulta de hoje) | **Verde**, inclusive no último envio (CI e varredura de segurança), com fumaça e testes de tela rodando lá |
| Documentação | 24 arquivos em `docs/`, conferidos por script (`check_docs`) |
| Histórico | 143 commits, todos em novembro/2026 |
| Peso do app web | `main.dart.js` 4,6 MB (≈ 1,36 MB compactado) |
| Funções da Vercel | 8 de 12 (limite do plano Hobby) |
| Dependências do app | 19 diretas; 15 pacotes com versão nova incompatível pelas restrições atuais |
| Custo (simulação do painel Contas) | US$ 0 até ~1.000 usuários ativos (com aviso na Vercel); ~US$ 3 com 5 mil; ~US$ 27 com 10 mil |
| Pontos soltos no código | 3 marcas de pendência (TODO/FIXME) em todo o projeto |

## 3. O que está funcionando bem
1. **O que mais custaria erro está testado.** Agenda, remarcar, trocar, pausar, faltas, horários livres, status de tarefas, afinação e metrônomo moram no núcleo, sem Flutter, e rodam em segundos. A "trava do primeiro que pega o horário" tem teste que **falha de verdade** quando quebro o código de propósito (conferi isso mais de uma vez).
2. **Publicar sem quebrar quem já usa.** Recurso novo nasce desligado e é liberado por chave (aula online, lembrete escolhido, acervo). A API ignora campos novos de app antigo e **mantém** o que já estava guardado. Isso foi decidido cedo e foi respeitado em todas as entregas.
3. **Custo conhecido antes de crescer.** A aba Custos › Contas projeta o gasto para 100, 1.000, 5.000 e 10.000 usuários; a simulação de carga mede comandos do Redis por usuário. O primeiro limite a apertar é o de chamadas de função da Vercel Hobby, não o banco.
4. **Observabilidade.** Painel com erros e bugs, funil de ativação, saúde, comparar agendas, suporte ao usuário e registro de cada ação do admin, com confirmação contra clique acidental.
5. **Documentação que não apodrece.** Há script que reprova se um módulo novo não estiver documentado e se a referência gerada estiver velha.
6. **A experiência do professor ficou coerente**: vínculo claro, Meu espaço, agenda em calendário com ações à vista, "Aluno faltou", lembrete escolhido, modais que mostram o que vai mudar antes de confirmar.
7. **Cuidado com o custo de cada recurso** (consultas espaçadas, uma mensagem por vez no QStash, contadores em lote). Isso evita a surpresa de conta que mata projeto pequeno.

## 4. Riscos e fraquezas (do mais grave ao menos)
### 4.1 Os dados do professor moram só no aparelho (risco alto)
Alunos, tarefas, observações, histórico e as faltas ficam no armazenamento do navegador ou do app. Se a pessoa limpar os dados do navegador, trocar de celular ou o sistema apagar o armazenamento de um site que ela não abre há dias (o Safari do iPhone faz isso com sites não instalados; vale conferir a regra atual), **tudo some e não há como recuperar**. Hoje a única proteção é exportar e importar por texto, à mão.
*Minha recomendação:* backup que o professor consiga ligar (arquivo exportável e lembrete periódico; ou cópia no servidor, com a decisão de privacidade que isso exige). Antes de qualquer crescimento.

### 4.2 Nenhum celular de verdade testado nesta rodada (risco alto)
Tudo foi conferido em Chrome com tela de celular simulada. O produto depende de **microfone em tempo real, vibração, instalação na tela inicial, notificações e botão voltar**. Esses pontos só se provam em Android e iPhone reais. Os lembretes (QStash e VAPID) também não foram confirmados ativos em produção.
*Recomendação:* rodada de 30 minutos nos dois sistemas (roteiro na seção 5 do `PLANO_DE_TESTES.md`).

### 4.3 Falta de teste na camada de tela e no `AppState` (risco médio-alto)
As regras estão bem protegidas; **a cola** entre regras e telas não. O teste de fumaça cobre fluxos do servidor e a abertura do app, mas **não clica nos botões do Flutter**. As ~26 mil linhas de interface e estado e as 165 funções do `AppState` dependem de conferência manual (a minha e a sua). Uma mudança de tela pode quebrar outra sem que ninguém perceba até um usuário reclamar.
*Recomendação:* separar do `AppState` pequenas interfaces para as telas que mais importam (formulário de aula, ficha do aluno, Comece por aqui) e testá-las como já fiz com os modais da agenda.

### 4.4 `AppState` virou o ponto único de mudança (risco médio)
4.267 linhas, 42 seções (afinação, perfil, professor, vínculo, agenda, horários livres, avisos, estudo, escalas, permissões, vibração...). Cada recurso novo engorda o mesmo arquivo; `teacher_page.dart` já tem 1,8 mil linhas. Ainda é gerenciável, mas o custo de cada mudança só cresce e a chance de efeito colateral também.
*Recomendação:* extrair por domínio, aos poucos, a cada recurso novo (agenda, vínculo, tarefas, estudo), como já fiz com `study_card`, `agenda_sheets` e `meeting_link`. Sem "grande refatoração".

### 4.5 Direção guiada por intuição, não por dados (risco médio)
Eu não li os números de uso de produção (não tenho a chave do painel). O que sei é que as prioridades vieram das suas ideias e do feedback de poucas pessoas (principalmente o Vinícius). Isso é natural no começo, mas o produto cresceu rápido: **não sei quantos professores e alunos realmente usam agenda, tarefas ou aula online**. Um exemplo concreto: o Meu espaço agora abre primeiro **para todos**; para quem só quer afinar, isso pode ser um passo a mais.
*Recomendação:* escolher 3 números e revisar toda semana (seção 6).

### 4.6 Peso e acessibilidade da versão web (risco médio-baixo)
4,6 MB de JavaScript mais o CanvasKit na primeira abertura é pesado em 4G fraco (depois o cache ajuda). A tradução para português somou +140 KB compactados. Como a tela é desenhada em canvas, leitores de tela dependem de rótulos explícitos, e só há 62 pontos com rótulo ou dica em todo o app.
*Recomendação:* medir tempo de abertura em 4G real; ampliar rótulos nas telas principais (Meu espaço, Agenda, Alunos).

### 4.7 Jurídico e privacidade antes de crescer (atenção)
Há política de privacidade e regras de retenção, mas **faltam a revisão por advogado** (acervo de links, direitos autorais, dados de alunos, possivelmente menores de idade) e o **teste de invasão básico**. Com mais usuários, a exposição cresce.

### 4.8 Licença da hospedagem (atenção)
O plano gratuito da Vercel é para **uso não comercial**. Se o app passar a gerar receita (anúncios, assinatura), o plano muda para o Pro (US$ 20 por mês), mesmo com poucos usuários.

### 4.9 Dívidas pequenas
- Os avisos de tela são classificados **pelo texto** (verde, laranja, azul). Funciona nas 117 chamadas de hoje, mas mudar uma frase pode mudar a cor. O certo é cada chamada dizer o tipo.
- Pacotes desatualizados (15) pedem uma rodada de atualização planejada.
- 14 arquivos com mais de 500 linhas.

### 4.10 Ritmo de mudança (observação de processo)
Seis commits ficaram acumulados antes de publicar, e entraram juntos mudanças que alteram **hábitos** (Meu espaço primeiro, barra de baixo reordenada, "Seu estudo" no Metrônomo, agenda em calendário). Para quem já usa, é muita mudança de uma vez e **não há aviso dentro do app explicando o que mudou**.
*Recomendação:* um aviso "O que mudou" no sino a cada entrega que mexe em navegação, e publicar em lotes menores.

## 5. Avaliação por área
| Área | Estado | Observação |
|---|---|---|
| Afinador | Maduro | Detecção testada (erro abaixo de 0,5 centavo de semitom em tons limpos; resposta rápida em notas curtas). **Não reavaliei a precisão em instrumentos reais nesta rodada.** |
| Metrônomo | Maduro | Sem deriva testada; agora com duas visões (Metrônomo e Estudo e timers). Latência no aparelho real é a incógnita. |
| Grade e escalas | Maduro | Exercício guiado com histórico; é o coração da parte de estudo. |
| Vínculo professor-aluno | Bom | Código e segredo anônimos, desfazer vínculo, painel de suporte. Fluxo claro. |
| Agenda | Bom | Calendário, remarcar, trocar, pausar, cancelar, faltas e lembrete escolhido. Falta pedido de troca do aluno e reposição. |
| Tarefas e validação | Bom | Status oficial decidido pelo professor; falta tutorial do aluno. |
| Aula online | Novo, atrás de chave | Só link (Meet, Zoom...). Sem uso real ainda; liberar para o Vinícius é o próximo teste. |
| Acervo | Novo, atrás de chave | Só links, por decisão jurídica; revisão de advogado pendente. |
| Painel admin | Forte | Mais maduro do que o app para o tamanho atual. |
| Infra e custo | Forte | Margem folgada; atenção à licença se houver receita. |

## 6. Para onde vamos (proposta)
### Horizonte A: estabilizar e medir (próximas 2 semanas)
1. **Você:** CI verde, 30 minutos em Android e iPhone reais, confirmar as chaves de lembrete, ligar Secret scanning e proteger o `main`.
2. **Eu:** backup e restauração dos dados do professor (risco 4.1) e aviso "O que mudou" no sino.
3. **Você e eu:** escolher **3 números** do painel e olhar toda semana. Sugestão: (a) % de perfis que vinculam um aluno; (b) % de professores que marcam aula toda semana; (c) % de alunos que abrem a agenda ou fazem uma tarefa na semana. Mais: quantos abrem direto o Afinador, para decidir se o Meu espaço deve abrir primeiro para todos.
4. **Eu:** testes de tela do formulário de aula, da ficha e do Comece por aqui, reduzindo o `AppState` por interfaces pequenas.

### Horizonte B: o dia a dia do professor (1 a 2 meses)
Na ordem de valor, cada item atrás de uma chave: pedido de troca do aluno; reposição das faltas; agenda em grade da semana; lembrete com o botão "Entrar"; tutorial do aluno; acervo para todos (depois da revisão jurídica). Extrair um domínio do `AppState` a cada item.

### Horizonte C: crescer com segurança (3 meses ou mais)
Metas e retenção a partir do funil; vídeos e divulgação (o painel Visitantes mede); decidir **monetização** (muda a hospedagem); carga real em ambiente de teste; acessibilidade; loja **só quando você decidir** (hoje adiada).

### O que eu **não** faria agora
- Nova funcionalidade grande sem antes olhar os números de uso.
- Loja de aplicativos (já decidido) ou troca de tecnologia.
- Guardar mais dados no servidor sem decidir a política de privacidade.
- Mais recursos para o professor antes de o backup existir.

## 7. O que estou achando do desenvolvimento
**O que está dando certo.** Ciclos curtos com pedidos concretos; a regra de **testar, mostrar no navegador e só então pedir o "sim, publicar"** evitou incidente; os testes que falham quando quebro o código de propósito me dão confiança real; as chaves de recursos e a compatibilidade da API deixam errar sem derrubar quem usa; e o hábito de medir custo antes de crescer é raro e valioso.

**O que me preocupa.**
1. **Velocidade maior que a validação com usuários.** Em 12 dias de commits entraram vários recursos de peso. Só uma pessoa de verdade (o Vinícius) é professor de teste, segundo o que sei. É pouco para confirmar que a direção está certa.
2. **Eu só enxergo pela web simulada.** Não uso o app no celular, não ouço o afinador, não sinto a vibração. Por isso insisto na rodada em aparelho real.
3. **A parte do código que mais cresce (`AppState` e telas) é a menos testada.** Está tudo ok hoje; fica caro amanhã.
4. **Mudanças de hábito empilhadas** (navegação) sem aviso ao usuário.
5. **Dependência de uma pessoa e de uma IA** para a manutenção. A documentação mitiga muito, mas vale um segundo par de olhos humano de vez em quando (revisão do código antes da loja, por exemplo).

**O que eu elogio sem reserva.** As decisões de privacidade e de custo tomadas **antes** do crescimento; o painel de suporte; e o cuidado de nunca quebrar um app antigo.

## 8. Decisões que preciso de você
1. **Backup dos dados do professor:** arquivo que ele guarda, cópia no servidor, ou os dois? (Muda a privacidade e o custo.)
2. **Meu espaço primeiro para todos** ou só para quem tem professor ou aluno? (Os números ajudam a decidir.)
3. **Quem são os próximos professores e alunos de teste** além do Vinícius? Cinco pessoas já mudam muito a qualidade do que sabemos.
4. **Haverá receita?** Se sim, o plano da hospedagem muda.
5. **Próximo recurso do professor:** pedido de troca do aluno ou reposição de faltas?

## 9. O que **não** consegui verificar
- Dados reais de uso em produção (não tenho acesso ao painel nem à chave).
- Qualquer coisa em Android ou iPhone reais: microfone, vibração, instalação, notificações, botão voltar do sistema.
- Precisão do afinador com instrumentos de verdade e latência do metrônomo no aparelho.
- Se os lembretes (QStash e VAPID) estão ativos na Vercel.
- Velocidade de abertura em 4G real e uso da página com leitor de tela.
- Regras atuais de armazenamento do Safari e dos navegadores para sites e PWAs (citei de memória; vale conferir).
