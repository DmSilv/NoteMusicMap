import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'package:afina_core/afina_core.dart';

const int kOutRate = 44100;

bool _initDone = false;
Future<void>? _initFuture;

/// Inicia o motor de áudio uma única vez.
Future<void> ensureAudio() {
  if (_initDone) return Future.value();
  return _initFuture ??= SoLoud.instance
      .init(sampleRate: kOutRate, bufferSize: 1024, channels: Channels.mono)
      .then((_) => _initDone = true);
}

/// Reproduz o metrônomo alimentando o motor com PCM contínuo gerado por
/// [MetronomeEngine]. O tempo vem da posição de AMOSTRA, nunca de Timer.
class MetronomePlayer {
  static const double _aheadSeconds = 0.25;
  static const int _chunk = 512;

  MetronomeEngine? _engine;
  AudioSource? _src;
  SoundHandle? _handle;
  Timer? _feeder;
  final Stopwatch _clock = Stopwatch();
  int _fed = 0;
  final List<ClickEvent> _pending = [];

  /// Compensação da latência de saída (ms). Ajustável na calibração.
  double outputLatencyMs = 0;

  bool get running => _engine != null;
  double get currentBpm => _engine?.currentBpm ?? 0;

  /// O que o modo desafio já fez nesta execução.
  ChallengeStats get challengeStats => _engine?.challengeStats ?? const ChallengeStats(0, 0);

  Future<void> start(MetronomeConfig cfg) async {
    if (running) return;
    await ensureAudio();
    final e = MetronomeEngine(kOutRate, cfg);
    _engine = e;
    _fed = 0;
    _pending.clear();
    final src = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.05,
      sampleRate: kOutRate,
      channels: Channels.mono,
      format: BufferType.f32le,
    );
    _src = src;
    _feed(frames: (kOutRate * 0.3).round()); // pré-carrega 300 ms
    _handle = SoLoud.instance.play(src);
    _clock
      ..reset()
      ..start();
    _feeder = Timer.periodic(const Duration(milliseconds: 25), (_) => _tick());
  }

  void _tick() {
    final playedFrames = (_clock.elapsedMicroseconds * kOutRate / 1e6).floor();
    final target = playedFrames + (kOutRate * _aheadSeconds).round();
    while (_fed < target) {
      _feed(frames: _chunk);
    }
  }

  void _feed({required int frames}) {
    final e = _engine;
    final src = _src;
    if (e == null || src == null) return;
    final pcm = e.render(frames);
    _pending.addAll(e.takeEvents());
    if (_pending.length > 4000) _pending.removeRange(0, _pending.length - 2000);
    _fed += frames;
    SoLoud.instance.addAudioDataStream(
        src, pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes));
  }

  void update(MetronomeConfig cfg) => _engine?.update(cfg);

  /// Eventos cujo instante de reprodução já chegou (para a tela piscar).
  List<ClickEvent> dueEvents() {
    final nowFrames = ((_clock.elapsedMicroseconds / 1e6) * kOutRate -
            outputLatencyMs * kOutRate / 1000)
        .floor();
    final due = <ClickEvent>[];
    while (_pending.isNotEmpty && _pending.first.sample <= nowFrames) {
      due.add(_pending.removeAt(0));
    }
    return due;
  }

  Future<void> stop() async {
    _feeder?.cancel();
    _feeder = null;
    final h = _handle;
    final s = _src;
    _engine = null;
    _handle = null;
    _src = null;
    _pending.clear();
    _clock.stop();
    if (h != null) {
      try {
        await SoLoud.instance.stop(h);
      } catch (_) {}
    }
    if (s != null) {
      try {
        await SoLoud.instance.disposeSource(s);
      } catch (_) {}
    }
  }
}

/// Tom de referência (diapasão / nota da corda).
///
/// Toca um trecho pré-calculado em LAÇO (veja `buildToneLoop`): a frequência é
/// exata e não há emendas nem dependência de temporizador, então não estala
/// mesmo com o app ocupado. Entrada e saída têm rampa de volume (sem "clique"),
/// e trocar de nota faz um cruzamento suave entre o tom antigo e o novo.
class TonePlayer {
  static const Duration _fade = Duration(milliseconds: 110);

