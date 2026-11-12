/// Erros do app: um catálogo único de códigos e textos em português, a classificação de qualquer
/// exceção num [AppError], a higienização dos detalhes técnicos (nunca saem nomes, códigos de
/// perfil, e-mails nem segredos) e o histórico dos últimos problemas. Dart puro e testável.
library;

import 'dart:async';
import 'dart:convert';
import 'i18n.dart';

/// Quão sério é o problema para quem usa o app.
enum ErrorSeverity {
  /// O app (ou um pedaço grande dele) não consegue continuar: tela cheia.
  critical,

  /// Uma ação falhou; o resto do app segue: aviso com "Tentar de novo".
  action,

  /// Só informa (ex.: sem internet): o app continua funcionando no aparelho.
  info,
}

/// Uma entrada do catálogo: o que a pessoa lê e o que pode fazer.
class ErrorSpec {
  final String code;
  final ErrorSeverity severity;
  final String title;
  final String message;

  /// Texto do botão principal ("Tentar de novo"…).
  final String action;
  const ErrorSpec(this.code, this.severity, this.title, this.message, this.action);
}

/// Catálogo único: todo código tem título, frase e ação. Para criar um erro novo, é aqui.
final Map<String, ErrorSpec> kErrorCatalog = {
  'NET-01': ErrorSpec('NET-01', ErrorSeverity.info, tr('Sem internet'),
      tr('Sem conexão agora. O que você fez fica guardado e é enviado quando a internet voltar.'), tr('Tentar de novo')),
  'NET-02': ErrorSpec('NET-02', ErrorSeverity.info, tr('Servidor indisponível'),
      tr('O servidor não respondeu. Tudo continua funcionando neste aparelho; tente de novo daqui a pouco.'), tr('Tentar de novo')),
  'NET-03': ErrorSpec('NET-03', ErrorSeverity.action, tr('Muitos pedidos'),
      tr('Foram muitos pedidos em pouco tempo. Aguarde um instante e tente de novo.'), tr('Tentar de novo')),
  'API-04': ErrorSpec('API-04', ErrorSeverity.action, tr('Pedido recusado'),
      tr('O servidor não aceitou este pedido. Confira os dados e tente de novo.'), tr('Tentar de novo')),
  'API-05': ErrorSpec('API-05', ErrorSeverity.action, tr('Erro no servidor'),
      tr('O servidor teve um problema ao responder. Tente de novo em instantes.'), tr('Tentar de novo')),
  'DATA-01': ErrorSpec('DATA-01', ErrorSeverity.action, tr('Dados inválidos'),
      tr('Os dados recebidos não estão no formato esperado. Nada foi alterado.'), tr('Voltar')),
  'STO-01': ErrorSpec('STO-01', ErrorSeverity.action, tr('Armazenamento'),
      tr('Não foi possível guardar neste aparelho. Verifique o espaço livre e tente de novo.'), tr('Tentar de novo')),
  'AUD-01': ErrorSpec('AUD-01', ErrorSeverity.action, tr('Áudio'),
      tr('O áudio não pôde ser usado agora. Confira o microfone e as permissões do aparelho.'), tr('Tentar de novo')),
  'UI-01': ErrorSpec('UI-01', ErrorSeverity.action, tr('Bloco não carregou'),
      tr('Uma parte desta tela não carregou. O resto continua funcionando.'), tr('Tentar de novo')),
  'APP-00': ErrorSpec('APP-00', ErrorSeverity.action, tr('Algo não funcionou'),
      tr('Houve um erro inesperado. Você pode tentar de novo; se repetir, envie o relatório.'), tr('Tentar de novo')),
  'APP-99': ErrorSpec('APP-99', ErrorSeverity.critical, tr('O app não conseguiu abrir'),
      tr('Algo impediu o app de iniciar. Seus dados continuam guardados neste aparelho.'), tr('Tentar de novo')),
};

/// Um problema registrado, já classificado e sem dados pessoais.
class AppError {
  /// Código do catálogo (ex.: `NET-01`).
  final String code;
  final ErrorSeverity severity;

