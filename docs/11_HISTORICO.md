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