  /// Timbre usado nas próximas notas (diapasão puro ou mais "cheio").
  ToneTimbre timbre = ToneTimbre.fork;

  /// Volume de 0 a 1.
  double volume = 0.9;

  /// Muda o volume (0,2 a 1) na hora, mesmo com o tom tocando.
  void setVolume(double v) {
    volume = v.clamp(0.2, 1.0).toDouble();
    final h = _handle;
    if (h != null) {
      try {
        SoLoud.instance.setVolume(h, volume);
      } catch (_) {}
    }
  }

  final Map<String, AudioSource> _cache = {};
  final List<String> _cacheOrder = [];
  SoundHandle? _handle;
  double _freq = 440;
  int _seq = 0; // descarta pedidos antigos se o usuário tocar rápido

  bool get running => _handle != null;
  double get frequency => _freq;

  Future<AudioSource> _source(double freq) async {
    final key = '${freq.toStringAsFixed(3)}-${timbre.index}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final loop = buildToneLoop(freq, sampleRate: kOutRate, timbre: timbre);
    final wav = pcm16Wav(loop.samples, loop.sampleRate);
    final src = await SoLoud.instance.loadMem('tone-$key', wav);
    _cache[key] = src;
    _cacheOrder.add(key);
    // Mantém poucos trechos na memória.
    while (_cacheOrder.length > 16) {
      final old = _cacheOrder.removeAt(0);
      final s = _cache.remove(old);
      if (s != null) {
        try {
          await SoLoud.instance.disposeSource(s);
        } catch (_) {}
      }
    }
    return src;
  }

