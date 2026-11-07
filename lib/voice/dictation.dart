import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Escrita por voz: toca no microfone de um campo, fala, e o texto aparece.
///
/// Usa o reconhecimento de fala do próprio aparelho (Android/iOS) ou do
/// navegador (Chrome, Edge, Safari). O app não grava nem envia áudio: quem
/// transcreve é o serviço do sistema (que pode ser online, como o do Google ou
/// da Apple). Só um campo ouve por vez, e o afinador é desligado antes para o
/// microfone ficar livre.
class Dictation extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  String? _localeId;

  /// Campo que está ouvindo agora (ou null).
  TextEditingController? _active;
  String _base = '';

  /// A pessoa já leu e aceitou como o ditado funciona (pergunta uma vez só).
  bool consented = false;
  SharedPreferences? _prefs;

  /// Chamado antes de começar a ouvir (o app desliga o afinador aqui).
  Future<void> Function()? beforeListen;

  /// Avisos curtos para o usuário.
  void Function(String message)? onMessage;

  bool get listening => _active != null;
  bool isListening(TextEditingController c) => identical(_active, c);

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

  /// Liga ou desliga o ditado no campo [c]. O texto falado é acrescentado ao que já está escrito.
  Future<void> toggle(TextEditingController c) async {
    if (isListening(c)) {
      await stop();
      return;
    }
    await stop();
    await beforeListen?.call();
    if (!await _init()) {
      onMessage?.call('Ditado indisponível aqui. Use o microfone do teclado do celular, se houver.');
      return;
    }
    _base = c.text.trimRight();
    _active = c;
    notifyListeners();
    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          pauseFor: const Duration(seconds: 5),
          listenFor: const Duration(seconds: 90),
        ),
      );
    } catch (_) {
      _active = null;
      notifyListeners();
      onMessage?.call('Não consegui ouvir agora. Tente de novo.');
    }
  }

  Future<void> stop() async {
    if (_active == null) return;
    _active = null;
    notifyListeners();
    try {
      await _stt.stop();
    } catch (_) {}
  }

  void _onResult(SpeechRecognitionResult r) {
    final c = _active;
    if (c == null) return;
    final words = r.recognizedWords.trim();
    if (words.isEmpty) return;
    final text = _base.isEmpty ? words : '$_base $words';
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    if (r.finalResult) {
      _active = null;
      notifyListeners();
    }
  }

  void _onStatus(String status) {
    if ((status == 'done' || status == 'notListening') && _active != null) {
      _active = null;
      notifyListeners();
    }
  }

  void _onError(SpeechRecognitionError e) {
    _active = null;
    notifyListeners();
    final m = e.errorMsg;
    if (m.contains('permission') || m.contains('not-allowed')) {
      onMessage?.call('Permita o uso do microfone para ditar.');
    } else if (m.contains('no_match') || m.contains('no-speech') || m.contains('speech_timeout')) {
      onMessage?.call('Não ouvi nada. Toque no microfone e fale de novo.');
    } else if (m.contains('network')) {
      onMessage?.call('Sem internet: o reconhecimento de voz deste aparelho precisa de conexão.');
    } else {
      onMessage?.call('O ditado parou. Tente de novo.');
    }
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }
}
