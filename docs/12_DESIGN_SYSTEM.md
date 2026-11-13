# Design system do Notemusic

**Regra permanente:** toda tela nova ou alterada segue este documento. O código está em `lib/ui/design_system.dart` (classe `Ds` e componentes `Ds*`); as cores continuam em `lib/ui/theme.dart`. Número solto de espaçamento, raio ou altura de botão não entra em tela nova.

## Princípios
1. **O essencial primeiro.** A primeira tela mostra só o que a pessoa usa a cada abertura e a **ação principal visível sem rolar** (ex.: botão **Ouvir** fixo embaixo no Afinador, play grande no Metrônomo, **Iniciar exercício** em Escalas).
2. **Configuração em modal.** Tudo que é ajuste ou alteração (captação do microfone, Lá de referência, compasso, som, tônica, meta diária…) fica num **modal que sobe de baixo** (`showDsSheet`), aberto por um botão **Ajustes ⚙** (`DsSettingsButton`). A pessoa altera, toca em **Concluir** e volta para a tela. Escolhas curtas e frequentes (instrumento, modo Cordas/Cromático/Pedal) ficam à vista.
3. **Texto explicativo no "?".** Parágrafos vão para `HelpButton`/`Help`; a tela mostra no máximo uma linha de apoio. `scripts/check_text.js` trava textos longos.
4. **Avisos e sugestões no sino.** "Como posso te chamar?" e "Instale no celular" ficam no sino (`lib/ui/suggestions.dart`), nunca presos no topo. Só o que bloqueia o uso (versão nova, vínculo desligado com gente dependendo dele) aparece como faixa fina.
5. **Uma ação principal por tela**, grande e na cor de destaque (`DsPrimaryButton`, 56 px).

## Medidas (base 8)
| Token | Valor | Uso |
|---|---|---|
| `Ds.s4 / s8 / s12 / s16 / s20 / s24 / s32` | 4 a 32 | escala de espaçamento |
| `Ds.screenPad` | 16 | margem lateral das telas (`Ds.screen` = margem completa de lista) |
| `Ds.cardPad` | 18 | espaço dentro do cartão (`AppCard`) |
| `Ds.gap` | 16 | entre cartões da mesma tela |
| `Ds.sectionGap` | 24 | entre seções |
| `Ds.tap` | 48 | alvo de toque mínimo (o tema já impõe 48 px de altura em botões cheios e com borda) |
| `Ds.primaryHeight` | 56 | botão de ação principal |
| `Ds.radiusCard / radiusControl` | 20 / 12 | cantos |
| `Ds.fontBody / fontSupport / fontLabel / fontTitle` | 16 / 14 / 13 / 20 | texto (nada abaixo de 13 em tela nova) |

## Componentes
- `showDsSheet(context, title:, listenable:, children:)`: o modal de ajustes (título, **Concluir**, conteúdo rolável que se atualiza sozinho).
- `DsSettingsButton`: botão "Ajustes" (ícone de controles).
- `DsPrimaryButton`: ação principal, largura total.
- `DsSettingRow`: rótulo + controle dentro de um modal.
- `DsGap`: espaço vertical padrão (`DsGap(Ds.s12)`, `DsGap.section()`).
- `AppCard`: cartão (18 px por dentro).
- `DsIconBadge`: ícone num quadradinho arredondado de fundo suave (usado no Meu espaço).
- `DsPickTile`: campo tocável de dia ou hora (rótulo pequeno em cima, valor em destaque).
- **Avisos curtos** (`showToast`, `lib/ui/toast.dart` e `toast_kind.dart`): três tipos pelo texto, **sucesso** (verde, ✓ em círculo), **atenção** (laranja) e **informação** (azul); fundo colorido, borda forte, barra de tempo e duração proporcional ao tamanho da frase (3 s ou mais; 4,2 s ou mais na atenção). Para o que é importante, use o **momento de sucesso** (`celebrate`).
- **Modais da agenda** (`lib/ui/agenda_sheets.dart`): remarcar, trocar e confirmar são **um modal só**, com o que muda (de → para), a conferência de choque ao vivo e o botão que só liga quando cabe. Confirmar uma ação destrutiva usa o botão laranja.
- `AgendaMonthGrid` (`lib/ui/agenda_calendar.dart`): calendário do mês, com pontinhos nos dias com aula; usado nas duas agendas.
- `SuggestionTiles`: cartões de sugestão do sino.

