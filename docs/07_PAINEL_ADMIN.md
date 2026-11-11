# Painel do administrador (`/admin`)

Página estática (`web/admin.html`, JavaScript puro, sem bibliotecas) que fala com `/api/stats` e `/api/admin`. Tudo que vem do servidor é escrito na tela com `textContent` (nunca HTML), então apelidos e mensagens de erro não executam nada.

## Entrar
- Abra `https://<seu-site>/admin` e digite a **chave de administrador** (`ADMIN_KEY`, ou `FEEDBACK_ADMIN_KEY` enquanto não houver uma própria). Ela fica só na aba (`sessionStorage`) e vai no cabeçalho `Authorization`.
- Errou a chave 10 vezes na hora → bloqueio temporário (429).
- Sem `ADMIN_KEY`/`FEEDBACK_ADMIN_KEY` configuradas, o painel responde 404 ("falta a variável").

## Topo da página
- **Semáforo de saúde** (`health`): verde "Tudo certo", amarelo "Atenção", vermelho "Problema". Vermelho: erro grave hoje ou pico de erros nas últimas 2 h. Amarelo: mais de 5 erros por 100 aberturas (com ≥ 20 aberturas) ou falha do servidor hoje. Passar o mouse mostra os motivos; tocar leva à aba Bugs.
- **Online agora** (atualiza a cada 30 s) e "atualizado às HH:MM · horário de Brasília · o dia de hoje é parcial".
- Cada número tem um **"?"** com a definição (dicionário `DEFS` em `admin.html`).

## Abas
| Aba | O que mostra |
|---|---|
| **Visão geral** | **Saúde do uso** (notificações negadas, versão antiga, IA hoje, perfis online e bloqueados); online agora; usuários hoje, 7 e 30 dias com ▲▼ contra o período anterior; total de aparelhos; **conquistas**; gráficos de 30 dias; **jornada do uso**; comparação 7×7 de aberturas, aulas, tarefas validadas, horários pegos, lembretes e vínculos |
| **Uso** | Quem usa hoje (aparelho/navegador, instalação, versão, abas) e o **mapa de calor** de aberturas por dia da semana × hora (30 dias) |
| **Pessoas** | Perfis (total, novos, ativos, inativos, professores, alunos), retorno D1/D7/D30, **retorno por semana de entrada**, crescimento, lista com busca por trecho do código, **perfis online agora** (e quem esteve há pouco), detalhe do perfil (bloquear, excluir, **suporte**: ver e encerrar vínculos, ver e apagar itens de agenda, gerar código de liberação) e o registro de ações do admin |
| **Bugs** | Resumo, erros por hora, lista agrupada com filtros, detalhe e ações |
| **Custos** | Comandos do Redis estimados no mês × cota de 500 mil |

## Números: como são calculados
- **Aparelhos** (HyperLogLog, erro ≈ 1%): distintos por janela. Um aparelho que abre 10 vezes conta 1. Quem limpa os dados ou reinstala conta como novo.
- **Perfis**: quem ligou o vínculo online (índice `pf:*`); menos que os aparelhos.
- **Ativos/inativos**: última atividade em 30 dias.
- **Retorno Dn**: entre quem entrou há ≥ n dias, quantos voltaram a partir do dia n (amostra de até 300 perfis dos últimos 90 dias).
- **Jornada**: passos com unidades diferentes (aparelhos, perfis, vínculos, aulas…); serve para ver onde afina, não é funil estrito.
- **Mapa de calor**: soma das aberturas por hora; os dados por hora só existem desde a atualização do painel.
- **Comparações ▲▼**: período atual × período anterior de mesma duração (HLL do período anterior; somas de contadores nas demais).

## Bugs: como usar
1. Abra a aba **Bugs**. O selo vermelho no título soma graves abertos + reabertos.
2. **Filtre** por período, gravidade, status, versão, plataforma, código ou texto (tela/mensagem).
3. Toque num bug para ver: onde, status, ocorrências, aparelhos afetados, primeira/última vez, **pilha**, versões/plataformas/instalações, tendência de 30 dias, **últimas 10 ocorrências** (com a trilha de telas: `Meu espaço › Agenda › Marcar aula`) e uma anotação.
4. Marque **Visto**, **Resolvido**, **Ignorar** ou **Reabrir**. Cada ação vai para o registro.
5. **Reabertura automática**: um bug "resolvido" que reaparece numa **versão publicada depois da correção** volta como "reaberto"; versão antiga (cache) não reabre.
6. Erros do **servidor** aparecem aqui com plataforma `server` e tela `API <endpoint>`.
7. Bugs sem ocorrência há **90 dias** são apagados sozinhos (ao abrir a lista).

