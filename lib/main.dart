import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

import 'app_state.dart';
import 'stats/error_service.dart';
import 'stats/stats_service.dart';
import 'ui/app_locale.dart';
import 'ui/app_logo.dart';
import 'ui/exit_sheet.dart';
import 'ui/hello_bar.dart';
import 'ui/metro_section.dart';
import 'ui/my_lessons_page.dart' show openMyLessons;
import 'ui/home_tabs.dart';
import 'ui/link_bar.dart';
import 'ui/error_ui.dart';
import 'ui/status_strip.dart';
import 'ui/teacher_page.dart' show handleIncomingStudentCode;
import 'ui/grid_page.dart';
import 'platform/web_install.dart' show webOnInstallEvents;
import 'ui/design_system.dart';
import 'ui/suggestions.dart';
import 'ui/notifications_sheet.dart';
import 'ui/profile_page.dart' show ProfilePage, handleIncomingTeacherCode;
import 'ui/metronome_page.dart';
import 'ui/study_page.dart';
import 'ui/theme.dart';
import 'ui/success_moment.dart';
import 'ui/toast.dart';
import 'ui/welcome_tour.dart';
import 'ui/tuner_page.dart';

AppState? _app;

/// Abre o app. Se algo falhar ao iniciar, mostra a tela de erro (com "Tentar de novo") em vez de
/// ficar em branco. Erros inesperados depois disso são classificados, guardados e avisados.
Future<void> _start() async {
  final app = _app ??= AppState();
  try {
    await app.load();
  } catch (e, st) {
    final err = classifyError(e, stack: st, where: tr('Início do app'));
    final critical = AppError(
        code: 'APP-99', severity: ErrorSeverity.critical, where: err.where, detail: err.detail, atMs: err.atMs);
    // Falha ao abrir é grave: avisa o desenvolvedor sozinho (anônimo, só dados técnicos).
    unawaited(ErrorReportService.send(buildErrorReport(
      critical,
      ReportEnv(
        deviceId: ErrorReportService.tempId(),
        build: StatsService.versionTag(),
        platform: StatsService.platformTag(),
        install: StatsService.installTag(),
      ),
      const [],
    )));
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(dark: true),
      localizationsDelegates: kLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: kAppLocale,
      home: CriticalErrorPage(error: critical, onRetry: _start),
    ));
    return;
  }
  runApp(AfinaApp(app: app));
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      if (kDebugMode) FlutterError.presentError(details);
      _app?.reportError(details.exception, details.stack, where: tr('Interface'));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _app?.reportError(error, stack);
      return true;
    };
    // Bloco que quebra ao desenhar: cartão amigável com código, no lugar da tela cinza/vermelha.
    if (!kDebugMode) {
      ErrorWidget.builder = (details) {
        final id = classifyError(details.exception, stack: details.stack, where: tr('Interface')).shortId;
        return FriendlyErrorWidget(id: id);
      };
    }
    _start();
  }, (error, stack) => _app?.reportError(error, stack));
}

class AfinaApp extends StatefulWidget {
  final AppState app;
  const AfinaApp({super.key, required this.app});

  @override
  State<AfinaApp> createState() => _AfinaAppState();
}

