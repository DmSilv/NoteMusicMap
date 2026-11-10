# App Flutter e núcleo

> A lista completa de arquivos, com a descrição de cada um, está em [referencia/ARQUIVOS.md](referencia/ARQUIVOS.md) (gerada do código). Aqui está o **modelo mental**.

## Estrutura
```
lib/                      app Flutter
  main.dart               inicialização, captura global de erros, abas, barra de cima
  app_state.dart          estado central (ChangeNotifier) — quase tudo passa por aqui
  ui/                     telas e peças de interface (49 arquivos)
  audio/                  microfone (record) e saída de som (flutter_soloud)
  link/ stats/ ai/ feedback/   clientes HTTP finos das funções em api/
  platform/               pontes web × celular (importação condicional: *_web.dart / *_stub.dart)
  data/repository.dart    persistência do perfil, sessões e alunos
  voice/                  ditado por voz
  dev/                    ferramentas só de desenvolvimento (DEV_DEMO)
packages/afina_core/      núcleo em Dart puro (lib/) + testes (test/)
```

## `AppState`: o centro do app
Um `ChangeNotifier` único (grande, de propósito: um lugar só para o estado). Principais blocos, na ordem do arquivo:
- **Afinador/áudio**: modo (cordas soltas, cromático, pedal), instrumento, sistema de afinação, Lá de referência, microfone.
- **Metrônomo, grade, estudo** (Pomodoro, cronômetro, "meu tempo").
- **Perfil e identidade**, **modo professor**, **alunos**, **aulas** (começar/encerrar), **tarefas** e **validação**.
- **Agenda** (`agenda` = aulas do professor, `myAgenda` = aulas do aluno, `visibleAgenda` = a lista que hub e agenda usam), **horários livres** (`openSlots`).
- **Vínculo online**: ligar/desligar, polling barato (`rev`), fila de envio (`doneOutbox`, `verdictOutbox`), `syncLinks`.
- **Avisos** (`notices`), **erros** (`errorLog`, `reportError`, `fail`), **relatórios** (`reportMode`, `crumbs`), **visões do hub** (`hubView`, `canSwitchHub`).
- **Persistência**: cada bloco tem seu `_load...`/`_save...` em `SharedPreferences` (chaves em [referencia/DADOS.md](referencia/DADOS.md)).

Regras de uso:
- Telas **leem** e chamam métodos; não guardam regra de negócio. Se há regra, ela vai para o núcleo e ganha teste.
- `notifyListeners()` **nunca** dentro de `build`; para registrar erro durante o desenho use `Future.microtask(notifyListeners)` (já feito em `reportError`/`fail`).
- Envios ao servidor entram em **filas locais** (reenviam sozinhas quando a conexão volta) e travam toque duplo (`_taking`, `_openSending`…).

## Núcleo `afina_core` (Dart puro)
Nada de Flutter nem `dart:io` (assim roda no navegador e nos testes de linha de comando). Cada módulo tem teste em `packages/afina_core/test`.

| Área | Módulos | O que decidem |
|---|---|---|
| Afinação e som | `tuning`, `pitch_detector` (McLeod), `tone_synth`, `metronome_engine`, `pedal`, `needle_spring`, `note_display`, `note_gate` | Matemática de afinação (igual, pitagórico, justo), detecção de altura, metrônomo por amostra exata, pedal, estabilização da nota exibida |
| Grade e exercícios | `pitch_grid`, `scale_exercise`, `practice_coach`, `rhythm_challenge`, `system_guide` | Grade de entonação, escalas guiadas, orientações, modo desafio |
| Estudo | `pomodoro`, `study_clock` | Temporizadores |
| Identidade e entrada | `identity`, `input_guard` | Perfil, código com dígito verificador, limpeza de tudo que se digita/cola/lê de QR |
| Professor/aluno | `teacher`, `lesson`, `lesson_week`, `methods`, `task_status` | Alunos, tarefas, aulas, "esta semana", métodos, **status oficial** (resumo, decisão, `VerdictEntry`) |
| Agenda e horários | `agenda`, `class_rules`, `open_slots` | `ClassSlot`, ocorrências, conflito, **fase e permissões da aula**, regras do horário livre |
| Hub | `hub`, `hub_view` | Destaque e blocos do Meu espaço; **visões Aluno/Professor** sem destino repetido |
| Vínculo | `link_status` | Estado do vínculo em linguagem simples |
| Erros e texto | `errors`, `error_report`, `markdown_lite` | Catálogo, classificação, higienização, relatório, trilha, markdown da IA |
| Saudação | `greeting` | "Bom dia / Boa tarde / Boa noite, Nome" pela hora local (faixa no Afinador e no Meu espaço, com convite para o apelido) |
| Aparelho | `device_tags` | Rótulos anônimos do aparelho para o painel (faixa de tela, idioma, versão do sistema, permissões) |
| Vínculo online | `link_pref` | Quando o vínculo liga sozinho (modo professor, professor ou aluno vinculado) e quando avisar que está desligado |

Convenções do núcleo:
- Funções **puras**: o relógio entra por parâmetro (`nowMs`), nunca `DateTime.now()` escondido.
- Contratos com o servidor (formato JSON) ficam no núcleo (`toWire`/`tryFrom`) e são **tolerantes**: lixo vindo da rede é descartado, nunca lança.
- Textos de interface que são regra (rótulos de fase, motivos de recusa) também ficam no núcleo, para testar.

## Plataformas (`lib/platform`)
Pares `x.dart` (exporta) → `x_web.dart` (navegador) e `x_stub.dart` (celular/teste), escolhidos por `if (dart.library.js_interop)`. Cobrem: instalar PWA, Web Push, vibração, apagar tudo e recarregar. O JavaScript do lado web está em `web/index.html` (`window.nmPush`) e `web/sw.js` (service worker, push).

## Telas principais (`lib/ui`)
| Tela | Arquivo | Notas |
|---|---|---|
| Afinador | `tuner_page.dart`, `pedal_view.dart`, `needle.dart` | Cordas soltas, cromático, Pedal |
| Metrônomo | `metronome_page.dart` | Som, subdivisão, tap tempo, desafio |
| Grade | `grid_page.dart`, `grid_board.dart`, `scale_exercise_page.dart` | Grade, escalas e arpejos |
| Meu espaço | `study_page.dart` + `hub_section.dart` | Hub por visão + estudo |
| Alunos / ficha | `teacher_page.dart`, `validation_ui.dart`, `task_form_page.dart` | Professor |
| Agendas | `agenda_page.dart` (professor e aluno), `slot_form_page.dart` | Rótulos explícitos "do professor"/"do aluno" |
| Horários | `open_slots_page.dart` | Publicar (professor) e pegar (aluno) |
| Aluno | `my_lessons_page.dart` | Aulas, tarefas e status oficial |
| Conta e ajustes | `profile_page.dart`, `settings_page.dart` | "Minha conta", vínculo, chave de recuperação, diagnóstico |
| Avisos e erros | `notifications_sheet.dart`, `error_ui.dart` | Sino; tela crítica; problemas recentes |

## Como acrescentar algo (resumo; receitas completas em [10_GUIA_DE_MANUTENCAO.md](10_GUIA_DE_MANUTENCAO.md))
1. Regra nova → módulo em `afina_core` + teste → exportar em `afina_core.dart`.
2. Estado → `AppState` (+ chave local se persistir).
3. Tela → `lib/ui`, lendo do `AppState`.
4. Servidor → ação nova em `api/` (aditiva) + teste em `api/*.test.js`.
5. `node scripts/gen_docs.js` e `flutter analyze`.
