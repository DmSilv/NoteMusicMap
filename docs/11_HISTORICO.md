# Histórico de entregas

Resumo do que já foi publicado, em ordem. O detalhe de cada etapa está no roteiro ([ROADMAP_ETAPAS.md](ROADMAP_ETAPAS.md)) e nos planos ([PLANO_TEXTO_E_NAVEGACAO.md](PLANO_TEXTO_E_NAVEGACAO.md), [PLANO_ERROS_ADMIN_DOCS.md](PLANO_ERROS_ADMIN_DOCS.md)). Os hashes ajudam a achar o commit (`git show <hash>`).

## Base do app (antes do roteiro)
Afinador (cordas soltas, cromático), metrônomo por amostra exata, grade de entonação, escalas guiadas, estudo (Pomodoro, cronômetro, meu tempo), IA multi-modelo com fila, modo professor local, **vínculo online**, aulas e tarefas, **agenda com lembrete por Web Push**, estatísticas anônimas e painel inicial.

## Roteiro em 6 etapas
| Etapa | Entrega | Commit |
|---|---|---|
| Pedal | Modo "Pedal" no Afinador (até 4 notas sustentadas) + ajuste de layout | `5e6a660`, `2ed9eb5` |
| 1 | Vínculo online claro e reversível (estado, reconectar, desativar) | `3711a3a` |
| 2 | Hub "Meu espaço" por papel | `8e33a0a` (+ `8de4215` botão Escalas) |
| 3 | **Professor como fonte oficial** do status das tarefas; resumo ao começar a aula | `872fb31` |
| 4 | **Horários livres** e "Pegar horário" | `3c774d5` |
| 5 | Painel do administrador: índice de perfis, indicadores, bloquear/excluir | `fcf3d5f` |
| 6 | Endurecimento: custos, limites, regressão, limpeza da trava de horários | `b22542c` |

## Depois do roteiro
| Entrega | Commit |
|---|---|
| Backlog: Meu espaço × Agenda sincronizados, regra única das aulas (`class_rules`), **central de avisos** | `d2bc73d` |
| Agenda do professor × agenda do aluno explícitas | `93cb2f4` |
| Conserto do deploy (limite de 12 funções: `.vercelignore`) | `deaabd5` |
| **Guardrails** de segurança (CSP em relatório, HSTS, código estrito, trava de toque duplo, testes) | `998b9ac` |
| Navegação: barra só com Avisos e Minha conta; "Eu" com Ajustes/Compartilhar; hub sem atalhos repetidos | `64dde75` |
| Área do professor vira **Alunos** (+ guia no "?" e trilha) | `873d4dc` |
| Alunos redesenhado; Minha conta com mais respiro; resposta da IA sem texto quebrado | `5013877` |
| Ícones nos botões de ação | `33462f2` |
| **Visões Aluno | Professor** no Meu espaço | `82ab0b9` |

## Plano "erros, admin, documentação"
| Pacote | Entrega | Commit |
|---|---|---|
| 1 | Tela e avisos de erro (catálogo, captura global, tela crítica, Problemas recentes) | `49e3928` |
| 2 | Coleta de relatórios de erro + aba **Bugs** no painel | `133d9a1` |
| 3 | Painel preciso e lúdico (abas, semáforo, definições, comparações, jornada, mapa de calor, coortes, custos) + erros do servidor | `2c4a770` |
| 4 | **Esta documentação** (+ `scripts/gen_docs.js`) | — |

## Backlog / ideias em aberto
- Dieta de texto nas demais telas (parágrafos → "?") e espaçamento do resto do app (plano em `PLANO_TEXTO_E_NAVEGACAO.md`).
- Padrão de tela único (título, voltar, "?", ação principal) e retorno ao ponto de partida em todas as ações.
- Cadastrar uma grade semanal de horários livres de uma vez.
- Testes em aparelhos reais: push (Android/iPhone), validar/devolver e pegar horário entre dois aparelhos, painel com dados reais, som do pedal.
- Remover o *fallback* `FEEDBACK_ADMIN_KEY` e passar a CSP para modo bloqueio quando seguro.
- Push para o administrador em bug crítico (hoje só o painel avisa).

## Apelido, saudação e largura (novembro/2026)
Faixa "Como posso te chamar?" (dispensável), saudação por hora com o apelido e coluna de 560 px centralizada no navegador em tela larga.

## Grade e cordas soltas (novembro/2026)
No temperamento igual, a grade passou a medir as cordas soltas de instrumentos de arco (ex.: Sol, Ré, Lá, Mi do violino) pelo mesmo alvo do afinador de cordas (quintas puras). Antes o Sol afinado aparecia 3,9 cents baixo na grade.

## Painel: aba Aparelhos e status de atualização (novembro/2026)
O app envia, uma vez por dia, uma ficha de categorias do aparelho (sistema e versão, tela, idioma, tema, toque, microfone, notificações). A aba Aparelhos do painel filtra por qualquer combinação, em 1, 7 ou 30 dias. O painel mostra "Atualizando…" e avisa, com toque para tentar de novo, quando não consegue atualizar.

## Vínculo ligado por padrão, nome obrigatório e atualização com aviso (novembro/2026)
O vínculo online liga sozinho para quem é professor ou tem professor/aluno vinculado; desligar pede confirmação clara (fica offline) e, se desligado com gente dependendo dele, aparece a faixa "Você está offline" com botão Ligar. Para se vincular (ou ser professor) o nome passa a ser obrigatório. "Versão nova disponível" vira faixa fixa com botão Atualizar, conferida ao abrir e ao voltar ao app. A tela inicial mostra o nome do professor ou a quantidade de alunos.

## Afinação visível e editável nas escalas (novembro/2026)
A tela de escalas ganhou a linha "Afinação" (ex.: Pitagórico · Lá 440 Hz), que abre a escolha do sistema; o exercício guiado mostra o mesmo selo, tocável. O texto de "Igual" deixou de afirmar temperamento igual puro quando as cordas soltas usam quintas puras.

