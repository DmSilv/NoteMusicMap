import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  ScaleExercise ex() => ScaleExercise(tonicMidi: 60, type: ScaleType.major, octaves: 1, zone: 10);

  test('a espera da nota atual cresce com o tempo, mesmo sem tocar nada', () {
    final e = ex();
    expect(e.waitingSeconds, 0);
    for (var i = 0; i < 5; i++) {
      e.feed(midi: null, cents: 0, clarity: 0, dt: 1);
    }
    expect(e.waitingSeconds, closeTo(5, 1e-9));
  });

  test('notas erradas também contam como espera (quem está perdido não avança)', () {
    final e = ex();
    for (var i = 0; i < 3; i++) {
      e.feed(midi: 70, cents: 0, clarity: 1, dt: 1);
    }
    expect(e.waitingSeconds, closeTo(3, 1e-9));
    expect(e.index, 0);
  });

  test('zera quando a nota é tocada e quando é pulada', () {
    final e = ex();
    for (var i = 0; i < 4; i++) {
      e.feed(midi: null, cents: 0, clarity: 0, dt: 1);
    }
    StepResult? r;
    for (var i = 0; i < 20 && r == null; i++) {
      r = e.feed(midi: 60, cents: 0, clarity: 1, dt: 0.1);
    }
    expect(r, isNotNull);
    expect(e.index, 1);
    expect(e.waitingSeconds, 0);
    e.feed(midi: null, cents: 0, clarity: 0, dt: 2);
    e.skip();
    expect(e.waitingSeconds, 0);
  });

  test('no modo livre não há espera (não existe "a nota da vez")', () {
    final e = ScaleExercise(tonicMidi: 60, type: ScaleType.major, octaves: 1, zone: 10, flow: true);
    e.feed(midi: null, cents: 0, clarity: 0, dt: 5);
    expect(e.waitingSeconds, 0);
  });
}
