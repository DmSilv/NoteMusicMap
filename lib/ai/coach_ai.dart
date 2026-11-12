import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:afina_core/afina_core.dart';

/// Endereço base da API. Na web usa o mesmo domínio do app; no celular, defina
/// `--dart-define=API_BASE=https://seu-app.vercel.app`.
const String kApiBase = String.fromEnvironment('API_BASE');

enum AiPhase { idle, sending, queued, done, failed }

/// Análise por IA (Gemini, via função da Vercel) para o modo Treinador.
///
/// Protege o plano gratuito: pede com calma, respeita o intervalo e o limite
/// diário, guarda a última resposta e, se o servidor estiver cheio (429),
/// entra numa FILA local e tenta de novo sozinho com espera crescente.
class CoachAi extends ChangeNotifier {
  CoachAi({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  SharedPreferences? _prefs;

  AiPhase phase = AiPhase.idle;
  String? text;
  String? message; // erro ou aviso para o usuário
  int queuedSeconds = 0; // tempo restante até a próxima tentativa
  int attempt = 0;
  bool consent = false;

  /// Resultado do último pedido de qualquer tipo (relatório do professor etc.).
  String? lastResult;
  String? lastKind;

  /// Quem respondeu ("Gemini", "Claude"...) e a posição na fila, se houver.
  String? provider;
  int? queuePosition;
  String? _ticket; // lugar reservado na fila do servidor

  static const int maxAttempts = 5;
  static const int _clientDailyLimit = 5;
  static const Duration _cooldown = Duration(seconds: 20);
  static const Duration _timeout = Duration(seconds: 58);

  Timer? _tick;
  bool _cancelled = false;
  DateTime? _lastRequest;

  bool get busy => phase == AiPhase.sending || phase == AiPhase.queued;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> load() async {
    final p = await _p;
    consent = p.getBool('ai_consent') ?? false;
    text = p.getString('ai_last_text');
    if (text != null) phase = AiPhase.done;
    notifyListeners();
  }

  Future<void> setConsent(bool v) async {
    consent = v;
    (await _p).setBool('ai_consent', v);
    notifyListeners();
  }

  Future<String> _deviceId() async {
    final p = await _p;
    var id = p.getString('ai_device');
    if (id == null) {
      final r = math.Random.secure();
      id = List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
      await p.setString('ai_device', id);
    }
    return id;
  }

  String get _today => DateTime.now().toIso8601String().substring(0, 10);

  Future<int> usedToday() async {
    final p = await _p;
    return p.getString('ai_day') == _today ? (p.getInt('ai_count') ?? 0) : 0;
  }

  Future<void> _countUse() async {
    final p = await _p;
    final n = await usedToday();
    await p.setString('ai_day', _today);
    await p.setInt('ai_count', n + 1);
  }

  Uri? _endpoint() {
    if (kApiBase.isNotEmpty) return Uri.parse('$kApiBase/api/coach');
    if (kIsWeb) return Uri.base.resolve('/api/coach');
    return null;
  }

  /// Pede a análise. [summary] é o texto só com números (sem áudio).
  Future<void> ask(String summary, {String kind = 'session_summary'}) async {
    if (busy) return;
    final ep = _endpoint();
    if (ep == null) {
      _fail(tr('A IA ainda não está configurada para este aplicativo.'));
      return;
    }
    if (!consent) {
      _fail(tr('Autorize o envio do resumo para usar a IA.'));
      return;
    }
    if (await usedToday() >= _clientDailyLimit) {
      _fail(tr('Você já usou as {0} análises de hoje. Volte amanhã!', [_clientDailyLimit]));
      return;
    }
    final last = _lastRequest;
    if (last != null && DateTime.now().difference(last) < _cooldown) {
      final left = _cooldown.inSeconds - DateTime.now().difference(last).inSeconds;
      _fail(tr('Aguarde {0} s para pedir de novo.', [left]));
      return;
    }

    _cancelled = false;
    attempt = 0;
    message = null;
    _ticket = null;
    queuePosition = null;
    provider = null;
    final id = await _deviceId();

    while (!_cancelled && attempt < maxAttempts) {
      attempt++;
      phase = AiPhase.sending;
      notifyListeners();
      _lastRequest = DateTime.now();
      try {
        final r = await _http
            .post(
              ep,
              headers: {'Content-Type': 'application/json', 'X-Device-Id': id},
              body: jsonEncode({'summary': summary, 'kind': kind, if (_ticket != null) 'ticket': _ticket}),
            )
            .timeout(_timeout);
        final data = _json(r.body);
        if (r.statusCode == 200 && data['text'] is String) {
          lastResult = data['text'] as String;
          lastKind = kind;
          provider = (data['label'] ?? data['provider']) as String?;
          _ticket = null;
          queuePosition = null;
          if (kind == 'session_summary') {
            text = lastResult;
            (await _p).setString('ai_last_text', text!);
          }
          await _countUse();
          phase = AiPhase.done;
          notifyListeners();
          return;
        }
        if (r.statusCode == 429) {
          final why = data['error'];
          if (why == 'user_daily' || why == 'daily_global') {
            _fail(why == 'user_daily'
                ? tr('Você atingiu o limite de hoje. Volte amanhã!')
                : tr('A IA gratuita atingiu o limite do dia. Tente amanhã.'));
            return;
          }
          final ms = (data['retryAfterMs'] as num?)?.toInt() ?? 15000;
          if (why == 'queued') {
            // O servidor guardou o nosso lugar: voltamos na hora marcada, com o bilhete.
            _ticket = data['ticket'] as String?;
            queuePosition = (data['position'] as num?)?.toInt() ?? queuePosition;
          }
          await _waitInQueue(ms, why == 'cooldown');
          continue;
        }
        _fail((data['error'] as String?) ?? tr('A IA não respondeu (erro {0}).', [r.statusCode]));
        return;
      } on TimeoutException {
        await _waitInQueue(8000, false);
      } catch (_) {
        _fail(tr('Sem conexão com a internet. O app continua funcionando normalmente.'));
        return;
      }
    }
    if (!_cancelled) {
      _fail(tr('A IA está muito ocupada agora. Tente de novo em alguns minutos.'));
    }
  }

  Map<String, dynamic> _json(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return const {};
  }

  /// Espera na fila com contagem regressiva (e um pouco de aleatoriedade para
  /// vários aparelhos não voltarem todos no mesmo instante).
  Future<void> _waitInQueue(int ms, bool fast) async {
    // Com lugar reservado na fila não precisa de sorteio; sem ele, sim.
    final jitter = math.Random().nextInt(_ticket != null ? 400 : 2500);
    var remaining = ((ms.clamp(1000, 90000) + jitter) / 1000).ceil();
    phase = AiPhase.queued;
    queuedSeconds = remaining;
    notifyListeners();
    final done = Completer<void>();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      queuedSeconds = remaining;
      notifyListeners();
      if (remaining <= 0 || _cancelled) {
        t.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    await done.future;
  }

  void cancel() {
    _cancelled = true;
    _tick?.cancel();
    phase = text != null ? AiPhase.done : AiPhase.idle;
    notifyListeners();
  }

  void _fail(String m) {
    message = m;
    phase = AiPhase.failed;
    notifyListeners();
  }

  void clear() {
    text = null;
    message = null;
    phase = AiPhase.idle;
    _prefs?.remove('ai_last_text');
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _http.close();
    super.dispose();
  }
}
