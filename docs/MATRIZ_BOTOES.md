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

## Meu espaço (professor, com 1 aluno, 1 aula e 1 horário livre) — segunda rodada, sem tocar na API de produção
| Botão | Resultado | Estado |
|---|---|---|
| Destaque "Agenda do professor" | abre a agenda com a aula de amanhã | ✅ |
| Destaque "Ficha de Marina" | abre a ficha (aula, "1 tarefa para validar" com Devolver/Confirmar, lista de tarefas) | ✅ |
| Bloco "Para validar" | abre a Área do professor | ✅ (ver achado 1) |
| Bloco "Alunos" | abre a Área do professor | ✅ (ver achado 1) |
| Ferramenta "Horários livres" | lista o horário livre, com lixeira e "Novo horário" | ✅ |
| Ferramenta "Relatórios" | abre a Área do professor | ✅ (ver achado 1) |
| Ferramenta "Metrônomo" | muda para a aba Metrônomo | ✅ |
| Ferramenta "Escalas" | abre a aba Grade na seção Escala | ✅ |
| Ferramenta "Ajustes" | abre Configurações | ✅ |
| Agenda: cartão da aula | **Remarcar**, **Trocar** e **Cancelar** sempre à vista; "Aluno não veio" aparece perto da hora e depois dela começar | ✅ |
| Ficha do aluno: Aluno faltou | abre o modal com 3 caminhos (faltou, avisou, quer remarcar) e registra a falta | ✅ |
| Alunos: Novo aluno | botão flutuante sempre à vista; Ler QR, Importar, Métodos e Senha ficam no menu ⋮ do topo | ✅ |
| Agenda: Mês / Semana | abre em **Mês** (calendário com pontinhos); alterna para a lista da semana | ✅ |
| Agenda: "Marcar aula" | abre o formulário (aluno, dia, hora, duração, repetir, observação) | ✅ |
| Formulário: horário no passado | mostra o aviso "Esse horário já passou…" | ✅ |
| Formulário: microfone (ditado) | abre o aviso "Escrever falando" | ✅ |

## Ainda não conferido (próxima rodada)
- Agenda: menu ⋮ da aula (Editar, Abrir ficha, Cancelar só esta, Cancelar todas), setas de semana/mês, "Hoje", "Ligar vínculo online".
- Formulário de aula: botão X (fechar), "Cancelar" e "Marcar aula" com data válida.
- Horários livres: "Novo horário" (data, hora, duração, repetir, Publicar), lixeira (confirmação), "Pegar horário" no lado do aluno.
- Ficha do aluno: "Começar a aula" (resumo), Confirmar/Devolver, "Nova tarefa", menu da tarefa, Iniciar, excluir aluno.
- Área do professor: Novo aluno, Ler QR do aluno, Meus métodos, Importar, Definir senha.
- Ajustes: interruptores e botões "?"; Perfil: Adicionar outro professor, desvincular, chave de recuperação, aba Professor.
- Afinador, Pedal e Grade: modos, "Ouvir", teclas, escalas.
- Lado do aluno inteiro (Agenda do aluno, Minhas aulas, marcar "fiz", Pegar horário).

## Achados
1. **Três atalhos para a mesma tela:** "Para validar", "Alunos" e "Relatórios" abrem a mesma Área do professor. "Para validar" deveria levar direto à validação do aluno que tem tarefa marcada. Entra na Fase 1 (navegação).
2. Nenhum botão quebrado nos itens conferidos. O aviso de horário no passado e os diálogos de confirmação funcionam.
3. O teste é instável neste ambiente (a janela do navegador mudou de tamanho e depois a aba caiu); por isso o que não está marcado ✅ **não foi validado**, não que esteja certo.

## Rodada 3 (após a navegação, pacote 1)
- ✅ Barra de cima: Avisos e Eu. ✅ Eu › Ajustes (abre Configurações com Aparência Auto/Claro/Escuro). ✅ Eu › Compartilhar app (QR, copiar link, enviar).
- ✅ Meu espaço: ferramentas agora são Agenda do professor, Horários livres, Metrônomo e Escalas. ✅ "Para validar" abre direto a ficha com a tarefa a validar.