  /// Onde aconteceu, em palavras (ex.: `Agenda do professor › Marcar aula`). Vazio se não se sabe.
  final String where;

  /// Detalhe técnico higienizado (tipo e mensagem da exceção, primeiros quadros da pilha).
  final String detail;
  final int atMs;

  const AppError({
    required this.code,
    required this.severity,
    this.where = '',
    this.detail = '',
    required this.atMs,
  });

  ErrorSpec get spec => kErrorCatalog[code] ?? kErrorCatalog['APP-00']!;
  String get title => spec.title;
  String get message => spec.message;
  String get action => spec.action;

  /// Código curto para a pessoa citar ao pedir ajuda (`E-7K2F`): o mesmo problema dá sempre o mesmo.
  String get shortId => errorShortId(code, detail);

  Map<String, dynamic> toJson() => {
        'c': code,
        's': severity.name,
        if (where.isNotEmpty) 'w': where,
        if (detail.isNotEmpty) 'd': detail,
        't': atMs,
      };

  static AppError? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final code = m['c'] as String;
      final sev = ErrorSeverity.values.where((e) => e.name == m['s']).firstOrNull ?? ErrorSeverity.action;
      return AppError(
        code: kErrorCatalog.containsKey(code) ? code : 'APP-00',
        severity: sev,
        where: sanitizeDetail(m['w'] as String?, max: 120),
        detail: sanitizeDetail(m['d'] as String?),
        atMs: ((m['t'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
      );
    } catch (_) {
      return null;
    }
  }
}

const int kMaxErrorDetail = 600;

final _shareCode = RegExp(r'\b[23456789A-HJ-NP-Za-hj-np-z]{4}-[23456789A-HJ-NP-Za-hj-np-z]{4}\b');
final _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
final _hexSecret = RegExp(r'\b[0-9a-fA-F]{24,}\b');
final _url = RegExp(r'https?://[^\s)]+');
final _longDigits = RegExp(r'\b\d{6,}\b');

/// Tira do texto tudo o que identifica alguém ou dá acesso: códigos de perfil (XXXX-XXXX), e-mails,
/// segredos (sequências longas em hexadecimal), endereços (ficam só o domínio) e números longos.
String sanitizeDetail(String? s, {int max = kMaxErrorDetail}) {
  if (s == null || s.isEmpty) return '';
  var t = s.replaceAll('\r', '');
  t = t.replaceAllMapped(_url, (m) {
    final host = Uri.tryParse(m.group(0)!)?.host ?? '';
    return host.isEmpty ? '[endereço]' : 'https://$host/…';
  });
  t = t
      .replaceAll(_email, '[e-mail]')
      .replaceAll(_hexSecret, '[segredo]')
      .replaceAll(_shareCode, '[código]')
      .replaceAll(_longDigits, '[número]');
  // controle e caracteres invisíveis
  t = t.replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]'), '');
  t = t.trim();
  final runes = t.runes.toList();
  return runes.length <= max ? t : String.fromCharCodes(runes.sublist(0, max)).trimRight();
}

/// Primeiros [frames] quadros da pilha, sem caminhos do computador de quem desenvolve.
String shortStack(StackTrace? st, {int frames = 6}) {
  if (st == null) return '';
  final lines = st.toString().split('\n').where((l) => l.trim().isNotEmpty).take(frames);
  return lines
      .map((l) => l.replaceAll(RegExp(r'[A-Za-z]:\\[^\s)]*|/(?:home|Users)/[^\s)]*'), '[caminho]').trim())
      .join('\n');
}

/// Código curto estável para citar: `E-` + 4 símbolos de um hash do código e do detalhe.
String errorShortId(String code, String detail) {
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  var h = 0x811C9DC5; // FNV-1a
  for (final b in utf8.encode('$code|${_firstLine(detail)}')) {
    h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
  }
  final out = StringBuffer('E-');
  for (var i = 0; i < 4; i++) {
    out.write(alphabet[h % 32]);
    h ~/= 32;
  }
  return out.toString();
}

