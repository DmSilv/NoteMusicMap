import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:afina_core/afina_core.dart';

/// Em que ponto o ditado está (a faixa de voz e o botão mostram isto em todos os campos).
enum DictationPhase {
  /// Nada acontecendo.
  idle,

  /// Pedindo o microfone / preparando o reconhecimento.
  starting,

  /// Ouvindo: o que for falado entra no campo.
  listening,

  /// Acabou há instantes: a faixa mostra por que parou e some sozinha.
  ended,
}

/// Por que o ditado parou.
enum DictationEnd { manual, silence, maxTime, nothing, error }

/// Escrita por voz: toca no microfone de um campo, fala, e o texto aparece.
///
/// Usa o reconhecimento de fala do próprio aparelho (Android/iOS) ou do
/// navegador (Chrome, Edge, Safari). O app não grava nem envia áudio: quem
/// transcreve é o serviço do sistema (que pode ser online, como o do Google ou
/// da Apple). Só um campo ouve por vez, e o afinador é desligado antes para o
/// microfone ficar livre.
class Dictation extends ChangeNotifier {
  /// Silêncio que faz o ditado parar sozinho, e tempo máximo de uma fala. Aparecem na faixa de voz.
  static const Duration pauseFor = Duration(seconds: 5);
  static const Duration listenFor = Duration(seconds: 90);

  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  String? _localeId;

  /// Campo que está ouvindo agora (ou null).
  TextEditingController? _active;
  String _base = '';

  DictationPhase phase = DictationPhase.idle;
  DictationEnd? endedBy;

  /// Quanto tempo já se ouviu (ms) e há quanto tempo não se ouve fala (ms): alimentam a contagem da faixa.
  final ValueNotifier<int> elapsedMs = ValueNotifier(0);
  final ValueNotifier<int> quietMs = ValueNotifier(0);

  /// Volume da fala agora, de 0 a 1 (o aparelho ou o navegador pode não informar: fica em 0).
  final ValueNotifier<double> level = ValueNotifier(0);

  DateTime? _startedAt;
  DateTime? _lastVoiceAt;
  bool _gotWords = false;
  Timer? _tick;
  Timer? _fade;

  /// A pessoa já leu e aceitou como o ditado funciona (pergunta uma vez só).
  bool consented = false;
  SharedPreferences? _prefs;

  /// Chamado antes de começar a ouvir (o app desliga o afinador aqui).
  Future<void> Function()? beforeListen;

  /// Avisos curtos para o usuário.
  void Function(String message)? onMessage;

  bool get listening => _active != null;
  bool isListening(TextEditingController c) => identical(_active, c);

  /// O campo [c] está pedindo o microfone ou ouvindo (o botão mostra "parar").
  bool isBusy(TextEditingController c) => identical(_active, c) && (phase == DictationPhase.starting || phase == DictationPhase.listening);

  Future<void> load(SharedPreferences p) async {
    _prefs = p;
    consented = p.getBool('dictation_ok') ?? false;
  }

