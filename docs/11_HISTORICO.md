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

## Indicadores de saúde do uso (novembro/2026)
A Visão geral do painel ganhou cinco cartões: notificações negadas, versão antiga do app, IA hoje (contra o limite diário), perfis online e perfis bloqueados (novo conjunto `pf:bl`). Saem de dados que o servidor já tem (fichas dos aparelhos dos últimos 7 dias, contador de IA, presença), em ~10 comandos por abertura. "Aulas pendentes" e "vínculos travados" ficaram de fora: o servidor não sabe o que espera envio no aparelho do professor.

## Presença online no admin (novembro/2026)
A aba Pessoas ganhou "Perfis online agora": perfis com vínculo ligado e app à frente que deram sinal nos últimos 12 min, e quem esteve online há pouco (offline). O sinal sai da consulta que o app já faz (`rev`/`sync`): no máximo 1 gravação de 2 comandos a cada 10 min por perfil (~12 comandos por hora de uso). Só código e horário são guardados; o app ganhou o aviso em Minha conta e na política de privacidade.

## Suporte do admin (novembro/2026)
O detalhe do perfil no painel ganhou: vínculos com data e última atividade (e selo "Também é aluno"), **encerrar vínculo**, **ver e apagar itens de agenda** e **código de liberação** de uso único (24 h) para recuperar a conta em outro aparelho (`claim` em `/api/link`; o app tem o campo em Minha conta › Chave de recuperação). Cada ação entra no registro e vira um aviso do tipo "suporte" no app (`sn` em `sync`/`rev`, sem custo extra). A rotina de desvincular foi para `api/_lib/unlink.js` e é a mesma do app e do painel. O nome do usuário não é editável pelo painel.

## Divulgação (novembro/2026)
Site: página `/sobre` (texto indexável + perguntas frequentes), `robots.txt`, `sitemap.xml`, título/descrição e dados estruturados melhores, `<noscript>`. Medição de origem das visitas por marca no link (`?o=yt`, `?o=ig`, `?o=tt`, `?o=zap`, `?o=site`), guardada no primeiro acesso do aparelho e mostrada em `/admin` › Uso › "De onde vieram". O plano de divulgação e os textos prontos ficam fora do repositório, na pasta local `divulgacao/`.
