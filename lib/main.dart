import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

import 'app_state.dart';
import 'ui/app_logo.dart';
import 'ui/status_strip.dart';
import 'ui/teacher_page.dart' show handleIncomingStudentCode;
import 'ui/grid_page.dart';
import 'ui/install_banner.dart';
import 'ui/profile_page.dart' show ProfilePage, handleIncomingTeacherCode;
import 'ui/settings_page.dart';
import 'ui/share_sheet.dart';
import 'ui/metronome_page.dart';
import 'ui/study_page.dart';
import 'ui/theme.dart';
import 'ui/toast.dart';
import 'ui/tuner_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.load();
  runApp(AfinaApp(app: app));
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
            builder: (context, child) =>
                KeyedSubtree(key: ValueKey(dark), child: child!),
            home: HomeShell(app: widget.app),
          ),
        );
      },
    );
  }
}

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
  }

  @override
  void dispose() {
    widget.app.goTab = null;
    super.dispose();
  }

  /// Abas já abertas. As outras só são criadas na primeira visita, o que acelera
  /// a abertura do app e evita construir telas que talvez nunca sejam usadas.
  final Set<int> _visited = {0};

  static const _titles = ['Afinador', 'Metrônomo', 'Grade', 'Meu espaço'];

  static const _tabNames = ['tuner', 'metronome', 'grid', 'study'];

  void _go(int i) {
    widget.app.markTab(_tabNames[i]);
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  /// Botão voltar na tela principal: de outra aba, volta ao Afinador; no
  /// Afinador, pergunta antes de sair do app.
  Future<void> _onBack() async {
    if (_index != 0) {
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

  Widget _page(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    final app = widget.app;
    final active = i == _index;
    final page = switch (i) {
      0 => TunerPage(app: app, active: active),
      1 => MetronomePage(app: app, active: active),
      2 => GridPage(app: app, active: active),
      _ => StudyPage(app: app, active: active),
    };
    // Aba escondida: sem animações rodando e sem repintar.
    return TickerMode(enabled: active, child: page);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
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
              Text(_titles[_index]),
            ],
          ),
          actions: [
            // Só este botão reage à troca de tema, não a barra inteira.
            ValueListenableBuilder<ThemeMode>(
              valueListenable: app.themeNotifier,
              builder: (context, mode, _) {
                final (icon, tip) = switch (mode) {
                  ThemeMode.system => (
                    Icons.brightness_auto,
                    'Tema: automático (toque para claro)',
                  ),
                  ThemeMode.light => (
                    Icons.light_mode,
                    'Tema: claro (toque para escuro)',
                  ),
                  ThemeMode.dark => (
                    Icons.dark_mode,
                    'Tema: escuro (toque para automático)',
                  ),
                };
                return IconButton(
                  tooltip: tip,
                  icon: Icon(icon),
                  onPressed: app.cycleTheme,
                );
              },
            ),
            IconButton(
              tooltip: 'Compartilhar',
              icon: const Icon(Icons.ios_share),
              onPressed: () => showShareSheet(context),
            ),
            // Atalho direto para o perfil (código, chave de recuperação e professor).
            ListenableBuilder(
              listenable: app,
              builder: (context, _) => IconButton(
                tooltip: 'Meu perfil',
                icon: Badge(
                  smallSize: 8,
                  label: app.unseenNotices > 0 ? Text('${app.unseenNotices}') : null,
                  isLabelVisible: app.unseenNotices > 0 || app.profile.recoveryShownAt == null,
                  backgroundColor: AppColors.sharp,
                  child: Icon(app.teacherMode ? Icons.school_outlined : Icons.account_circle_outlined),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ProfilePage(app: app)),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Configurações',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) {
                  app.markTab('settings');
                  return SettingsPage(app: app);
                }),
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
              StatusStrip(app: app, onPomodoro: () => _go(3)),
              // "Instale o Notemusic no celular": só no navegador, enquanto não instalou.
              InstallBanner(app: app),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [for (var i = 0; i < 4; i++) _page(i)],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
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
            NavigationDestination(icon: Icon(Icons.insights), label: 'Meu espaço'),
          ],
        ),
      ),
    );
  }
}