## Importação de métodos removida (novembro/2026)
A importação de métodos por texto colado saiu: cada método e lição é cadastrado um a um. "Copiar lista" continua. A cópia de dados de um aluno para outro aparelho não mudou.

## Tablet deitado com duas telas (novembro/2026)
Em tela deitada com 900 px ou mais de largura, o app mostra duas telas lado a lado (padrão: Afinador e Metrônomo), cada lado com o seu seletor (Afinador, Metrônomo, Grade, Meu espaço); a mesma tela não aparece nos dois lados, a barra de baixo some e a escolha é lembrada. Em celular, tablet em pé e telas estreitas nada muda; em navegador largo e em pé continua a coluna central de 560 px.

## Escalas na barra de baixo (novembro/2026)
A barra tem 5 itens: Afinador, Metrônomo, Grade, Escalas e Meu espaço. A Grade ficou com Grade e Ajustes; as escalas e arpejos guiados viraram a aba Escalas (os atalhos do Meu espaço levam a ela). No tablet deitado o seletor de cada lado também ganhou Escalas. O painel passa a contar a aba "scales".

## Minha conta em lista (novembro/2026)
A tela "Minha conta" deixou as abas Perfil e Professor e virou uma lista curta: nome e código no topo, grupos Vínculos (vínculo online, meus professores, minhas aulas), Professor (modo professor e meus alunos) e Conta (chave de recuperação, ajustes, compartilhar). Cada linha abre a sua tela. O código e o QR agora são um só, em "Meu código e QR", com seletor "Para meu professor / Para meus alunos" (o segundo só no modo professor). Nenhuma função foi removida e a API não mudou.

## Metrônomo: piscar e vibrar de verdade (novembro/2026)
"Piscar a tela na batida" agora dá um clarão na tela do metrônomo (forte = mais claro) além de acender a bolinha; **não usa a lanterna** (sites não controlam a lanterna de forma confiável). "Vibrar na batida" usa pulsos de 70 ms (forte) e 45 ms (demais), mostra por que não vibra quando o aparelho não suporta (iPhone/iPad, computador) e ganhou "Testar vibração". "Zerar" dos cronômetros virou "Reiniciar". Barra de cima alinhada à margem de 16 px.

## Ajustes finos de tela, microfone sozinho e ícones (novembro/2026)
Margem lateral de 16 px e cartões de 18 px (cabe em 360 px sem quebrar o menu); botões do Afinador logo abaixo das cordas; **microfone liga sozinho no Afinador** (só depois de liberado uma vez, desliga ao sair da aba, preferência em Ajustes); barra de cima com sino e perfil em círculos (inicial do nome) e aba Meu espaço com ícone de calendário; ícones do Meu espaço em quadradinhos coloridos; o aviso "Ouvindo" não se repete nas telas que já têm o botão do microfone.

## Meu espaço com foco na agenda (novembro/2026)
O Meu espaço passou a abrir pela **agenda**: a próxima aula em destaque, as próximas 3 (14 dias) e os atalhos (agenda completa, horários livres, pegar horário) dentro do mesmo bloco; a faixa de "Ferramentas" (que repetia Metrônomo e Escalas da barra de baixo) saiu. O resumo de estudo e o cronômetro viraram **um bloco só** (`FramelessScope` tira a moldura dos cartões internos). Os dados e gráficos (últimos 7 dias, evolução nas escalas, treinador) foram para a tela **Evolução** (`lib/ui/evolution_page.dart`), aberta por "Evolução" no bloco de estudo.

## Design system e telas principais enxutas (novembro/2026)
Criado `lib/ui/design_system.dart` e `docs/12_DESIGN_SYSTEM.md` (regra permanente para toda tela). Afinador, Metrônomo, Grade, Escalas e Meu espaço passaram a mostrar só o essencial e a ação principal; os ajustes foram para modais ("Ajustes ⚙", "Concluir"). Apelido e "Instalar" saíram do topo e foram para o sino; cartões com 20 px, margem de 20 px e botões de 48 px no tema.

## Links curtos de divulgação (novembro/2026)
Foram criados `/yt`, `/ig`, `/tt`, `/zap` e `/l`, que abrem o app já com a origem marcada (`?o=`), para o link falado e digitado nos vídeos ser curto. O roteiro do vídeo V09 (foco em abrir o link no Shorts) fica em `divulgacao/videos/`.

## Backlog fechado: CSP em bloqueio, dieta de texto e aviso da chave (novembro/2026)
A política de segurança de conteúdo (CSP) passou de "somente relatório" para **bloqueio**, depois de aplicá-la localmente e conferir app, abas, conta, som e painel sem violações. 19 textos longos de tela foram encurtados (de 37 para 19 acima de 110 caracteres) e `scripts/check_text.js` impede que voltem a crescer. O painel (Sistema) avisa quando ainda usa a chave do feedback no lugar da `ADMIN_KEY`; o *fallback* continua no código até você confirmar que a `ADMIN_KEY` própria está na Vercel.

## Aviso de bug grave, precisão dos bugs e exportação (novembro/2026)
O painel avisa por notificação do navegador quando surge um bug grave novo ou reaberto (`push` em `/api/admin`, `api/_lib/admin_push.js`, `sw.js`; até 5 navegadores, 6 avisos por hora, precisa das chaves VAPID). Os bugs agrupam melhor (números e endereços variáveis saem da impressão digital) e mostram se ainda acontecem na versão publicada agora (filtro "só na versão atual"). Bugs e Pessoas exportam CSV no navegador; Pessoas busca também pelo apelido (100 mais recentes).

## Indicadores de saúde do uso (novembro/2026)
A Visão geral do painel ganhou cinco cartões: notificações negadas, versão antiga do app, IA hoje (contra o limite diário), perfis online e perfis bloqueados (novo conjunto `pf:bl`). Saem de dados que o servidor já tem (fichas dos aparelhos dos últimos 7 dias, contador de IA, presença), em ~10 comandos por abertura. "Aulas pendentes" e "vínculos travados" ficaram de fora: o servidor não sabe o que espera envio no aparelho do professor.

