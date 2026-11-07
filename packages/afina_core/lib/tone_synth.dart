/// Síntese do tom de referência (diapasão) como um trecho que se repete sem
/// emendas.
///
/// Em vez de gerar o som aos pedaços em tempo real (o que falha se um pedaço
/// atrasa), calcula-se UM trecho com um número inteiro de ciclos. Quando o
/// motor de áudio o repete em laço, a fase continua perfeita: sem estalos e
/// sem depender de temporizador.
library;

import 'dart:math' as math;
import 'dart:typed_data';

enum ToneTimbre {
  /// Senoide pura: o som de um diapasão de verdade (e o mais fácil de comparar).
  fork,

  /// Um pouco mais "cheio" (flauta de afinação): audível em alto-falante pequeno.
  soft,
}

class ToneLoop {
  /// Amostras (-1..1) de exatamente [cycles] ciclos.
  final Float32List samples;
  final int sampleRate;
  final int cycles;

  /// Frequência real obtida ao repetir o trecho em laço.
  final double effectiveHz;

  ToneLoop(this.samples, this.sampleRate, this.cycles, this.effectiveHz);

  /// Erro em cents entre o pedido e o que realmente toca.
  double centsError(double requestedHz) =>
      1200 * math.log(effectiveHz / requestedHz) / math.ln2;
}

/// Gera o trecho para [freq] Hz. Escolhe o número de ciclos cujo comprimento
/// (em amostras inteiras) deixa a frequência obtida o mais perto possível da
/// pedida, com no máximo [maxSeconds] de duração.
ToneLoop buildToneLoop(
  double freq, {
  int sampleRate = 44100,
  ToneTimbre timbre = ToneTimbre.fork,
  double maxSeconds = 2.0,
}) {
  final maxCycles = math.max(1, (freq * maxSeconds).floor());
  var bestN = 1;
  var bestL = (sampleRate / freq).round();
  var bestErr = double.infinity;
  for (var n = 1; n <= maxCycles; n++) {
    final l = (n * sampleRate / freq).round();
    if (l < 8) continue;
    final eff = n * sampleRate / l;
    final err = (eff - freq).abs() / freq;
    if (err < bestErr) {
      bestErr = err;
      bestN = n;
      bestL = l;
    }
    if (err < 1e-5 && l >= sampleRate ~/ 4) break; // < 0,02 cent
  }

  final partials = switch (timbre) {
    ToneTimbre.fork => const [1.0],
    ToneTimbre.soft => const [1.0, 0.22, 0.08, 0.03],
  };
  final out = Float32List(bestL);
  var peak = 0.0;
  for (var i = 0; i < bestL; i++) {
    // fase de 0 a 2π*N: o trecho fecha exatamente sobre si mesmo
    final ph = 2 * math.pi * bestN * i / bestL;
    var v = 0.0;
    for (var h = 0; h < partials.length; h++) {
      // não deixa harmônicos passarem de Nyquist
      if (freq * (h + 1) < sampleRate / 2) v += partials[h] * math.sin((h + 1) * ph);
    }
    out[i] = v;
    if (v.abs() > peak) peak = v.abs();
  }
  final g = peak > 0 ? 0.9 / peak : 1.0;
  for (var i = 0; i < bestL; i++) {
    out[i] *= g;
  }
  return ToneLoop(out, sampleRate, bestN, bestN * sampleRate / bestL);
}

/// Empacota amostras mono (-1..1) em um arquivo WAV PCM de 16 bits.
Uint8List pcm16Wav(Float32List samples, int sampleRate) {
  final dataLen = samples.length * 2;
  final b = ByteData(44 + dataLen);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // tamanho do bloco fmt
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little); // bytes por segundo
  b.setUint16(32, 2, Endian.little); // bytes por quadro
  b.setUint16(34, 16, Endian.little); // bits
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    b.setInt16(44 + i * 2, v, Endian.little);
  }
  return b.buffer.asUint8List();
}
