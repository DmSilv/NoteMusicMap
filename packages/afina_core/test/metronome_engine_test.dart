import 'dart:typed_data';

import 'package:afina_core/metronome_engine.dart';
import 'package:test/test.dart';

/// Renderiza [total] amostras em blocos de [chunk] e junta tudo.
Float32List renderAll(MetronomeEngine e, int total, int chunk) {
  final out = Float32List(total);
  var pos = 0;
  while (pos < total) {
    final n = (total - pos) < chunk ? (total - pos) : chunk;
    out.setRange(pos, pos + n, e.render(n));
    pos += n;
  }
  return out;
}

void main() {
  const sr = 44100;

  group('posição dos ticks', () {
    test('120 BPM: tick i em i*22050 exatos, sem deriva em 10 min', () {
      final e = MetronomeEngine(sr, MetronomeConfig.signature(4, bpm: 120));
      final events = <ClickEvent>[];
      // 10 minutos = 1200 batidas
      var rendered = 0;
      while (rendered < sr * 600) {
        e.render(4096);
        rendered += 4096;
        events.addAll(e.takeEvents());
      }
      expect(events.length, greaterThanOrEqualTo(1200));
      for (var i = 0; i < 1200; i++) {
        expect(events[i].sample, i * 22050, reason: 'tick $i');
      }
    });

    test('97 BPM (período fracionário): erro < 0.5 amostra após 20 mil ticks', () {
      final e = MetronomeEngine(sr, MetronomeConfig.signature(4, bpm: 97));
      final period = sr * 60.0 / 97;
      var maxErr = 0.0;
      var idx = 0;
      var rendered = 0;
      while (idx < 20000) {
        e.render(8192);
        rendered += 8192;
        for (final ev in e.takeEvents()) {
          final err = (ev.sample - idx * period).abs();
          if (err > maxErr) maxErr = err;
          idx++;
        }
      }
      expect(rendered, greaterThan(0));
      expect(maxErr, lessThanOrEqualTo(0.5 + 1e-6));
    });

    test('tercinas: 3 cliques por tempo, igualmente espaçados', () {
      final e = MetronomeEngine(
          sr, MetronomeConfig.signature(4, bpm: 90, subdivision: 3));
      e.render(sr * 4);
      final ev = e.takeEvents();
      final period = sr * 60.0 / (90 * 3);
      for (var i = 0; i < 12; i++) {
        expect(ev[i].sample, (i * period).round());
        expect(ev[i].sub, i % 3);
        expect(ev[i].beat, (i ~/ 3) % 4);
      }
    });
  });

  group('blocos', () {
    test('renderizar em blocos diferentes gera exatamente o mesmo áudio', () {
      final cfg = MetronomeConfig.signature(5, bpm: 133, subdivision: 2);
      final a = renderAll(MetronomeEngine(sr, cfg), sr * 6, 4096);
      final b = renderAll(MetronomeEngine(sr, cfg), sr * 6, 137);
      final c = renderAll(MetronomeEngine(sr, cfg), sr * 6, 1);
      expect(b, orderedEquals(a));
      expect(c, orderedEquals(a));
    });

    test('o clique começa na amostra do tick e o resto é silêncio', () {
      final e = MetronomeEngine(sr, MetronomeConfig.signature(4, bpm: 60));
      final buf = renderAll(e, sr * 2, 1000);
      // 1º tick em 0 (rampa de ataque começa em 0); 2º em 44100.
      var firstNonZero = -1;
      for (var i = 1; i < buf.length; i++) {
        if (buf[i] != 0) {
          firstNonZero = i;
          break;
        }
      }
      expect(firstNonZero, 1);
      // Entre o fim do clique (~45 ms) e o próximo tick, silêncio total.
      for (var i = (sr * 0.06).round(); i < sr; i++) {
        expect(buf[i], 0.0, reason: 'amostra $i');
      }
      expect(buf[sr + 1], isNot(0.0));
    });

    test('pico nunca passa de 1.0, mesmo a 300 BPM com semicolcheias', () {
      final e = MetronomeEngine(
          sr, MetronomeConfig.signature(4, bpm: 300, subdivision: 4));
      final buf = renderAll(e, sr * 3, 2048);
      var peak = 0.0;
      for (final s in buf) {
        if (s.abs() > peak) peak = s.abs();
      }
      expect(peak, lessThanOrEqualTo(1.0));
      expect(peak, greaterThan(0.2));
    });
  });

  group('sons', () {
    for (final snd in ClickSound.values) {
      test('${snd.name}: sem estalo, < 60 ms, sem clipping, todos os acentos', () {
        for (final acc in [Accent.strong, Accent.medium, Accent.weak]) {
          final cfg = MetronomeConfig.signature(4, bpm: 60, sound: snd)
              .copyWith(accents: [acc, acc, acc, acc], volume: 1.0);
          final buf = renderAll(MetronomeEngine(sr, cfg), sr, 512);
          expect(buf[0], 0.0);
          var peak = 0.0;
          for (final s in buf) {
            if (s.abs() > peak) peak = s.abs();
          }
          expect(peak, greaterThan(0.3), reason: '$snd $acc');
          expect(peak, lessThanOrEqualTo(1.0));
          // depois de 60 ms, silêncio
          for (var i = (sr * 0.06).round(); i < sr; i++) {
            expect(buf[i], 0.0, reason: '$snd $acc amostra $i');
          }
        }
      });
    }
  });

  group('acentos e compassos', () {
    test('4/4 acentua o 1; 6/8 em grupos de 3 acentua 1 e 4', () {
      final e4 = MetronomeEngine(sr, MetronomeConfig.signature(4, bpm: 240));
      e4.render(sr * 2);
      final a4 = e4.takeEvents().map((e) => e.accent).take(4).toList();
      expect(a4, [Accent.strong, Accent.weak, Accent.weak, Accent.weak]);

      final e6 = MetronomeEngine(
          sr, MetronomeConfig.signature(6, bpm: 240, groupSize: 3));
      e6.render(sr * 2);
      final a6 = e6.takeEvents().map((e) => e.accent).take(6).toList();
      expect(a6, [
        Accent.strong, Accent.weak, Accent.weak,
        Accent.medium, Accent.weak, Accent.weak,
      ]);
    });

    test('tempo mudo não gera som, mas continua contando', () {
      final cfg = MetronomeConfig.signature(4, bpm: 240).copyWith(
        accents: [Accent.strong, Accent.mute, Accent.weak, Accent.mute],
      );
      final e = MetronomeEngine(sr, cfg);
      e.render(sr * 2);
      final ev = e.takeEvents().take(4).toList();
      expect(ev.map((x) => x.audible), [true, false, true, false]);
    });

    test('contagem inicial: compassos negativos, depois começa no 0', () {
      final cfg = MetronomeConfig.signature(4, bpm: 240)
          .copyWith(countInBars: 2);
      final e = MetronomeEngine(sr, cfg);
      e.render(sr * 6);
      final ev = e.takeEvents();
      expect(ev.first.bar, -2);
      expect(ev[8].bar, 0);
      expect(ev[8].beat, 0);
    });
  });

  group('mudança de andamento e treino', () {
    test('mudar o BPM vale a partir do próximo tick, sem salto', () {
      final e = MetronomeEngine(sr, MetronomeConfig.signature(4, bpm: 60));
      e.render(sr * 3 + 100); // ticks em 0, 44100, 88200, 132300
      e.update(e.config.copyWith(bpm: 120));
      e.render(sr * 3);
      final ev = e.takeEvents();
      final gaps = <int>[];
      for (var i = 1; i < ev.length; i++) {
        gaps.add(ev[i].sample - ev[i - 1].sample);
      }
      expect(gaps.first, 44100);
      expect(gaps.last, 22050);
      // Nenhum intervalo estranho: só 44100 e 22050 (e talvez um de transição).
      for (final g in gaps) {
        expect(g == 44100 || g == 22050, isTrue, reason: 'gap $g');
      }
    });

    test('treino: +10 BPM a cada 2 compassos até o teto', () {
      final cfg = MetronomeConfig.signature(4, bpm: 100).copyWith(
        trainer: const TempoTrainer(everyBars: 2, stepBpm: 10, maxBpm: 130),
      );
      final e = MetronomeEngine(sr, cfg);
      e.render(sr * 60);
      final ev = e.takeEvents();
      double bpmAtBar(int bar) =>
          ev.firstWhere((x) => x.bar == bar && x.beat == 0 && x.sub == 0).bpm;
      expect(bpmAtBar(0), 100);
      expect(bpmAtBar(1), 100);
      expect(bpmAtBar(2), 110);
      expect(bpmAtBar(4), 120);
      expect(bpmAtBar(6), 130);
      expect(bpmAtBar(8), 130); // teto
    });

    test('compassos silenciosos: toca 2, cala 1', () {
      final cfg = MetronomeConfig.signature(4, bpm: 240).copyWith(
        silent: const SilentBars(playBars: 2, muteBars: 1),
      );
      final e = MetronomeEngine(sr, cfg);
      e.render(sr * 8);
      final ev = e.takeEvents();
      bool audibleBar(int b) =>
          ev.where((x) => x.bar == b).every((x) => x.audible);
      bool silentBar(int b) =>
          ev.where((x) => x.bar == b).every((x) => !x.audible);
      expect(audibleBar(0), isTrue);
      expect(audibleBar(1), isTrue);
      expect(silentBar(2), isTrue);
      expect(audibleBar(3), isTrue);
      expect(silentBar(5), isTrue);
    });
  });

  group('tap tempo', () {
    test('toques a 500 ms = 120 BPM', () {
      final t = TapTempo();
      expect(t.tap(0), isNull);
      expect(t.tap(500), closeTo(120, 1e-9));
      expect(t.tap(1000), closeTo(120, 1e-9));
    });
    test('pausa longa reinicia a contagem', () {
      final t = TapTempo();
      t.tap(0);
      t.tap(500);
      expect(t.tap(10000), isNull);
      expect(t.tap(10750), closeTo(80, 1e-9));
    });
  });
}