## Presença online no admin (novembro/2026)
A aba Pessoas ganhou "Perfis online agora": perfis com vínculo ligado e app à frente que deram sinal nos últimos 12 min, e quem esteve online há pouco (offline). O sinal sai da consulta que o app já faz (`rev`/`sync`): no máximo 1 gravação de 2 comandos a cada 10 min por perfil (~12 comandos por hora de uso). Só código e horário são guardados; o app ganhou o aviso em Minha conta e na política de privacidade.

## Suporte do admin (novembro/2026)
O detalhe do perfil no painel ganhou: vínculos com data e última atividade (e selo "Também é aluno"), **encerrar vínculo**, **ver e apagar itens de agenda** e **código de liberação** de uso único (24 h) para recuperar a conta em outro aparelho (`claim` em `/api/link`; o app tem o campo em Minha conta › Chave de recuperação). Cada ação entra no registro e vira um aviso do tipo "suporte" no app (`sn` em `sync`/`rev`, sem custo extra). A rotina de desvincular foi para `api/_lib/unlink.js` e é a mesma do app e do painel. O nome do usuário não é editável pelo painel.

## Divulgação (novembro/2026)
Site: página `/sobre` (texto indexável + perguntas frequentes), `robots.txt`, `sitemap.xml`, título/descrição e dados estruturados melhores, `<noscript>`. Medição de origem das visitas por marca no link (`?o=yt`, `?o=ig`, `?o=tt`, `?o=zap`, `?o=site`), guardada no primeiro acesso do aparelho e mostrada em `/admin` › Uso › "De onde vieram". O plano de divulgação e os textos prontos ficam fora do repositório, na pasta local `divulgacao/`.

## Grade mais limpa (novembro/2026)
A grade da tela Grade ficou menor (4 oitavas por padrão, ~52 px por linha) e ganhou o botão "Ampliar a grade" para tocar em tela cheia. A legenda virou uma barra de cores com três rótulos (Grave: suba · Afinado · Agudo: desça). O seletor de oitavas é um trilho único com uma janela que desliza (números 0–8, ponto nas já tocadas, "Lá" na 4) e setas redondas. Quantidade de oitavas e "Seguir a nota que eu toco" foram para o modal "Ajustes da grade".

## Modo desafio em três desafios (novembro/2026)
O Modo desafio do metrônomo ganhou três desafios com nome: **Sumiço** (o metrônomo some e volta), **Elástico** (o andamento estica e encolhe) e **Surpresa total** (os dois), mais uma dificuldade Leve/Médio/Intenso. A tela diz exatamente o que vai acontecer ("A cada 4 a 8 compassos… de 100 para cerca de 122 ou 78"), mostra uma prévia de 16 compassos e, tocando, avisa na hora ("Sumiço! Segure o pulso…", "Mais rápido!"). O fim mostra quantas vezes o metrônomo sumiu ou mudou. O formato salvo (`l`, `t`, `s`) não mudou: quem já usava o desafio continua igual.

## Grade em tela cheia legível (novembro/2026)
Na tela cheia a grade ganhou margens laterais maiores e letras bem maiores; com o celular em pé a grade gira: as 12 notas viram linhas e as oitavas viram colunas, e o texto fica reto e grande.

## Afinação na Grade (novembro/2026)
Os Ajustes da grade ganharam "Afinação": Lá de referência (415 a 443 Hz, com ajuste fino) e sistema (Igual, Pitagórico, Justo), os mesmos das Escalas e do Afinador.

## Arpejos e escalas com 4 oitavas e cores por oitava (novembro/2026)
Escalas e arpejos aceitam até 4 oitavas (também nas tarefas do professor; o formato salvo é o mesmo, só o limite subiu de 3 para 4). Durante o exercício guiado, os quadradinhos vêm em blocos "1ª oitava", "2ª oitava"… com uma tinta bem leve por oitava (violeta, rosa, dourado, prata; `lib/ui/octave_colors.dart`). A prévia "Notas do exercício" é só informativa: texto simples, sem moldura nem cor, para não parecer botão.

## Escalas e arpejos mais enxutos (novembro/2026)
A tela Escalas ficou mais limpa: o cartão da escala tem título menor e a explicação do arpejo foi para o "?"; no exercício guiado os textos explicativos dos modos foram para o "?", o pedido de microfone ficou compacto e, com 1 oitava, os quadradinhos não ganham bloco colorido.

## Exercício guiado: o essencial primeiro (novembro/2026)
No exercício guiado, o bloco de tocar (nota, agulha e orientação) vem logo no topo; o progresso virou uma linha fina embaixo dele, e o jeito de tocar (Livre ou Guiado) e a afinação foram para o modal de ajustes (botão na barra de cima). Os textos ficaram curtos ("Sua vez!", "Qualquer uma da escala!") e o aviso de espera "Toque uma nota" ficou pequeno e discreto.

## Revisão dos ícones (novembro/2026)
Ícones trocados para combinar com o texto: Evolução (gráfico com brilho), Seu estudo (livro aberto, deixando o cronômetro só para o metrônomo), Escalas (degraus), Arpejos (teclas de piano), aba Afinador (onda de som, já que os controles deslizantes são o ícone de Ajustes), Publicar horário, Apagar tudo e recomeçar (lixeira), Pesquisa rápida e Meus alunos (grupo).

## Ícones sumindo depois de atualizar (novembro/2026)
Causa: a fonte de ícones do Flutter muda a cada publicação (só leva os ícones usados) mas mantém o mesmo nome, e o site mandava guardar `assets/`, `canvaskit/` e `icons/` por 7 dias; o navegador misturava o código novo com a fonte velha e ícones sumiam (em aba anônima funciona porque não há cache). Correção: esses arquivos agora sempre conferem com o servidor (`must-revalidate`, resposta curta 304 quando nada mudou), o service worker pede `no-cache` e ganhou um cache por versão (carimbado pelo build), e, se uma versão nova do service worker assumir logo ao abrir, a página recarrega uma vez sozinha. Ninguém precisa limpar cache.

