# Painel do administrador (`/admin`)

Página estática (`web/admin.html`, JavaScript puro, sem bibliotecas) que fala com `/api/stats` e `/api/admin`. Tudo que vem do servidor é escrito na tela com `textContent` (nunca HTML), então apelidos e mensagens de erro não executam nada.

## Entrar
- Abra `https://<seu-site>/admin` e digite a **chave de administrador** (`ADMIN_KEY`, ou `FEEDBACK_ADMIN_KEY` enquanto não houver uma própria). Ela fica só na aba (`sessionStorage`) e vai no cabeçalho `Authorization`.
- Errou a chave 10 vezes na hora → bloqueio temporário (429).
- Sem `ADMIN_KEY`/`FEEDBACK_ADMIN_KEY` configuradas, o painel responde 404 ("falta a variável").

## Visual e como ler (mesmo padrão do app)
O painel (`web/admin.html`) usa o **design system do app** (ver `12_DESIGN_SYSTEM.md`, seção "Painel"): as mesmas cores, a escala de espaço de 8 em 8, cartões de 20 px de raio e movimento suave (que se desliga com "reduzir movimento"). Para ficar fácil de entender:
- **Cada título tem uma frase de apoio** em linguagem simples ("Quantas pessoas estão usando o app neste momento…"), e o "?" abre a explicação completa.
- **As abas têm ícone, nome e uma dica** (passe o mouse ou segure o dedo). Um traço verde desliza até a aba escolhida.
- **Visão geral:** primeiro "Agora mesmo" (quem usa), depois "Saúde do uso" (sinais de problema).
- **Números** contam até o valor ao carregar; as barras e os medidores crescem ao entrar na aba.
- **Cores com o mesmo sentido do app:** verde = bom ou ligado, laranja = atenção, vermelho = problema, azul = informação.
- **Celular:** a marca e o estado rolam junto; só as abas ficam fixas. As janelas (ficha do perfil, bug, confirmação) sobem de baixo, como no app. No computador, abrem no centro.
- Um teste (`api/admin_design.test.js`) garante que as cores sejam iguais às de `lib/ui/theme.dart` e que todo título tenha frase de apoio.

## Topo da página
- **Semáforo de saúde** (`health`): verde "Tudo certo", amarelo "Atenção", vermelho "Problema". Vermelho: erro grave hoje ou pico de erros nas últimas 2 h. Amarelo: mais de 5 erros por 100 aberturas (com ≥ 20 aberturas) ou falha do servidor hoje. Passar o mouse mostra os motivos; tocar leva à aba Bugs.
- **Online agora** (atualiza a cada 30 s) e "atualizado às HH:MM · horário de Brasília · o dia de hoje é parcial".
- Cada número tem um **"?"** com a definição (dicionário `DEFS` em `admin.html`).

## Abas
| Aba | O que mostra |
|---|---|
| **Visão geral** | **Saúde do uso** (notificações negadas, versão antiga, IA hoje, perfis online e bloqueados); online agora; usuários hoje, 7 e 30 dias com ▲▼ contra o período anterior; total de aparelhos; **conquistas**; gráficos de 30 dias; **jornada do uso**; comparação 7×7 de aberturas, aulas, tarefas validadas, horários pegos, lembretes e vínculos |
| **Uso** | Quem usa hoje (aparelho/navegador, instalação, versão, abas) e o **mapa de calor** de aberturas por dia da semana × hora (30 dias) |
| **Pessoas** | Perfis (total, novos, ativos, inativos, professores, alunos), retorno D1/D7/D30, **retorno por semana de entrada**, crescimento, lista com busca por trecho do código ou **pelo apelido** (nos 100 mais recentes) e **exportar CSV**, **perfis online agora** (e quem esteve há pouco), detalhe do perfil (**ficha com tempo de uso e aparelho**, bloquear, excluir, **suporte**: ver e encerrar vínculos, ver e apagar itens de agenda, gerar código de liberação) e o registro de ações do admin |
| **Bugs** | Resumo, erros por hora, **avisos de bug grave** (notificação neste navegador), lista agrupada com filtros (inclui **só na versão atual**), **exportar CSV**, detalhe e ações |
| **Partituras** | **Formulário do dedilhado do violino (Flesch)**: lista as escalas que vêm no app, as que você corrigiu e as que incluiu; para editar, escolhe tônica (com a outra grafia, Fá♯ ou Sol♭), tipo e oitavas, toca em *Carregar notas* e preenche o dedo (0 a 4) só nas notas em que o livro escreve número, mais o 8va (da nota X até a Y). Avisa, sem impedir, quando um 0 não cai numa corda solta. A seção **O que falta preencher** mostra, para o tipo e as oitavas escolhidos, cada tonalidade com ✓ (já tem) ou ○ (falta); tocar numa que falta abre o formulário nela, e **Sugerir pelo molde** (escala maior de 3 oitavas) preenche com o que as 12 maiores lidas têm em comum, só como ponto de partida para conferir com o livro (não salva sozinho). O que salva vale no lugar do que vem no app (próxima abertura do app, até 5 minutos); *Voltar ao que vem no app* apaga a correção |
| **Custos** | Comandos do Redis estimados no mês × cota de 500 mil |

