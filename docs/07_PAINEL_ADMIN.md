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
| **Visão geral** | Online agora; usuários hoje, 7 e 30 dias com ▲▼ contra o período anterior; total de aparelhos; **conquistas**; gráficos de 30 dias; **jornada do uso**; comparação 7×7 de aberturas, aulas, tarefas validadas, horários pegos, lembretes e vínculos |
| **Uso** | Quem usa hoje (aparelho/navegador, instalação, versão, abas) e o **mapa de calor** de aberturas por dia da semana × hora (30 dias) |
| **Pessoas** | Perfis (total, novos, ativos, inativos, professores, alunos), retorno D1/D7/D30, **retorno por semana de entrada**, crescimento, lista com busca por trecho do código, detalhe do perfil (bloquear, excluir) e o registro de ações do admin |
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