## Como aplicar numa tela nova (checklist)
1. Qual é a ação principal? Ela aparece sem rolar?
2. O que é ajuste? Vai para um `showDsSheet`.
3. Algum parágrafo? Vai para o "?".
4. Margens e espaços vêm de `Ds`? Botões com 48 px ou mais?
5. Abri no navegador em 390×844 e olhei antes de pedir "sim, publicar"?

## Painel do administrador (`web/admin.html`)
O painel segue o mesmo sistema, em CSS:
- **Cores:** as do app, no tema escuro (`--bg`, `--surface`, `--surface2`, `--outline`, `--text`, `--dim`, `--accent`, `--flat`, `--sharp`). Vermelho (`--bad`) só para problema. Um teste compara com `lib/ui/theme.dart`.
- **Espaço:** `--s4` a `--s32` (4, 8, 12, 16, 20, 24, 32). Nada de números soltos como 10, 14 ou 22 px.
- **Raios:** 20 (cartão e janela), 12 (botão e campo) e pílula.
- **Toque:** botões e campos com 40 a 48 px; texto de apoio a partir de 13 px.
- **Estrutura de uma seção:** título (17 px, forte) + **frase de apoio** + conteúdo em cartões. O "?" guarda a explicação longa.
- **Movimento:** entrada suave dos blocos e dos cartões, barras que crescem, números que contam, indicador que desliza entre as abas, janelas que sobem de baixo. Tudo para com "reduzir movimento".

## Onde já está aplicado
Afinador (instrumento + Ajustes, Ouvir fixo), Metrônomo (BPM, play e Modo desafio à vista; ajustes no modal), Grade (ajustes no modal), Escalas (escala + Iniciar à vista; configurar no modal), Meu espaço (agenda em primeiro lugar; estudo e cronômetro num bloco só; gráficos na tela Evolução; meta no modal; explicações dos timers no "?"), sino com sugestões. Telas de professor e aluno (listas, fichas) ainda usam os espaçamentos antigos e entram nas próximas passadas.

## Acessibilidade dos controles (regra para toda tela)
- **Um controle por área.** Nunca um botão dentro de outro (ex.: "?" dentro de um cartão tocável): o toque fica ambíguo e o alvo, pequeno. O "?" fica ao lado do cartão, como botão próprio (`HelpButton(outlined: true)`), e o cartão que abre ajustes é o `DsConfigCard`.
- **Alvo de toque de pelo menos 48 px** (`Ds.tap`), inclusive no "?" (antes 36) e nas setas de oitava (44). O tema usa `MaterialTapTargetSize.padded` e densidade normal, então até botões "compactos" têm área de toque de 48 px.
- **Leitor de tela:** cartão tocável = um item só, com rótulo, resumo e a dica "Toque para alterar"; ícone decorativo fora da leitura; botão só de ícone sempre com `tooltip`.
- **Foco e passagem do mouse** visíveis (teclado e computador).
- Testes: `test/ui/ds_config_card_test.dart` (um controle por área, 48 px, leitor de tela).

## Partitura (regra de cor e tamanho)
- A partitura é escrita em **tinta do tema** (`AppColors.text`: preto no claro, branco no escuro) sobre o cartão do tema (`AppColors.surface`), como uma partitura impressa. Cor só na **cabeça da nota** tocada (afinada, grave, aguda, as mesmas cores da agulha), nunca para escrever a pauta, a armadura ou as hastes: a leitura não depende de cor nem do tema.
- Sempre **dentro da largura do celular**: o tamanho do espaço de pauta é calculado pela largura disponível (entre 6 e 10,5 px) e o que não cabe em altura vira páginas (`1 / 2`). Nada de rolagem horizontal.
- Peça única: `StaffView` / `StaffCard` (`lib/ui/`). Teste: `test/ui/staff_view_test.dart` (claro e escuro, larguras de 300 a 420 px, páginas).
- **Cor independente do tema do app:** o ajuste **Cor da partitura** (igual ao app, clara ou escura, `StaffPaper`) vale só para a partitura. Clara = papel branco com tinta `#111B25`; escura = fundo preto com tinta branca; as cores das notas tocadas são fixas por fundo (as da agulha em cada tema) e o teste `staff_view_test.dart` exige contraste mínimo de cada uma com o seu fundo (4:1 no claro, 5:1 a 7:1 no escuro).
