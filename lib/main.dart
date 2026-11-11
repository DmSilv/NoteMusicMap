import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

import 'app_state.dart';
import 'stats/error_service.dart';
import 'stats/stats_service.dart';
import 'ui/app_logo.dart';
import 'ui/hello_bar.dart';
import 'ui/link_bar.dart';
import 'ui/error_ui.dart';
import 'ui/status_strip.dart';
import 'ui/teacher_page.dart' show handleIncomingStudentCode;
import 'ui/grid_page.dart';
import 'platform/web_install.dart' show webOnInstallEvents;
import 'ui/suggestions.dart';
import 'ui/notifications_sheet.dart';
import 'ui/profile_page.dart' show ProfilePage, handleIncomingTeacherCode;
import 'ui/metronome_page.dart';
import 'ui/study_page.dart';
import 'ui/theme.dart';
import 'ui/toast.dart';
import 'ui/tuner_page.dart';

AppState? _app;

/// Abre o app. Se algo falhar ao iniciar, mostra a tela de erro (com "Tentar de novo") em vez de
/// ficar em branco. Erros inesperados depois disso são classificados, guardados e avisados.
Future<void> _start() async {
  final app = _app ??= AppState();
  try {
    await app.load();
  } catch (e, st) {
    final err = classifyError(e, stack: st, where: 'Início do app');
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
      _app?.reportError(details.exception, details.stack, where: 'Interface');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _app?.reportError(error, stack);
      return true;
    };
    // Bloco que quebra ao desenhar: cartão amigável com código, no lugar da tela cinza/vermelha.
    if (!kDebugMode) {
      ErrorWidget.builder = (details) {
        final id = classifyError(details.exception, stack: details.stack, where: 'Interface').shortId;
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

  /// Boas-vindas com os acessos de que o app precisa (só na primeira abertura).
  Future<void> _onboarding() async {
    final ctx = _navKey.currentContext;
    if (ctx == null || !mounted) return;
    Widget item(IconData i, String t, String d) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(d, style: const TextStyle(fontSize: 13, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Vamos deixar tudo pronto'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: AppLogo(size: 56)),
              const SizedBox(height: 14),
              const Text('O Notemusic usa:'),
              item(
                Icons.mic,
                'Microfone',
                'Para ouvir seu instrumento. O som é analisado no aparelho e nunca é gravado nem enviado.',
              ),
              item(
                Icons.vibration,
                'Vibração',
                'Na batida do metrônomo, no fim do timer e nas notas das escalas. Você pode desligar depois.',
              ),
              item(
                Icons.cloud_outlined,
                'Internet (opcional)',
                'Só se você pedir a análise por IA. O resto funciona sem internet.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Permitir'),
          ),
        ],
      ),
    );
    widget.app.markOnboarded();
    if (ok == true) await widget.app.requestAllPermissions();
  }

  /// Explica para que o microfone é usado antes do primeiro pedido do sistema.
  Future<bool> _micRationale() async {
    final ctx = _navKey.currentContext;
    if (ctx == null) return true;
    final r = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Usar o microfone?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: AppLogo(size: 56)),
            SizedBox(height: 16),
            Text(
              'Para dizer se a nota está afinada, o Notemusic precisa ouvir seu instrumento.\n\n'
              'O som é analisado no próprio aparelho e descartado na hora: nada é gravado nem enviado.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Continuar'),
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
    // Primeiro uso: pede de uma vez tudo o que o app precisa.
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
          showToast(context, '${e.title}. Código ${e.shortId}.',
              icon: errorIcon(e.severity), color: errorTint(e.severity), duration: const Duration(seconds: 4));
        })
        ..scheduleFrame();
    };
    // Avisos curtos ao ligar/desligar funções.
    widget.app.onMessage = (msg) {
      if (!mounted) return;
      final micOn = msg.startsWith('Microfone ligado');
      final micOff = msg.startsWith('Microfone desligado');
      // Mostra depois do quadro atual: se o aviso veio de uma troca de tema, as
      // cores do aviso já são as do tema novo.
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (!mounted) return;
          showToast(
            context,
            msg,
            icon: micOn
                ? Icons.mic
                : (micOff ? Icons.mic_off : Icons.info_outline),
            color: micOn
                ? AppColors.inTune
                : (micOff ? AppColors.textDim : null),
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
      listenable: widget.app.themeNotifier,
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
            scaffoldMessengerKey: _messengerKey,
            navigatorKey: _navKey,
            theme: theme,
            darkTheme: theme,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            // A chave recria a árvore ao trocar de tema: as cores do app são
            // lidas de AppColors e precisam ser reavaliadas.
            builder: (context, child) {
              final tree = KeyedSubtree(key: ValueKey(dark), child: child!);
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
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // O hub (Meu espaço) usa isto para levar a outras abas (ex.: Metrônomo).
    widget.app.goTab = _go;
    // O navegador libera a instalação um pouco depois de abrir a página: atualiza o sino.
    webOnInstallEvents(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.app.goTab = null;
    super.dispose();
  }

  /// Abas já abertas. As outras só são criadas na primeira visita, o que acelera
  /// a abertura do app e evita construir telas que talvez nunca sejam usadas.
  final Set<int> _visited = {0};

  static const _titles = ['Afinador', 'Metrônomo', 'Grade', 'Escalas', 'Meu espaço'];

  static const _tabNames = ['tuner', 'metronome', 'grid', 'scales', 'study'];

  static const _icons = [Icons.tune, Icons.timer_outlined, Icons.grid_view_rounded, Icons.queue_music, Icons.calendar_month_rounded];

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

  /// Botão voltar na tela principal: de outra aba, volta ao Afinador; no
  /// Afinador, pergunta antes de sair do app.
  Future<void> _onBack() async {
    if (_index != 0 && !isSplitLayout(MediaQuery.sizeOf(context))) {
      _go(0);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sair do Notemusic?'),
        content: const Text(
          'Se estiver tocando ou estudando, o app para de ouvir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Ficar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (leave == true) SystemNavigator.pop();
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
          titleSpacing: 14,
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
                tooltip: 'Avisos',
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
                tooltip: 'Minha conta: perfil, ajustes e compartilhar',
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
              StatusStrip(app: app, hideMic: !split && (_index == 0 || _index == 2 || _index == 3), onPomodoro: () => _go(4)),
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
        bottomNavigationBar: split ? null : NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _go,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.tune), label: 'Afinador'),
            NavigationDestination(
              icon: Icon(Icons.timer_outlined),
              label: 'Metrônomo',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_rounded),
              label: 'Grade',
            ),
            NavigationDestination(icon: Icon(Icons.queue_music), label: 'Escalas'),
            NavigationDestination(icon: Icon(Icons.calendar_month_rounded), label: 'Meu espaço'),
          ],
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