## Regra de cadastros e limpeza de perfis (novembro/2026)
Regra escrita em docs/03 (seção 10): visitante não cria cadastro; o perfil nasce só com intenção (e apelido); limite por origem subiu de 30 para 100 por dia, com aviso no painel acima de 30 (escola ou igreja no mesmo Wi-Fi); perfis vazios e parados há 60 dias são apagados automaticamente (e pelo botão "Limpar agora" em Saúde do uso). A política de privacidade avisa da limpeza.

## Ajustes mais limpos (novembro/2026)
A tela Ajustes virou uma lista curta de linhas (ícone, título e valor atual): Aparência e tela, Afinação, Som de referência, Nomes das notas, Microfone, Metrônomo, Grade, Estudo, Permissões e privacidade, Sobre o app, Problemas e diagnóstico, Restaurar e apagar. Cada linha abre um modal ("Concluir" para voltar), com os textos bem mais curtos (explicações longas foram para o "?" ou saíram). Nova peça no design system: `DsNavRow`.

## Piscar e vibrar desligados por padrão (novembro/2026)
"Piscar a tela na batida" e "Vibrar na batida" agora vêm desligados para quem abre o app pela primeira vez (e em Restaurar ajustes). Quem já tinha a escolha salva no aparelho continua com ela. A vibração é a mesma dos exercícios de escala e do Pomodoro, então esses também começam sem vibrar.

## Bug: Atualizar o app e Apagar tudo falhavam (novembro/2026)
Primeiro bug reportado pelo painel: "EvalError ... unsafe-eval". As duas ações usavam `eval`, que a política de segurança (CSP) do site proíbe, então "Atualizar o app" e "Apagar tudo e recomeçar" não faziam nada. Agora as rotinas ficam em web/index.html (`nmUpdateApp`, `nmHardReset`) e o Dart só as chama, sem afrouxar a CSP. Um teste de proteção falha se `eval` voltar ao código.

## Aba Visitantes no painel (novembro/2026)
Nova aba "Visitantes" no /admin para medir a divulgação: aparelhos de hoje (e ontem e 7 dias), novos, voltaram, sem cadastro (estimativa: aparelhos de hoje menos perfis ativos hoje), online agora e perfis novos; tabela de origem por dia (YouTube, Instagram, TikTok, WhatsApp, site e sem marca, pela marca ?o= do link); o que usaram hoje (afinador, metrônomo, grade, escalas…); microfone, instalação e notificações; aparelhos por hora e região. Vem de `action: visitors` em `api/admin.js`, só com contadores que já existiam (~35 comandos por abertura da aba). As visualizações do YouTube e do Instagram não chegam ao app, só quem abriu o link.

## Acervo e repertório do professor, em teste (novembro/2026)
Novo recurso liberado só para os códigos em `LIBRARY_TESTERS` (começa com o professor de teste): o professor cadastra métodos (Acervo) e peças (Repertório) como **links** (Drive, IMSLP, YouTube…), organizados em pastas, para todos os alunos ou para alguns. O aluno vinculado abre pelo cartão "Material de <professor>" em Meu espaço. Ao passar uma tarefa, a nova opção **Material do professor** leva o aluno direto ao item, à pasta ou ao acervo todo. Não guarda arquivo (custo ~zero), tem declaração de direitos, denúncia e moderação no painel. Ações novas na API: `lib_list`, `lib_put`, `lib_del`, `lib_report` e, no painel, `library` e `library_hide`. Tarefa nova do tipo `material` (apps antigos mostram como escala; só atinge quem recebe tarefa do professor de teste).

## Momento de sucesso (novembro/2026)
Quando algo importante dá certo, em vez de só o aviso pequeno no topo, sobe uma folha de baixo com um ✓ desenhado, uma frase e o detalhe, e some sozinha em ~2,4 s (um toque fecha). Usado em três momentos: **pegar um horário** ("Horário garantido!", só se o servidor confirmou), **marcar uma aula** ("Aula marcada!") e **enviar uma tarefa** ("Tarefa enviada", só quando a entrega chegou de verdade ao servidor). Erros e avisos comuns continuam no aviso do topo. Junto vai uma batida de vibração bem leve (22 ms), que se desliga em Ajustes › Permissões e privacidade ("Batida leve ao dar certo"); com "reduzir animações" ligado no aparelho o ✓ aparece parado. Peça nova: `lib/ui/success_moment.dart` (`showSuccessMoment`) e `AppState.celebrate`. Não usa servidor nem arquivo de animação: custo zero.

## Painel: confirmação de ações em modal (novembro/2026)
O painel deixou de usar o `confirm()`/`prompt()` do navegador. Toda ação que altera algo abre um modal que sobe de baixo, com o motivo, quem é afetado e se desfaz; o botão de confirmar só libera depois de 0,7 s, as ações sem volta pedem para segurar 1,5 s e excluir dados pede digitar o código. Ações que antes não confirmavam (limpar perfis, esconder item do acervo, cancelar código, mudar status de bug, avisos de bug grave) agora confirmam. Só mudou o `web/admin.html`; a API não mudou.

## Recursos liberados aos poucos (novembro/2026)
Nova aba **Recursos** no painel: cada novidade (hoje o Acervo e a Aula online, que ainda não existe) nasce desligada e é liberada por código (com ou sem os alunos vinculados), por parte dos usuários (1 a 99%) ou para todos; **Desligado** corta para todos na hora. O servidor decide e a sincronização do app passa a trazer `ff` (lista de recursos ligados), que apps antigos ignoram. O acervo passou a usar as chaves (LIBRARY_TESTERS continua valendo como ponto de partida). Custo: nenhum comando a mais por sincronização para o próprio perfil (campo `ff` do perfil) e 1 comando por sincronização de aluno com professor (consulta em lote); a configuração geral fica 60 s na memória da função.

