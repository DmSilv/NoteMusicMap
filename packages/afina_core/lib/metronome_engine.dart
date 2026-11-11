/// Motor do metrônomo: gera PCM com cliques posicionados em AMOSTRAS exatas.
///
/// Por que assim: o app não agenda cliques com Timer (que oscila 5-20 ms). Em
/// vez disso, gera o áudio contínuo e coloca cada clique na amostra certa.
/// Como o tempo vem do relógio de áudio, não há deriva nem "trava".
///
/// Propriedades garantidas por teste (test/metronome_engine_test.dart):
///  - posição do tick i = i * período (sem acumular erro);
///  - renderizar em blocos de qualquer tamanho dá o MESMO áudio;
///  - mudança de BPM vale a partir do próximo tick, sem salto;
///  - o pico nunca passa de 1.0 (sem clipping, mesmo com cliques sobrepostos).
library;

import 'rhythm_challenge.dart';
import 'dart:math' as math;
import 'dart:typed_data';

enum Accent { strong, medium, weak, mute }

enum ClickSound { click, wood, beep, clave, drum }

class TempoTrainer {
  /// A cada [everyBars] compassos soma [stepBpm], até [maxBpm].
  final int everyBars;
  final double stepBpm;
  final double maxBpm;
  const TempoTrainer(
      {this.everyBars = 4, this.stepBpm = 4, this.maxBpm = 160});
}

class SilentBars {
  /// Toca [playBars] compassos e silencia [muteBars] (treino de pulso interno).
  final int playBars;
  final int muteBars;
  const SilentBars({this.playBars = 2, this.muteBars = 1});
}

class MetronomeConfig {
  final double bpm;
  final int beatsPerBar;

  /// Cliques por tempo (1 = só o tempo; 2 = colcheias; 3 = tercinas; 4 = semicolcheias).
  final int subdivision;

  /// Acento de cada tempo (tamanho = beatsPerBar). O primeiro é o "um".
  final List<Accent> accents;

  /// Quais subdivisões soam (tamanho = subdivision); o índice 0 é o próprio tempo.
  final List<bool> subdivisionMask;
  final ClickSound sound;
  final double volume;
  final int countInBars;
  final TempoTrainer? trainer;
  final SilentBars? silent;

  /// Modo desafio ("sabotagem"): surpresas temporárias de andamento e silêncio.
  final ChallengeConfig? challenge;

  const MetronomeConfig({
    this.bpm = 100,
    this.beatsPerBar = 4,
    this.subdivision = 1,
    this.accents = const [
      Accent.strong, Accent.weak, Accent.weak, Accent.weak,
    ],
    this.subdivisionMask = const [true],
    this.sound = ClickSound.click,
    this.volume = 0.8,
    this.countInBars = 0,
    this.trainer,
    this.silent,
    this.challenge,
  });

  /// Cria a configuração com acentos padrão para [beats] tempos.
  factory MetronomeConfig.signature(
    int beats, {
    double bpm = 100,
    int subdivision = 1,
    ClickSound sound = ClickSound.click,
    int? groupSize,
  }) {
    final acc = List<Accent>.filled(beats, Accent.weak);
    acc[0] = Accent.strong;
    if (groupSize != null && groupSize > 1) {
      for (var i = groupSize; i < beats; i += groupSize) {
        acc[i] = Accent.medium;
      }
    }
    return MetronomeConfig(
      bpm: bpm,
      beatsPerBar: beats,
      subdivision: subdivision,
      accents: acc,
      subdivisionMask: List<bool>.filled(subdivision, true),
      sound: sound,
    );
  }

