# Matriz de botões (Fase 0 do plano)

Validação feita no Chrome em tamanho de celular (500×765), com um perfil de teste (professor com 1 aluno e 1 professor vinculado).
Legenda: ✅ conferido em tela e funcionou · ⬜ ainda não conferido · ❌ defeito.

## Barra de cima (todas as abas)
| Botão | Resultado esperado | Estado |
|---|---|---|
| Tema (sol/lua) | alterna automático → claro → escuro | ✅ |
| Compartilhar | abre QR + "Copiar link" + "Enviar" | ✅ |
| Avisos (sino) | abre a central de avisos; vazia mostra a mensagem | ✅ |
| Perfil / Professor (capelo) | abre "Perfil e professor" | ✅ |
| Ajustes (engrenagem) | abre Ajustes | ⬜ |

## Perfil e professor
| Botão | Resultado esperado | Estado |
|---|---|---|
| Copiar código | copia e mostra "Código copiado." | ✅ |
| Reconectar agora | mostra "Conectado." | ✅ |
| Desativar | abre confirmação "Desativar o vínculo online?" (Cancelar / Desativar) | ✅ (só abrir; não confirmei) |
| Ver minhas aulas | abre "Minhas aulas" | ✅ |
| Adicionar outro professor | abre leitor de QR / código | ⬜ |
| Ícone de desvincular professor | pede confirmação | ⬜ |
| Chave de recuperação (mostrar/copiar) | abre a chave com aviso | ⬜ |
| Aba "Professor" | mostra a área de professor | ⬜ |

## Pendentes de conferir (roteiro para a próxima rodada)
- **Meu espaço:** destaque (botões de cada estado: sem aula, próxima, em andamento), blocos "Para validar", "Alunos", "Tarefas", "Agenda do aluno", ferramentas (Agenda do professor, Horários livres, Pegar horário, Relatórios, Metrônomo, Escalas, Perfil, Ajustes), faixa de aviso (Ver / Dispensar), selo de conexão.
- **Agendas:** Hoje, Semana/Mês, setas, "Marcar aula", menu da aula (Editar, Abrir ficha, Cancelar só esta, Cancelar todas), ativar lembretes.
- **Horários livres:** Novo horário (data, hora, duração, repetir, Publicar), apagar (com confirmação), Pegar horário (confirmar).
- **Alunos e ficha:** Novo aluno, Ler QR do aluno, Importar, Começar a aula (resumo), validar/devolver, Nova tarefa, menu de tarefa, excluir aluno (confirmação).
- **Ajustes:** cada interruptor e botão de ajuda "?".
- **Afinador / Metrônomo / Grade:** modos, "Ouvir", pedal, escalas.

## Achados até agora
- Nenhum defeito encontrado nos botões conferidos.
- Observação: o app de teste local fala com a API **de produção**; o perfil de teste usado aqui existe lá (código de teste). Na próxima rodada usar a API local de demonstração para não criar perfis reais.
