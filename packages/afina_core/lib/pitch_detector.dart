/// Detector de altura (pitch) pelo método McLeod (MPM), implementação própria
/// a partir do artigo público "A Smarter Way to Find Pitch" (McLeod & Wyvill).
///
/// Decisões de precisão:
///  - NSDF (função de diferença quadrática normalizada) em vez de
///    autocorrelação pura: não viés para lags curtos e dá "clareza" 0..1.
///  - Escolhe o PRIMEIRO pico alto (>= cutoff * maior pico), o que evita erro
///    de oitava para baixo em sons ricos em harmônicos (violino, voz).
///  - Interpolação parabólica no pico: resolução bem abaixo de 1 cent.
///  - A janela precisa cobrir pelo menos 2 períodos da nota mais grave.
library;

import 'dart:math' as math;
import 'dart:typed_data';

class PitchResult {
  final double frequency;

  /// 0..1; quanto mais perto de 1, mais periódico/confiável.
  final double clarity;
  final double rms;
  const PitchResult(this.frequency, this.clarity, this.rms);
}

/// Por que a última análise não devolveu nota (para o diagnóstico da captação).
enum PitchReject {
  /// Houve nota.
  none('ok'),

  /// Sinal abaixo do nível mínimo.
  quiet('sinal fraco'),

  /// Nenhum período encontrado (ruído, silêncio, som sem altura).
  noPeak('sem altura definida'),

  /// Achou um período, mas pouco "limpo" (abaixo da clareza mínima).
  unclear('som pouco limpo'),

  /// Frequência fora da faixa do instrumento.
  range('fora da faixa');

  final String label;
  const PitchReject(this.label);
}

class McLeodPitchDetector {
  /// Medidas da última chamada de [detect], mesmo quando não houve nota.
  double lastRms = 0;
  double lastClarity = 0;
  double lastFreq = 0;
  PitchReject lastReject = PitchReject.quiet;

  final int sampleRate;
  final int windowSize;
  final double minFreq;
  final double maxFreq;
  double cutoff;

  /// Clareza mínima (0..1). Menor = aceita sons menos "limpos" (voz, ar, ruído).
  double minClarity;

  /// Nível mínimo de sinal. Menor = ouve notas mais fracas.
  double minRms;

  late final int _tauMax;
  late final int _tauMin;
  late final Float64List _nsdf;

  McLeodPitchDetector({
    required this.sampleRate,
    this.windowSize = 4096,
    this.minFreq = 40,
    this.maxFreq = 2200,
    this.cutoff = 0.93,
    this.minClarity = 0.85,
    this.minRms = 0.004,
  }) {
    _tauMax = math.min(windowSize ~/ 2, (sampleRate / minFreq).ceil());
    _tauMin = math.max(2, (sampleRate / maxFreq).floor());
    _nsdf = Float64List(_tauMax + 2);
  }

  /// [buf] deve ter exatamente [windowSize] amostras (-1..1).
  PitchResult? detect(List<double> buf, {int offset = 0}) {
    assert(buf.length >= offset + windowSize);
    final n = windowSize;

    var energy = 0.0;
    for (var i = 0; i < n; i++) {
      final v = buf[offset + i];
      energy += v * v;
    }
    final rms = math.sqrt(energy / n);
    lastRms = rms;
    lastClarity = 0;
    lastFreq = 0;
    if (rms < minRms) {
      lastReject = PitchReject.quiet;
      return null;
    }

    // NSDF direto: O(n * tauMax). Rápido o bastante para ~20 quadros/s.
    final nsdf = _nsdf;
    for (var tau = 0; tau <= _tauMax; tau++) {
      var acf = 0.0;
      var m = 0.0;
      final lim = n - tau;
      for (var j = 0; j < lim; j++) {
        final a = buf[offset + j];
        final b = buf[offset + j + tau];
        acf += a * b;
        m += a * a + b * b;
      }
      nsdf[tau] = m > 0 ? 2 * acf / m : 0;
    }

    // Picos-chave: o máximo de cada lóbulo positivo depois do primeiro cruzamento.
    var tau = 1;
    while (tau < _tauMax && nsdf[tau] > 0) {
      tau++;
    }
    final peaks = <int>[];
    var bestPeakVal = 0.0;
    while (tau < _tauMax) {
      while (tau < _tauMax && nsdf[tau] <= 0) {
        tau++;
      }
      var peakIdx = -1;
      var peakVal = 0.0;
      while (tau < _tauMax && nsdf[tau] > 0) {
        if (nsdf[tau] > peakVal) {
          peakVal = nsdf[tau];
          peakIdx = tau;
        }
        tau++;
      }
      if (peakIdx >= _tauMin && peakIdx > 1 && peakIdx < _tauMax) {
        peaks.add(peakIdx);
        if (peakVal > bestPeakVal) bestPeakVal = peakVal;
      }
    }
    if (peaks.isEmpty) {
      lastReject = PitchReject.noPeak;
      return null;
    }

    final threshold = cutoff * bestPeakVal;
    var chosen = peaks.first;
    for (final p in peaks) {
      if (nsdf[p] >= threshold) {
        chosen = p;
        break;
      }
    }

    // Interpolação parabólica.
    final a = nsdf[chosen - 1];
    final b = nsdf[chosen];
    final c = nsdf[chosen + 1];
    final denom = a - 2 * b + c;
    final shift = denom == 0 ? 0.0 : 0.5 * (a - c) / denom;
    final tauRefined = chosen + shift;
    final clarity = b - 0.25 * (a - c) * shift;
    final freq = sampleRate / tauRefined;
    lastClarity = clarity.clamp(0.0, 1.0);
    lastFreq = freq;
    if (clarity < minClarity) {
      lastReject = PitchReject.unclear;
      return null;
    }
    if (freq < minFreq || freq > maxFreq) {
      lastReject = PitchReject.range;
      return null;
    }
    lastReject = PitchReject.none;
    return PitchResult(freq, clarity.clamp(0.0, 1.0), rms);
  }
}

