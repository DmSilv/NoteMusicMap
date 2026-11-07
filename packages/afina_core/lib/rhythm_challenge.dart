/// Modo desafio do metrônomo ("sabotagem"): de vez em quando, de surpresa, o
/// andamento muda por alguns compassos ou o metrônomo fica mudo, e depois volta
/// sempre ao andamento que a pessoa configurou. Serve para treinar a percepção do
/// pulso e manter o tempo "por dentro".
///
/// Dart puro e determinístico (o sorteio vem de um [Random] que se pode fixar), então
/// dá para testar. A cada compasso o motor pergunta [RhythmChallenge.barFor] o que
/// fazer naquele compasso.
library;

import 'dart:math';

/// O que acontece num compasso do desafio.
enum ChallengeKind { normal, faster, slower, silence }

/// Decisão para UM compasso: multiplicador do andamento e se fica mudo.
class ChallengeBar {
  final ChallengeKind kind;

  /// 1.0 = andamento original; 1.2 = 20% mais rápido; 0.8 = 20% mais lento.
  final double factor;
  const ChallengeBar(this.kind, this.factor);

  static const normal = ChallengeBar(ChallengeKind.normal, 1.0);
  static const silence = ChallengeBar(ChallengeKind.silence, 1.0);

  /// Metrônomo mudo (som e marcação visual).
  bool get muted => kind == ChallengeKind.silence;
}

/// Ajustes do desafio.
class ChallengeConfig {
  /// 1 = leve, 2 = médio, 3 = intenso.
  final int level;

  /// Pode mudar o andamento (mais rápido / mais lento, ou alternar).
  final bool tempoChanges;

  /// Pode ficar em silêncio por alguns compassos.
  final bool silences;

  const ChallengeConfig({this.level = 2, this.tempoChanges = true, this.silences = true});

  /// Sem nada habilitado o desafio não faz nada.
  bool get active => tempoChanges || silences;

  ChallengeConfig copyWith({int? level, bool? tempoChanges, bool? silences}) => ChallengeConfig(
      level: (level ?? this.level).clamp(1, 3),
      tempoChanges: tempoChanges ?? this.tempoChanges,
      silences: silences ?? this.silences);

  Map<String, dynamic> toJson() => {'l': level, 't': tempoChanges, 's': silences};

  static ChallengeConfig? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      return ChallengeConfig(
        level: ((m['l'] as num?)?.toInt() ?? 2).clamp(1, 3),
        tempoChanges: m['t'] != false,
        silences: m['s'] != false,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ChallengeConfig &&
      other.level == level &&
      other.tempoChanges == tempoChanges &&
      other.silences == silences;

  @override
  int get hashCode => Object.hash(level, tempoChanges, silences);
}

/// Resumo do que o desafio fez (para mostrar no fim).
class ChallengeStats {
  final int tempoChanges;
  final int silences;
  const ChallengeStats(this.tempoChanges, this.silences);
}

/// Sorteia, compasso a compasso, as surpresas. Regras:
/// - os primeiros compassos são normais (a pessoa se acomoda);
/// - entre duas surpresas há sempre compassos normais (no mínimo 2);
/// - toda surpresa é temporária e depois volta ao andamento original (fator 1.0);
/// - o silêncio dura poucos compassos e o retorno vem de surpresa.
class RhythmChallenge {
  final ChallengeConfig config;
  final Random _rnd;

  int? _origin; // primeiro compasso visto
  int _next = 0; // próximo compasso relativo que o sorteio vai entregar
  int _tempo = 0, _sil = 0;
  int _counted = -1; // último compasso de início de surpresa já contado
  final Map<int, ChallengeKind> _starts = {}; // compasso relativo -> tipo da surpresa que começa ali

  RhythmChallenge(this.config, {Random? random}) : _rnd = random ?? Random();

  ChallengeStats get stats => ChallengeStats(_tempo, _sil);