class _AfinaAppState extends State<AfinaApp> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  /// Apresentação do primeiro acesso (só na primeira abertura). Não pede nada: o microfone é
  /// pedido na hora em que a pessoa for ouvir (ver [_micRationale]) e o professor só vira
  /// professor se tocar na porta "Sou professor".
  Future<void> _onboarding() async {
    final ctx = _navKey.currentContext;
    if (ctx == null || !mounted) return;
    final choice = await showWelcomeTour(ctx);
    widget.app.markOnboarded();
    widget.app.trackAct(switch (choice) {
      TourChoice.study => 'door_study',
      TourChoice.hasTeacher => 'door_student',
      TourChoice.teacher => 'door_teacher',
      TourChoice.look => 'door_look',
    });
    unawaited(widget.app.checkVibration());
    switch (choice) {
      case TourChoice.study:
        widget.app.goTab?.call(kTabTuner);
      case TourChoice.hasTeacher:
        widget.app.goTab?.call(kTabStudy); // o Meu espaço já traz "Ler QR do professor"
      case TourChoice.teacher:
        widget.app.goTab?.call(kTabStudy);
        final c = _navKey.currentContext;
        if (c == null || !mounted) return;
        // ignore: use_build_context_synchronously
        if (await requireNickname(c, widget.app, reason: tr('Para ser professor, seus alunos precisam ver o seu nome.'))) {
          widget.app.setTeacherMode(true);
        }
      case TourChoice.look:
        break;
    }
  }

  /// Explica para que o microfone é usado antes do primeiro pedido do sistema.
  Future<bool> _micRationale() async {
    final ctx = _navKey.currentContext;
    if (ctx == null) return true;
    final r = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(tr('Usar o microfone?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: AppLogo(size: 56)),
            SizedBox(height: 16),
            Text(
              tr('Para dizer se a nota está afinada, o Notemusic precisa ouvir seu instrumento.\n\nO som é analisado no próprio aparelho e descartado na hora: nada é gravado nem enviado.'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Agora não')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Continuar')),
          ),
        ],
      ),
    );
    return r == true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.markTab('tuner');
    widget.app.askMicRationale = _micRationale;
    // Primeiro uso: apresentação curta (sem pedir nada).
    if (!widget.app.onboarded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onboarding());
    }
    // Aberto por um QR/link de aluno (?aluno=CÓDIGO): leva ao cadastro já preenchido.
    if (widget.app.incomingStudentCode != null || widget.app.incomingTeacherCode != null) {
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        final ctx = _navKey.currentContext;
        // O contexto vem do navegador do app, lido agora (depois da espera), não guardado antes.
        if (!mounted || ctx == null) return;
        // ignore: use_build_context_synchronously
        handleIncomingStudentCode(ctx, widget.app);
        // ignore: use_build_context_synchronously
        handleIncomingTeacherCode(ctx, widget.app);
      });
    }
    // Aviso de erro: mesmo formato sempre (ícone de alerta, frase e código para citar).
    widget.app.onError = (e) {
      if (!mounted) return;
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (!mounted) return;
          showToast(context, tr('{0}. Código {1}.', [e.title, e.shortId]),
              icon: errorIcon(e.severity), color: errorTint(e.severity), duration: const Duration(seconds: 4));
        })
        ..scheduleFrame();
    };
    // Momento de sucesso: folha que sobe de baixo e some sozinha.
    widget.app.onSuccess = (title, detail) {
      if (!mounted) return;
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          final ctx = _navKey.currentContext;
          if (!mounted || ctx == null) return;
          // ignore: use_build_context_synchronously
          showSuccessMoment(ctx, title, detail: detail);
        })
        ..scheduleFrame();
    };
    // Avisos curtos ao ligar/desligar funções.
    widget.app.onMessage = (msg) {
      if (!mounted) return;
      final micOn = msg.startsWith(tr('Microfone ligado'));
      final micOff = msg.startsWith(tr('Microfone desligado'));
      // Mostra depois do quadro atual: se o aviso veio de uma troca de tema, as
      // cores do aviso já são as do tema novo.
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (!mounted) return;
          showToast(
            context,
            msg,
            // Microfone tem ícone próprio; os demais avisos ganham tipo (sucesso, atenção, informação) pelo texto.
            icon: micOn ? Icons.mic : (micOff ? Icons.mic_off : null),
            color: micOn ? AppColors.inTune : (micOff ? AppColors.textDim : null),
          );
        })
        ..scheduleFrame();
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Ao voltar para o app (reabrir, trocar de aba), confere se um professor adicionou o aluno.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Em segundo plano o app não consulta o servidor (custo e bateria).
    widget.app.setForeground(state == AppLifecycleState.resumed);
  }

  /// Acompanha o claro/escuro do sistema quando o modo é "Automático".
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.app.themeNotifier, widget.app.langNotifier]),
      builder: (context, _) {
        final platformDark =
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
        final dark = switch (widget.app.themeNotifier.value) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system => platformDark,
        };
        final theme = buildTheme(dark: dark);
        return ToastificationWrapper(
          child: MaterialApp(
            title: 'Notemusic',
            debugShowCheckedModeBanner: false,
            localizationsDelegates: kLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            locale: localeFor(widget.app.langNotifier.value),
            scaffoldMessengerKey: _messengerKey,
            navigatorKey: _navKey,
            theme: theme,
            darkTheme: theme,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            // A chave recria a árvore ao trocar de tema: as cores do app são
            // lidas de AppColors e precisam ser reavaliadas.
            builder: (context, child) {
              final tree = KeyedSubtree(key: ValueKey('$dark-${widget.app.langNotifier.value.name}'), child: child!);
              final mq = MediaQuery.of(context);
              // No navegador/tela larga o app não estica: fica numa coluna de
              // largura de celular, centralizada, e as laterais ficam escuras.
              if (mq.size.width <= kMaxAppWidth || isSplitLayout(mq.size)) return tree;
              return ColoredBox(
                color: Color.lerp(AppColors.bg, Colors.black, dark ? 0.45 : 0.08)!,
                child: Center(
                  child: SizedBox(
                    width: kMaxAppWidth,
                    child: MediaQuery(
                      data: mq.copyWith(size: Size(kMaxAppWidth, mq.size.height)),
                      child: ClipRect(child: tree),
                    ),
                  ),
                ),
              );
            },
            home: HomeShell(app: widget.app),
          ),
        );
      },
    );
  }
}