String _firstLine(String s) => s.split('\n').first;

/// Código do catálogo para um status HTTP.
String errorCodeForStatus(int status) {
  if (status == 429) return 'NET-03';
  if (status == 503 || status == 502 || status == 504 || status == 404) return 'NET-02';
  if (status >= 500) return 'API-05';
  if (status >= 400) return 'API-04';
  return 'APP-00';
}

/// Transforma qualquer exceção num [AppError] do catálogo. Reconhece pelo NOME do tipo para não
/// depender de `dart:io` (que não existe no navegador).
AppError classifyError(Object error, {StackTrace? stack, String where = '', int? nowMs}) {
  final at = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final type = error.runtimeType.toString();
  final text = error.toString();
  String code;
  if (error is TimeoutException) {
    code = 'NET-01';
  } else if (type.contains('SocketException') ||
      type.contains('ClientException') ||
      type.contains('XMLHttpRequest') ||
      text.contains('Failed host lookup') ||
      text.contains('Failed to fetch')) {
    code = 'NET-01';
  } else if (error is FormatException || type.contains('TypeError') && text.contains('is not a subtype')) {
    code = 'DATA-01';
  } else if (type.contains('PlatformException') && (text.contains('microphone') || text.contains('audio') || text.contains('Audio'))) {
    code = 'AUD-01';
  } else if (text.contains('QuotaExceeded') || text.contains('DOMException') && text.contains('storage')) {
    code = 'STO-01';
  } else {
    code = 'APP-00';
  }
  final spec = kErrorCatalog[code]!;
  final detail = sanitizeDetail([
    type,
    if (text.isNotEmpty && text != type) text.split('\n').first,
    shortStack(stack),
  ].join('\n'));
  return AppError(code: code, severity: spec.severity, where: sanitizeDetail(where, max: 120), detail: detail, atMs: at);
}

/// Histórico dos últimos problemas (mais novo primeiro). O mesmo problema em sequência vira uma
/// linha só, com a contagem.
class ErrorLog {
  static const int kMax = 20;
  final List<AppError> items = [];
  final Map<String, int> _repeats = {};

  /// Quantas vezes o problema [e] já aconteceu (mesmo código curto).
  int repeatsOf(AppError e) => _repeats[e.shortId] ?? 1;

  /// Registra [e]. Devolve true se é um problema NOVO (diferente do último), false se é repetição.
  bool add(AppError e) {
    final isRepeat = items.isNotEmpty && items.first.shortId == e.shortId;
    _repeats[e.shortId] = (_repeats[e.shortId] ?? 0) + 1;
    if (isRepeat) {
      items[0] = e;
    } else {
      items.insert(0, e);
      if (items.length > kMax) items.removeRange(kMax, items.length);
    }
    return !isRepeat;
  }

  void clear() {
    items.clear();
    _repeats.clear();
  }

  String toJsonString() => jsonEncode([for (final e in items) e.toJson()]);

  static ErrorLog fromJsonString(String? raw) {
    final log = ErrorLog();
    if (raw == null || raw.isEmpty) return log;
    try {
      for (final x in (jsonDecode(raw) as List).take(kMax)) {
        final e = AppError.tryFrom(x);
        if (e != null) log.items.add(e);
      }
    } catch (_) {
      // histórico corrompido: começa vazio
    }
    return log;
  }

  /// Texto para a pessoa copiar e mandar (sem dados pessoais).
  String report({String appVersion = ''}) {
    final b = StringBuffer(tr('Relatório de problemas do Notemusic'));
    if (appVersion.isNotEmpty) b.write(' · $appVersion');
    for (final e in items) {
      b
        ..write('\n\n[${e.shortId}] ${e.code} · ${e.title}')
        ..write(e.where.isEmpty ? '' : tr('\nOnde: {0}', [e.where]))
        ..write(tr('\nQuando: {0}', [DateTime.fromMillisecondsSinceEpoch(e.atMs).toIso8601String()]))
        ..write(e.detail.isEmpty ? '' : '\n${e.detail}');
    }
    return b.toString();
  }
}
