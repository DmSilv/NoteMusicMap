// Mede quão ALTO o metrônomo soa: `dart run tool/metro_loudness.dart` (dentro de packages/afina_core).
// Para cada som e cada acento, renderiza um clique no volume máximo e mostra:
//  - pico (0 a 1: o teto é 1,0, sem estourar);
//  - energia em dB relativos a 1 (RMS da janela de 100 ms depois do clique);
//  - "sonoridade": energia ponderada pelo ouvido (curva A, IEC 61672), em dB. É a que melhor acompanha o que se ESCUTA:
//    cliques curtos e agudos têm pico alto mas energia baixa, por isso soam fracos.
// Use o número da sonoridade para comparar antes e depois de mexer nos sons.
// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';

const sr = 48000;

double aWeightDb(double f) {
  final f2 = f * f;
  final ra = (math.pow(12194, 2) * f2 * f2) /
      ((f2 + math.pow(20.6, 2)) * math.sqrt((f2 + math.pow(107.7, 2)) * (f2 + math.pow(737.9, 2))) * (f2 + math.pow(12194, 2)));
  return 20 * (math.log(ra) / math.ln10) + 2.0;
}

/// Energia ponderada pelo ouvido (dB) de [x]: soma dos |X(f)|² vezes o peso A, de 100 Hz a 8 kHz.
double perceived(List<double> x) {
  var sum = 0.0;
  for (var f = 100.0; f <= 8000; f += 10) {
    var re = 0.0, im = 0.0;
    final w = 2 * math.pi * f / sr;
    for (var i = 0; i < x.length; i++) {
      re += x[i] * math.cos(w * i);
      im -= x[i] * math.sin(w * i);
    }
    final p = (re * re + im * im) / (x.length * x.length);
    sum += p * math.pow(10, aWeightDb(f) / 10);
  }
  return 10 * (math.log(sum + 1e-18) / math.ln10);
}

double rmsDb(List<double> x) {
  var s = 0.0;
  for (final v in x) {
    s += v * v;
  }
  return 10 * (math.log(s / x.length + 1e-18) / math.ln10);
}

void main(List<String> args) {
  final names = {for (final s in ClickSound.values) s: s.name};
  final rows = <List<String>>[];
  var sumPerceived = 0.0, n = 0;
  for (final snd in ClickSound.values) {
    for (final acc in [Accent.strong, Accent.medium, Accent.weak]) {
      final cfg = MetronomeConfig.signature(4, bpm: 60, sound: snd).copyWith(accents: [acc, acc, acc, acc], volume: 1.0);
      final e = MetronomeEngine(sr, cfg);
      final pcm = e.render(sr); // 1 s a 60 BPM = 1 clique no instante 0
      final seg = [for (var i = 0; i < (sr * 0.1).round(); i++) pcm[i].toDouble()];
      var peak = 0.0;
      for (final v in seg) {
        if (v.abs() > peak) peak = v.abs();
      }
      final p = perceived(seg);
      sumPerceived += p;
      n++;
      rows.add([names[snd]!, acc.name, peak.toStringAsFixed(2), rmsDb(seg).toStringAsFixed(1), p.toStringAsFixed(1)]);
    }
  }
  print('som      acento   pico   energia(dB)  sonoridade(dB)');
  for (final r in rows) {
    print('${r[0].padRight(8)} ${r[1].padRight(8)} ${r[2].padRight(6)} ${r[3].padLeft(10)}  ${r[4].padLeft(12)}');
  }
  print('\nMÉDIA da sonoridade: ${(sumPerceived / n).toStringAsFixed(1)} dB  (quanto MAIOR, mais alto soa; +3 dB = o dobro de energia, +10 dB = soa cerca de 2x mais alto)');
}
