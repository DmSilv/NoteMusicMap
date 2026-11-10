# Notemusic · Roteiro por etapas (acompanhamento)

Atualizado em 09/11/2026. **Regra de ouro:** o app está em produção. Cada etapa só é publicada com o "sim" do Daniel,
depois de analyze + testes (núcleo, API) + conferência na tela, dizendo o que muda e como desfazer.
Custo e escala entram em toda etapa (medir comandos do Redis; ver `memory/scalability-costs`).

## Já publicado
| Item | Commit |
|---|---|
| Afinador alinhado, guia do sistema de afinação, "Esta semana", cartões da aba Estudo | 62089e8 |
| Tarefas fora de aula, formulário novo, nome + código do aluno, avisos ao aluno | 62089e8 |
| Validação de tarefas pelo professor, motivo do envio parado, consulta barata (`rev`) | 622be7e |
| Agenda de aulas, lembrete push 15 min, painel `/admin` (métricas anônimas) | 61d966c |

## Pronto, aguardando "sim, publicar"
| Item | Estado |
|---|---|
| Modo **Pedal** (notas juntas) no Afinador | construído e testado (núcleo 414, API 106); falta publicar |

## Etapas deste pedido (ordem de execução)
Legenda: ⬜ a fazer · 🟨 em andamento · ✅ pronto (local) · 🚀 publicado

### Etapa 1 · Vínculo online claro e reversível — 🚀 publicada
**Por quê primeiro:** é pequena, independente e ajuda a diagnosticar todo o resto.
- Cartão de status em linguagem simples: Desligado / Conectando / Conectado / Sem internet / Servidor indisponível / Aguardando o outro lado, com a última atualização.
- Botões: **Desativar**, **Ativar** e **Reconectar agora** (desliga e liga + sincroniza), com confirmação do que muda.
- Aviso curto do que cada estado significa e o que fazer.
- **Testes:** função pura de estado (núcleo), reconexão e fila preservada (estado do app), textos por estado.

### Etapa 2 · Navegação e telas por papel (hub) — 🚀 publicada
- Tirar a dependência do ícone do topo: um **hub** com seções por papel.
  - Aluno: Próxima aula · Agenda · Tarefas · Pedir horário · Ferramentas (metrônomo, escalas, timers) · Perfil e vínculo.
  - Professor: Hoje · Alunos · Agenda e horários · Pedidos · Relatórios · Ferramentas · Perfil e vínculo.
- Tela do aluno com foco nas **aulas agendadas**.
- **Testes:** regras de quais seções cada papel vê (núcleo), navegação nos dois papéis, conferência visual em celular e tela larga.

### Etapa 3 · Status das tarefas com o professor no comando — 🚀 publicada
- O professor é a fonte oficial do status (pendente / concluída / devolvida). O aluno pode sinalizar "fiz" (já existe).
- **Resumo ao começar a próxima aula:** pendentes × concluídas × a validar, sem bloquear a aula; notificação ao professor quando o aluno sinaliza.
- O aluno passa a **ver o status oficial** (volta do servidor: ação nova, aditiva).
- **Testes:** resumo (núcleo), ações do servidor (API), compatibilidade com o app antigo.
- **Feito:** `task_status.dart` (resumo, estado oficial, `VerdictEntry`); API `verdict` (professor decide; "devolver" também derruba o "fiz") e `verdicts` (aluno busca) + contador `vr` em `rev`/`sync` (aditivo); fila de envio no professor; aluno vê "validada / aguardando o professor / refazer"; diálogo de início de aula com resumo e pendentes. Custo: decisão = 3 comandos no servidor; aluno só busca quando `vr` muda.

### Etapa 4 · Horários disponíveis e pedidos de horário — 🟨 em andamento
- Professor cadastra, altera e gerencia **horários disponíveis** (semanais ou avulsos, com duração) e **move/cancela** a aula de qualquer aluno.
- Aluno vê os horários livres do **seu professor** (só de quem já está vinculado) e **pega** um: confirma na hora (primeiro a pegar leva) e vira aula na agenda, com lembrete.
- Regras: sem choque com aulas marcadas, sem horário passado, um horário só pode ser pego uma vez, limites por aluno e por professor.
- **Testes:** modelo e regras (núcleo), ações e segurança do servidor (API: só vinculados, versão, limites), custo por ação documentado.

### Etapa 5 · Painel do administrador: indicadores e usuários — ⬜
- **Indicadores:** perfis totais, **ativos × inativos** (última atividade), professores ativos, alunos, crescimento (novos por semana, WAU/MAU, retenção D1/D7/D30), uso por recurso.
- **Gestão de usuários (CRUD):** listar/buscar, ver detalhe (papel, vínculos, atividade), editar apelido, bloquear/desbloquear e excluir (com confirmação e registro). Observação: o app **não tem login**; "usuário" = perfil anônimo (código + apelido).
- **Testes:** índice de perfis, atividade, retenção, CRUD e segurança (API), proteção da chave de admin.

### Etapa 6 · Endurecimento final — ⬜
- Revisão de custo de Redis por ação e de polling; limites; textos; acessibilidade; regressão completa (núcleo + API + roteiro manual); atualizar este documento.

## Decisões já tomadas
- **Sem cadastro/login** (decisão do Daniel, 09/11): administrador trabalha com perfis anônimos (código, apelido, entrou em, última atividade, papel, vínculos, uso).
- **Horários:** o professor pré-define os horários disponíveis; o aluno **pega** um (confirma na hora, sem aprovação) e o professor pode mover/cancelar depois, com controle total.
- **Status das tarefas:** o professor é a fonte oficial; a cada aula valida o que passou na anterior e passa tarefas novas. O aluno só sinaliza "fiz".
- Notificações com o app fechado: Web Push + QStash (feito); chaves já configuradas.
- Métricas anônimas, desligáveis em Configurações (feito).

## Pendências do Daniel
- Responder as decisões de design das etapas 3, 4 e 5 (ver conversa).
- Testar o som do Pedal e o lembrete push em aparelhos reais.

## Backlog (pedido do Daniel, 09/11 — implementar depois)
- Sincronizar melhor **Meu espaço** com a **Agenda** (uma só fonte de verdade).
- Estruturar melhor a **regra de negócio das aulas** (estados, quem muda o quê, remarcar/cancelar).
- **Modal só de notificações** (central de avisos) para acompanhar mais fácil.