/// Largura máxima do app em tela larga (navegador no computador).
const double kMaxAppWidth = 560;

/// Largura a partir da qual, com a tela deitada, o app mostra duas telas lado a lado.
const double kSplitMinWidth = 900;

bool isSplitLayout(Size s) => s.width >= kSplitMinWidth && s.width > s.height;

class HomeShell extends StatefulWidget {
  final AppState app;
  const HomeShell({super.key, required this.app});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = kHomeTab;

  @override
  void initState() {
    super.initState();
    // O hub (Meu espaço) usa isto para levar a outras abas (ex.: Metrônomo).
    widget.app.goTab = _go;
    // Chegou aula nova do professor (ele encerrou a aula): se o aluno está no Meu espaço, um modal leva ao Diário.
    widget.app.onLessonsArrived = _lessonArrived;
    // O navegador libera a instalação um pouco depois de abrir a página: atualiza o sino.
    webOnInstallEvents(() {
      if (mounted) setState(() {});
    });
  }

  void _lessonArrived(List<SharedLesson> fresh) {
    if (!mounted || _index != kHomeTab || fresh.isEmpty) return;
    final onlyTasks = fresh.every((l) => l.tasksOnly);
    showDsSheet(
      context,
      title: onlyTasks ? tr('Tarefas novas') : tr('Aula encerrada'),
      listenable: widget.app,
      children: (c) => [
        Text(newLessonsMessage(fresh), style: const TextStyle(fontSize: Ds.fontBody, height: 1.4)),
        const SizedBox(height: Ds.s20),
        DsPrimaryButton(
          icon: Icons.menu_book_rounded,
          label: tr('Ver o Diário de aula'),
          onPressed: () {
            Navigator.of(c).pop();
            openMyLessons(context, widget.app);
          },
        ),
        const SizedBox(height: Ds.s8),
        Center(child: TextButton(onPressed: () => Navigator.of(c).pop(), child: Text(tr('Depois')))),
      ],
    );
  }

  @override
  void dispose() {
    widget.app.onLessonsArrived = null;
    widget.app.goTab = null;
    super.dispose();
  }

  /// Abas já abertas. As outras só são criadas na primeira visita, o que acelera
  /// a abertura do app e evita construir telas que talvez nunca sejam usadas.
  final Set<int> _visited = {kHomeTab};

  static final _titles = [tr('Afinador'), tr('Metrônomo'), tr('Grade'), tr('Escalas'), tr('Meu espaço')];

  static const _tabNames = ['tuner', 'metronome', 'grid', 'scales', 'study'];

  static const _icons = [Icons.graphic_eq_rounded, Icons.timer_outlined, Icons.grid_view_rounded, Icons.queue_music, Icons.calendar_month_rounded];

  /// Em duas telas: qual lado recebe o próximo atalho (o último que a pessoa tocou).
  bool _focusRight = true;