  MetronomeConfig copyWith({
    double? bpm,
    int? beatsPerBar,
    int? subdivision,
    List<Accent>? accents,
    List<bool>? subdivisionMask,
    ClickSound? sound,
    double? volume,
    int? countInBars,
    Object? trainer = _keep,
    Object? silent = _keep,
    Object? challenge = _keep,
  }) =>
      MetronomeConfig(
        bpm: bpm ?? this.bpm,
        beatsPerBar: beatsPerBar ?? this.beatsPerBar,
        subdivision: subdivision ?? this.subdivision,
        accents: accents ?? this.accents,
        subdivisionMask: subdivisionMask ?? this.subdivisionMask,
        sound: sound ?? this.sound,
        volume: volume ?? this.volume,
        countInBars: countInBars ?? this.countInBars,
        trainer: identical(trainer, _keep)
            ? this.trainer
            : trainer as TempoTrainer?,
        silent:
            identical(silent, _keep) ? this.silent : silent as SilentBars?,
        challenge: identical(challenge, _keep) ? this.challenge : challenge as ChallengeConfig?,
      );
}

const Object _keep = Object();

/// Um tick (tempo ou subdivisão) no fio do tempo.
class ClickEvent {
  final int sample;
  final int bar; // negativo durante a contagem inicial
  final int beat; // 0-based
  final int sub; // 0-based
  final Accent accent;
  final bool audible;
  final double bpm;

  /// Silêncio do modo desafio: nem som nem marcação na tela.
  final bool hidden;

  /// O que o modo desafio está fazendo neste compasso (para a tela avisar).
  final ChallengeKind challenge;
  const ClickEvent(this.sample, this.bar, this.beat, this.sub, this.accent,
      this.audible, this.bpm, {this.hidden = false, this.challenge = ChallengeKind.normal});
}

class _Voice {
  final int start;
  final Float32List wave;
  final double gain;
  _Voice(this.start, this.wave, this.gain);
}

class MetronomeEngine {
  final int sampleRate;
  MetronomeConfig _cfg;
  double _baseBpm; // BPM do treino de andamento (o original da pessoa, ou o que o trainer já subiu)
  double _bpm; // BPM efetivo agora (o desafio pode alterar por alguns compassos)
  RhythmChallenge? _challenge;
  ChallengeBar _cb = ChallengeBar.normal;
  final math.Random? _random;

  double _nextTick = 0;
  int _rendered = 0;
  late int _bar;
  int _beat = 0;
  int _sub = 0;
  int _barsSinceStep = 0;

  final List<_Voice> _voices = [];
  final List<ClickEvent> _events = [];
  final Map<String, Float32List> _waves = {};

  MetronomeEngine(this.sampleRate, MetronomeConfig cfg, {math.Random? random})
      : _cfg = cfg,
        _baseBpm = cfg.bpm,
        _bpm = cfg.bpm,
        _random = random {
    _bar = -cfg.countInBars;
    _setupChallenge();
    _applyChallenge();
  }

  void _setupChallenge() {
    final c = _cfg.challenge;
    _challenge = (c != null && c.active) ? RhythmChallenge(c, random: _random) : null;
    _cb = ChallengeBar.normal;
  }

  /// Pede ao desafio o que fazer no compasso atual e recalcula o andamento.
  void _applyChallenge() {
    final ch = _challenge;
    _cb = (ch != null && _bar >= 0) ? ch.barFor(_bar) : ChallengeBar.normal;
    _bpm = (_baseBpm * _cb.factor).clamp(20.0, 320.0).toDouble();
  }

  /// O que o desafio já fez nesta execução (mudanças de andamento e silêncios).
  ChallengeStats get challengeStats => _challenge?.stats ?? const ChallengeStats(0, 0);

  MetronomeConfig get config => _cfg;
  double get currentBpm => _bpm;
  int get renderedSamples => _rendered;