  // Faixas por nível: (compassos normais mín, máx), (mudança de andamento, % mín, máx),
  // (duração da surpresa mín, máx), (silêncio mín, máx).
  ({int nMin, int nMax, int pMin, int pMax, int dMin, int dMax, int sMin, int sMax}) get _lv => switch (config.level) {
        1 => (nMin: 6, nMax: 10, pMin: 6, pMax: 12, dMin: 2, dMax: 3, sMin: 1, sMax: 2),
        3 => (nMin: 2, nMax: 5, pMin: 20, pMax: 35, dMin: 2, dMax: 6, sMin: 2, sMax: 4),
        _ => (nMin: 4, nMax: 8, pMin: 12, pMax: 22, dMin: 2, dMax: 4, sMin: 2, sMax: 3),
      };

  int _between(int a, int b) => a + _rnd.nextInt(b - a + 1);

  /// O compasso [bar] (a partir de 0; a contagem inicial, negativa, é sempre normal).
  /// Chame com compassos consecutivos e crescentes.
  ChallengeBar barFor(int bar) {
    if (bar < 0 || !config.active) return ChallengeBar.normal;
    _origin ??= bar;
    final rel = bar - _origin!;
    // Garante que a fila cobre até o compasso pedido.
    while (_next <= rel) {
      _refill();
    }
    // Conta a surpresa quando ela de fato começa (e não quando foi sorteada).
    final started = _starts[rel];
    if (started != null && rel > _counted) {
      _counted = rel;
      if (started == ChallengeKind.silence) {
        _sil++;
      } else {
        _tempo++;
      }
    }
    return _take(rel);
  }

  final List<ChallengeBar> _plan = []; // plano compasso a compasso (relativo ao primeiro)

  ChallengeBar _take(int rel) => rel < _plan.length ? _plan[rel] : ChallengeBar.normal;

  void _refill() {
    // 1) Bloco normal (o primeiro é um pouco mais longo para a pessoa se acomodar).
    final lv = _lv;
    final normals = _between(lv.nMin, lv.nMax) + (_plan.isEmpty ? 2 : 0);
    for (var i = 0; i < normals; i++) {
      _plan.add(ChallengeBar.normal);
    }
    // 2) Uma surpresa.
    final kinds = <ChallengeKind>[
      if (config.tempoChanges) ChallengeKind.faster,
      if (config.tempoChanges) ChallengeKind.slower,
      if (config.silences) ChallengeKind.silence,
    ];
    final kind = kinds[_rnd.nextInt(kinds.length)];
    switch (kind) {
      case ChallengeKind.silence:
        _starts[_plan.length] = ChallengeKind.silence;
        final n = _between(lv.sMin, lv.sMax);
        for (var i = 0; i < n; i++) {
          _plan.add(ChallengeBar.silence);
        }
      case ChallengeKind.faster:
      case ChallengeKind.slower:
        // Nos níveis 2 e 3, às vezes alterna: acelera e depois freia (ou o contrário).
        _starts[_plan.length] = kind;
        final mix = config.level >= 2 && _rnd.nextDouble() < 0.35;
        final first = kind;
        final second = kind == ChallengeKind.faster ? ChallengeKind.slower : ChallengeKind.faster;
        void blocks(ChallengeKind k, int n) {
          final pct = _between(lv.pMin, lv.pMax) / 100.0;
          final f = k == ChallengeKind.faster ? 1 + pct : 1 - pct;
          for (var i = 0; i < n; i++) {
            _plan.add(ChallengeBar(k, f));
          }
        }
        if (mix) {
          blocks(first, _between(2, max(2, lv.dMax ~/ 2 + 1)));
          blocks(second, _between(2, max(2, lv.dMax ~/ 2 + 1)));
        } else {
          blocks(first, _between(lv.dMin, lv.dMax));
        }
      case ChallengeKind.normal:
        break;
    }
    _next = _plan.length;
  }
}
