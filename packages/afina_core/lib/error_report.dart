/// Montagem do relatório de erro que o app envia ao servidor: trilha de telas (breadcrumbs),
/// ambiente (versão, aparelho), modo de envio e freio contra repetição. Dart puro e testável.
/// Nada de conteúdo pessoal: só nomes de telas e ações, e o detalhe já higienizado.
library;

import 'errors.dart';
import 'i18n.dart';

/// Quando o app envia sozinho um relatório de erro.
enum ReportMode {
  /// Só erros graves (padrão).
  critical,

  /// Todos os erros inesperados (exceto avisos de conexão).
  all,

  /// Nunca sozinho (a pessoa ainda pode tocar em "Enviar relatório").
  off,
}

String reportModeLabel(ReportMode m) => switch (m) {
      ReportMode.critical => tr('Só os graves'),
      ReportMode.all => tr('Todos os erros'),
      ReportMode.off => tr('Nunca'),
    };

/// O app deve enviar este erro sozinho, neste modo? (Envio manual não passa por aqui.)
bool shouldAutoSend(ReportMode mode, ErrorSeverity severity) => switch (mode) {
      ReportMode.off => false,
      ReportMode.critical => severity == ErrorSeverity.critical,
      ReportMode.all => severity != ErrorSeverity.info,
    };

final _crumbOk = RegExp(r'^[\p{L}\p{N} ›._:-]{1,40}$', unicode: true);

/// Os últimos passos da pessoa no app (só nomes fixos de telas e ações; nunca conteúdo).
class Breadcrumbs {
  static const int kMax = 10;
  final List<String> items = [];

  /// Anota um passo. Ignora o que não for um nome simples e o que repete o passo anterior.
  void add(String step) {
    final s = step.trim();
    if (!_crumbOk.hasMatch(s)) return;
    if (items.isNotEmpty && items.last == s) return;
    items.add(s);
    if (items.length > kMax) items.removeAt(0);
  }

  void clear() => items.clear();
}

/// Onde e como o app está rodando (para o servidor agrupar e filtrar).
class ReportEnv {
  /// Código aleatório do aparelho (o mesmo das estatísticas anônimas; não é o código de perfil).
  final String deviceId;

  /// Versão do app (início do código da versão publicada) ou `dev`.
  final String build;

  /// `android-chrome`, `ios-safari`, `windows-edge`, `android-app`…
  final String platform;

  /// `app`, `pwa` ou `browser`.
  final String install;

  /// Estado do vínculo online (`online`, `offline`, `off`…).
  final String link;

  /// Visão do Meu espaço: `student`, `teacher` ou vazio.
  final String view;
  const ReportEnv({
    required this.deviceId,
    this.build = 'dev',
    this.platform = 'outro',
    this.install = 'browser',
    this.link = '',
    this.view = '',
  });
}

/// O pacote que vai ao servidor (o servidor higieniza e valida de novo).
Map<String, dynamic> buildErrorReport(AppError e, ReportEnv env, List<String> crumbs) => {
      'id': env.deviceId,
      'c': e.code,
      's': e.severity.name,
      'w': sanitizeDetail(e.where, max: 120),
      'd': sanitizeDetail(e.detail),
      'v': env.build,
      'pl': env.platform,
      'in': env.install,
      if (env.link.isNotEmpty) 'lk': env.link,
      if (env.view.isNotEmpty) 'vw': env.view,
      'bc': [for (final c in crumbs.take(Breadcrumbs.kMax)) c],
    };

/// Freio do envio automático: o mesmo problema no máximo uma vez a cada [window] e um teto por
/// sessão do app, para um erro em repetição nunca virar uma enxurrada de pedidos.
class ReportGate {
  final Duration window;
  final int maxPerSession;
  final Map<String, DateTime> _last = {};
  int _sent = 0;
  ReportGate({this.window = const Duration(minutes: 10), this.maxPerSession = 20});

  /// Pode enviar [shortId] agora? Se sim, já conta como enviado.
  bool allow(String shortId, DateTime now) {
    if (_sent >= maxPerSession) return false;
    final last = _last[shortId];
    if (last != null && now.difference(last) < window) return false;
    _last[shortId] = now;
    _sent++;
    return true;
  }
}
