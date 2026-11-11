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
| `Ds.screenPad` | 20 | margem lateral das telas (`Ds.screen` = margem completa de lista) |
| `Ds.cardPad` | 20 | espaço dentro do cartão (`AppCard`) |
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
- `AppCard`: cartão (20 px por dentro).
- `SuggestionTiles`: cartões de sugestão do sino.

## Como aplicar numa tela nova (checklist)
1. Qual é a ação principal? Ela aparece sem rolar?
2. O que é ajuste? Vai para um `showDsSheet`.
3. Algum parágrafo? Vai para o "?".
4. Margens e espaços vêm de `Ds`? Botões com 48 px ou mais?
5. Abri no navegador em 390×844 e olhei antes de pedir "sim, publicar"?

## Onde já está aplicado
Afinador (instrumento + Ajustes, Ouvir fixo), Metrônomo (BPM, play e Modo desafio à vista; ajustes no modal), Grade (ajustes no modal), Escalas (escala + Iniciar à vista; configurar no modal), Meu espaço (meta no modal, explicações dos timers no "?"), sino com sugestões. Telas de professor e aluno (listas, fichas) ainda usam os espaçamentos antigos e entram nas próximas passadas.
