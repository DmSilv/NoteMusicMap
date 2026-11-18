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
/// - A pesquisa ativa vem do servidor (GET /api/feedback?survey=1, com cache de CDN): o administrador escolhe quando liberar e retirar.
///   O convite aparece de forma automática no máximo 3 vezes por pesquisa (pode ser dispensado), some depois de respondida
///   e cada aparelho participa de no máximo 3 pesquisas por mês (o servidor também confere).
/// - Cada envio leva um id de participação (pid) e o id da pesquisa (sv), para o painel juntar as respostas.
/// - Sem internet, a resposta fica numa fila e é enviada depois.
class FeedbackService extends ChangeNotifier {
  FeedbackService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  SharedPreferences? _prefs;

  /// O código do perfil de quem responde (o painel do dono mostra de quem é a resposta). Definido pelo app.
  String Function()? profileCode;

  static const int maxSnoozes = 2;
  static const int _maxPending = 20;

  /// A pesquisa ativa agora (a última resposta boa do servidor) ou null.
  SurveyDef? survey;

  /// Respondeu à pesquisa rápida antiga (anterior às pesquisas do painel): não é convidado de novo à versão nova dela.
  bool legacyAnswered = false;
  Set<String> _done = {};
  String _monthKey = '';
  int _monthCount = 0;
  int snoozes = 0;
  DateTime? snoozeUntil;
  DateTime? firstSeen;

  /// Última nota dada (1..5) ou 0.
  int rating = 0;
  List<Map<String, dynamic>> _pending = [];
  bool sending = false;

  Future<void> load(SharedPreferences p) async {
    _prefs = p;
    legacyAnswered = p.getBool('fb_answered') ?? false;
    _done = (p.getStringList('fb_done') ?? const <String>[]).toSet();
    _monthKey = p.getString('fb_mkey') ?? '';
    _monthCount = p.getInt('fb_mcount') ?? 0;
    survey = parseSurvey(jsonEncode({'survey': _tryJson(p.getString('fb_survey'))})).survey;
    if (p.getString('fb_snz_sid') != (survey?.id ?? '')) {
      // Pesquisa nova: o "agora não" da anterior não vale para ela.
      await p.setInt('fb_snoozes', 0);
      await p.remove('fb_snooze_until');
      await p.setString('fb_snz_sid', survey?.id ?? '');
    }
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
    unawaited(syncSurvey());
  }

  static Object? _tryJson(String? raw) {
    try {
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  int get pendingCount => _pending.length;

  static String _monthOf(DateTime t) => '${t.year}${t.month}';

  /// A pesquisa ativa já foi respondida neste aparelho?
  bool get surveyAnswered {
    final s = survey;
    return s != null && (_done.contains(s.id) || (s.key == 'rapida' && legacyAnswered));
  }

  /// Dá para responder agora: há pesquisa ativa, ainda não respondida, e o limite do mês não foi atingido.
  bool canAnswer({DateTime? now}) {
    final s = survey;
    if (s == null || surveyAnswered) return false;
    final t = now ?? DateTime.now();
    return !(_monthKey == _monthOf(t) && _monthCount >= s.monthMax);
  }

  /// Hora de convidar para a pesquisa? Depois de alguns exercícios ou de 3 dias de uso.
  bool surveyDue({required int sessions, DateTime? now}) {
    final t = now ?? DateTime.now();
    if (!canAnswer(now: t) || snoozes > maxSnoozes) return false;
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

  /// Um GET por abertura (a CDN guarda por 5 minutos, então o banco quase não é tocado). Sem rede ou com resposta estranha,
  /// fica a pesquisa que já havia; com resposta boa e sem pesquisa ativa, o convite some.
  Future<void> syncSurvey() async {
    final base = _endpoint();
    if (base == null) return;
    try {
      final r = await _http.get(base.replace(queryParameters: {'survey': '1'})).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final res = parseSurvey(r.body);
      if (!res.ok) return;
      final novo = res.survey;
      if (novo?.id == survey?.id && jsonEncode(novo?.toJson()) == jsonEncode(survey?.toJson())) return;
      survey = novo;
      final p = _prefs;
      if (p != null) {
        if (novo == null) {
          await p.remove('fb_survey');
        } else {
          await p.setString('fb_survey', jsonEncode(novo.toJson()));
        }
        if (p.getString('fb_snz_sid') != (novo?.id ?? '')) {
          snoozes = 0;
          snoozeUntil = null;
          await p.setInt('fb_snoozes', 0);
          await p.remove('fb_snooze_until');
          await p.setString('fb_snz_sid', novo?.id ?? '');
        }
      }
      notifyListeners();
    } catch (_) {
      // sem rede: fica o que já valia
    }
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
              body: jsonEncode({...body, if ((profileCode?.call() ?? '').isNotEmpty) 'profile': profileCode!()}))
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

  /// Uma vez por perfil neste aparelho: diz ao servidor de quem é este aparelho, para as respostas que já foram enviadas
  /// (sem o perfil) também aparecerem no painel com o dono. Não cria resposta nova.
  Future<void> identify({required String version, required String platform}) async {
    final code = profileCode?.call() ?? '';
    if (code.isEmpty || _prefs?.getString('fb_ident') == code) return;
    if (await _post(_base('identify', version, platform))) await _prefs?.setString('fb_ident', code);
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

  String _newPid() {
    final r = math.Random.secure();
    return List.generate(16, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  /// Envia as respostas da pesquisa ativa ([answers]: id da pergunta -> resposta, na língua do painel/português).
  /// Todas as respostas deste envio levam o mesmo `pid`, e o painel mostra como UMA participação.
  Future<bool> sendSurvey(Map<String, String> answers, {required String version, required String platform}) async {
    final s = survey;
    if (s == null) return false;
    final pid = _newPid();
    final now = DateTime.now();
    _done.add(s.id);
    if (_monthKey != _monthOf(now)) {
      _monthKey = _monthOf(now);
      _monthCount = 0;
    }
    _monthCount += 1;
    await _prefs?.setStringList('fb_done', _done.toList());
    await _prefs?.setString('fb_mkey', _monthKey);
    await _prefs?.setInt('fb_mcount', _monthCount);
    final items = [
      for (final q in s.questions)
        if ((answers[q.id] ?? '').trim().isNotEmpty) {..._base('survey', version, platform), 'qid': q.id, 'answer': answers[q.id]!.trim(), 'sv': s.id, 'pid': pid},
    ];
    return _deliver(items);
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