## Aula online (novembro/2026, atrás da chave `aula_online`)
Aulas e horários livres ganham o modo **Presencial/Online** e o **link da sala** (pode ser posto depois); o aluno vê "Aula online" e o botão **Entrar** (agenda e Meu espaço); o professor pode guardar um **link padrão**. Só aparece para quem tiver o recurso liberado na aba Recursos. O servidor ignora modo e link sem a chave e mantém o que já havia quando o pedido vem de app antigo. Arquivos: `api/_lib/agenda.js` (`cleanMeetUrl`), `api/link.js` (`meet_set`, `keepOnline`), `packages/afina_core/lib/agenda.dart` (`meetingUrl`, modo e link no `ClassSlot`), `lib/ui/meeting_link.dart`.

## Controle da agenda do professor (novembro/2026)
Novas ações no menu da aula: **Remarcar só esta aula** (aula semanal), **Trocar horário com outro aluno** e, na barra da agenda, **Pausar aulas** (férias). Dá para **trocar o aluno** de uma aula ao editar (o aluno anterior deixa de ver e é avisado). As mudanças são conferidas juntas (sem choque, sem passado) e aplicadas de uma vez; cada aluno afetado é avisado. Também corrigido: ao mudar o horário de uma regra semanal, as datas já canceladas passavam a apontar para o horário antigo. Os seletores de data do Flutter apareciam em inglês: resolvido depois, ver "Textos do Flutter em português".

## Painel: ativação, comparar agendas e acabamento (novembro/2026)
Novo cartão **Ativação** na Visão geral (primeira vez de cada perfil em cada etapa), botão **Comparar agendas** em cada vínculo (professor × aluno: igual, falta, diferente ou sobra), "agora há X s" no topo e acabamento visual (transições, estados de foco e clique, esqueleto de carregamento). O intervalo do "agora" ficou em 30 s de propósito (custo). O funil só conta a partir da publicação desta versão.

## Tutoriais e Comece por aqui (novembro/2026)
Novo cartão **Comece por aqui** no Meu espaço do professor (vincular um aluno, marcar uma aula, passar uma tarefa, com progresso) e tutorial com tela escura e destaque nos botões (**Ver como funciona**, e o "?" da agenda). Opcional, só no aparelho, com "Rever tutoriais" em Ajustes. O tutorial do aluno ainda não existe.

## Relatório de contas no painel e plano de testes (novembro/2026)
Aba Custos ganhou **Contas**: quanto custa manter a plataforma hoje e para 100, 1.000, 5.000, 10.000 ou N usuários (em dólar e reais, com avisos de limite). Novo script `scripts/simulate_load.js` (carga lógica) e `docs/PLANO_DE_TESTES.md`. Conclusão da simulação: com ~1.000 usuários ativos o banco ainda cabe no grátis; o primeiro limite a apertar é o de chamadas de função da Vercel (Hobby), e uso comercial exige o plano Pro (US$ 20/mês).

## Teste de fumaça no CI (novembro/2026)
Novo `scripts/smoke.js`, executado no CI depois do build: repete os fluxos principais (marcar, pegar horário com dois alunos ao mesmo tempo, tarefa, aula online, remarcar, trocar, pausar, painel) e abre o app num Chrome sem janela. Falha sozinho se um fluxo quebrar; comprovado quebrando a trava "o primeiro leva" de propósito.

## Testes de tela do Flutter no CI (novembro/2026)
Novo `scripts/ui_tests.js`: monta um pacote isolado só com as peças de tela sem áudio e roda `flutter test` nele (funciona neste computador e no CI). Cobre o modal de sucesso e o tutorial guiado (`test/ui/`, 11 testes). Comprovado quebrando o tempo de fechar e o botão Pular de propósito. Telas que dependem do `AppState` ainda não têm teste de tela.

## Textos do Flutter em português (novembro/2026)
O app passou a usar `flutter_localizations` com `pt-BR` (`lib/ui/app_locale.dart`, ligado nos dois `MaterialApp` de `lib/main.dart`). Seletor de data ("Selecione a data", "novembro de 2026", D S T Q Q S S), seletor de hora, "OK" e "Cancelar" saem em português; conferido no navegador em 390×844 e coberto por `test/ui/app_locale_test.dart` (inclui um teste de controle sem a configuração, que sai em inglês). Custo: o Flutter embute os textos de todos os idiomas, então o `main.dart.js` cresceu de 4,08 MB para 4,76 MB (de 1,22 MB para 1,36 MB compactado, +11,5%); o arquivo é guardado pelo cache do aparelho depois da primeira visita.

## Lembrete escolhido pelo professor (novembro/2026, atrás da chave `lembrete_escolha`)
O aviso deixou de ser fixo em 15 minutos: o professor escolhe por aula (sem lembrete, 5, 10, 15, 30 min, 1 h, 2 h ou 1 dia antes) no formulário de aula e no de horário livre. Campo `r` no horário; servidor com padrão 15 e compatível com apps antigos; texto da notificação pelo tempo que falta. Arquivos: `api/_lib/agenda.js` (`REMIND_OPTIONS`, `scheduleNext`), `api/link.js` (`keepRemind`), `api/_lib/features.js`, `web/sw.js`, `packages/afina_core/lib/agenda.dart` (`remindMin`, `kRemindOptions`, `remindLabel`), `lib/ui/remind_field.dart`. Testes: `api/remind_choice.test.js` (14) e `packages/afina_core/test/remind_test.dart` (9).