Tipos: **grave** (derruba algo importante, ex.: falha ao abrir), **de ação** (uma ação falhou), **de conexão** (internet). Os códigos estão em [referencia/ERROS.md](referencia/ERROS.md).

## Custos
Estimativa = contadores do app × custo médio por ação (tabela `COST` em `api/admin.js`, mesma de [CUSTOS_E_REGRESSAO.md](CUSTOS_E_REGRESSAO.md)). Mostra o total dos últimos 30 dias, % do plano, projeção no ritmo da última semana, onde gasta mais e o gasto por dia. **É estimativa**: o Upstash não informa o uso real por aqui. A consulta barata do vínculo (`rev`) é amostrada (1 em 10) para ser medida sem encarecer.

## Chaves de desligar e ajuste
- `ERRORS_DISABLED=1` na Vercel → `/api/errors` aceita e **descarta** tudo (o app continua normal).
- `ERRORS_DAILY_CAP` (padrão 150) → teto de relatórios de erro por dia.

## Custo do próprio painel (só quando aberto)
`health` ≈ 16 comandos (a cada 5 min com o painel aberto), `kpis` ≈ 35, `costs` ≈ 90, `bugs` até ≈ 115, `bug` 6, `list` ≈ 27.

## Suporte ao usuário (detalhe do perfil)
Tudo abre no detalhe do perfil (aba Pessoas). Cada ação pede confirmação, vai para o registro e **avisa a pessoa no app** (aviso do tipo "suporte" na tela Minha conta e na central de avisos).
- **Vínculos**: lista de alunos (se for professor) e de professores (se for aluno), com data e última atividade; selo "Também é aluno" quando o perfil tem os dois papéis. **Encerrar vínculo** apaga o vínculo dos dois lados e o que dependia dele (aulas, marcações, decisões, horários pegos).
- **Agenda**: "Ver agenda deste perfil" mostra aulas que marcou, horários livres e aulas marcadas para ele; **Apagar** remove um item que esteja travando.
- **Liberar a conta em outro aparelho**: gera um código de uso único (vale 24 h) que aparece uma vez na tela. A pessoa digita o código do perfil e o de suporte em Minha conta › Chave de recuperação, no aparelho novo. O painel nunca vê a chave de recuperação; o aparelho antigo perde o acesso. Gerar outro código cancela o anterior; dá para cancelar o pendente. Passe o código só depois de confirmar que está falando com o dono.
- **Nome** não é editado pelo painel: o app reenvia o apelido a cada sincronização e desfaria a edição. O usuário muda o nome no app.

## Perfis online agora (aba Pessoas)
Mostra os perfis com o vínculo online ligado e o app aberto à frente que deram sinal nos últimos **12 minutos**, e abaixo quem esteve online nas últimas 48 h (offline). Toque numa linha para abrir o perfil. O app avisa no máximo a cada 10 minutos (2 comandos do Redis), então a lista pode atrasar alguns minutos; é um número de **perfis**, diferente do "Online agora" da Visão geral, que conta aparelhos (mesmo sem vínculo). Quem só usa o afinador, sem telas de vínculo abertas, pode não aparecer. Só código e horário do último sinal são guardados; o texto de privacidade do app e a política dizem isso.

## Saúde do uso (Visão geral)
Cinco cartões no topo, atualizados ao abrir ou tocar em Atualizar (cerca de 10 comandos do Redis):
- **Notificações negadas**: entre os aparelhos dos últimos 7 dias que já responderam, quantos negaram (mostra também liberaram e "ainda não foram perguntados"). Alto = o convite para ativar os lembretes está chegando na hora errada ou mal explicado.
- **Versão antiga do app**: aparelhos fora da versão publicada agora (compara com o código em produção, `VERCEL_GIT_COMMIT_SHA`). Aparelhos sem versão informada ficam de fora.
- **IA hoje**: pedidos admitidos no dia contra o limite diário global (`AI_RPD`).
- **Perfis online**: os mesmos da aba Pessoas (últimos 12 min).
- **Perfis bloqueados**: conjunto `pf:bl`, mantido ao bloquear, liberar e excluir; **conta só os bloqueios feitos depois desta atualização**.
Ainda **não existem** indicadores de "aulas pendentes" e "vínculos travados": o servidor não sabe o que está esperando envio no aparelho do professor (isso fica só no app dele), e medir pelo servidor exigiria varrer todos os perfis.