## Confirmação de ações (modal)
Toda ação que altera algo abre um modal que sobe de baixo (função `askConfirm` em `web/admin.html`): diz o que vai acontecer, quem é afetado e se dá para desfazer. O botão de confirmar só libera depois de ~0,7 s. As ações sem volta pedem **segurar o botão por 1,5 s** (encerrar vínculo, gerar código de liberação, apagar item de agenda) ou **digitar o código** do perfil (excluir dados). Esc ou toque fora cancela. Cobre: limpar perfis, avisos de bug grave (ativar, desativar, teste), esconder item do acervo, encerrar vínculo, código de liberação (gerar e cancelar), apagar item de agenda, bloquear e liberar, excluir dados e mudar o status de um bug. Um teste de proteção (`api/guardrails.test.js`) falha se voltar `confirm()`/`prompt()` ou se uma dessas ações perder o modal.

## Recursos (liberação aos poucos)
Aba **Recursos**: um cartão por novidade (`api/_lib/features.js`). Estados: **Desligado** (vale para todos, inclusive quem está na lista, e chega em até 1 minuto), **Só liberados** (lista de códigos; no acervo, também os de `LIBRARY_TESTERS`), **Parte dos usuários** (1 a 99%, sempre os mesmos usuários, pelo código; a lista continua valendo) e **Todos**. Dá para liberar um código e, se o recurso vale para os alunos, **os alunos vinculados a ele** (até 200). Todas as mudanças passam pelo modal de confirmação (Todos e Desligado pedem digitar o nome do recurso) e entram no registro. Ações da API: `features`, `feature_set`, `feature_grant`, `feature_revoke`.

## Ativação e acompanhamento (suporte)
- **Ativação** (Visão geral): quantos perfis fizeram cada coisa **pela primeira vez** (criar o perfil, vincular, marcar a 1ª aula, enviar a 1ª aula ou tarefa, pegar um horário livre, concluir uma tarefa), com a porcentagem sobre os perfis criados. Cada perfil conta uma vez por etapa e só a partir do dia em que o contador começou (campo `ms` do perfil e hash `fn:ms`; custo: 3 comandos uma única vez por perfil e etapa, nada nas demais chamadas). Ação `funnel`.
- **Comparar agendas** (detalhe do perfil, ao lado de cada vínculo): mostra as aulas do professor com aquele aluno e o que o aluno recebeu, marcando **Igual**, **Falta no aluno**, **Diferente no aluno** ou **Sobra no aluno**. Serve para achar "o aluno não recebeu a aula". Ação `agenda_pair`; não mostra link da aula.
- **Idade do "agora"**: o topo mostra "agora há X s" (um relógio na tela, sem consultar o servidor). O "agora" continua atualizando a cada 30 s só com a aba à frente: 15 s dobraria o custo no Upstash.
- Visual: abas com transição, cartões que reagem ao passar o mouse, botões com estados de foco e clique, esqueleto de carregamento (`.skel`); tudo respeita "reduzir movimento".

## Contas: quanto custa manter a plataforma (aba Custos)
Seção **Contas** na aba Custos: o gasto de hoje (últimos 30 dias), uma tabela de cenários (100, 1.000, 5.000, 10.000 e o número que você digitar), a cotação do dólar editável e uma opção "O app gera receita" (o plano Hobby da Vercel é só para uso não comercial). O consumo por usuário ativo pode ser o **simulado** (`node scripts/simulate_load.js`) ou o **real** dos contadores, que só aparece com 30 ou mais usuários ativos. Preços de tabela em `api/_lib/cost_model.js` (`PRICES`, com a data da consulta): atualize quando os serviços mudarem. A conta é pura: não gasta comando do Redis. Ações: `costs` (devolve `measured`) e `cost_report`. Mostra também custos que não são mensais (Google Play, Apple, domínio) e avisos de limite (banco, lembretes, funções da Vercel).

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

