import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/coach_ai.dart' show kApiBase;

import '../platform/web_push.dart' show webDeviceProbe, webPushPermission, webPushStandalone, webPushSupported, webUserAgent;
import 'package:afina_core/afina_core.dart';

/// Estatísticas ANÔNIMAS de uso (para o painel do administrador). Manda um aviso ao abrir o app
/// e uma batida a cada ~5 minutos enquanto ele está à frente. Vai só: um código aleatório do
/// aparelho (que NÃO é o código de professor/aluno), o tipo de aparelho/navegador e sistema, a faixa de tela, idioma, tema, toque, estado do microfone e das
/// notificações (só categorias), a versão do app
/// e quais abas foram abertas. Nunca áudio, nome, localização ou o que a pessoa toca.
/// Pode ser desligado em Configurações. Falhas são silenciosas: nunca atrapalham o app.
class StatsService {
  StatsService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  String _id = '';
  String _origin = ''; // de onde veio o primeiro acesso (marca ?o= do link, ex.: yt, ig, zap); vazio = direto
  bool enabled = true;
  String _dimsDay = ''; // dia (AAAA-MM-DD) em que a plataforma/versão foi enviada
  String _tabsDay = '';
  final Set<String> _tabsSent = {};
  final Set<String> _tabsPending = {};
  DateTime? lastOpen;

  /// Estado do microfone ("sim", "nao" ou "nd"); o AppState informa.
  String Function()? micProbe;

  /// Características do aparelho em categorias curtas (nada identifica a pessoa):
  /// sistema e versão, faixa de tela, idioma, tema, toque, microfone e notificações.
  Map<String, String> deviceExtras() {
    if (!kIsWeb) return {'mic': micProbe?.call() ?? 'nd'};
    final p = webDeviceProbe();
    return {
      'os': osVersionTag(webUserAgent()),
      'sc': screenTag(p.width),
      'lg': langTag(p.lang),
      'th': p.dark ? 'escuro' : 'claro',
      'tc': yesNoTag(p.touch),
      'mic': micProbe?.call() ?? 'nd',
      'nt': notifTag(webPushSupported(), webPushPermission()),
      'tz': tzTag(DateTime.now().timeZoneOffset.inMinutes),
      'mem': memTag(p.mem),
      'cpu': cpuTag(p.cpu),
      'net': netTag(p.net),
      'dpr': dprTag(p.dpr),
    };
  }

  Uri? _endpoint() {
    if (kApiBase.isNotEmpty) return Uri.parse('$kApiBase/api/stats');
    if (kIsWeb) {
      final h = Uri.base.host;
      if (h == 'localhost' || h == '127.0.0.1' || h.isEmpty) return null; // teste local não suja os números
      return Uri.base.resolve('/api/stats');
    }
    return null;
  }

  String _newId() {
    final r = math.Random.secure();
    const a = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(24, (_) => a[r.nextInt(a.length)]).join();
  }

  void load(SharedPreferences p) {
    enabled = p.getBool('stats_on') ?? true;
    _id = p.getString('stats_id') ?? '';
    if (_id.length < 16) {
      _id = _newId();
      p.setString('stats_id', _id);
    }
    _origin = p.getString('stats_origin') ?? '';
    if (_origin.isEmpty && kIsWeb) {
      // Marca do link (ex.: ?o=yt): só letras minúsculas e números, até 8; vale o PRIMEIRO acesso.
      final o = (Uri.base.queryParameters['o'] ?? '').toLowerCase();
      if (RegExp(r'^[a-z0-9]{1,8}$').hasMatch(o)) {
        _origin = o;
        p.setString('stats_origin', o);
      }
    }
    _dimsDay = p.getString('stats_dims_day') ?? '';
    final t = p.getString('stats_tabs') ?? '';
    final parts = t.split('|');
    if (parts.length == 2) {
      _tabsDay = parts[0];
      _tabsSent.addAll(parts[1].split(',').where((x) => x.isNotEmpty));
    }
  }

  void setEnabled(bool v, SharedPreferences? p) {
    enabled = v;
    p?.setBool('stats_on', v);
  }