  /// Prepara os tons com antecedência, um por vez e com pausas curtas, para que
  /// tocar uma corda depois seja instantâneo (sem trabalho pesado na hora do
  /// toque, que no navegador pode causar falhas no som).
  Future<void> preload(Iterable<double> freqs) async {
    try {
      await ensureAudio();
      for (final f in freqs) {
        await _source(f);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } catch (_) {}
  }

  /// Começa (ou troca para) a nota [freq].
  Future<void> play(double freq) async {
    await ensureAudio();
    final my = ++_seq;
    _freq = freq;
    final src = await _source(freq);
    if (my != _seq) return; // chegou um pedido mais novo
    final old = _handle;
    final h = SoLoud.instance.play(src, looping: true, volume: 0);
    SoLoud.instance.fadeVolume(h, volume, _fade);
    _handle = h;
    if (old != null) _fadeOutAndStop(old);
  }

  void setFrequency(double f) {
    if (running) play(f);
  }

  void _fadeOutAndStop(SoundHandle h) {
    try {
      SoLoud.instance.fadeVolume(h, 0, _fade);
    } catch (_) {}
    Future<void>.delayed(_fade + const Duration(milliseconds: 40), () async {
      try {
        await SoLoud.instance.stop(h);
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    _seq++;
    final h = _handle;
    _handle = null;
    if (h != null) _fadeOutAndStop(h);
  }
}

/// Alarme sutil do Pomodoro: um sino suave de duas notas.
/// Fim de foco = notas descendo (hora de relaxar); fim de pausa = subindo
/// (hora de voltar). Usa o mesmo caminho do diapasão (WAV em memória), que é
/// confiável no navegador. O som é gerado uma vez e guardado.
class ChimePlayer {
  final Map<bool, AudioSource> _cache = {};

  Future<AudioSource> _source(bool endOfFocus) async {
    final hit = _cache[endOfFocus];
    if (hit != null) return hit;
    final pcm = buildChime(endOfFocus: endOfFocus, sampleRate: kOutRate);
    final src = await SoLoud.instance
        .loadMem('chime-$endOfFocus', pcm16Wav(pcm, kOutRate));
    _cache[endOfFocus] = src;
    return src;
  }

  Future<void> play({required bool endOfFocus, double volume = 0.5}) async {
    await ensureAudio();
    final src = await _source(endOfFocus);
    SoLoud.instance.play(src, volume: volume.clamp(0.05, 1.0));
  }
}

/// Pedal (bordão): várias notas ao mesmo tempo, cada uma em laço (como o diapasão), com entrada
/// e saída suaves. Cada nota é uma "voz" independente; o volume de cada uma cai com o número
/// de notas para a soma não estourar.
class PedalPlayer {
  static const Duration _fade = Duration(milliseconds: 140);

  ToneTimbre timbre = ToneTimbre.fork;

  /// Volume geral de 0 a 1.
  double volume = 0.9;

  final Map<String, AudioSource> _cache = {};
  final List<String> _cacheOrder = [];
  final Map<String, SoundHandle> _voices = {}; // "midi|freq|timbre" -> som
  int _seq = 0; // descarta pedidos antigos se o usuário tocar rápido

  bool get running => _voices.isNotEmpty;
  int get voices => _voices.length;

  Future<AudioSource> _source(double freq) async {
    final key = '${freq.toStringAsFixed(3)}-${timbre.index}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final loop = buildToneLoop(freq, sampleRate: kOutRate, timbre: timbre);
    final src = await SoLoud.instance.loadMem('pedal-$key', pcm16Wav(loop.samples, loop.sampleRate));
    _cache[key] = src;
    _cacheOrder.add(key);
    while (_cacheOrder.length > 48) {
      final old = _cacheOrder.removeAt(0);
      final s = _cache.remove(old);
      if (s != null) {
        try {
          await SoLoud.instance.disposeSource(s);
        } catch (_) {}
      }
    }
    return src;
  }

  /// Prepara as notas com antecedência (uma por vez, com pausas curtas) para tocar na hora.
  Future<void> preload(Iterable<double> freqs) async {
    try {
      await ensureAudio();
      for (final f in freqs) {
        await _source(f);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    } catch (_) {}
  }

  double _gain(int n) => pedalVoiceGain(n) * volume;

  /// Faz o pedal soar EXATAMENTE estas notas ([midi], [Hz]): entram as novas, saem as que
  /// sumiram e as que continuam só ajustam o volume. Mudar a frequência (outro Lá ou sistema)
  /// troca a nota com um cruzamento suave.
  Future<void> setNotes(List<(int, double)> notes) async {
    final my = ++_seq;
    if (notes.isEmpty) return stop();
    await ensureAudio();
    final want = <String, double>{
      for (final n in notes) '${n.$1}|${n.$2.toStringAsFixed(3)}|${timbre.index}': n.$2,
    };
    final fresh = <String, AudioSource>{};
    for (final e in want.entries) {
      if (!_voices.containsKey(e.key)) fresh[e.key] = await _source(e.value);
      if (my != _seq) return; // chegou um pedido mais novo
    }
    for (final k in _voices.keys.where((k) => !want.containsKey(k)).toList()) {
      _fadeOutAndStop(_voices.remove(k)!);
    }
    final g = _gain(want.length);
    for (final h in _voices.values) {
      try {
        SoLoud.instance.fadeVolume(h, g, _fade);
      } catch (_) {}
    }
    for (final e in fresh.entries) {
      final h = SoLoud.instance.play(e.value, looping: true, volume: 0);
      SoLoud.instance.fadeVolume(h, g, _fade);
      _voices[e.key] = h;
    }
  }

  /// Muda o volume geral na hora, mesmo com as notas tocando.
  void setVolume(double v) {
    volume = v.clamp(0.2, 1.0).toDouble();
    final g = _gain(_voices.length);
    for (final h in _voices.values) {
      try {
        SoLoud.instance.setVolume(h, g);
      } catch (_) {}
    }
  }

  void _fadeOutAndStop(SoundHandle h) {
    try {
      SoLoud.instance.fadeVolume(h, 0, _fade);
    } catch (_) {}
    Future<void>.delayed(_fade + const Duration(milliseconds: 40), () async {
      try {
        await SoLoud.instance.stop(h);
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    _seq++;
    final hs = _voices.values.toList();
    _voices.clear();
    for (final h in hs) {
      _fadeOutAndStop(h);
    }
  }
}
