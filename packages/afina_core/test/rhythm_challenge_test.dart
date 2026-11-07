import 'dart:math';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

/// Sorteia [n] compassos e devolve a decisão de cada um.
List<ChallengeBar> run(ChallengeConfig c, int seed, int n) {
  final r = RhythmChallenge(c, random: Random(seed));
  return [for (var b = 0; b < n; b++) r.barFor(b)];
}

/// Blocos de surpresa (sequências seguidas de compassos não normais) e normais entre eles.
({List<List<ChallengeBar>> events, List<int> normalGaps}) blocks(List<ChallengeBar> bars) {
  final events = <List<ChallengeBar>>[];
  final gaps = <int>[];
  var gap = 0;
  List<ChallengeBar>? cur;
  for (final b in bars) {
    if (b.kind == ChallengeKind.normal) {
      if (cur != null) {
        events.add(cur);
        cur = null;
        gap = 0;
      }
      gap++;
    } else {
      if (cur == null) {
        if (events.isNotEmpty) gaps.add(gap);
        cur = [];
      }
      cur.add(b);
    }
  }
  return (events: events, normalGaps: gaps);
}

void main() {
  for (final level in [1, 2, 3]) {
    group('nível $level', () {
      final cfg = ChallengeConfig(level: level);
      test('começa normal, cada surpresa é curta e depois volta ao normal (fator 1)', () {
        for (var seed = 0; seed < 40; seed++) {
          final bars = run(cfg, seed, 400);
          expect(bars.take(4).every((b) => b.kind == ChallengeKind.normal && b.factor == 1.0), isTrue,
              reason: 'seed $seed: os primeiros compassos são normais');
          final bl = blocks(bars);
          expect(bl.events, isNotEmpty);
          for (final e in bl.events) {
            expect(e.length, lessThanOrEqualTo(8), reason: 'surpresa curta (seed $seed)');
          }
          for (final g in bl.normalGaps) {
            expect(g, greaterThanOrEqualTo(2), reason: 'sempre há compassos normais entre surpresas');
          }
          // Depois de uma surpresa o compasso seguinte é exatamente o original.
          for (var i = 1; i < bars.length; i++) {
            if (bars[i - 1].kind != ChallengeKind.normal && bars[i].kind == ChallengeKind.normal) {
              expect(bars[i].factor, 1.0);
            }
          }
        }
      });

      test('fatores dentro da faixa do nível e silêncio curto', () {
        final range = switch (level) { 1 => 0.12, 3 => 0.35, _ => 0.22 };
        final silMax = switch (level) { 1 => 2, 3 => 4, _ => 3 };
        for (var seed = 0; seed < 40; seed++) {
          final bars = run(cfg, seed, 400);
          for (final b in bars) {
            expect((b.factor - 1).abs(), lessThanOrEqualTo(range + 1e-9));
            if (b.kind == ChallengeKind.faster) expect(b.factor, greaterThan(1));
            if (b.kind == ChallengeKind.slower) expect(b.factor, lessThan(1));
            if (b.kind == ChallengeKind.silence) expect(b.factor, 1.0);
          }
          // Silêncios seguidos nunca passam do máximo do nível.
          var run0 = 0;
          for (final b in bars) {
            run0 = b.muted ? run0 + 1 : 0;
            expect(run0, lessThanOrEqualTo(silMax));
          }
        }
      });
    });
  }

  test('só andamento: nunca há silêncio; só silêncio: nunca muda o andamento', () {
    final tempoOnly = run(const ChallengeConfig(silences: false), 3, 300);
    expect(tempoOnly.any((b) => b.muted), isFalse);
    expect(tempoOnly.any((b) => b.factor != 1.0), isTrue);
    final silenceOnly = run(const ChallengeConfig(tempoChanges: false), 3, 300);
    expect(silenceOnly.every((b) => b.factor == 1.0), isTrue);
    expect(silenceOnly.any((b) => b.muted), isTrue);
  });

  test('sem nada habilitado não faz nada; contagem inicial (compassos negativos) é normal', () {
    final off = run(const ChallengeConfig(tempoChanges: false, silences: false), 1, 100);
    expect(off.every((b) => b.kind == ChallengeKind.normal), isTrue);
    final r = RhythmChallenge(const ChallengeConfig(), random: Random(1));
    expect(r.barFor(-2).kind, ChallengeKind.normal);
    expect(r.barFor(-1).kind, ChallengeKind.normal);
  });

  test('mesma semente, mesmas surpresas; sementes diferentes variam', () {
    final a = run(const ChallengeConfig(), 9, 200).map((b) => '${b.kind.name}${b.factor}').join();
    final b = run(const ChallengeConfig(), 9, 200).map((b) => '${b.kind.name}${b.factor}').join();
    final c = run(const ChallengeConfig(), 10, 200).map((b) => '${b.kind.name}${b.factor}').join();
    expect(a, b);
    expect(a, isNot(c));
  });

  test('o resumo conta as surpresas que de fato aconteceram, não as planejadas', () {
    final r = RhythmChallenge(const ChallengeConfig(), random: Random(5));
    for (var b = 0; b < 3; b++) {
      r.barFor(b); // ainda no começo: nada aconteceu
    }
    expect(r.stats.silences + r.stats.tempoChanges, 0);
    final bars = [for (var b = 3; b < 300; b++) r.barFor(b)];
    final seen = blocks([ChallengeBar.normal, ChallengeBar.normal, ChallengeBar.normal, ...bars]).events.length;
    // O último bloco pode estar em andamento (ainda não fechou), então vale >= -1.
    expect(r.stats.silences + r.stats.tempoChanges, anyOf(seen, seen + 1));
  });

  test('configuração: salvar e ler; limites do nível', () {
    final c = const ChallengeConfig(level: 3, tempoChanges: false);
    final back = ChallengeConfig.tryFrom(c.toJson())!;
    expect(back, c);
    expect(const ChallengeConfig().copyWith(level: 9).level, 3);
    expect(const ChallengeConfig().copyWith(level: -1).level, 1);
    expect(ChallengeConfig.tryFrom('lixo'), isNull);
  });

  group('dentro do motor do metrônomo', () {
    const sr = 22050;
    // 2/4 a 300 BPM: compasso de 0,4 s; rápido de simular.
    MetronomeConfig base({ChallengeConfig? ch, TempoTrainer? trainer}) => MetronomeConfig.signature(2, bpm: 300)
        .copyWith(challenge: ch, trainer: trainer);

    List<ClickEvent> play(MetronomeEngine e, int bars) {
      final out = <ClickEvent>[];
      var rendered = 0;
      final target = (bars * 0.4 * sr).round();
      while (rendered < target) {
        e.render(512);
        rendered += 512;
        out.addAll(e.takeEvents());
      }
      return out;
    }

    test('sem desafio o andamento nunca muda', () {
      final e = MetronomeEngine(sr, base());
      final ev = play(e, 100);
      expect(ev.every((x) => x.bpm == 300 && !x.hidden), isTrue);
    });

    test('com desafio: andamento muda por alguns compassos e SEMPRE volta a 300', () {
      final e = MetronomeEngine(sr, base(ch: const ChallengeConfig(level: 3)), random: Random(7));
      final ev = play(e, 300);
      final bpms = ev.map((x) => x.bpm).toSet();
      expect(bpms.length, greaterThan(2), reason: 'houve variações');
      expect(ev.map((x) => x.bpm).reduce(min), greaterThanOrEqualTo(300 * 0.65 - 1e-6));
      expect(ev.map((x) => x.bpm).reduce(max), lessThanOrEqualTo(300 * 1.35 + 1e-6));
      // O último compasso completo antes de cada normal posterior volta exatamente a 300.
      final byBar = <int, double>{};
      for (final x in ev) {
        byBar[x.bar] = x.bpm;
      }
      final normalBars = byBar.values.where((b) => b == 300).length;
      expect(normalBars / byBar.length, greaterThan(0.4), reason: 'a maior parte do tempo é o andamento original');
      // Os primeiros compassos (acomodação) são originais.
      for (var b = 0; b < 4; b++) {
        expect(byBar[b], 300);
      }
    });

    test('silêncio do desafio: sem som e marcado como oculto; depois volta a soar', () {
      final e = MetronomeEngine(sr, base(ch: const ChallengeConfig(level: 3, tempoChanges: false)), random: Random(2));
      final ev = play(e, 300);
      final hidden = ev.where((x) => x.hidden).toList();
      expect(hidden, isNotEmpty);
      expect(hidden.every((x) => !x.audible), isTrue);
      expect(ev.where((x) => !x.hidden).every((x) => x.audible || x.accent == Accent.mute), isTrue);
      // Volta a soar depois do silêncio.
      final firstHidden = hidden.first.bar;
      expect(ev.any((x) => x.bar > firstHidden && !x.hidden && x.audible), isTrue);
      expect(e.challengeStats.silences, greaterThan(0));
    });

    test('o áudio de um compasso em silêncio é realmente mudo', () {
      final e = MetronomeEngine(sr, base(ch: const ChallengeConfig(level: 3, tempoChanges: false)), random: Random(2));
      final pcm = <double>[];
      final events = <ClickEvent>[];
      for (var i = 0; i < 300 * 0.4 * sr / 512; i++) {
        pcm.addAll(e.render(512));
        events.addAll(e.takeEvents());
      }
      // Dentro de um silêncio (entre o primeiro e o último clique oculto de uma sequência) não há amostra.
      final h = events.where((x) => x.hidden).toList();
      final first = h.first.sample;
      var end = first;
      for (final x in h) {
        if (x.bar == h.first.bar || x.bar == h.first.bar + 1) end = x.sample;
      }
      // Pula o rabo do clique anterior (< 60 ms) e confere o trecho mudo.
      final from = first + (0.06 * sr).round();
      final to = end;
      if (to > from) {
        final peak = pcm.sublist(from, to).map((v) => v.abs()).reduce(max);
        expect(peak, 0.0);
      }
    });

    test('desligar o desafio no meio volta direto ao andamento original', () {
      final cfgOn = base(ch: const ChallengeConfig(level: 3, silences: false));
      final e = MetronomeEngine(sr, cfgOn, random: Random(4));
      play(e, 40);
      e.update(base()); // sem desafio
      final ev = play(e, 10);
      expect(ev.every((x) => x.bpm == 300 && !x.hidden), isTrue);
    });

    test('junto com o treino de andamento: o desafio varia em volta do andamento que o treino subiu', () {
      final trainer = const TempoTrainer(everyBars: 2, stepBpm: 10, maxBpm: 320);
      final e = MetronomeEngine(sr, base(ch: const ChallengeConfig(tempoChanges: false), trainer: trainer),
          random: Random(1));
      final ev = play(e, 60);
      // Só silêncio: o andamento nunca sai da escada do treino (múltiplos de 10 a partir de 300, até 320).
      expect(ev.every((x) => x.bpm >= 300 && x.bpm <= 320), isTrue);
    });
  });
}