  /// Troca a configuração sem reiniciar. Vale a partir do próximo tick.
  void update(MetronomeConfig cfg) {
    final bpmChanged = cfg.bpm != _cfg.bpm;
    final challengeChanged = cfg.challenge != _cfg.challenge;
    final beats = cfg.beatsPerBar;
    final subs = cfg.subdivision;
    _cfg = cfg;
    if (bpmChanged) _baseBpm = cfg.bpm;
    if (challengeChanged) _setupChallenge();
    if (bpmChanged || challengeChanged) _applyChallenge();
    if (_beat >= beats) _beat = 0;
    if (_sub >= subs) _sub = 0;
  }

  /// Eventos gerados desde a última chamada (para sincronizar a tela).
  List<ClickEvent> takeEvents() {
    final e = List<ClickEvent>.of(_events);
    _events.clear();
    return e;
  }

  double _period() => sampleRate * 60.0 / (_bpm * _cfg.subdivision);

  bool _isMuted(int bar) {
    final s = _cfg.silent;
    if (s == null || bar < 0) return false;
    final cycle = s.playBars + s.muteBars;
    return (bar % cycle) >= s.playBars;
  }

  Accent _accentFor(int beat, int sub) {
    if (sub == 0) {
      return beat < _cfg.accents.length ? _cfg.accents[beat] : Accent.weak;
    }
    final on = sub < _cfg.subdivisionMask.length ? _cfg.subdivisionMask[sub] : true;
    return on ? Accent.weak : Accent.mute;
  }

  Float32List _wave(ClickSound s, Accent a, bool isSub) {
    final key = '${s.index}-${a.index}-$isSub';
    return _waves.putIfAbsent(key, () => _buildClick(s, a, isSub));
  }

