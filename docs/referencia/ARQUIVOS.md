# Mapa de arquivos

> **Gerado automaticamente** por `scripts/gen_docs.js` a partir do código. Não edite à mão: rode `node scripts/gen_docs.js`.
> Cada linha traz a descrição que está no cabeçalho do próprio arquivo. Se uma descrição estiver ruim, melhore o comentário no código.

## App Flutter (`lib/`)

| Arquivo | O que faz |
|---|---|
| `lib/ai/coach_ai.dart` | Análise por IA: pede ao servidor (`/api/coach`) um resumo, relatório ou plano a partir de números de afinação (nunca áudio), com fila, limite diário e endereço base da API (`kApiBase`). |
| `lib/app_state.dart` | Estado central do app (ChangeNotifier): afinador, metrônomo, grade, estudo, perfil, alunos, aulas, agenda, horários livres, avisos, erros, vínculo online e preferências. Quase toda tela lê e escreve aqui. |
| `lib/audio/audio_out.dart` | Saída de áudio (SoLoud): tom de referência, metrônomo por amostra exata, sinos e o Pedal (notas sustentadas, até 4 vozes). |
| `lib/audio/pitch_source.dart` | Entrada de áudio: microfone (`record`) alimentando o detector de altura, com o quadro de análise (nota, tempo e nível do sinal). |
| `lib/data/repository.dart` | Onde ficam os dados que pertencem ao PERFIL (e que um dia serão sincronizados): o próprio perfil, o histórico de sessões e os alunos do professor. A interface não sabe se os dados estão no aparelho ou na nuvem. Hoje… |
| `lib/dev/frame_meter.dart` | Medidor de fluidez, SÓ para builds de desenvolvimento (kDevDemo). Enquanto a simulação roda, mede a cada quadro: - o INTERVALO entre quadros (quanto tempo a tela leva para ser atualizada); - o CUSTO do quadro: do… |
| `lib/feedback/feedback_service.dart` | Nota do app e pesquisa rápida (1 ou 2 perguntas por aparelho). - Só envia quando a pessoa toca em "Enviar". Vai a resposta, a versão do app e um código do aparelho que o servidor embaralha. Sem nome, e-mail ou áudio.… |
| `lib/link/link_service.dart` | Cliente da API de vínculo (`/api/link`): vincular, aulas, tarefas feitas, decisões do professor, agenda, horários livres e notificações. Fala só com o servidor do app. |
| `lib/main.dart` | Abre o app. Se algo falhar ao iniciar, mostra a tela de erro (com "Tentar de novo") em vez de ficar em branco. Erros inesperados depois disso são classificados, guardados e avisados. |
| `lib/platform/hard_reset.dart` | Apagar tudo e recarregar o app (botão "Apagar tudo e recomeçar"): escolhe a versão da web ou a de celular (importação condicional). |
| `lib/platform/hard_reset_stub.dart` | Fora da web não há cache de página para limpar. |
| `lib/platform/hard_reset_web.dart` | Desregistra o service worker, apaga os caches e os dados do site e recarrega, para o usuário receber a versão mais nova mesmo se a página ficou "presa". |
| `lib/platform/web_install.dart` | Instalar o app na tela inicial (PWA): detecta se já está instalado e abre o convite de instalação; escolhe a versão web ou a de celular. |
| `lib/platform/web_install_stub.dart` | Fora da web (app nativo) não há o que instalar pelo navegador. |
| `lib/platform/web_install_web.dart` | O app já está aberto "como app instalado" (tela cheia, sem barra do navegador)? |
| `lib/platform/web_push.dart` | Notificações do navegador (Web Push): permissão, inscrição e suporte; escolhe a versão web ou a de celular. |
| `lib/platform/web_push_stub.dart` | Fora da web não há notificação de navegador (o app nativo usaria outro caminho). |
| `lib/platform/web_push_web.dart` | Ponte para `window.nmPush` (definida em web/index.html). Tudo protegido: se algo faltar ou o navegador recusar, devolve "sem suporte" em vez de lançar erro. |
| `lib/platform/web_vibrate.dart` | Vibração no navegador (batida do metrônomo e exercícios); escolhe a versão web ou a de celular. |
| `lib/platform/web_vibrate_stub.dart` | Fora da web não há vibração de navegador (o plugin nativo cuida disso). |
| `lib/platform/web_vibrate_web.dart` | Vibração na web: o plugin `vibration` só funciona em Android/iOS nativos, então aqui chamamos `navigator.vibrate` direto. Funciona no Chrome, Edge e Firefox do Android (depois de a pessoa tocar na tela uma vez). O… |
| `lib/stats/error_service.dart` | Envia um relatório de erro (anônimo e já higienizado) para o servidor. Falha em silêncio: relatar um erro nunca pode causar outro. Em teste local (localhost) não envia. |
| `lib/stats/stats_service.dart` | Estatísticas ANÔNIMAS de uso (para o painel do administrador). Manda um aviso ao abrir o app e uma batida a cada ~5 minutos enquanto ele está à frente. Vai só: um código aleatório do aparelho (que NÃO é o código de… |
| `lib/ui/agenda_actions.dart` | Controle da agenda do professor: remarcar só uma aula, trocar horários entre dois alunos e pausar um período. Toda mudança mostra antes o que vai acontecer e quem é avisado, e só vale se couber na agenda (sem choque). |
| `lib/ui/agenda_calendar.dart` | Calendário do mês para as agendas (professor e aluno): a semana começa na segunda, cada dia com aula leva pontinhos (um por aula, até 3), o dia de hoje tem um anel e o dia escolhido fica preenchido. |
| `lib/ui/agenda_page.dart` | Agenda do PROFESSOR: as aulas marcadas, por semana ou por mês. Marcar, mudar, cancelar uma aula (ou só um dia de uma aula semanal) e ligar o lembrete de 15 minutos. |
| `lib/ui/agenda_sheets.dart` | Modais da agenda do professor (remarcar uma aula, trocar horários, confirmar). Cada ação é UM modal só: o que vai mudar aparece antes (de → para), a conferência de choque é feita ao vivo e o botão só liga quando cabe… |
| `lib/ui/app_locale.dart` | O app fala português do Brasil ou inglês: os textos do próprio Flutter (seletor de data e hora, "OK"/"Cancelar", copiar/colar, nomes de mês e dia) seguem o idioma escolhido (veja `Lang` e `tr()` em afina_core). Custo… |
| `lib/ui/app_logo.dart` | Logo do Notemusic: um mostrador de afinador (arco verde, a cor do app) com uma nota musical branca no centro. Mesma geometria de tools/make_icons.mjs. |
| `lib/ui/design_system.dart` | Design system do Notemusic. REGRA: toda tela nova ou alterada usa estes valores e estes componentes (ver docs/12_DESIGN_SYSTEM.md). Números soltos de espaçamento, raio ou altura de botão não entram em tela nova.… |
| `lib/ui/dictation_button.dart` | Botão de microfone para ditar num campo de texto. Use como `suffixIcon` do `InputDecoration`. Pisca em vermelho enquanto ouve; tocar de novo para. |
| `lib/ui/error_ui.dart` | Telas e blocos de erro: tela crítica (APP-99), cartão amigável no lugar de bloco que quebrou e a lista "Problemas recentes". |
| `lib/ui/evolution_page.dart` | "Evolução": segunda tela do Meu espaço, com os dados de estudo e os gráficos (últimos 7 dias, taxa de acerto nas escalas e orientações do treinador). |
| `lib/ui/exit_sheet.dart` | Pergunta antes de fechar o app (botão voltar na tela principal). Devolve true só se a pessoa tocar em "Sair do app": tocar fora, arrastar para baixo ou apertar voltar de novo significa FICAR. O botão grande e… |
| `lib/ui/feedback_sheet.dart` | Dar uma nota de 1 a 5 ao app (com comentário opcional). |
| `lib/ui/grid_board.dart` | A grade principal, no estilo do Tonemap: 12 colunas (Dó a Si) e uma linha por oitava, com os agudos em cima. Cada quadrado mostra o nome da nota, a cor da última vez que foi tocada, quantas vezes (×3) e, na nota que… |
| `lib/ui/grid_cell.dart` | Um quadrado da grade de entonação (nota, cor da última vez, brilho e contagem). |
| `lib/ui/grid_fullscreen.dart` | Grade em tela cheia para usar durante o estudo: notas nas colunas (Dó a Si) e oitavas nas linhas (agudos no topo), em pé ou deitado. Embaixo: legenda de cores e navegação de oitavas. |
| `lib/ui/grid_page.dart` | Aba Grade, dividida em três seções simples: - Grade: ouvir e ver as notas; - Escala: exercício guiado e relatório; - Ajustes: cada ajuste abre num modal próprio. |
| `lib/ui/grid_widgets.dart` | Peças da aba Grade: seletor de oitavas, teclado de uma oitava e legendas. |
| `lib/ui/guidance_banner.dart` | Banner de orientação do exercício: GRANDE, colorido e que NÃO some depressa. Diz claramente o que fazer (SUBA / DESÇA / AFINADA) e quanto falta. - a orientação fica pelo menos [minShow] na tela antes de trocar (evita… |
| `lib/ui/hello_bar.dart` | Pergunta "Como posso te chamar?" e grava o apelido no perfil. Antes de vincular: o nome é obrigatório (sem ele o professor não sabe quem é o aluno). Devolve true se já havia nome ou se a pessoa acabou de informar. |
| `lib/ui/home_tabs.dart` | Abas da tela principal. Os ids são fixos (o hub e os atalhos usam estes números); só a ORDEM na barra de baixo muda. |
| `lib/ui/hub_section.dart` | "Meu espaço": o topo da aba. Um destaque grande (o que importa agora), dois blocos do que pede ação e uma faixa de ferramentas. Muda conforme o papel (aluno, professor ou os dois). |
| `lib/ui/install_banner.dart` | Faixa "Instale o Notemusic no celular" (só no navegador, enquanto não instalou). |
| `lib/ui/library_page.dart` | Abre o acervo. Sem [teacher]: o próprio professor (edita). Com [teacher]: o aluno (só abre e denuncia). [focusTitle] e [folder] vêm de uma tarefa "Material do professor": filtram e destacam o item. |
| `lib/ui/link_bar.dart` | Aviso do alto da tela quando o vínculo online está DESLIGADO mas há quem dependa dele (modo professor, professor ou aluno vinculado): sem ele, nada chega ao aparelho. |
| `lib/ui/markdown_lite.dart` | Mostra um texto em Markdown simples (o que a IA devolve): títulos com `##`, tópicos com `-`, listas numeradas, **negrito** e *itálico*. A leitura dos trechos mora no núcleo (`parseInline`), com testes; aqui só se… |
| `lib/ui/meeting_link.dart` | Abre o link da aula online no navegador do aparelho. Sites conhecidos (Meet, Zoom, Teams…) abrem direto; qualquer outro mostra antes o endereço, para a pessoa saber para onde está indo. |
| `lib/ui/methods_page.dart` | "Meus métodos e lições": a biblioteca do professor. Cadastrar, editar, copiar a lista. Ela também cresce sozinha com o que é digitado nas tarefas. |
| `lib/ui/metro_section.dart` | Qual visão a aba Metrônomo mostra: 0 = o metrônomo, 1 = estudo e timers (resumo, cronômetro, Pomodoro). Um só valor para o app todo: as pílulas de Pomodoro e relógio da faixa de cima trocam para 1 antes de ir à aba. |
| `lib/ui/metronome_page.dart` | Aba Metrônomo: andamento, compasso, subdivisão, som, tap tempo e modo desafio. |
| `lib/ui/mic_pill.dart` | Aviso fixo na barra superior enquanto o microfone está captando: ponto pulsante + "Ouvindo". Visível em qualquer aba; tocar desliga. |
| `lib/ui/my_lessons_page.dart` | Minhas aulas (aluno): aulas e tarefas recebidas do professor, com o status oficial (validada, aguardando, refazer) e o botão de treinar. |
| `lib/ui/needle.dart` | Ponteiro do afinador com movimento fluido. Em vez de reiniciar uma animação a cada leitura do microfone (o que dá trancos), um relógio a 60 fps aproxima o ponteiro do valor alvo com suavização exponencial. O… |
| `lib/ui/note_widgets.dart` | Nome de nota com o acidente (♯/♭) DESENHADO, elevado ao lado da letra, e a oitava pequena embaixo, tudo alinhado à linha de base: "Sol" + ♯ + 4. O ♯ e o ♭ são traçados à mão (não vêm da fonte): assim têm sempre o… |
| `lib/ui/notifications_sheet.dart` | Central de avisos (sino): lista todos os avisos, marca como lidos, limpa e leva ao lugar certo conforme o tipo. |
| `lib/ui/octave_colors.dart` | Uma cor para cada oitava do exercício (escalas e arpejos), diferente das cores de afinação (azul, verde, laranja): violeta, rosa, dourado e prata. |
| `lib/ui/open_slots_page.dart` | Horários livres do professor (publicar e apagar) e "Pegar horário" do aluno. |
| `lib/ui/paper_picker.dart` | A partitura está escura agora? ("Igual ao app" segue o tema.) |
| `lib/ui/pedal_view.dart` | Modo "Pedal" do Afinador: escolha notas num teclado e elas soam juntas, sustentadas. Serve para tocar uma melodia por cima (bordão) e para treinar o ouvido com intervalos e acordes. Soa no sistema de afinação… |
| `lib/ui/perf.dart` | Um [Listenable] que nunca avisa nada. Uma aba escondida escuta este em vez do app: assim ela não se reconstrói enquanto não está na tela, e volta a atualizar sozinha (o ListenableBuilder reassina) quando fica visível. |
| `lib/ui/pomodoro_card.dart` | Timer de estudo (Pomodoro) com alarme sutil. |
| `lib/ui/profile_page.dart` | "Minha conta": lista curta com o código que identifica você (sem cadastro) e a chave de recuperação, que permite levar o histórico para outro aparelho. |
| `lib/ui/progress_cards.dart` | Evolução da taxa de acerto nos exercícios de escala. |
| `lib/ui/qr_scan_page.dart` | Abre a câmera para ler o QR de um aluno ou de um professor. Também deixa digitar o código na mesma tela (se a câmera estiver sem permissão ou o QR não sair). Devolve o código lido, ou null se a pessoa voltar. [want]… |
| `lib/ui/ref_a_dialog.dart` | Diálogo do Lá de referência (415 a 443 Hz e valor livre). |
| `lib/ui/remind_field.dart` | Escolha do lembrete de uma aula: com quanto tempo de antecedência o professor e o aluno são avisados. Um campo só (a lista abre num modal), para não pesar o formulário. O padrão é [kReminderMinutes]. |
| `lib/ui/reminder_card.dart` | Lembrete de aula 15 minutos antes (notificação do navegador, mesmo com o app fechado). Mostra a situação deste aparelho e o botão para ligar ou desligar. |
| `lib/ui/safe_input.dart` | Filtro de digitação: tira na hora caracteres de controle e invisíveis (inclusive os que invertem a direção do texto) e corta no tamanho do campo, contando letras e não bytes. Colar um texto gigante também é cortado. |
| `lib/ui/scale_exercise_page.dart` | Exercício de escala guiado: o app mostra a próxima nota, acompanha a afinação de cada uma e, no fim, dá a pontuação e orientações. |
| `lib/ui/scale_settings.dart` | Os ajustes da escala num lugar só, sem modal dentro de modal: tudo aparece na própria folha, em seções, e é a MESMA folha na aba Escalas e na tela do exercício (a pessoa não precisa lembrar onde está cada coisa). Só… |
| `lib/ui/settings_page.dart` | Ajustes: aparência, afinação, microfone, metrônomo, grade, estudo, permissões e privacidade, conta, sobre e diagnóstico (problemas recentes e envio de relatórios). |
| `lib/ui/share_sheet.dart` | Compartilhar o app (QR, copiar link, enviar) e o convite do professor. |
| `lib/ui/slot_form_page.dart` | Formulário de aula marcada (aluno, dia, hora, duração, repetir, observação) com as regras de horário. |
| `lib/ui/smooth_color.dart` | Transição suave de cor para os quadrados da grade e do ponteiro. |
| `lib/ui/speed_trainer_card.dart` | "Acelerar aos poucos" na tela do metrônomo: liga e desliga num toque, mostra o resumo em frase e, tocando, mostra o BPM que subiu, quanto falta para o próximo aumento e o caminho até o teto. Os ajustes ficam numa… |
| `lib/ui/staff_card.dart` | Resultado de uma nota tocada (cents de desvio) -> cor da cabeça da nota; null = ainda não tocada ou pulada. |
| `lib/ui/staff_settings.dart` | Texto curto do que está valendo na partitura (para o resumo do ajuste). |
| `lib/ui/staff_view.dart` | Resultado de uma nota já tocada (pinta a cabeça da nota). |
| `lib/ui/status_strip.dart` | Faixa fina logo abaixo da barra superior com os avisos que ficam ativos: microfone ouvindo e timer do Pomodoro. Só aparece quando há algo ativo, e os dois avisos ficam lado a lado, sem disputar espaço com o título e… |
| `lib/ui/student_identity.dart` | Selo do vínculo online e campo do código do aluno, na ficha e na lista. |
| `lib/ui/study_card.dart` | "Seu estudo": o tempo estudado hoje, os dias seguidos, a meta diária e o cronômetro/Pomodoro num cartão só. Mora na aba Metrônomo (onde a pessoa já está praticando); os dados e gráficos ficam na tela "Evolução". |
| `lib/ui/study_page.dart` | "Meu espaço": o foco é a AGENDA (próxima aula e o que vem depois), os alunos, as tarefas e o acervo. O estudo (resumo, cronômetro e Pomodoro) mora na aba Metrônomo (`study_card.dart`). |
| `lib/ui/study_timers.dart` | Bloco "Como você quer estudar?": submenu com Pomodoro, Cronômetro e Meu tempo, cada um com uma explicação curta de quando usar. |
| `lib/ui/success_moment.dart` | "Momento de sucesso": uma folha que sobe de baixo com um ✓ desenhado, uma frase e um detalhe, e some sozinha. Serve para os poucos momentos em que algo importante deu certo (pegar um horário, marcar uma aula, enviar… |
| `lib/ui/suggestions.dart` | Sugestões do app (não são avisos de aula): ficam no sino, não presas no topo da tela. Hoje: informar o apelido e instalar no celular. |
| `lib/ui/task_form_page.dart` | Formulário de tarefa (escala, arpejo, método e lição, repertório ou outra) com observações. |
| `lib/ui/teacher_page.dart` | Tela Alunos do professor (lista, novo aluno, QR, importar, métodos, senha) e a ficha do aluno (aula, tarefas, validação, observações, relatórios). |
| `lib/ui/theme.dart` | Paleta do app, com tema escuro e claro. As cores que mudam com o tema são `getters` lidos a cada construção de tela. [AppColors.dark] é definido uma vez por troca de tema em `main.dart` (que recria a árvore de… |
| `lib/ui/toast.dart` | Aviso curto no TOPO da tela: aparece deslizando, some sozinho e pode ser arrastado para dispensar. Não cobre os botões de baixo nem exige toque. O tipo (sucesso, atenção, informação) vem do texto, ou de [kind]; muda… |
| `lib/ui/toast_kind.dart` | Tipos de aviso curto: o tipo define cor, ícone e quanto tempo fica na tela. |
| `lib/ui/tour/start_card.dart` | "Comece por aqui": três passos para o professor novo (vincular, marcar aula, passar tarefa), com o progresso, um atalho para cada passo e o tutorial "Ver como funciona". Some sozinho quando tudo foi feito e dá para… |
| `lib/ui/tour/tour.dart` | Tutorial guiado: escurece a tela, deixa um buraco redondo no botão e mostra uma caixinha com o que ele faz. Nunca é obrigatório (sempre tem "Pular") e nunca trava: se um botão não estiver na tela, o passo é pulado. O… |
| `lib/ui/trainer_editor.dart` | Ajustes do "Acelerar aos poucos", em quatro perguntas simples e um resumo em frase: 1. Quando aumentar (por tempo ou por compassos), 2. Quanto aumentar, 3. Até quantos BPM, 4. "Fica assim: …". Só botões de escolha e… |
| `lib/ui/transitions.dart` | Troca "sai e depois entra" para usar no `AnimatedSwitcher`. O padrão (fade cruzado) deixa os dois textos um em cima do outro por um instante, o que parece bagunçado. Aqui quem sai some depressa (e encolhe um pouco) e… |
| `lib/ui/tuner_page.dart` | Aba Afinador: cordas soltas, cromático e Pedal; ponteiro, desvio, frequência, Lá de referência e tônica. |
| `lib/ui/tuning_guide.dart` | Explicação didática do sistema de afinação escolhido, com a tabela de alvos da tônica (em Hz, contra a afinação igual) e botões para OUVIR cada nota. Aparece no Afinador (modo Cromático) e nas Configurações. |
| `lib/ui/tuning_pick.dart` | Nome curto do sistema de afinação em uso ("Pitagórico"). |
| `lib/ui/undo_snack.dart` | Aviso de baixo com o botão "Desfazer": serve para toda ação que some com algo da tela (esconder um cartão, tirar um item). Fica 8 segundos (tempo de ler e decidir), é flutuante e o botão tem alvo de toque grande.… |
| `lib/ui/validation_ui.dart` | Na ficha do aluno: as tarefas que ELE marcou como feitas e que esperam a validação do professor. Só viram "feitas" (finalizadas) quando o professor confirma; se não, voltam a pendente. |
| `lib/ui/widgets.dart` | Peças comuns de interface: cartões, seleção de opções, folha de ajuda ("?") e textos de ajuda em um lugar só. |
| `lib/voice/dictation.dart` | Escrita por voz: toca no microfone de um campo, fala, e o texto aparece. Usa o reconhecimento de fala do próprio aparelho (Android/iOS) ou do navegador (Chrome, Edge, Safari). O app não grava nem envia áudio: quem… |

## Núcleo em Dart puro (`packages/afina_core/lib/`)

| Arquivo | O que faz |
|---|---|
| `packages/afina_core/lib/absence.dart` | Falta do aluno a uma aula, registrada pelo professor (só neste aparelho; faz parte da ficha do aluno). [noShow]: faltou sem avisar. [notified]: avisou que não vem. |
| `packages/afina_core/lib/afina_core.dart` | Ponto de entrada do núcleo: reexporta todos os módulos de `packages/afina_core/lib`. |
| `packages/afina_core/lib/agenda.dart` | Agenda de aulas: o professor marca aulas com os alunos (uma vez ou toda semana) e o aluno vê as suas. Dart puro e testável: o relógio é sempre passado de fora. A aula que se repete toda semana é UMA regra só (não uma… |
| `packages/afina_core/lib/class_rules.dart` | Regra única das aulas: em que fase está cada aula, o que dá para mudar nela e quais aulas entram na agenda mostrada. Hub (Meu espaço), agenda e lembretes usam estas mesmas funções, para nunca mostrarem números ou… |
| `packages/afina_core/lib/device_tags.dart` | Rótulos curtos e ANÔNIMOS de aparelho para as estatísticas do painel. Só categorias (nunca o texto cru do navegador): cada rótulo tem até 10 letras ou números minúsculos, o que permite combinar filtros sem… |
| `packages/afina_core/lib/error_report.dart` | Montagem do relatório de erro que o app envia ao servidor: trilha de telas (breadcrumbs), ambiente (versão, aparelho), modo de envio e freio contra repetição. Dart puro e testável. Nada de conteúdo pessoal: só nomes… |
| `packages/afina_core/lib/errors.dart` | Erros do app: um catálogo único de códigos e textos em português, a classificação de qualquer exceção num [AppError], a higienização dos detalhes técnicos (nunca saem nomes, códigos de perfil, e-mails nem segredos) e… |
| `packages/afina_core/lib/greeting.dart` | Saudação conforme a hora do dia (relógio local do aparelho). 5h às 11h59: "Bom dia" · 12h às 17h59: "Boa tarde" · o resto: "Boa noite". |
| `packages/afina_core/lib/hub.dart` | Regras do hub "Meu espaço": o que vai no bloco grande (destaque) e os textos dos blocos menores, sempre dizendo o que fazer quando não há nada. Dart puro e testável. |
| `packages/afina_core/lib/hub_view.dart` | Visões do "Meu espaço": quem é professor também pode ser aluno de outra pessoa, então o hub tem duas visões separadas (Aluno e Professor) e cada destino aparece UMA vez por visão. Dart puro e testável: a tela só… |
| `packages/afina_core/lib/i18n.dart` | Idiomas do app (português e inglês) e a função [tr]. Como funciona: o texto no código é o PORTUGUÊS (`tr('Salvar')`). Com o idioma em português, [tr] devolve o próprio texto; em inglês, procura a tradução em [kEn]… |
| `packages/afina_core/lib/i18n_en.dart` | Dicionário português → inglês. A chave é o texto em português exatamente como está em `tr('...')` no código. Marcadores `{0}`, `{1}`… recebem os valores. As traduções ficam em partes (`i18n_en_*.dart`) e são juntadas… |
| `packages/afina_core/lib/i18n_en_a.dart` | Parte A do dicionário português → inglês (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b00.dart` | Dicionário português → inglês, parte b00 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b01.dart` | Dicionário português → inglês, parte b01 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b02.dart` | Dicionário português → inglês, parte b02 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b03.dart` | Dicionário português → inglês, parte b03 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b04.dart` | Dicionário português → inglês, parte b04 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b05.dart` | Dicionário português → inglês, parte b05 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b06.dart` | Dicionário português → inglês, parte b06 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b07.dart` | Dicionário português → inglês, parte b07 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b08.dart` | Dicionário português → inglês, parte b08 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b09.dart` | Dicionário português → inglês, parte b09 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b10.dart` | Dicionário português → inglês, parte b10 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b11.dart` | Dicionário português → inglês, parte b11 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_b12.dart` | Dicionário português → inglês, parte b12 (ver i18n_en.dart). |
| `packages/afina_core/lib/i18n_en_srv.dart` | Dicionário português → inglês, parte srv (ver i18n_en.dart). |
| `packages/afina_core/lib/identity.dart` | Identidade do perfil (Fase 1): quem é a pessoa, sem cadastro e sem servidor. - [Profile.id]: UUID do perfil. Todos os dados pertencem a ele, não ao aparelho. - [Profile.secret]: 256 bits aleatórios que provam que… |
| `packages/afina_core/lib/input_guard.dart` | Limpeza e limites de tudo que a pessoa digita, cola ou lê de um QR. Dart puro. O app não monta HTML nem consulta banco com esses textos, mas eles aparecem na tela, vão para backups colados e (em resumo) para a IA.… |
| `packages/afina_core/lib/lesson.dart` | Aulas: o professor começa a aula com um aluno, pode pausar, e ao encerrar o que ele passou nela (tarefas e observações) é empacotado para o aluno receber. Dart puro e testável (o relógio é sempre passado de fora). |
| `packages/afina_core/lib/lesson_week.dart` | "Esta semana" do aluno: junta as tarefas das aulas recebidas dos últimos 7 dias e as que ficaram em aberto de aulas mais antigas. Dart puro e testável. |
| `packages/afina_core/lib/library.dart` | Acervo e Repertório do professor: só LINKS (Google Drive, IMSLP, YouTube…), nenhum arquivo é guardado. A mesma lista de sites aceitos existe no servidor (api/_lib/library.js): mantenha as duas iguais. |
| `packages/afina_core/lib/link_pref.dart` | Regra do "Vínculo online": ligado por padrão para quem tem professor, aluno ou modo professor, e só desligado se a pessoa escolheu desligar (e confirmou o aviso). |
| `packages/afina_core/lib/link_status.dart` | Estado do vínculo online em linguagem simples: o que está acontecendo com a conexão, o que isso significa para a pessoa e o que ela pode fazer. Dart puro e testável. |
| `packages/afina_core/lib/markdown_lite.dart` | Markdown simples da IA (títulos `##`, tópicos, listas numeradas, **negrito** e *itálico*): leitura dos trechos em linha e conversão para texto puro com quebras de linha (para copiar). Dart puro e testável; a tela só… |
| `packages/afina_core/lib/methods.dart` | Biblioteca de métodos do professor (ex.: Suzuki, Ševčík) com as lições de cada um. O professor cadastra, importa de um texto colado e exporta. Dart puro e testável. |
| `packages/afina_core/lib/metronome_engine.dart` | Motor do metrônomo: gera PCM com cliques posicionados em AMOSTRAS exatas. Por que assim: o app não agenda cliques com Timer (que oscila 5-20 ms). Em vez disso, gera o áudio contínuo e coloca cada clique na amostra… |
| `packages/afina_core/lib/needle_spring.dart` | Movimento natural de ponteiro: mola amortecida e mapeamento de ângulo. Fica no núcleo (Dart puro) para poder ser testado sem a interface. |
| `packages/afina_core/lib/note_display.dart` | Estabilizador da nota EXIBIDA (a que fica em destaque na tela). A grade continua registrando cada nota que o microfone ouve (as cores são fiéis ao que foi tocado). Só o DESTAQUE ao vivo (nome da nota, ponteiro e… |
| `packages/afina_core/lib/note_gate.dart` | Porta de registro da sessão: só vira nota da grade (cor, ×N, placar) o que se mantém por um tempo mínimo. Corta o que o músico não tocou de verdade: a passagem entre duas notas (de Lá para Si o dedo cruza o Lá♯),… |
| `packages/afina_core/lib/open_slots.dart` | Horários disponíveis do professor e o aluno que "pega" um deles. Dart puro e testável. Um horário disponível usa o mesmo formato de [ClassSlot] (data, duração, semanal ou avulso). Quando o aluno pega um, o servidor o… |
| `packages/afina_core/lib/pedal.dart` | Pedal (bordão / drone): várias notas soando ao mesmo tempo para tocar uma melodia por cima ou treinar o ouvido. Dart puro e testável: escolhe as notas, calcula as frequências no sistema de afinação escolhido (Igual,… |
| `packages/afina_core/lib/pitch_detector.dart` | Detector de altura (pitch) pelo método McLeod (MPM), implementação própria a partir do artigo público "A Smarter Way to Find Pitch" (McLeod & Wyvill). Decisões de precisão: - NSDF (função de diferença quadrática… |
| `packages/afina_core/lib/pitch_grid.dart` | Estabilizador de notas + grade de entonação + relatório de escala. A grade guarda, para cada nota (número MIDI), a MÉDIA PONDERADA do desvio em cents em relação ao alvo do sistema escolhido. Ponderação por clareza e… |
| `packages/afina_core/lib/pomodoro.dart` | Temporizador de estudo no estilo Pomodoro: foco, pausa curta e pausa longa. Lógica pura (sem relógio próprio): quem usa passa o instante atual em milissegundos. Isso deixa tudo testável e permite retomar depois de o… |
| `packages/afina_core/lib/practice_coach.dart` | Treinador: analisa o histórico de escalas e devolve orientações em português, como "Suas notas Mi estão ficando baixas: tente colocá-las um pouco mais altas". É uma análise por regras (estatística sobre as suas… |
| `packages/afina_core/lib/rhythm_challenge.dart` | Modo desafio do metrônomo ("sabotagem"): de vez em quando, de surpresa, o andamento muda por alguns compassos ou o metrônomo fica mudo, e depois volta sempre ao andamento que a pessoa configurou. Serve para treinar a… |
| `packages/afina_core/lib/scale_exercise.dart` | Exercício de escalas guiado (estilo "sistema de escalas" de Carl Flesch): o músico toca a escala subindo e descendo, em 1, 2 ou 3 oitavas, e o app acompanha nota por nota, medindo a afinação de cada uma. Dois jeitos… |
| `packages/afina_core/lib/scale_spelling.dart` | Grafia das notas de uma escala ou arpejo: cada grau ganha a sua LETRA (Dó, Ré, Mi... em sequência), como está escrito na partitura. É o que faz a Dó menor melódica subir com Lá e Si naturais e descer com Si♭ e Lá♭, e… |
| `packages/afina_core/lib/speed_trainer.dart` | Ajudantes do "Acelerar aos poucos": opções prontas, textos em linguagem simples e o tempo até o teto. Dart puro (sem Flutter), testado em test/speed_trainer_test.dart. |
| `packages/afina_core/lib/staff_layout.dart` | Distribuição da partitura na largura da tela: quebra em linhas (sistemas), espaça as notas, calcula hastes, barras, tercinas e linhas suplementares. Tudo em "espaços de pauta" (1 espaço = a distância entre duas… |
| `packages/afina_core/lib/staff_notation.dart` | Partitura de escalas e arpejos (clave de Sol, compasso 4/4, como no "sistema de escalas" de Flesch). Esta parte é só MÚSICA, em Dart puro e testável: posição da nota na pauta, armadura de clave, quando aparece ♯ ♭ ♮… |
| `packages/afina_core/lib/start_checklist.dart` | "Comece por aqui": o que o professor novo precisa fazer para o app render (vincular, marcar aula, passar tarefa). Dart puro: o app diz o que já aconteceu e esta lógica diz o que falta e qual é o próximo passo. |
| `packages/afina_core/lib/study_clock.dart` | Relógios de estudo: CRONÔMETRO (conta para cima) e MINUTERIA (conta para baixo até um tempo escolhido). Dart puro: o relógio de parede é passado de fora (ms), então dá para testar e para retomar depois de fechar o app. |
| `packages/afina_core/lib/system_guide.dart` | Dados para explicar o "Sistema de afinação" na tela: para a tônica escolhida, qual é o ALVO de cada nota no sistema (igual, pitagórico ou justo) e quanto ele difere do temperamento igual, em Hz. Dart puro e testável. |
| `packages/afina_core/lib/task_status.dart` | Decisão oficial do professor sobre uma tarefa que o aluno marcou como feita. |
| `packages/afina_core/lib/teacher.dart` | Área do professor (versão local, sem login): alunos, tarefas, observações, relatórios e troca de dados por texto. Dart puro e testável. |
| `packages/afina_core/lib/tone_synth.dart` | Síntese do tom de referência (diapasão) como um trecho que se repete sem emendas. Em vez de gerar o som aos pedaços em tempo real (o que falha se um pedaço atrasa), calcula-se UM trecho com um número inteiro de… |
| `packages/afina_core/lib/tuning.dart` | Matemática de afinação do app. Tudo aqui é teoria musical pública (razões de intervalos de 3 e 5 limites, cents, temperamento igual). Nenhum código de terceiros. DECISÕES DE PRECISÃO (leia antes de mudar): 1. A… |
| `packages/afina_core/lib/violin_fingering.dart` | Dedilhado do violino para as escalas do "sistema de escalas" de Carl Flesch, lido das páginas do método. O Flesch NÃO numera todas as notas: só os pontos de mudança (começo de posição, nota no alto, uso do 4º dedo no… |

## Testes do núcleo (`packages/afina_core/test/`)

| Arquivo | O que faz |
|---|---|
| `packages/afina_core/test/absence_test.dart` | Testes do módulo `absence`. |
| `packages/afina_core/test/agenda_test.dart` | 18/11/2026 é quarta-feira. |
| `packages/afina_core/test/arpeggio_test.dart` | Testes do módulo `arpeggio`. |
| `packages/afina_core/test/class_rules_test.dart` | Testes do módulo `class_rules`. |
| `packages/afina_core/test/device_tags_test.dart` | Testes do módulo `device_tags`. |
| `packages/afina_core/test/error_report_test.dart` | Testes do módulo `error_report`. |
| `packages/afina_core/test/errors_test.dart` | Testes do módulo `errors`. |
| `packages/afina_core/test/fast_notes_test.dart` | Sinal de violino sintético: escala de Sol maior (Sol3 a Sol4) com notas de [noteMs] cada, ligadas (sem pausa), com vibrato e um pouco de ruído. |
| `packages/afina_core/test/greeting_test.dart` | Testes do módulo `greeting`. |
| `packages/afina_core/test/grid_replay_test.dart` | Toca [cents] por [seconds] (quadros de 30 ms) a partir de [t0]; devolve o instante final. |
| `packages/afina_core/test/hub_test.dart` | a aula das 13:00 (60 min) acaba às 14:00: no instante do fim já não é "em andamento" |
| `packages/afina_core/test/hub_view_test.dart` | Testes do módulo `hub_view`. |
| `packages/afina_core/test/i18n_test.dart` | "{0} de {1}, {2}" (dia, mês, dia da semana) vira "{2}, {1} {0}" |
| `packages/afina_core/test/identity_test.dart` | Troca de um caractere por outro diferente do alfabeto. |
| `packages/afina_core/test/input_guard_test.dart` | Testes do módulo `input_guard`. |
| `packages/afina_core/test/lesson_delivery_test.dart` | dados antigos (sem a chave) continuam lendo, como "não se aplica" |
| `packages/afina_core/test/lesson_test.dart` | Testes do módulo `lesson`. |
| `packages/afina_core/test/lesson_week_test.dart` | Testes do módulo `lesson_week`. |
| `packages/afina_core/test/library_test.dart` | Testes do módulo `library`. |
| `packages/afina_core/test/link_pref_test.dart` | Testes do módulo `link_pref`. |
| `packages/afina_core/test/link_status_test.dart` | Testes do módulo `link_status`. |
| `packages/afina_core/test/markdown_lite_test.dart` | Testes do módulo `markdown_lite`. |
| `packages/afina_core/test/methods_test.dart` | Testes do módulo `methods`. |
| `packages/afina_core/test/metronome_engine_test.dart` | Renderiza [total] amostras em blocos de [chunk] e junta tudo. |
| `packages/afina_core/test/needle_spring_test.dart` | Simula [seconds] com passos de [dt] e devolve a trajetória (posições). |
| `packages/afina_core/test/note_display_test.dart` | Alimenta o filtro com [n] por [seconds], num quadro a cada 30 ms, a partir de [t0]. Devolve a lista do que foi exibido em cada quadro. |
| `packages/afina_core/test/note_gate_test.dart` | Alimenta a porta com [n] por [seconds], um quadro a cada 17 ms, desde [t0]. Devolve o instante final. |
| `packages/afina_core/test/open_slots_test.dart` | Testes do módulo `open_slots`. |
| `packages/afina_core/test/open_strings_grid_test.dart` | O afinador de cordas afina em quintas puras (Sol3 = 195,56 Hz). Em temperamento igual o Sol3 seria 196,00 Hz (3,9 cents acima). A grade precisa concordar. |
| `packages/afina_core/test/pedal_test.dart` | a soma das amplitudes no pior caso fica contida (< 1,6) |
| `packages/afina_core/test/pitch_detector_test.dart` | Gera um tom com harmônicos [amps] (índice 0 = fundamental). |
| `packages/afina_core/test/pitch_grid_test.dart` | Sobe devagar até +52 cents. |
| `packages/afina_core/test/pomodoro_test.dart` | Testes do módulo `pomodoro`. |
| `packages/afina_core/test/remind_test.dart` | Testes do módulo `remind`. |
| `packages/afina_core/test/rhythm_challenge_test.dart` | Sorteia [n] compassos e devolve a decisão de cada um. |
| `packages/afina_core/test/scale_coach_test.dart` | Passos de uma escala em que cada nota (pitch class) tem um viés fixo. |
| `packages/afina_core/test/scale_flow_test.dart` | Sol maior, 1 oitava. |
| `packages/afina_core/test/scale_spelling_test.dart` | maiores: Fá♯ (padrão) e Sol♭ (outra grafia) são a mesma tecla |
| `packages/afina_core/test/scale_waiting_test.dart` | Testes do módulo `scale_waiting`. |
| `packages/afina_core/test/speed_trainer_test.dart` | Renderiza [seconds] segundos e devolve os eventos de "primeiro tempo" de cada compasso. |
| `packages/afina_core/test/staff_layout_test.dart` | as notas com 8va usam a posição escrita (uma oitava abaixo) |
| `packages/afina_core/test/staff_notation_test.dart` | Leitor independente: lê a partitura como um músico (armadura + acidentes valem até a barra de compasso) e devolve a nota MIDI que cada evento representa. Se bater com a sequência do exercício, a escrita está certa. |
| `packages/afina_core/test/start_checklist_test.dart` | Testes do módulo `start_checklist`. |
| `packages/afina_core/test/study_clock_test.dart` | Testes do módulo `study_clock`. |
| `packages/afina_core/test/system_guide_test.dart` | em Hz, na oitava 4: Mi justo (5/4 de 261,626) = 327,03 Hz contra 329,63 do igual |
| `packages/afina_core/test/task_status_test.dart` | Testes do módulo `task_status`. |
| `packages/afina_core/test/teacher_test.dart` | Código com verificação correta, gerado na hora. |
| `packages/afina_core/test/tone_synth_test.dart` | Do contrabaixo ao violino agudo, e referências de orquestra. |
| `packages/afina_core/test/tuning_test.dart` | C2 fica ~5.87 cents abaixo do temperado. |
| `packages/afina_core/test/vibrato_test.dart` | Violino sintético: segue [midis] (cada um por [noteMs]) com [centerCents] de desvio médio e vibrato de ±[depth] cents a [rate] Hz. |
| `packages/afina_core/test/violin_fingering_test.dart` | Cordas soltas do violino: Sol3, Ré4, Lá4, Mi5. |

## API (funções da Vercel, `api/`)

| Arquivo | O que faz |
|---|---|
| `api/admin.js` | /api/admin: painel do administrador (indicadores e gestão de perfis anônimos). POST { action, ... } com "Authorization: Bearer <chave de admin>". Ações: kpis indicadores (total, ativos x inativos, professores,… |
| `api/ai-status.js` | GET /api/ai-status: quais serviços de IA estão ativos e quanto se espera na fila. Nunca devolve chaves; só o necessário para o app mostrar o estado. |
| `api/coach.js` | Função da Vercel: POST /api/coach (IA com vários serviços e fila) Recebe um RESUMO de números (nunca áudio) e um tipo de pedido, escolhe o serviço de IA certo (Gemini, OpenAI, Claude, Groq, Mistral, OpenRouter),… |
| `api/errors.js` | POST /api/errors: relatório de erro do app (anônimo e sem dados pessoais). O app manda o que aconteceu (código, tela, detalhe já higienizado, versão, aparelho, trilha de telas). O servidor higieniza DE NOVO (nunca… |
| `api/feedback.js` | POST /api/feedback: nota do app e respostas das pesquisas rápidas (anônimas). GET /api/feedback: resumo para o dono do app (exige FEEDBACK_ADMIN_KEY). Privacidade: guarda só a resposta, a versão e um código do… |
| `api/fingering.js` | GET /api/fingering: dedilhados do violino que o administrador corrigiu ou incluiu (ver _lib/fingering.js). Público e sem dado pessoal. O app busca uma vez por abertura; a CDN guarda a resposta por 5 minutos, então o… |
| `api/link.js` | POST /api/link: vínculo entre professor e aluno, registrado dos dois lados. Quem lê o QR (ou digita o código) do outro cria o vínculo; ele passa a valer para os dois, e cada um vê o outro na sua lista na próxima… |
| `api/remind.js` | POST /api/remind: chamado pelo QStash 15 minutos antes de uma aula. Envia a notificação ao professor e ao aluno (Web Push) e agenda o lembrete da próxima aula (se a aula é semanal). Só aceita mensagens que o próprio… |
| `api/stats.js` | /api/stats: métricas ANÔNIMAS de uso do app. POST (o app, sem chave): { t: 'open'\|'beat', id, d?: { pl, in, v, o?, x?: { os, sc, lg, th, tc, mic, nt } }, tabs?: [...] } id = código aleatório do aparelho (NÃO é o… |

## Apoio da API (`api/_lib/`, não conta como função)

| Arquivo | O que faz |
|---|---|
| `api/_lib/admin_push.js` | Aviso (Web Push) para o administrador quando aparece um bug GRAVE novo (ou um grave reaberto). As inscrições do navegador do admin ficam em `adm:ps` (feitas no painel, com a chave de admin). Custo: zero quando não há… |
| `api/_lib/agenda.js` | Agenda de aulas no servidor: limpeza do que chega, cálculo da próxima aula e agendamento do lembrete (QStash), uma mensagem por vez (a aula semanal agenda a próxima ao disparar). |
| `api/_lib/config.js` | Configuração lida das variáveis de ambiente da Vercel. NENHUMA chave fica no código. |
| `api/_lib/cost_model.js` | Quanto custa manter a plataforma: projeção de gastos por número de usuários. Função pura (sem rede, sem Redis), usada pelo painel (aba Custos › Contas) e testada em api/cost_model.test.js. De onde vêm os números: -… |
| `api/_lib/error_store.js` | Gravação dos relatórios de erro no Redis (usada pelo endpoint do app e pelos erros do próprio servidor). Limites, agrupamento por impressão digital, reabertura e modo leve num só lugar. |
| `api/_lib/errors_lib.js` | Regras dos relatórios de erro (iguais às do app, em `afina_core/errors.dart`): higienização, impressão digital do bug, validação do pacote e nomes das chaves no Redis. |
| `api/_lib/features.js` | Recursos liberados aos poucos ("chaves"): cada novidade nasce desligada, é liberada por código de perfil, depois por porcentagem e, por fim, para todos. O SERVIDOR decide; o app só esconde o que não está ligado.… |
| `api/_lib/fingering.js` | Dedilhado do violino (método de Flesch) editado pelo administrador. O app traz as escalas já conferidas (packages/afina_core/lib/violin_fingering.dart). O administrador pode corrigir uma delas ou incluir outra pelo… |
| `api/_lib/library.js` | Acervo e Repertório do professor (só LINKS, nenhum arquivo é guardado aqui). O professor cadastra título, autor e o endereço do material (Google Drive, IMSLP, YouTube…); o aluno vinculado abre o endereço. Liberado só… |
| `api/_lib/metrics.js` | Métricas anônimas de uso: nomes das chaves, o dia (fuso de Brasília) e o contador que o servidor soma sozinho quando algo acontece (aula enviada, vínculo criado...). Falhar aqui NUNCA pode derrubar o que o usuário… |
| `api/_lib/profiles.js` | Índice dos perfis anônimos (código + apelido) para o painel do administrador: quando entrou, última atividade, papel (professor / aluno) e bloqueio. NÃO há cadastro nem login. Custo: 3 comandos quando o perfil nasce;… |
| `api/_lib/prompts.js` | Instruções de cada tipo de pedido. O texto recebido é DADO, nunca instrução. |
| `api/_lib/providers.js` | Um adaptador por serviço de IA. Todos recebem {system, prompt} e devolvem {status: 'ok'\|'busy'\|'auth'\|'error', text?, model?, retryAfterMs?}. |
| `api/_lib/queue.js` | FILA JUSTA entre aparelhos: cada serviço de IA tem um limite de pedidos por minuto; cada pedido RESERVA o próximo horário livre ("slot"), na ordem de chegada. Se o horário está perto, o servidor espera e atende; se… |
| `api/_lib/router.js` | REGRA DE NEGÓCIO: qual IA atende cada tipo de pedido, e quando trocar de serviço. - cada tipo de pedido tem uma ordem de preferência e um "nível" de modelo (rápido e barato para resumos; mais capaz para relatórios e… |
| `api/_lib/store.js` | Contadores, estado de saúde e fila. Usa o Upstash Redis (REST) quando configurado, para valer entre TODAS as instâncias da Vercel; senão cai para a memória da instância. |
| `api/_lib/store_cmd.js` | Comandos genéricos do Redis (HyperLogLog, conjuntos ordenados, contadores em hash) para as métricas, com um emulador mínimo em memória para os testes. Em produção vai tudo ao Upstash, em lote (`/pipeline`): uma ida e… |
| `api/_lib/sweep.js` | Limpeza de perfis abandonados: um perfil SEM vínculo, SEM aluno/professor, SEM horários nem notificações e parado há 60 dias é apagado. Quem tem qualquer vínculo ou agenda, e quem foi bloqueado, nunca é apagado.… |
| `api/_lib/unlink.js` | Desfaz o vínculo entre um professor e um aluno e apaga tudo o que dependia dele. Usado pelo app (ação "unlink" de /api/link) e pelo suporte do painel (/api/admin). |
| `api/_lib/webpush.js` | Web Push (RFC 8030 + VAPID RFC 8292 + criptografia aes128gcm RFC 8291) só com o módulo `crypto` do Node: o projeto não instala pacotes npm, então nada de dependência externa. |

## Testes da API (ficam fora do deploy via `.vercelignore`)

| Arquivo | O que faz |
|---|---|
| `api/_lib/webpush.test.js` | Exemplo oficial da RFC 8291 (apêndice A). |
| `api/admin.test.js` | Testes do painel do administrador (indicadores e gestão de perfis), sem rede: `node --test api/admin.test.js` |
| `api/admin_design.test.js` | O painel segue o mesmo design system do app: `node --test api/admin_design.test.js` (cores iguais às de lib/ui/theme.dart, escala de espaço, abas com ícone, frase de apoio em todo título, movimento que se desliga). |
| `api/admin_push.test.js` | Aviso de bug grave ao admin (Web Push), precisão dos bugs e busca por nome, sem rede: `node --test api/admin_push.test.js` |
| `api/agenda.test.js` | Testes da agenda e dos lembretes, sem rede: `node --test api/agenda.test.js` |
| `api/agenda_control.test.js` | Testes do controle da agenda (trocar o aluno de uma aula, remarcar uma data, pausar): `node --test api/agenda_control.test.js` |
| `api/avail.test.js` | Testes dos horários disponíveis (professor) e de "pegar horário" (aluno), sem rede: `node --test api/avail.test.js` |
| `api/coach.test.js` | Testes da IA (vários serviços + fila) sem rede e sem chaves reais: `node --test api/` |
| `api/cost_model.test.js` | Testes da conta de custos (quanto custa manter a plataforma): `node --test api/cost_model.test.js` |
| `api/errors.test.js` | Relatórios de erro do app e a aba "Bugs" do painel, sem rede: `node --test api/errors.test.js` |
| `api/features.test.js` | Testes das chaves de recursos (liberação aos poucos): `node --test api/features.test.js` |
| `api/feedback.test.js` | Testes da nota do app e das pesquisas rápidas, sem rede: `node --test api/feedback.test.js` |
| `api/fingering.test.js` | Dedilhado do violino editado no painel: validação, notas de cada escala, ações do admin e a leitura pública. `node --test api/fingering.test.js` |
| `api/funnel.test.js` | Testes do funil de ativação e da comparação de agendas do painel: `node --test api/funnel.test.js` |
| `api/guardrails.test.js` | Guardrails de segurança da API: entradas malformadas, gigantes e hostis. Nada pode quebrar, vazar segredo ou gravar lixo. `node --test api/guardrails.test.js` |
| `api/indicators.test.js` | Testes dos indicadores de saúde do uso no painel, sem rede: `node --test api/indicators.test.js` |
| `api/library.test.js` | Testes do Acervo e Repertório do professor (só links): `node --test api/library.test.js` |
| `api/link.test.js` | Testes do vínculo professor-aluno, sem rede: `node --test api/link.test.js` |
| `api/online.test.js` | Testes da aula online (link da aula, modo online/presencial, link padrão): `node --test api/online.test.js` |
| `api/painel_precisao.test.js` | Painel mais preciso: saúde, custos, coortes, período anterior, horas, limpeza e erros do servidor. `node --test api/painel_precisao.test.js` |
| `api/presence.test.js` | Testes da presença (quem está online agora) no painel, sem rede: `node --test api/presence.test.js` |
| `api/remind_choice.test.js` | Testes do lembrete escolhido pelo professor (chave `lembrete_escolha`): `node --test api/remind_choice.test.js` |
| `api/stats.test.js` | Testes das métricas anônimas e do painel de admin, sem rede: `node --test api/stats.test.js` |
| `api/support.test.js` | Testes do suporte do painel (vínculo, agenda, código de liberação e aviso ao usuário), sem rede: `node --test api/support.test.js` |
| `api/sweep.test.js` | Testes da limpeza de perfis abandonados e do aviso de origens com muitos perfis: `node --test api/sweep.test.js` |
| `api/user_study.test.js` | Tempo de estudo, modelo e cidade por perfil no painel, sem rede: `node --test api/user_study.test.js` |
| `api/user_usage.test.js` | Tempo de uso e ficha do aparelho por perfil no painel, sem rede: `node --test api/user_usage.test.js` |
| `api/visitors.test.js` | Testes da aba "Visitantes" do painel (quem usa sem cadastro): `node --test api/visitors.test.js` |

## Site e painel (`web/`)

| Arquivo | O que faz |
|---|---|
| `web/admin.html` | Página HTML: Notemusic · Painel |
| `web/flutter_bootstrap.js` | Sem o service worker do Flutter (nesta versão ele só se desregistra). O app usa o próprio `sw.js`, registrado no index.html, para funcionar sem internet e poder ser instalado. |
| `web/google20427e013f6bcf29.html` | _(sem descrição no cabeçalho)_ |
| `web/index.html` | Página HTML: Notemusic: afinador, metrônomo e estudo para instrumentos de corda |
| `web/manifest.json` | Configuração (JSON). |
| `web/sobre.html` | Página HTML: Notemusic: afinador, metrônomo e estudo para instrumentos de corda (grátis, sem cadastro) |
| `web/sw.js` | Service worker do Notemusic: faz o app abrir e funcionar SEM internet depois da primeira visita e cumpre o requisito de "app instalável" dos navegadores. Estratégia: rede primeiro, cache como reserva. Com internet o… |

## Scripts e configuração

| Arquivo | O que faz |
|---|---|
| `vercel.json` | Configuração (JSON). |
| `.vercelignore` | Arquivos que NÃO vão para a Vercel (testes da API), para ficar abaixo do limite de 12 funções do plano Hobby. |
| `pubspec.yaml` | Dependências e metadados do app Flutter. |
| `scripts/gen_vapid.js` | Gera o par de chaves das notificações (Web Push / VAPID). Uso: node scripts/gen_vapid.js Copie os dois valores para as variáveis de ambiente da Vercel (Settings > Environment Variables): VAPID_PUBLIC_KEY = (a chave… |
| `scripts/vercel_build.sh` | Build do Notemusic (Flutter Web) para a Vercel. A Vercel não tem o Flutter, então baixamos uma versão FIXA (a mesma testada localmente) para o build ser reproduzível e não quebrar quando sair uma versão nova. |
| `scripts/gen_docs.js` | Gera as partes da documentação que vêm direto do código (para nunca ficarem velhas): docs/referencia/ARQUIVOS.md mapa de todos os arquivos, com a descrição do cabeçalho de cada um docs/referencia/API.md endpoints e… |
| `scripts/check_docs.js` | Verifica se a documentação continua em dia com o código. Falha (código 1) se: 1. a referência gerada (docs/referencia) estiver desatualizada; 2. algum link relativo entre os documentos estiver quebrado; 3. um módulo… |

Total: **285** arquivos mapeados.
