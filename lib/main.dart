import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/app_logo.dart';
import 'ui/pomodoro_card.dart';
import 'ui/grid_page.dart';
import 'ui/settings_page.dart';
import 'ui/metronome_page.dart';
import 'ui/study_page.dart';
import 'ui/theme.dart';
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
              'Para dizer se a nota está afinada, o Tom e Tempo precisa ouvir seu instrumento.\n\n'
              'O som é analisado no próprio aparelho e descartado na hora: nada é gravado nem enviado.',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continuar')),
        ],
      ),
    );
    return r == true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.askMicRationale = _micRationale;
    // Avisos curtos ao ligar/desligar funções.
    widget.app.onMessage = (msg) {
      final m = _messengerKey.currentState;
      if (m == null) return;
      m
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 2400),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 84),
        ));
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Acompanha o claro/escuro do sistema quando o modo é "Automático".
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final platformDark = WidgetsBinding
                .instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
        final dark = switch (widget.app.themeMode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system => platformDark,
        };
        final theme = buildTheme(dark: dark);
        return MaterialApp(
          title: 'Tom e Tempo',
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

  static const _titles = ['Afinador', 'Metrônomo', 'Grade', 'Estudo'];

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final (themeIcon, themeTip) = switch (app.themeMode) {
      ThemeMode.system => (Icons.brightness_auto, 'Tema: automático (toque para claro)'),
      ThemeMode.light => (Icons.light_mode, 'Tema: claro (toque para escuro)'),
      ThemeMode.dark => (Icons.dark_mode, 'Tema: escuro (toque para automático)'),
    };
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        title: Row(children: [
          const AppLogo(size: 30),
          const SizedBox(width: 10),
          Text(_titles[_index]),
        ]),
        actions: [
          PomodoroPill(app: app, onTap: () => setState(() => _index = 3)),
          IconButton(
            tooltip: themeTip,
            icon: Icon(themeIcon),
            onPressed: app.cycleTheme,
          ),
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => SettingsPage(app: app)),
            ),
          ),
        ],
      ),
      // IndexedStack mantém cada aba viva (a grade e o metrônomo continuam).
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            TunerPage(app: app),
            MetronomePage(app: app),
            GridPage(app: app),
            StudyPage(app: app),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tune), label: 'Afinador'),
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Metrônomo'),
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Grade'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Estudo'),
        ],
      ),
    );
  }
}