## Meu espaço no centro, proteção do botão voltar e telas mais limpas (novembro/2026)
- **Meu espaço** passou para o **centro** da barra de baixo (Afinador, Metrônomo, Meu espaço, Grade, Escalas) e é a aba que **abre primeiro**; os ids internos das abas não mudaram (`lib/ui/home_tabs.dart`). Voltar de outra aba leva ao Meu espaço.
- **Voltar do celular**: a pergunta de sair virou uma folha (`lib/ui/exit_sheet.dart`) com **Continuar no app** em destaque e **Sair do app** discreto; não empilha perguntas se o voltar for apertado várias vezes. Um teste achou e corrigiu um estouro de 18 px em tela baixa.
- **Formulário de aula** (`lib/ui/slot_form_page.dart`) em três blocos (Aluno, Quando, Detalhes), com dia e hora em campos com rótulo, e o resumo da aula e "como chega ao aluno" num bloco só.
- **Acervo** (`lib/ui/library_page.dart`): cartões com ícone, autor e site do link; pastas numa linha que rola; "Adicionar material" virou botão flutuante; no formulário só o essencial fica à vista (tipo, título, link, pasta) e autor e observação ficam em "Mais detalhes".

## Agenda em calendário, modais de remarcar/trocar e avisos mais visíveis (novembro/2026)
- **Agenda do professor e do aluno abrem em calendário** (mês, com pontinhos nos dias com aula; o dia escolhido lista as aulas). A visão de semana continua na troca "Mês / Semana". O aluno abre no dia da próxima aula. O que explica e configura (faixa da agenda, lembretes) foi para o fim da tela.
- **Remarcar e trocar horário** viraram um modal só cada (`lib/ui/agenda_sheets.dart`): dia e hora (ou a lista de aulas), o que muda de → para, conferência de choque ao vivo e botão que só liga quando cabe. Cancelar e pausar usam a mesma folha de confirmação, com botão laranja.
- **Avisos curtos** por tipo (sucesso, atenção, informação) com ícone em círculo, fundo colorido, barra de tempo e duração proporcional ao texto.
- Um teste achou e corrigiu a leitura duplicada do número do dia para leitores de tela.

## Ações da agenda à vista, "Aluno faltou" e tela de Alunos (novembro/2026)
- **Agenda:** **Remarcar**, **Trocar** e **Cancelar** ficam à vista em cada aula (antes eram itens do menu de três pontos); cancelar uma aula semanal pergunta se é só esta ou todas.
- **Aluno faltou** (`lib/ui/agenda_actions.dart`, `absenceFlow`; modelo em `afina_core/lib/absence.dart`): segunda rota ao lado de "Começar a aula", com faltou sem avisar, avisou que não vem e quer remarcar. 9 testes no núcleo e 7 de tela.
- **Alunos:** lista agrupada (Aula hoje, Para validar, Todos os outros), cartões com aula do dia em destaque e marca de faltas, botão flutuante "Novo aluno" e extras no menu do topo.

## "Seu estudo" foi para o Metrônomo (novembro/2026)
O bloco **Seu estudo** (tempo de hoje, dias seguidos, meta diária, cronômetro, Pomodoro e o link "Evolução") saiu do Meu espaço e agora fica na aba **Metrônomo**, abaixo do modo desafio (`lib/ui/study_card.dart`). O Meu espaço ficou só com agenda, alunos, tarefas, acervo e o convite de feedback. As pílulas de Pomodoro e relógio da faixa de cima agora levam ao Metrônomo.

## Metrônomo com duas visões (novembro/2026)
A aba Metrônomo ganhou um seletor no topo: **Metrônomo** (padrão) e **Estudo e timers**. O "Seu estudo" só aparece na segunda visão, então a primeira fica limpa e a troca está sempre à vista. As pílulas de Pomodoro e relógio da faixa de cima abrem direto a visão de estudo (`lib/ui/metro_section.dart`). A escolha vale até fechar o app.

## Painel do administrador no padrão do app (novembro/2026)
O painel foi redesenhado com o design system do app: cores iguais (testadas contra `theme.dart`), escala de espaço de 8 em 8, cartões e janelas com os mesmos raios, abas com ícone e indicador que desliza, **uma frase de apoio em cada título** (38 ao todo), "Agora mesmo" antes de "Saúde do uso" na Visão geral, seletor de modo dos recursos em 4 botões iguais, estado do sistema numa linha que rola de lado no celular, janelas que sobem de baixo, avisos no estilo dos avisos do app e animações (entrada, barras, números que contam) que respeitam "reduzir movimento". Dados, ações e confirmações não mudaram. Teste novo: `api/admin_design.test.js` (6).

## Metrônomo mais alto e "Acelerar aos poucos" refeito (novembro/2026)
- **Volume:** sons reforçados (corpo mais longo, harmônicos para o alto-falante do celular, saturação suave, batidas fracas mais fortes) e volume padrão no máximo: **+9,4 dB** de sonoridade medida. Ferramenta nova: `packages/afina_core/tool/metro_loudness.dart`.
- **Acelerar aos poucos:** saiu do modal de Ajustes (três barras, uma de 40 a 320 com 280 passos, e o BPM da tela nem mostrava a subida) para um **card na tela do metrônomo**, com ajustes em quatro perguntas simples (por tempo ou compassos, quanto aumentar, teto com − e +), resumo em frase e acompanhamento ao vivo. Novo: aumento **por tempo** (15 s a 2 min). 15 testes no núcleo e 9 de tela.

