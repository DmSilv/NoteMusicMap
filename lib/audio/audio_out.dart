import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

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

/// Tom de referência (diapasão / nota da corda) com fase contínua: a
/// frequência é exata e não há estalo ao ligar/desligar.
class TonePlayer {
  static const double _aheadSeconds = 0.2;
  static const int _chunk = 512;

  AudioSource? _src;
  SoundHandle? _handle;
  Timer? _feeder;
  final Stopwatch _clock = Stopwatch();
  int _fed = 0;
  double _phase = 0;
  double _freq = 440;
  double _gain = 0; // atual (rampa)
  double _gainTarget = 0.3;
  bool _stopping = false;

  bool get running => _src != null && !_stopping;
  double get frequency => _freq;

  Future<void> play(double freq) async {
    _freq = freq;
    if (running) return; // só troca a frequência
    await ensureAudio();
    _stopping = false;
    _gain = 0;
    _fed = 0;
    final src = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.05,
      sampleRate: kOutRate,
      channels: Channels.mono,
      format: BufferType.f32le,
    );
    _src = src;
    _feed((kOutRate * 0.25).round());
    _handle = SoLoud.instance.play(src);
    _clock
      ..reset()
      ..start();
    _feeder = Timer.periodic(const Duration(milliseconds: 25), (_) {
      final played = (_clock.elapsedMicroseconds * kOutRate / 1e6).floor();
      final target = played + (kOutRate * _aheadSeconds).round();
      while (_fed < target) {
        _feed(_chunk);
      }
    });
  }

  void setFrequency(double f) => _freq = f;

  void _feed(int frames) {
    final src = _src;
    if (src == null) return;
    final out = Float32List(frames);
    final rampPerSample = 1 / (kOutRate * 0.03); // 30 ms
    for (var i = 0; i < frames; i++) {
      if (_gain < _gainTarget) {
        _gain = math.min(_gainTarget, _gain + rampPerSample * _gainTarget);
      } else if (_gain > _gainTarget) {
        _gain = math.max(_gainTarget, _gain - rampPerSample * 0.3);
      }
      _phase += 2 * math.pi * _freq / kOutRate;
      if (_phase > 2 * math.pi) _phase -= 2 * math.pi;
      // senoide com um toque de 2º e 3º harmônico para ficar audível em
      // alto-falante de celular, sem mudar a altura percebida.
      final v = math.sin(_phase) +
          0.25 * math.sin(2 * _phase) +
          0.10 * math.sin(3 * _phase);
      out[i] = (_gain * v).toDouble();
    }
    _fed += frames;
    SoLoud.instance.addAudioDataStream(
        src, out.buffer.asUint8List(out.offsetInBytes, out.lengthInBytes));
  }

  Future<void> stop() async {
    if (_src == null || _stopping) return;
    _stopping = true;
    _gainTarget = 0;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _feeder?.cancel();
    _feeder = null;
    final h = _handle;
    final s = _src;
    _handle = null;
    _src = null;
    _clock.stop();
    _gainTarget = 0.3;
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
    _stopping = false;
  }
}

/// Alarme sutil do Pomodoro: um sino suave de duas notas.
/// Fim de foco = notas descendo (hora de relaxar); fim de pausa = subindo
/// (hora de voltar). Volume baixo, ataque macio e decaimento longo, para não
/// assustar quem está tocando.
class ChimePlayer {
  Future<void> play({required bool endOfFocus, double volume = 0.5}) async {
    await ensureAudio();
    const sr = kOutRate;
    final notes = endOfFocus ? [880.0, 659.25] : [659.25, 880.0];
    const noteGap = 0.32; // s entre as duas notas
    const total = 2.2; // s
    final n = (sr * total).round();
    final pcm = Float32List(n);
    for (var k = 0; k < notes.length; k++) {
      final start = (k * noteGap * sr).round();
      final f = notes[k];
      for (var i = 0; start + i < n; i++) {
        final t = i / sr;
        final attack = math.min(1.0, t / 0.012);
        final env = attack * math.exp(-t / 0.55);
        if (env < 0.0005) break;
        // fundamental + harmônicos suaves (timbre de sininho)
        final v = math.sin(2 * math.pi * f * t) +
            0.30 * math.sin(2 * math.pi * f * 2.0 * t) * math.exp(-t / 0.25) +
            0.12 * math.sin(2 * math.pi * f * 3.01 * t) * math.exp(-t / 0.12);
        pcm[start + i] += (env * v * 0.30 * volume).toDouble();
      }
    }
    for (var i = 0; i < n; i++) {
      pcm[i] = pcm[i].clamp(-1.0, 1.0);
    }
    final src = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.05,
      sampleRate: sr,
      channels: Channels.mono,
      format: BufferType.f32le,
    );
    SoLoud.instance.addAudioDataStream(
        src, pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes));
    SoLoud.instance.setDataIsEnded(src);
    final h = SoLoud.instance.play(src);
    Future<void>.delayed(const Duration(milliseconds: 2600), () async {
      try {
        await SoLoud.instance.stop(h);
        await SoLoud.instance.disposeSource(src);
      } catch (_) {}
    });
  }
}