/// Ajuste do detector para o instrumento: janela curta e faixa de frequências
/// estreita deixam a leitura bem mais RÁPIDA (notas rápidas) e barata.
///
/// O custo do detector cresce com (janela × maior período). Para um violino
/// (Sol3 = 196 Hz) basta uma janela de 2048 amostras e período máximo de ~280
/// amostras, contra 4096 e 1100 do ajuste geral: cerca de 7 vezes menos conta
/// e uma leitura nova a cada ~17 ms em vez de ~35 ms.
class DetectorProfile {
  final int window;
  final int hop;
  final double minFreq;
  final double maxFreq;
  const DetectorProfile(this.window, this.hop, this.minFreq, this.maxFreq);

  /// Perfil para um instrumento cuja nota mais grave tem [lowestHz]. A janela
  /// cobre pelo menos 4 períodos da nota mais grave (com folga de 20% para
  /// cordas desafinadas).
  factory DetectorProfile.forLowest(double lowestHz, {int sampleRate = 44100}) {
    final minF = (lowestHz * 0.8).clamp(25.0, 400.0).toDouble();
    var w = 1024;
    while (w < 4096 && w < 4 * sampleRate / minF) {
      w *= 2;
    }
    // Passo curto (~12 ms) nas janelas pequenas: a nota nova é vista mais cedo.
    // Janelas grandes (graves) mantêm o passo longo para poupar bateria.
    return DetectorProfile(w, w <= 2048 ? 512 : 768, minF, 3200);
  }
}

/// Detector com janela adaptativa: usa a janela curta quando a nota anterior era
/// aguda (muitos períodos cabem nela) e uma média quando era grave. Janela menor =
/// leitura mais rápida; os testes mostram a mesma precisão. Instrumentos de janela
/// grande (violoncelo, contrabaixo) não são alterados.
class AdaptiveWindowDetector {
  /// Detectores do mais longo ao mais curto, com a frequência mínima da nota
  /// anterior para usar cada um.
  final List<McLeodPitchDetector> _dets;
  final List<double> _from;
  double _lastFreq = 0;
  McLeodPitchDetector _used;

  AdaptiveWindowDetector._(this._dets, this._from) : _used = _dets.first;

  factory AdaptiveWindowDetector.forProfile(DetectorProfile p, {int sampleRate = 44100}) {
    McLeodPitchDetector mk(int w) => McLeodPitchDetector(
        sampleRate: sampleRate, windowSize: w, minFreq: p.minFreq, maxFreq: p.maxFreq);
    if (p.window == 2048) {
      // Violino/viola: grave (< ~1,9x o limite inferior) 1536; agudo 1024.
      return AdaptiveWindowDetector._([mk(1536), mk(1024)], [0, p.minFreq * 1.875]);
    }
    return AdaptiveWindowDetector._([mk(p.window)], [0]);
  }

  /// Amostras que o chamador deve fornecer (a janela do perfil, mais antiga primeiro).
  int get inputSize => _dets.map((d) => d.windowSize).reduce(math.max);

  /// Detector usado na última chamada (para ler as medidas de diagnóstico).
  McLeodPitchDetector get last => _used;

  set minClarity(double v) {
    for (final d in _dets) {
      d.minClarity = v;
    }
  }

  set minRms(double v) {
    for (final d in _dets) {
      d.minRms = v;
    }
  }

  /// [buf] tem [inputSize] amostras (a mais antiga primeiro); a janela escolhida
  /// usa as mais recentes.
  PitchResult? detect(List<double> buf) {
    var k = 0;
    for (var i = 0; i < _dets.length; i++) {
      if (_lastFreq >= _from[i]) k = i;
    }
    final d = _dets[k];
    _used = d;
    final r = d.detect(buf, offset: buf.length - d.windowSize);
    _lastFreq = r?.frequency ?? 0;
    return r;
  }

  void reset() => _lastFreq = 0;
}