## Versão em inglês (novembro/2026)
- **O app inteiro fala inglês**: ~1.950 textos (app, núcleo e mensagens do servidor). O idioma segue o aparelho e troca em Ajustes › Aparência e tela › Idioma / Language (Auto, Português, English). Português continua o padrão e não mudou.
- **Como**: texto no código em português dentro de `tr('...')` e dicionário `packages/afina_core/lib/i18n_en_*.dart`; ver `13_IDIOMAS.md`. Mesmo texto com sentidos diferentes usa `@@contexto`.
- **Também acompanham o idioma**: nomes das notas (C D E…), dias e meses, datas (dia/mês, ou mês/dia nos EUA, Canadá e Filipinas), tipo dos avisos (sucesso/atenção), lembretes de aula (service worker), resposta da IA (`lang` no `/api/coach`, compatível com apps antigos) e mensagens do servidor (traduzidas ao mostrar).
- **Lógica que dependia de texto** passou a depender de tipo: `ScaleType.isMinor`, `isDefaultStudentName`.
- **Teste e CI**: `node scripts/check_i18n.js` (cobertura das traduções), `i18n_test.dart` (núcleo), `toast_kind_en_test.dart` e um teste de `/api/coach` com `lang`. A "dieta de texto" (`check_text.js`) passou a contar também `Text(tr('...'))`.
- **Limites conhecidos**: páginas estáticas (`index.html`, `sobre.html`) e painel do administrador seguem em português; fora da web a troca de idioma só vale por completo ao reiniciar o app (na web a página recarrega sozinha).

## Grade: faixa mais folgada e botão de ampliar (novembro/2026)
- **Faixa "afinada" da grade** passou de ±10 para **±14 cents** (`kGridInTuneCents`): a cor do quadrado é a média das leituras (ataque, vibrato), então acertar e ver o verde estava difícil demais. Escalas, exercícios guiados e afinador seguem em ±10 (`kInTuneCents`). Fora da faixa as cores continuam pedindo correção.
- **Média mais estável**: cada leitura pesa pela clareza ao quadrado (leitura suja do ataque pesa menos).
- **Botão "Ampliar a grade"** saiu do link solto embaixo e virou botão de ícone no topo, junto do microfone e do zerar; o "?" das cores foi para o lado da legenda.

## Ficha da pessoa no painel: tempo de uso e aparelho (novembro/2026)
- Modal do perfil redesenhado (cabeçalho, números, gráfico de 14 dias, cartão Aparelho, atividade, dados no servidor, botões fixos) e lista com online, visto, hoje e total. Detalhes em `07_PAINEL_ADMIN.md`.
- Servidor: `profiles.seen` passou a gravar tempo de uso e ficha do aparelho no mesmo HSET da presença (custo de comandos inalterado); `api/user_usage.test.js` (9 testes, inclusive o de custo). App: manda a ficha com o vínculo (`dv`) respeitando as estatísticas anônimas. Texto de privacidade do app (PT e EN) e `05_SEGURANCA_E_PRIVACIDADE.md` atualizados.

## Cartão de resumo que é o botão de configurar (novembro/2026)
- Nova peça `DsConfigCard` (`design_system.dart`): resumo do que está valendo + **ícone de ajustes na ponta direita**; tocar em qualquer parte abre o modal. Usada em **Escalas e Arpejos** (o cartão com o nome da escala), **Grade** ("Ajustes da grade · Igual · Lá 440 Hz") e **Metrônomo** ("4/4 · colcheias · Clique"). Saiu o botão "Configurar escala" solto embaixo. No Afinador o botão fica, porque o cartão do instrumento já abre outra coisa (a lista de instrumentos).

## Escalas guiada e livre: mapa de oitavas, direção e grafia por direção (novembro/2026)
- **Tela de exercício sem rolar**: cartão da nota mais baixo, banner de orientação compacto (altura fixa, "TOQUE UMA NOTA" menor) e um **mapa da escala**: uma linha por oitava ("Dó4", "Dó5"…) com todas as notas e o número da oitava em cada quadradinho, a nota atual destacada e a linha dela realçada. Vale para escalas e arpejos, no modo guiado e no livre. A etiqueta "▲ subindo / ▼ descendo" fica no cartão.
- **Direção** (`ScaleDirection`): só subindo, só descendo (começa na nota mais aguda) ou os dois. Em Configurar escala e nos Ajustes do exercício; guardada no aparelho (`scale_dir`).
- **Grafia como na partitura** (`scale_spelling.dart`): cada grau ganha a sua letra; a **Dó menor melódica** sobe com Lá e Si naturais e desce com Si♭ e Lá♭; **Ré menor** sobe com Si natural e Dó♯ e desce na armadura; maiores com a grafia certa (Lá♭, não Sol♯); cromática sobe com sustenidos e desce com bemóis. A lista de notas da tela de Escalas mostra uma linha "subindo" e outra "descendo". A menor melódica é a menor do sistema de Flesch (as alturas já eram assim; o que faltava era o nome certo em cada direção).
- **Ainda aberto**: a ordem exata dos arpejos de cada tonalidade menor no Flesch (ver pergunta ao Daniel).

## Partitura nas escalas e arpejos (novembro/2026)
- **Escrita de partitura dentro do app**, no estilo do MuseScore: clave de Sol, armadura, compasso 4/4, acidentes (♯ ♭ ♮, e entre parênteses quando voltam no compasso seguinte), linhas suplementares, colcheias ligadas, tercinas com o "3", barra final. Desenhada com a fonte **Leland** (a do MuseScore 4, licença SIL OFL, em `assets/fonts/` com o texto da licença), sem biblioteca externa e sem servidor.
- **Três camadas**: `staff_notation` (música: nota, pauta, armadura, acidentes, ritmo), `staff_layout` (distribuição na largura do celular, ambas em Dart puro e testadas) e `lib/ui/staff_view.dart` (desenho). O desenho nunca decide o nome de uma nota: só desenha o que o modelo entrega. Teste de ida e volta em **todas as tonalidades, tipos, oitavas, direções e ritmos**: ler a partitura (armadura + acidentes) devolve exatamente a sequência do exercício.
- **Tela do exercício** (guiado e livre) e **aba Escalas**: a partitura substitui o mapa de oitavas e a lista "Notas do exercício". A nota de agora fica com um destaque atrás; as já tocadas pintam só a **cabeça da nota** (verde afinada, azul grave, laranja aguda), então a leitura não depende de cor. Linhas que não cabem viram "páginas" (`1 / 2`) e a página vira sozinha com a nota atual.
- **Claro e escuro**: a partitura usa "tinta" do tema (preto no claro, branco no escuro) sobre o cartão; testada nos dois.
- **Ajustes** (modal da escala e do exercício): **Partitura ligada/desligada**, **como escrever as notas** (semínimas, mínimas, colcheias, tercinas; o exercício toca igual) e **nome das notas** (sem nomes, só as agudas com linha suplementar, todas). Desligada, volta o mapa de oitavas. Com instrumento transpositor a partitura não aparece (o mapa continua).
- **Ainda aberto**: arpejos exatos do Flesch (aguardando as notas dos três primeiros arpejos em Ré menor), clave de Fá/Dó, lupa da nota atual e 8va para notas muito agudas.