  void _go(int i) {
    widget.app.markTab(_tabNames[i]);
    if (isSplitLayout(MediaQuery.sizeOf(context))) {
      final a = widget.app;
      if (i != a.splitLeft && i != a.splitRight) {
        if (_focusRight) {
          a.setSplit(a.splitLeft, i);
        } else {
          a.setSplit(i, a.splitRight);
        }
      }
      setState(() => _index = i);
      return;
    }
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  bool _askingExit = false;

  /// Botão voltar na tela principal: de outra aba, volta ao Meu espaço; no
  /// Meu espaço, pergunta antes de sair do app.
  Future<void> _onBack() async {
    if (_index != kHomeTab && !isSplitLayout(MediaQuery.sizeOf(context))) {
      _go(kHomeTab);
      return;
    }
    // Já está perguntando (voltar apertado várias vezes): não empilha outra pergunta.
    if (_askingExit) return;
    _askingExit = true;
    final leave = await confirmExitApp(context);
    _askingExit = false;
    if (leave) SystemNavigator.pop();
  }

  /// Uma tela inteira dentro de um dos lados (as duas ficam ativas ao mesmo tempo).
  Widget _pagePane(int i) {
    final app = widget.app;
    return TickerMode(
      enabled: true,
      child: switch (i) {
        0 => TunerPage(app: app, active: true),
        1 => MetronomePage(app: app, active: true),
        2 => GridPage(app: app, active: true),
        3 => GridPage(app: app, active: true, scalesOnly: true),
        _ => StudyPage(app: app, active: true),
      },
    );
  }

  Widget _paneSelector(bool left, int cur, int other) {
    final a = widget.app;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
          segments: [
            for (var i = 0; i < 5; i++)
              ButtonSegment<int>(
                value: i,
                icon: Icon(_icons[i], size: 18),
                tooltip: _titles[i],
                // Só o lado escolhido mostra o nome (com 5 telas os nomes não cabem em todos).
                label: i == cur ? Text(_titles[i], maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                enabled: i == cur || i != other, // a mesma tela não aparece nos dois lados
              ),
          ],
          selected: {cur},
          onSelectionChanged: (s) {
            final v = s.first;
            if (left) {
              a.setSplit(v, a.splitRight);
            } else {
              a.setSplit(a.splitLeft, v);
            }
            a.markTab(_tabNames[v]);
            setState(() {
              _focusRight = !left;
              _index = v;
            });
          },
        ),
      ),
    );
  }

  Widget _splitBody() {
    final a = widget.app;
    Widget pane(bool left, int cur, int other) => Expanded(
          child: Column(children: [
            _paneSelector(left, cur, other),
            const Divider(height: 1),
            Expanded(child: KeyedSubtree(key: ValueKey('pane${left ? 'L' : 'R'}-$cur'), child: _pagePane(cur))),
          ]),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500),
        child: Row(children: [
          pane(true, a.splitLeft, a.splitRight),
          const VerticalDivider(width: 1),
          pane(false, a.splitRight, a.splitLeft),
        ]),
      ),
    );
  }

  Widget _page(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    final app = widget.app;
    final active = i == _index;
    final page = switch (i) {
      0 => TunerPage(app: app, active: active),
      1 => MetronomePage(app: app, active: active),
      2 => GridPage(app: app, active: active),
      3 => GridPage(app: app, active: active, scalesOnly: true),
      _ => StudyPage(app: app, active: active),
    };
    // Aba escondida: sem animações rodando e sem repintar.
    return TickerMode(enabled: active, child: page);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final split = isSplitLayout(MediaQuery.sizeOf(context));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          // Bordas alinhadas com a margem das telas (16 px) dos dois lados.
          titleSpacing: Ds.screenPad,
          actionsPadding: const EdgeInsets.only(right: 10),
          title: Row(
            children: [
              const AppLogo(size: 30),
              const SizedBox(width: 10),
              Text(split ? 'Notemusic' : _titles[_index]),
            ],
          ),
          actions: [
            // Central de avisos: tudo o que chegou (aulas, tarefas, horários) num só lugar.
            ListenableBuilder(
              listenable: app,
              builder: (context, _) => IconButton(
                tooltip: tr('Avisos'),
                icon: Badge(
                  label: (app.unseenNotices + suggestionCount(app)) > 0 ? Text('${app.unseenNotices + suggestionCount(app)}') : null,
                  isLabelVisible: (app.unseenNotices + suggestionCount(app)) > 0,
                  backgroundColor: AppColors.sharp,
                  child: _BarCircle(
                    fill: AppColors.surface2,
                    child: Icon(Icons.notifications_none_rounded, size: 22, color: AppColors.text),
                  ),
                ),
                onPressed: () => showNotificationsSheet(context, app),
              ),
            ),
            // Atalho direto para o perfil (código, chave de recuperação e professor).
            ListenableBuilder(
              listenable: app,
              builder: (context, _) => IconButton(
                tooltip: tr('Minha conta: perfil, ajustes e compartilhar'),
                icon: Badge(
                  smallSize: 8,
                  isLabelVisible: app.profile.recoveryShownAt == null,
                  backgroundColor: AppColors.sharp,
                  child: _ProfileAvatar(app: app),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ProfilePage(app: app)),
                ),
              ),
            ),
          ],
        ),
        // IndexedStack mantém o estado de cada aba aberta (a grade e o metrônomo
        // continuam). Só a aba visível escuta mudanças e se reconstrói.
        body: SafeArea(
          child: Column(
            children: [
              // Microfone e Pomodoro ativos: faixa própria, longe do título.
              StatusStrip(app: app, hideMic: !split && (_index == 0 || _index == 2 || _index == 3), onPomodoro: () {
                metroSection.value = kMetroSectionStudy; // Pomodoro e relógio abrem a visão de estudo
                _go(kTabMetronome);
              }),
              // Saudação com o apelido (ou convite para preencher), só nas telas principais.
              // Versão nova disponível (faixa fixa, com botão).
              UpdateBar(app: app),
              // Vínculo desligado com gente dependendo dele: avisa que está offline.
              if (split || _index == 0 || _index == 4) LinkOffBar(app: app),
              // Saudação só no Meu espaço; apelido e "instalar" ficam no sino.
              if (split || _index == 4) HelloBar(app: app),
              Expanded(
                child: split
                    ? _splitBody()
                    : IndexedStack(
                        index: _index,
                        children: [for (var i = 0; i < 5; i++) _page(i)],
                      ),
              ),
            ],
          ),
        ),
        // Em duas telas, cada lado tem o seu seletor: a barra de baixo não é necessária.
        // Em telas estreitas (até ~360 px) o rótulo diminui para "Meu espaço" caber numa linha só, em vez de quebrar em duas.
        bottomNavigationBar: split
            ? null
            : NavigationBarTheme(
                data: Theme.of(context).navigationBarTheme.copyWith(
                      labelTextStyle: WidgetStateProperty.all(TextStyle(fontSize: MediaQuery.sizeOf(context).width < 360 ? 10 : 11.5, fontWeight: FontWeight.w600)),
                    ),
                child: NavigationBar(
                  selectedIndex: kTabOrder.indexOf(_index),
                  onDestinationSelected: (k) => _go(kTabOrder[k]),
                  destinations: [
                    for (final t in kTabOrder) NavigationDestination(icon: Icon(_icons[t]), label: _titles[t]),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Círculo de 36 px usado nos ícones da barra de cima.
class _BarCircle extends StatelessWidget {
  final Widget child;
  final Color fill;
  final Color? border;
  const _BarCircle({required this.child, required this.fill, this.border});

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: border == null ? null : Border.all(color: border!, width: 1.5),
        ),
        child: child,
      );
}

/// Perfil na barra de cima: a inicial do nome (ou um ícone) dentro de um círculo na cor de destaque.
class _ProfileAvatar extends StatelessWidget {
  final AppState app;
  const _ProfileAvatar({required this.app});

  @override
  Widget build(BuildContext context) {
    final name = (app.profile.name ?? '').trim();
    return _BarCircle(
      fill: AppColors.accent.withValues(alpha: 0.18),
      border: AppColors.accent.withValues(alpha: 0.7),
      child: name.isEmpty
          ? Icon(app.teacherMode ? Icons.school_rounded : Icons.person_rounded, size: 20, color: AppColors.accent)
          : Text(name.characters.first.toUpperCase(),
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 16)),
    );
  }
}
