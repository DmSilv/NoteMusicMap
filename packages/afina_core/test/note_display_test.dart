import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

TrackedNote note(int midi, [double cents = 0]) =>
    TrackedNote(midi, 440, 440, cents, 0.95);

/// Alimenta o filtro com [n] por [seconds], num quadro a cada 30 ms, a partir
/// de [t0]. Devolve a lista do que foi exibido em cada quadro.
List<TrackedNote?> feed(NoteDisplayFilter f, TrackedNote? n, double t0, double seconds) {
  final out = <TrackedNote?>[];
  for (var t = 0.0; t < seconds - 1e-9; t += 0.03) {
    out.add(f.update(n, t0 + t));
  }
  return out;
}

void main() {
  group('NoteDisplayFilter', () {
    test('a primeira nota depois do silêncio aparece na hora', () {
      final f = NoteDisplayFilter();
      expect(f.update(note(60), 1.0)?.midi, 60);
    });

    test('mesma nota: o desvio acompanha ao vivo', () {
      final f = NoteDisplayFilter();
      f.update(note(60, 2), 0);
      expect(f.update(note(60, -7), 0.03)?.cents, -7);
      expect(f.update(note(60, 11), 0.06)?.cents, 11);
    });

    test('nota diferente só assume depois do tempo de confirmação e de permanência', () {
      final f = NoteDisplayFilter(); // commit 0,10 / dwell 0,18
      feed(f, note(60), 0, 0.6); // Dó em destaque há bastante tempo
      final out = feed(f, note(62), 0.6, 0.6); // Ré começa em 0,6
      // nos primeiros 0,09 s ainda é Dó
      expect(out.where((e) => e!.midi == 60).length, greaterThanOrEqualTo(3));
      expect(out.first!.midi, 60);
      // e depois vira Ré e fica
      expect(out.last!.midi, 62);
      final firstRe = out.indexWhere((e) => e!.midi == 62);
      expect(firstRe * 0.03, greaterThanOrEqualTo(0.09));
      expect(firstRe * 0.03, lessThan(0.17));
    });

    test('tempo mínimo: a nota fica pelo menos o "dwell" na tela', () {
      final f = NoteDisplayFilter(); // dwell 0,18
      f.update(note(60), 0); // Dó aparece em 0
      TrackedNote? at;
      var changedAt = -1.0;
      for (var t = 0.03; t < 1.5; t += 0.03) {
        at = f.update(note(62), t); // Ré estável desde 0,03
        if (at!.midi == 62 && changedAt < 0) changedAt = t;
      }
      // Ré já era estável em 0,13, mas Dó só pode sair depois de 0,18
      expect(changedAt, greaterThanOrEqualTo(0.18));
      expect(changedAt, lessThan(0.25));
    });

    test('nota de passagem rápida nunca aparece', () {
      final f = NoteDisplayFilter();
      feed(f, note(60), 0, 1.0);
      final seen = <int>{};
      for (final e in feed(f, note(61), 1.0, 0.12)) {
        seen.add(e!.midi); // semitom intermediário por 0,12 s
      }
      for (final e in feed(f, note(60), 1.12, 0.5)) {
        seen.add(e!.midi);
      }
      expect(seen, {60});
    });

    test('glissando por várias notas: só a nota onde pousou aparece', () {
      final f = NoteDisplayFilter();
      feed(f, note(60), 0, 1.0);
      final seen = <int>[];
      var t = 1.0;
      for (final m in [61, 62, 63, 64]) {
        for (final e in feed(f, note(m), t, 0.1)) {
          seen.add(e!.midi); // passa 0,1 s em cada semitom
        }
        t += 0.1;
      }
      for (final e in feed(f, note(65), t, 0.8)) {
        seen.add(e!.midi); // pousa em Fá
      }
      expect(seen.toSet(), {60, 65});
      expect(seen.last, 65);
    });

    test('candidatas que se alternam não chegam a assumir', () {
      final f = NoteDisplayFilter();
      feed(f, note(60), 0, 1.0);
      final seen = <int>{};
      var t = 1.0;
      for (var i = 0; i < 20; i++) {
        seen.add(f.update(note(i.isEven ? 62 : 63), t)!.midi);
        t += 0.03;
      }
      expect(seen, {60});
    });

    test('enquanto espera, a nota atual fica parada (desvio congelado)', () {
      final f = NoteDisplayFilter();
      f.update(note(60, 4), 0);
      f.update(note(60, 6), 0.03);
      final held = f.update(note(62, -20), 0.06)!;
      expect(held.midi, 60);
      expect(held.cents, 6); // não vira -20 nem some
    });

    test('silêncio: espera o tempo de soltura e apaga; a próxima nota volta na hora', () {
      final f = NoteDisplayFilter(); // release 0,25
      f.update(note(60), 0);
      expect(f.update(null, 0.1)?.midi, 60);
      expect(f.update(null, 0.24)?.midi, 60);
      expect(f.update(null, 0.26), isNull);
      expect(f.update(note(64), 0.4)?.midi, 64); // sem esperar confirmação
    });

    test('silêncio curto no meio da nota não apaga nem troca', () {
      final f = NoteDisplayFilter();
      feed(f, note(60), 0, 0.5);
      expect(f.update(null, 0.5)?.midi, 60);
      expect(f.update(null, 0.53)?.midi, 60);
      expect(f.update(note(60, 3), 0.56)?.cents, 3);
    });

    test('velocidade Rápida troca bem mais cedo que Calma', () {
      double changeTime(NoteSwitchSpeed s) {
        final f = NoteDisplayFilter(speed: s);
        feed(f, note(60), 0, 1.5);
        for (var t = 1.5; t < 4; t += 0.01) {
          if (f.update(note(62), t)!.midi == 62) return t - 1.5;
        }
        return 99;
      }

      final fast = changeTime(NoteSwitchSpeed.fast);
      final normal = changeTime(NoteSwitchSpeed.normal);
      final calm = changeTime(NoteSwitchSpeed.calm);
      expect(fast, lessThan(normal));
      expect(normal, lessThan(calm));
      expect(fast, lessThan(0.15));
      expect(calm, greaterThanOrEqualTo(0.3));
    });

    test('mudar a velocidade vale para as próximas trocas', () {
      final f = NoteDisplayFilter(speed: NoteSwitchSpeed.calm);
      feed(f, note(60), 0, 2.0);
      f.speed = NoteSwitchSpeed.fast;
      var t = 2.0;
      var got = false;
      for (var i = 0; i < 10 && !got; i++) {
        got = f.update(note(62), t)!.midi == 62;
        t += 0.03;
      }
      expect(got, isTrue);
    });

    test('reset apaga tudo', () {
      final f = NoteDisplayFilter();
      f.update(note(60), 0);
      f.reset();
      expect(f.shown, isNull);
      expect(f.update(note(67), 5)?.midi, 67);
    });

    /// Toca [midis] (uma nota a cada [step] s, quadros de 30 ms) e devolve as
    /// notas que chegaram a ser destacadas, na ordem.
    List<int> shownDuring(NoteDisplayFilter f, List<int> midis, double step) {
      final shown = <int>[];
      var t = 0.0;
      for (final m in midis) {
        for (var k = 0.0; k < step - 1e-9; k += 0.03) {
          final s = f.update(note(m), t + k)?.midi;
          if (s != null && (shown.isEmpty || shown.last != s)) shown.add(s);
        }
        t += step;
      }
      return shown;
    }

    test('passagem rápida (semicolcheias): acelera sozinho e mostra quase todas as notas', () {
      const run = [60, 62, 64, 65, 67, 69, 71, 72]; // 8 notas de 125 ms
      final normal = shownDuring(NoteDisplayFilter(), run, 0.125);
      expect(normal.length, greaterThanOrEqualTo(6));
      // Em ordem e sem inventar notas.
      for (var i = 1; i < normal.length; i++) {
        expect(normal[i], greaterThan(normal[i - 1]));
      }
    });

    test('devagar continua calmo: notas de passagem rápidas isoladas não pulam o destaque', () {
      final f = NoteDisplayFilter();
      feed(f, note(60), 0, 1.0);
      // um único toque rápido em outra nota (80 ms) não chega a assumir
      feed(f, note(62), 1.0, 0.08);
      expect(feed(f, note(60), 1.08, 0.5).every((e) => e!.midi == 60), isTrue);
    });

    test('a opção Calma nunca é acelerada', () {
      const run = [60, 62, 64, 65, 67, 69, 71, 72];
      final calm = shownDuring(NoteDisplayFilter(speed: NoteSwitchSpeed.calm), run, 0.125);
      expect(calm.length, lessThanOrEqualTo(3));
    });

    test('os tempos crescem de Rápida para Calma', () {
      const v = NoteSwitchSpeed.values;
      for (var i = 1; i < v.length; i++) {
        expect(v[i].commit, greaterThan(v[i - 1].commit));
        expect(v[i].dwell, greaterThan(v[i - 1].dwell));
        expect(v[i].release, greaterThan(v[i - 1].release));
      }
    });
  });
}
