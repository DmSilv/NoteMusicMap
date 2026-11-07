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

class McLeodPitchDetector {
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
  PitchResult? detect(List<double> buf) {
    assert(buf.length >= windowSize);
    final n = windowSize;

    var energy = 0.0;
    for (var i = 0; i < n; i++) {
      energy += buf[i] * buf[i];
    }
    final rms = math.sqrt(energy / n);
    if (rms < minRms) return null;

    // NSDF direto: O(n * tauMax). Rápido o bastante para ~20 quadros/s.
    final nsdf = _nsdf;
    for (var tau = 0; tau <= _tauMax; tau++) {
      var acf = 0.0;
      var m = 0.0;
      final lim = n - tau;
      for (var j = 0; j < lim; j++) {
        final a = buf[j];
        final b = buf[j + tau];
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
    if (peaks.isEmpty) return null;

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
    if (clarity < minClarity) return null;

    final freq = sampleRate / tauRefined;
    if (freq < minFreq || freq > maxFreq) return null;
    return PitchResult(freq, clarity.clamp(0.0, 1.0), rms);
  }
}