  static String _today() {
    final n = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// "android-chrome", "ios-safari", "windows-edge"… (ou "android-app" no app nativo).
  static String platformTag() {
    if (!kIsWeb) {
      return switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android-app',
        TargetPlatform.iOS => 'ios-app',
        TargetPlatform.windows => 'windows-app',
        TargetPlatform.macOS => 'mac-app',
        TargetPlatform.linux => 'linux-app',
        _ => 'outro-app',
      };
    }
    final ua = webUserAgent();
    final os = RegExp('Android').hasMatch(ua)
        ? 'android'
        : RegExp('iPhone|iPad|iPod').hasMatch(ua)
            ? 'ios'
            : RegExp('Windows').hasMatch(ua)
                ? 'windows'
                : RegExp('Mac OS X|Macintosh').hasMatch(ua)
                    ? 'mac'
                    : RegExp('Linux|X11').hasMatch(ua)
                        ? 'linux'
                        : 'outro';
    final br = RegExp('SamsungBrowser').hasMatch(ua)
        ? 'samsung'
        : RegExp('Edg/|EdgA/|EdgiOS/').hasMatch(ua)
            ? 'edge'
            : RegExp('Firefox|FxiOS').hasMatch(ua)
                ? 'firefox'
                : RegExp('Chrome|CriOS').hasMatch(ua)
                    ? 'chrome'
                    : RegExp('Safari').hasMatch(ua)
                        ? 'safari'
                        : 'outro';
    return '$os-$br';
  }

  static String installTag() => !kIsWeb ? 'app' : (webPushStandalone() ? 'pwa' : 'browser');

  /// Código aleatório deste aparelho (o mesmo das estatísticas; NÃO é o código de perfil).
  String get deviceId => _id;

  static String versionTag() {
    const b = String.fromEnvironment('BUILD_ID');
    if (b.isEmpty || b == 'local') return 'dev';
    return b.length > 7 ? b.substring(0, 7) : b;
  }

  /// Uma aba (ou tela) foi aberta: vai na próxima batida (só uma vez por dia por aba).
  void markTab(String name, SharedPreferences? p) {
    final day = _today();
    if (_tabsDay != day) {
      _tabsDay = day;
      _tabsSent.clear();
    }
    if (_tabsSent.contains(name)) return;
    _tabsPending.add(name);
  }

  Future<void> _post(Map<String, dynamic> body) async {
    final ep = _endpoint();
    if (ep == null || !enabled) return;
    try {
      await _http
          .post(ep, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 8));
    } catch (_) {/* sem internet: tudo bem, é só estatística */}
  }

  List<String> _takeTabs(SharedPreferences? p) {
    final t = _tabsPending.toList();
    _tabsPending.clear();
    _tabsSent.addAll(t);
    if (t.isNotEmpty) p?.setString('stats_tabs', '$_tabsDay|${_tabsSent.join(',')}');
    return t;
  }

  /// Ao abrir o app (ou voltar depois de um tempo): conta o acesso. Plataforma e versão vão só
  /// uma vez por dia.
  Future<void> open(SharedPreferences? p) async {
    if (!enabled || _id.length < 16) return;
    lastOpen = DateTime.now();
    final day = _today();
    final body = <String, dynamic>{'t': 'open', 'id': _id};
    if (_dimsDay != day) {
      body['d'] = {'pl': platformTag(), 'in': installTag(), 'v': versionTag(), if (_origin.isNotEmpty) 'o': _origin, 'x': deviceExtras()};
      _dimsDay = day;
      p?.setString('stats_dims_day', day);
    }
    final tabs = _takeTabs(p);
    if (tabs.isNotEmpty) body['tabs'] = tabs;
    await _post(body);
  }

  /// A cada ~5 min com o app à frente: "estou online" (e as abas novas do dia).
  Future<void> beat(SharedPreferences? p) async {
    if (!enabled || _id.length < 16) return;
    final body = <String, dynamic>{'t': 'beat', 'id': _id};
    final tabs = _takeTabs(p);
    if (tabs.isNotEmpty) body['tabs'] = tabs;
    await _post(body);
  }

  void dispose() => _http.close();
}