  Float32List _buildClick(ClickSound s, Accent a, bool isSub) {
    // Sons sintetizados: transiente de ruído (ataque) + parciais com
    // decaimento próprio (corpo). Determinístico (ruído com semente fixa).
    // Todos terminam em < 60 ms.
    final k = a == Accent.strong ? 1.0 : (a == Accent.medium ? 0.84 : 0.70);
    final sub = isSub ? 0.85 : 1.0;
    // (razão, amplitude, decaimento em s)
    late List<(double, double, double)> parts;
    late double base, noiseAmp, noiseDecay, dur;
    var sweep = 0.0;
    var attackMs = 0.5;
    switch (s) {
      case ClickSound.click:
        base = 1900 * k * sub;
        parts = [(1, 1.0, 0.006), (2.0, 0.35, 0.003)];
        noiseAmp = 0.7;
        noiseDecay = 0.0015;
        dur = 0.03;
      case ClickSound.wood:
        base = 820 * k * sub;
        parts = [(1, 1.0, 0.018), (2.76, 0.55, 0.008), (5.4, 0.25, 0.004)];
        noiseAmp = 0.3;
        noiseDecay = 0.002;
        dur = 0.055;
      case ClickSound.clave:
        base = 2400 * k * sub;
        parts = [(1, 1.0, 0.012), (1.5, 0.3, 0.006)];
        noiseAmp = 0.2;
        noiseDecay = 0.0015;
        dur = 0.05;
      case ClickSound.beep:
        base = 880 * k * sub;
        parts = [(1, 1.0, 0.03), (2.0, 0.2, 0.02)];
        noiseAmp = 0.0;
        noiseDecay = 0.001;
        dur = 0.055;
        attackMs = 3;
      case ClickSound.drum:
        base = 170 * k * sub;
        parts = [(1, 1.0, 0.035)];
        noiseAmp = 0.35;
        noiseDecay = 0.002;
        dur = 0.055;
        sweep = 1.2;
    }
    final n = (sampleRate * dur).round();
    final out = Float32List(n);
    final attack = math.max(1, (sampleRate * attackMs / 1000).round());
    final tailLen = math.max(1, (sampleRate * 0.004).round());
    var seed = 12345;
    var lp = 0.0;
    final phases = List<double>.filled(parts.length, 0);
    var peak = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final white = (seed / 0x3fffffff) - 1.0;
      lp += 0.45 * (white - lp); // passa-baixa simples no ruído
      var v = noiseAmp * lp * math.exp(-t / noiseDecay);
      for (var p = 0; p < parts.length; p++) {
        final (r, amp, d) = parts[p];
        final f = base * r * (1 + sweep * math.exp(-t / 0.012));
        phases[p] += 2 * math.pi * f / sampleRate;
        v += amp * math.exp(-t / d) * math.sin(phases[p]);
      }
      if (i < attack) v *= i / attack; // sem estalo no início
      final tail = n - i;
      if (tail < tailLen) v *= tail / tailLen; // fecha suave
      out[i] = v;
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak > 0) {
      final g = 0.95 / peak;
      for (var i = 0; i < n; i++) {
        out[i] *= g;
      }
    }
    return out;
  }

  /// Gera [frames] amostras mono (-1..1) e avança o relógio.
  Float32List render(int frames) {
    final out = Float32List(frames);
    final end = _rendered + frames;

    // 1) Gera os ticks que caem neste bloco.
    while (_nextTick.round() < end) {
      final at = _nextTick.round();
      final muted = _isMuted(_bar) || _cb.muted;
      final accent = _accentFor(_beat, _sub);
      final audible = !muted && accent != Accent.mute;
      _events.add(ClickEvent(at, _bar, _beat, _sub, accent, audible, _bpm, hidden: _cb.muted, challenge: _cb.kind));
      if (audible) {
        final gain = switch (accent) {
          Accent.strong => 1.0,
          Accent.medium => 0.8,
          Accent.weak => _sub == 0 ? 0.6 : 0.4,
          Accent.mute => 0.0,
        };
        _voices.add(_Voice(at, _wave(_cfg.sound, accent, _sub != 0), gain));
      }
      _nextTick += _period();
      _advanceCounters();
    }

    // 2) Mistura as vozes ativas.
    final vol = _cfg.volume;
    for (final v in _voices) {
      final from = math.max(v.start, _rendered);
      final to = math.min(v.start + v.wave.length, end);
      for (var s = from; s < to; s++) {
        out[s - _rendered] += v.wave[s - v.start] * v.gain * vol;
      }
    }
    _voices.removeWhere((v) => v.start + v.wave.length <= end);
    for (var i = 0; i < frames; i++) {
      if (out[i] > 1) out[i] = 1;
      if (out[i] < -1) out[i] = -1;
    }
    _rendered = end;
    return out;
  }

  void _advanceCounters() {
    _sub++;
    if (_sub < _cfg.subdivision) return;
    _sub = 0;
    _beat++;
    if (_beat < _cfg.beatsPerBar) return;
    _beat = 0;
    _bar++;
    // Treino de andamento: só depois da contagem inicial.
    final t = _cfg.trainer;
    if (t != null && _bar > 0) {
      _barsSinceStep++;
      if (_barsSinceStep >= t.everyBars) {
        _barsSinceStep = 0;
        _baseBpm = math.min(t.maxBpm, _baseBpm + t.stepBpm);
      }
    }
    _applyChallenge(); // surpresas do modo desafio, sempre voltando ao andamento original
  }
}

/// Toque para marcar o andamento ("tap tempo").
class TapTempo {
  final int maxTaps;
  final int resetAfterMs;
  final List<int> _taps = [];
  TapTempo({this.maxTaps = 6, this.resetAfterMs = 2000});

  /// Registra um toque em [nowMs]. Devolve o BPM estimado (ou null com 1 toque).
  double? tap(int nowMs) {
    if (_taps.isNotEmpty && nowMs - _taps.last > resetAfterMs) _taps.clear();
    _taps.add(nowMs);
    if (_taps.length > maxTaps) _taps.removeAt(0);
    if (_taps.length < 2) return null;
    final avg = (_taps.last - _taps.first) / (_taps.length - 1);
    return 60000 / avg;
  }

  void reset() => _taps.clear();
}