### Partitura: fundo preto, dica nas notas agudas e dedilhado (novembro/2026)
- **Escuro de verdade:** no tema escuro o cartão da partitura é **preto puro** com tinta **branca pura** (`StaffColors.paper/ink`); no claro, branco com tinta escura.
- **Dica automática em nota aguda** (`kHighNotePos` = Dó6 para cima, 2ª linha suplementar acima): no modo guiado, se a nota atual espera mais de `kHintAfterSeconds` (4 s, `ScaleExercise.waitingSeconds`), aparece o nome dela (com a oitava) numa plaquinha embaixo da pauta. Só ela, só quando a pessoa demora; a faixa já fica reservada, então nada pula na tela. Ajuste **Dica nas notas agudas** (ligada por padrão) e o nome fixo das notas passou a vir **desligado** por padrão.
- **Dedilhado em cima das notas** (infraestrutura): `buildStaffScore(fingers: ...)` coloca o número (0 a 4, glifos da Leland) acima da nota, da haste, da barra e do "3", todos do compasso na mesma altura, com espaço mínimo entre notas. **Ainda sem dados**: a tabela do Flesch depende das páginas do método (ver pergunta ao Daniel); nada é mostrado até ela existir.
- **8va nas notas muito agudas** (como o Flesch escreve): de Sol6 para cima (`kOttavaPos`) a nota é desenhada uma oitava abaixo (`StaffEvent.writtenPos`; a posição real `pos` continua valendo para o som e para os testes) sob uma linha tracejada "8va" com a pontinha no fim, e ganha o **nome embaixo**. Só em trechos de 3 notas seguidas ou mais e sempre com o grupo de barra inteiro. Ajuste **Notas muito agudas (8va)**, ligado por padrão. Dedilhado: só números em cima das notas (1 a 4, 0 na corda solta), sem numerais de corda; a tabela do Flesch espera fotos mais nítidas.
- **Dedilhado do Flesch, primeira escala** (`violin_fingering.dart`): lido de uma foto nítida do Nº 5, **Si♭ maior, 3 oitavas** (2 bemóis). O número só aparece nas notas em que o livro o escreve (11 de 43): 4º dedo no Ré4 e no Lá4 subindo (no lugar das cordas soltas), 1º dedo nas mudanças de posição, 4 4 no topo, 3 e 3 na descida e cordas soltas (0) no Lá4 e no Ré4 descendo. Só violino; ajuste **Dedilhado do Flesch** aparece só nas escalas que têm tabela. Teste de segurança: todo 0 precisa cair numa corda solta (confirmou a leitura). As demais escalas entram conforme as fotos, uma a uma, conferidas pelo Daniel.
- **Mi♭ maior (Nº 5, 3 oitavas)** entrou na tabela, lido de outra foto. Descoberta: os pontos de mudança do Flesch usam o **mesmo molde** em tons diferentes (1 nas notas 10, 16 e 18, 4 4 no topo, 3 e 3 na descida), e só mudam onde o tom tem corda solta (Si♭ maior: 4º dedo no Ré4 e no Lá4 subindo, cordas soltas descendo). **8va como no livro**: a tabela diz onde (Mi♭ maior: do Si♭6 ao Dó7; Si♭ maior: nenhum). Com tabela, o 8va segue o livro; sem tabela, a regra automática (Sol6 para cima). A foto de 5 bemóis (Si♭ menor?) ainda não entrou: falta confirmar tom e se é natural ou melódica.
- **Formulário do dedilhado no painel do administrador** (aba **Partituras**): o Daniel preenche e corrige as escalas do Flesch sem mexer em código. O servidor guarda só as correções (um hash `fing:violin` no Redis; 1 comando por salvar, 1 por leitura) e o app busca `GET /api/fingering` uma vez por abertura (CDN de 5 min), guarda a última resposta no aparelho e funciona sem internet. O que vem do servidor vale no lugar da tabela do app; entrada inválida é ignorada dos dois lados (índice fora da sequência, dedo fora de 0 a 4, 8va invertido). Ação do painel: `fing_list`, `fing_rows`, `fing_save`, `fing_delete` (em `/api/admin`, sem endpoint novo além do GET público: 9 de 12 funções). O painel mostra as notas de cada escala com o nome certo (Sol♭ e Dó♭ em Sol♭ maior) e marca as cordas soltas. `scripts/gen_fingering_seed.js` gera o seed do painel a partir da tabela do app e um teste garante que os dois não se separem.
- **Outra grafia da tônica** (Sol♭ maior em vez de Fá♯ maior; também Dó♯/Ré♭, Dó♭/Si e as menores Ré♯, Lá♭ e Lá♯): a escala agora pode ser escrita nas duas, com a armadura certa (6 bemóis em vez de 6 sustenidos). No seletor de tônica cada grafia é uma opção. Sol♭ maior (Nº 5, 3 oitavas) entrou na tabela do Flesch com 8va da nota 18 à 26.
- **Cor da partitura independente do tema do app** (ajuste na Partitura: *Igual ao app*, *Clara* ou *Escura*; guardado em `scale_paper`): dá para ter a partitura em papel branco dentro do app escuro, ou preta dentro do claro, sem mexer no resto do app. `StaffColors.light` e `StaffColors.dark` são fixas; o cartão e as cores das notas seguem a escolha.
