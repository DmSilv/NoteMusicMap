import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

const sr = 44100;
const window = 4096;
const hop = 1024;

/// Soma de harmônicos de uma altura que varia no tempo ([freqAt] em Hz por segundo), com [noise] de ruído.
List<double> synth(double seconds, double Function(double t) freqAt, double amp, {List<double> amps = const [1, 0.7, 0.5, 0.35, 0.2], double noise = 0.0, int seed = 1}) {
  final rnd = math.Random(seed);
  final n = (seconds * sr).round();
  final out = List<double>.filled(n, 0);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    phase += 2 * math.pi * freqAt(i / sr) / sr;
    var s = 0.0;
    for (var h = 0; h < amps.length; h++) {
      s += amps[h] * math.sin((h + 1) * phase);
    }
    out[i] = amp * s + noise * (rnd.nextDouble() * 2 - 1);
  }
  return out;
}

/// Violino: notas paradas de 0,5 s (Sol3, Ré4, Lá4, Mi5) com vibrato leve.
double violinFreq(double t) {
  const midis = [55, 62, 69, 76];
  final f = etFreq(midis[(t / 0.5).floor().clamp(0, 3)].toDouble(), 440);
  return f * math.pow(2, 15 * math.sin(2 * math.pi * 5.5 * t) / 1200);
}

/// Fala: a altura anda o tempo todo (sílabas de ~150 ms, com glides de vários semitons), 110 a 230 Hz.
double speechFreq(double t) {
  final syl = (t / 0.15).floor();
  final r = math.Random(syl * 7 + 3);
  final a = 120 + r.nextDouble() * 100;
  final b = 120 + r.nextDouble() * 100;
  final x = (t / 0.15) - syl;
  return a + (b - a) * x;
}

/// Passa o sinal pelo detector e pelo foco; devolve (quadros com nota, quadros aceitos).
({int voiced, int accepted}) run(List<double> signal, InstrumentFocus focus, {int from = 0}) {
  final det = McLeodPitchDetector(sampleRate: sr, windowSize: window, minFreq: 80, maxFreq: 3200, minClarity: 0.72, minRms: 0.0018);
  var voiced = 0, accepted = 0;
  for (var end = window + from; end <= signal.length; end += hop) {
    final r = det.detect(signal.sublist(end - window, end));
    if (r == null) continue;
    voiced++;
    if (focus.accept(rms: r.rms, clarity: r.clarity, freq: r.frequency, dt: hop / sr)) accepted++;
  }
  return (voiced: voiced, accepted: accepted);
}

List<double> mix(List<double> a, List<double> b) => [for (var i = 0; i < a.length; i++) a[i] + (i < b.length ? b[i] : 0)];

void main() {
  test('o violino sozinho, com vibrato e dinâmica, passa inteiro', () {
    final v = synth(2.0, violinFreq, 0.12);
    final r = run(v, InstrumentFocus());
    expect(r.voiced, greaterThan(40));
    expect(r.accepted / r.voiced, greaterThan(0.95));
  });

  test('uma nota mais suave do próprio violino (−9 dB) ainda passa', () {
    final loud = synth(1.0, (t) => 440, 0.12);
    final soft = synth(1.0, (t) => 440, 0.04); // ~ −9,5 dB
    final r = run([...loud, ...soft], InstrumentFocus());
    expect(r.accepted / r.voiced, greaterThan(0.95));
  });

  test('voz de quem está perto (bem mais fraca) tocando junto do violino é ignorada', () {
    final violin = synth(2.0, violinFreq, 0.12);
    final voice = synth(2.0, speechFreq, 0.012, amps: const [1, 0.6, 0.4, 0.3], noise: 0.004, seed: 9);
    final focus = InstrumentFocus();
    run(violin.sublist(0, sr ~/ 2), focus); // o foco aprende o nível do violino
    // depois, só a voz ao redor (o violino parou): quadros bem mais fracos que a referência
    final r = run([...List<double>.filled(sr ~/ 4, 0), ...voice], focus);
    expect(r.voiced, greaterThan(10), reason: 'o detector achou notas na voz (senão o teste não prova nada)');
    expect(r.accepted / r.voiced, lessThan(0.2), reason: 'voz fraca não vira nota');
  });

  test('voz com a altura escorregando e pouco limpa é ignorada mesmo no mesmo volume', () {
    final voice = synth(2.0, speechFreq, 0.1, amps: const [1, 0.6, 0.4, 0.3], noise: 0.06, seed: 4);
    final r = run(voice, InstrumentFocus());
    expect(r.voiced, greaterThan(8));
    expect(r.accepted / r.voiced, lessThan(0.4));
  });

  test('"Livre" (sem a regra do nível) deixa passar o que for fraco', () {
    final loud = synth(0.6, (t) => 440, 0.12);
    final soft = synth(0.6, (t) => 392, 0.01);
    final strict = run([...loud, ...soft], InstrumentFocus());
    final free = run([...loud, ...soft], InstrumentFocus(relativeFloor: 0, wanderRule: false));
    expect(free.accepted, greaterThanOrEqualTo(strict.accepted));
    expect(free.accepted, free.voiced);
  });

  test('a referência cai com o silêncio: depois de uma pausa longa um som fraco volta a valer', () {
    final f = InstrumentFocus(halfLifeSeconds: 4);
    f.accept(rms: 0.1, clarity: 0.97, freq: 440, dt: 0.02);
    expect(f.accept(rms: 0.01, clarity: 0.97, freq: 440, dt: 0.02), isFalse);
    for (var i = 0; i < 400; i++) {
      f.accept(rms: 0.0001, clarity: 0.1, freq: 0, dt: 0.05); // 20 s de silêncio
    }
    expect(f.accept(rms: 0.01, clarity: 0.97, freq: 440, dt: 0.02), isTrue);
  });
}
