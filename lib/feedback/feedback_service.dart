import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/coach_ai.dart' show kApiBase;
import 'package:afina_core/afina_core.dart';

/// Nota do app e pesquisa rápida (1 ou 2 perguntas por aparelho).
///
/// - Só envia quando a pessoa toca em "Enviar". Vai a resposta, a versão do app
///   e um código do aparelho que o servidor embaralha. Sem nome, e-mail ou áudio.
/// - A pesquisa aparece de forma automática no máximo 3 vezes por aparelho (o
///   convite pode ser dispensado) e some para sempre depois de respondida.
/// - Sem internet, a resposta fica numa fila e é enviada depois.
class FeedbackService extends ChangeNotifier {
  FeedbackService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  SharedPreferences? _prefs;

  /// Identificador da pesquisa (a resposta da pergunta 1 usa este id).
  static const String surveyId = 'mais_usa';
  static const String improveId = 'melhorar';
  static const int maxSnoozes = 2;
  static const int _maxPending = 20;

  /// Perguntas da pesquisa rápida.
  static final List<String> featureOptions = [
    tr('Afinador'),
    tr('Metrônomo'),
    tr('Grade de notas'),
    tr('Escalas e exercícios'),
    tr('Estudo (timer)'),
  ];

  bool surveyAnswered = false;
  int snoozes = 0;
  DateTime? snoozeUntil;
  DateTime? firstSeen;

  /// Última nota dada (1..5) ou 0.
  int rating = 0;
  List<Map<String, dynamic>> _pending = [];
  bool sending = false;

  Future<void> load(SharedPreferences p) async {
    _prefs = p;
    surveyAnswered = p.getBool('fb_answered') ?? false;
    snoozes = p.getInt('fb_snoozes') ?? 0;
    snoozeUntil = DateTime.tryParse(p.getString('fb_snooze_until') ?? '');
    rating = p.getInt('fb_rating') ?? 0;
    firstSeen = DateTime.tryParse(p.getString('fb_first') ?? '');
    if (firstSeen == null) {
      firstSeen = DateTime.now();
      await p.setString('fb_first', firstSeen!.toIso8601String());
    }
    try {
      final raw = p.getString('fb_pending');
      if (raw != null) {
        _pending = [for (final x in (jsonDecode(raw) as List)) (x as Map).cast<String, dynamic>()];
      }
    } catch (_) {
      _pending = [];
    }
    notifyListeners();
    unawaited(flushPending());
  }

  int get pendingCount => _pending.length;

  /// Hora de convidar para a pesquisa? Depois de alguns exercícios ou de 3 dias de uso.
  bool surveyDue({required int sessions, DateTime? now}) {
    final t = now ?? DateTime.now();
    if (surveyAnswered || snoozes > maxSnoozes) return false;
    if (snoozeUntil != null && t.isBefore(snoozeUntil!)) return false;
    final days = firstSeen == null ? 0 : t.difference(firstSeen!).inDays;
    return sessions >= 2 || days >= 3;
  }

  /// "Agora não": pergunta de novo em 7 dias (no máximo mais 2 vezes).
  Future<void> snooze({DateTime? now}) async {
    snoozes += 1;
    snoozeUntil = (now ?? DateTime.now()).add(const Duration(days: 7));
    await _prefs?.setInt('fb_snoozes', snoozes);
    await _prefs?.setString('fb_snooze_until', snoozeUntil!.toIso8601String());
    notifyListeners();
  }

  // ---------------- envio ----------------
  Uri? _endpoint() {
    if (kApiBase.isNotEmpty) return Uri.parse('$kApiBase/api/feedback');
    if (kIsWeb) return Uri.base.resolve('/api/feedback');
    return null;
  }

  Future<String> _deviceId() async {
    final p = _prefs;
    var id = p?.getString('ai_device');
    if (id == null) {
      final r = math.Random.secure();
      id = List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
      await p?.setString('ai_device', id);
    }
    return id;
  }

  Future<void> _savePending() async {
    await _prefs?.setString('fb_pending', jsonEncode(_pending));
  }

  /// Tenta enviar uma mensagem; true se o servidor aceitou ou recusou de vez
  /// (400/429: não adianta repetir). false = tentar depois.
  Future<bool> _post(Map<String, dynamic> body) async {
    final ep = _endpoint();
    if (ep == null) return false;
    try {
      final r = await _http
          .post(ep,
              headers: {'Content-Type': 'application/json', 'X-Device-Id': await _deviceId()},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) return true;
      return r.statusCode == 400 || r.statusCode == 429;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _base(String kind, String version, String platform) =>
      {'kind': kind, 'version': version, 'platform': platform};

  /// Envia (ou enfileira) as mensagens. Devolve true se todas foram entregues agora.
  Future<bool> _deliver(List<Map<String, dynamic>> items) async {
    sending = true;
    notifyListeners();
    var all = true;
    for (final m in items) {
      if (!await _post(m)) {
        all = false;
        if (_pending.length < _maxPending) _pending.add(m);
      }
    }
    await _savePending();
    sending = false;
    notifyListeners();
    return all;
  }

  Future<void> flushPending() async {
    if (_pending.isEmpty || sending) return;
    final todo = List<Map<String, dynamic>>.from(_pending);
    _pending = [];
    for (final m in todo) {
      if (!await _post(m)) _pending.add(m);
    }
    await _savePending();
    notifyListeners();
  }

  /// Nota de 1 a 5 (com comentário opcional). Pode ser trocada depois.
  Future<bool> sendRating(int stars, String comment, {required String version, required String platform}) async {
    final s = stars.clamp(1, 5);
    rating = s;
    await _prefs?.setInt('fb_rating', s);
    final body = {
      ..._base('rating', version, platform),
      'rating': s,
      if (comment.trim().isNotEmpty) 'comment': comment.trim(),
    };
    return _deliver([body]);
  }

  /// Pesquisa rápida: [feature] (obrigatória) e [improve] (opcional).
  Future<bool> sendSurvey(String feature, String improve, {required String version, required String platform}) async {
    surveyAnswered = true;
    await _prefs?.setBool('fb_answered', true);
    final items = [
      {..._base('survey', version, platform), 'qid': surveyId, 'answer': feature},
      if (improve.trim().isNotEmpty) {..._base('survey', version, platform), 'qid': improveId, 'answer': improve.trim()},
    ];
    return _deliver(items);
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