  Future<void> setConsent(bool v) async {
    consented = v;
    await _prefs?.setBool('dictation_ok', v);
    notifyListeners();
  }

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(onError: _onError, onStatus: _onStatus);
      if (_ready) _localeId = await _pickLocale();
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Prefere português do Brasil; senão qualquer português; senão o padrão do aparelho.
  Future<String?> _pickLocale() async {
    try {
      final ls = await _stt.locales();
      for (final l in ls) {
        if (RegExp(r'^pt[_-]BR$', caseSensitive: false).hasMatch(l.localeId)) return l.localeId;
      }
      for (final l in ls) {
        if (RegExp(r'^pt', caseSensitive: false).hasMatch(l.localeId)) return l.localeId;
      }
    } catch (_) {}
    return null;
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final now = DateTime.now();
      if (_startedAt != null) elapsedMs.value = now.difference(_startedAt!).inMilliseconds;
      if (_lastVoiceAt != null) quietMs.value = now.difference(_lastVoiceAt!).inMilliseconds;
    });
  }

  /// A faixa fica um instante dizendo por que parou e depois some.
  void _finish(DictationEnd why) {
    _tick?.cancel();
    _tick = null;
    final was = phase;
    _active = null;
    endedBy = why;
    level.value = 0;
    phase = (was == DictationPhase.idle || why == DictationEnd.error) ? DictationPhase.idle : DictationPhase.ended;
    notifyListeners();
    _fade?.cancel();
    if (phase == DictationPhase.ended) {
      _fade = Timer(const Duration(milliseconds: 2200), () {
        if (phase == DictationPhase.ended) {
          phase = DictationPhase.idle;
          notifyListeners();
        }
      });
    }
  }

  /// Quando o reconhecimento termina sozinho: foi o silêncio, o tempo máximo ou não se ouviu nada?
  DictationEnd _whyItEnded() {
    if (!_gotWords) return DictationEnd.nothing;
    if (elapsedMs.value >= listenFor.inMilliseconds - 1500) return DictationEnd.maxTime;
    return DictationEnd.silence;
  }

  /// Liga ou desliga o ditado no campo [c]. O texto falado é acrescentado ao que já está escrito.
  Future<void> toggle(TextEditingController c) async {
    if (isListening(c)) {
      await stop();
      return;
    }
    await stop();
    _fade?.cancel();
    // A faixa aparece já ("Preparando o microfone…"): pedir a permissão ou iniciar o reconhecimento pode demorar.
    _active = c;
    phase = DictationPhase.starting;
    endedBy = null;
    _gotWords = false;
    elapsedMs.value = 0;
    quietMs.value = 0;
    notifyListeners();
    await beforeListen?.call();
    if (!await _init()) {
      _active = null;
      phase = DictationPhase.idle;
      notifyListeners();
      onMessage?.call(tr('Ditado indisponível aqui. Use o microfone do teclado do celular, se houver.'));
      return;
    }
    _base = c.text.trimRight();
    try {
      await _stt.listen(
        onResult: _onResult,
        onSoundLevelChange: (l) => level.value = ((l + 2) / 12).clamp(0.0, 1.0),
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          pauseFor: pauseFor,
          listenFor: listenFor,
        ),
      );
      if (identical(_active, c) && phase == DictationPhase.starting) _markListening();
    } catch (_) {
      _active = null;
      phase = DictationPhase.idle;
      notifyListeners();
      onMessage?.call(tr('Não consegui ouvir agora. Tente de novo.'));
    }
  }

  void _markListening() {
    _startedAt = DateTime.now();
    _lastVoiceAt = _startedAt;
    phase = DictationPhase.listening;
    _startTick();
    notifyListeners();
  }

  Future<void> stop() async {
    if (_active == null) return;
    final wasListening = phase == DictationPhase.listening;
    _finish(wasListening ? DictationEnd.manual : DictationEnd.error);
    try {
      await _stt.stop();
    } catch (_) {}
  }

  void _onResult(SpeechRecognitionResult r) {
    final c = _active;
    if (c == null) return;
    if (phase == DictationPhase.starting) _markListening();
    final words = r.recognizedWords.trim();
    if (words.isEmpty) return;
    _gotWords = true;
    _lastVoiceAt = DateTime.now();
    quietMs.value = 0;
    final text = _base.isEmpty ? words : '$_base $words';
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    if (r.finalResult) _finish(_whyItEnded());
  }

  void _onStatus(String status) {
    if (status == 'listening' && _active != null && phase == DictationPhase.starting) _markListening();
    if ((status == 'done' || status == 'notListening') && _active != null) _finish(_whyItEnded());
  }

  void _onError(SpeechRecognitionError e) {
    _finish(DictationEnd.error);
    final m = e.errorMsg;
    if (m.contains('permission') || m.contains('not-allowed')) {
      onMessage?.call(tr('Permita o uso do microfone para ditar.'));
    } else if (m.contains('no_match') || m.contains('no-speech') || m.contains('speech_timeout')) {
      onMessage?.call(tr('Não ouvi nada. Toque no microfone e fale de novo.'));
    } else if (m.contains('network')) {
      onMessage?.call(tr('Sem internet: o reconhecimento de voz deste aparelho precisa de conexão.'));
    } else {
      onMessage?.call(tr('O ditado parou. Tente de novo.'));
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _fade?.cancel();
    _stt.cancel();
    super.dispose();
  }
}
