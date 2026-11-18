/// Foco no instrumento: separa o que o músico toca do que está ao redor (vozes de quem está perto, TV, conversa).
///
/// O detector de altura acha "nota" em qualquer som com altura, inclusive na fala. Aqui duas regras baratas, só sobre
/// o que o detector já mede (nível, clareza, frequência), decidem se um quadro vale para a GRADE e para o placar:
///
///  1. **Mais fraco que o instrumento.** O instrumento está perto do microfone, as vozes ao redor estão longe. Guarda-se
///     o nível recente do som limpo (a referência, que cai devagar com o silêncio) e quadros bem abaixo dela são ignorados.
///  2. **Altura que escorrega.** Fala é uma altura que anda o tempo todo e com pouca "limpeza"; nota de instrumento fica
///     parada (mesmo com vibrato, que é regular e limpo). Quadros pouco limpos e muito instáveis em seguida são ignorados.
///
/// Dart puro. O destaque ao vivo do afinador não passa por aqui (continua imediato); só o que vira registro da sessão.
library;

import 'dart:math' as math;

class InstrumentFocus {
  /// Fração da referência abaixo da qual o quadro é "ao redor" (0 desliga a regra 1).
  final double relativeFloor;

  /// Em quantos segundos a referência cai pela metade quando não há som limpo.
  final double halfLifeSeconds;

  /// Referência mínima para a regra 1 valer (nível eficaz): abaixo disso ainda não se sabe qual é o nível do instrumento.
  final double minReference;

  /// Clareza (0..1) a partir da qual um quadro é "som limpo" (conta para a referência e nunca é tratado como fala).
  final double cleanClarity;

  /// Quadros que a regra 2 olha para trás e a mudança média (cents entre quadros) que já é "escorregando".
  final int wanderFrames;
  final double wanderCents;

  /// Liga a regra 2 (altura que escorrega).
  final bool wanderRule;

  InstrumentFocus({
    this.relativeFloor = 0.22,
    this.halfLifeSeconds = 12,
    this.minReference = 0.01,
    this.cleanClarity = 0.9,
    this.wanderFrames = 10,
    this.wanderCents = 45,
    this.wanderRule = true,
  });

  double _ref = 0;
  final List<double> _logs = []; // frequências em cents (log) dos últimos quadros com nota
  final List<double> _clar = [];

  /// O nível de referência do instrumento agora (para diagnóstico).
  double get reference => _ref;

  /// Quantos quadros foram ignorados por serem mais fracos / por escorregarem (para diagnóstico).
  int quietIgnored = 0;
  int wanderIgnored = 0;

  void reset() {
    _ref = 0;
    _logs.clear();
    _clar.clear();
    quietIgnored = 0;
    wanderIgnored = 0;
  }

  /// O quadro (com nota) deve ser considerado? [rms] nível eficaz, [clarity] 0..1, [freq] Hz, [dt] segundos do quadro.
  bool accept({required double rms, required double clarity, required double freq, required double dt}) {
    _ref *= math.pow(0.5, dt / halfLifeSeconds).toDouble();
    final clean = clarity >= cleanClarity;
    if (clean && rms > _ref) _ref = rms;

    // histórico de altura para a regra 2
    if (freq > 0) {
      _logs.add(1200 * math.log(freq) / math.ln2);
      _clar.add(clarity);
      if (_logs.length > wanderFrames) {
        _logs.removeAt(0);
        _clar.removeAt(0);
      }
    }

    if (relativeFloor > 0 && _ref >= minReference && rms < _ref * relativeFloor) {
      quietIgnored++;
      return false;
    }
    if (wanderRule && !clean && _logs.length >= wanderFrames ~/ 2) {
      var sum = 0.0;
      var meanClarity = 0.0;
      for (var i = 1; i < _logs.length; i++) {
        // saltos de oitava de um quadro só não contam como escorregar (são erro do detector)
        final d = (_logs[i] - _logs[i - 1]).abs();
        sum += d > 900 ? 0 : d;
      }
      for (final c in _clar) {
        meanClarity += c;
      }
      meanClarity /= _clar.length;
      final avg = sum / (_logs.length - 1);
      if (avg > wanderCents && meanClarity < cleanClarity + 0.03) {
        wanderIgnored++;
        return false;
      }
    }
    return true;
  }
}