## Avisos de bug grave (Bugs)
O painel pode avisar você por **notificação do navegador** quando aparece um bug **grave novo** ou um grave **resolvido que reabre** (volta numa versão publicada depois da correção). Bugs de ação e de conexão não avisam.
1. Aba **Bugs** › "Avisos de bug grave" › **Ativar avisos neste navegador** (o navegador pede a permissão; cada navegador ativa uma vez, até 5 aparelhos). **Enviar teste** confirma que chega.
2. Precisa das chaves **VAPID** na Vercel (as mesmas dos lembretes de aula). Sem elas o cartão diz "indisponível" e nada quebra.
3. Limite de **6 avisos por hora** no total (um erro em loop não vira spam) e 5 testes por hora. Inscrição que o navegador apagou (404/410) é removida sozinha.
4. Custo: nada quando não há bug grave novo; num bug grave novo, ~3 comandos mais 1 envio por navegador. Falhar o aviso nunca atrapalha o relatório do app.
5. Para parar: **Desativar** no mesmo cartão. Ativar e desativar entram no registro de ações.

## Precisão dos bugs
- **Mesmo bug, números diferentes**: a impressão digital ignora números e endereços de memória da 1ª linha do erro ("índice 3 fora de 10" e "índice 4 fora de 12" agrupam). Bugs antigos gravados com a regra anterior aparecem uma vez separados do grupo novo; os antigos saem sozinhos em 90 dias.
- **Ainda acontece na versão atual?** Cada bug mostra "só em versões antigas" quando não ocorreu na versão publicada agora, e o filtro **só na versão atual** esconde esse ruído.

## Exportar e buscar
- **Exportar CSV** (Bugs e Pessoas): gera o arquivo no próprio navegador a partir da lista que está na tela (nada é enviado a lugar nenhum). Células que começariam com = + - @ ganham um apóstrofo, para a planilha não executar como fórmula.
- **Pessoas › pelo apelido**: lê o apelido dos 100 perfis mais recentes (100 comandos por busca; só quando você clica em Buscar). Para achar alguém mais antigo, use o código.

## Ficha da pessoa: tempo de uso e aparelho
Ao tocar num perfil da aba **Pessoas** abre a ficha: cabeçalho (inicial, apelido, código que copia com um toque, papéis, **online agora** ou "visto há…"), quatro números (**hoje, 7 dias, dias ativos de 14, total**), o gráfico dos **últimos 14 dias**, o cartão **Aparelho** (aparelho e navegador, sistema, instalação, versão do app, tela, toque, densidade, memória, processador, idioma, tema, fuso, região, rede, microfone e notificações; quantas vezes trocou de aparelho e o aparelho anterior), **Atividade**, **Dados no servidor** e, abaixo, vínculos, liberação de conta e agenda. Os botões de Bloquear/Excluir/Fechar ficam fixos embaixo. A lista ganhou bolinha de online, **Visto**, **Hoje** e **Total** (e o CSV, as colunas `online_agora`, `minutos_hoje`, `minutos_total`).

- **Tempo de uso é ESTIMADO**: o servidor soma, a cada sinal de presença (≥ 10 min de intervalo), os minutos desde o sinal anterior se foi em até 12 min (mesma sessão); depois de uma pausa maior abre uma sessão nova (vale 1 min). Só conta com o app à frente e o **vínculo online ligado**. Não é o tempo de estudo.
- **Ficha do aparelho**: o app manda a ficha (as mesmas categorias curtas das estatísticas anônimas) na primeira chamada da sessão e a cada 6 h; o servidor soma navegador, "família" do sistema, celular/computador e região aproximada (cabeçalhos da Vercel). Só é gravada se **mudou** ou se passou 1 dia. Não vai quem desligou as "Estatísticas anônimas".
- **Custo no Redis: zero comandos a mais.** O perfil já é lido em toda chamada; tempo e ficha entram no **mesmo HSET** da presença (1 gravação a cada 10 min) em campos do próprio hash do perfil (`uh` histórico de 14 dias, `tm`/`ns` totais, `dv`/`dp`/`dn`/`df`/`dt` ficha atual, anterior, trocas, primeira vez, atualizada). Abrir a ficha continua custando as mesmas ~12 leituras; a lista de 25 continua com um HMGET por perfil (agora com 3 campos a mais).

- **Estudo e modelo/cidade** (também na ficha): o app manda os minutos estudados nos últimos 7 dias (campo `sm`, só números) junto com a ficha; o servidor deduz **modelo** (`Sec-CH-UA-Model`, pedido por `Accept-CH` no `vercel.json`, ou o User-Agent do Android) e **cidade aproximada** (cabeçalho da Vercel). O IP em si **não** é guardado, e o que a pessoa toca (escalas, notas, acertos) **não** sai do aparelho.
