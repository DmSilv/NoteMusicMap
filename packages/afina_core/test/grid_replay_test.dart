import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

/// Toca [cents] por [seconds] (quadros de 30 ms) a partir de [t0]; devolve o instante final.
double play(PitchGrid g, int midi, double cents, double seconds, double t0) {
  const dt = 0.03;
  var t = t0;
  for (var i = 0; i < (seconds / dt).round(); i++) {
    t += dt;
    g.add(midi, cents, 0.95, dt, t);
  }
  return t;
}

void main() {
  test('afinou o Sol (de -20 a 0) e tocou de novo: a cor segue a tocada nova', () {
    final g = PitchGrid(history: HistoryMode.medium, holdSeconds: null);
    var t = play(g, 55, -20, 12, 0); // girando a cravelha, ainda baixo
    t += 2.0; // troca para a aba Grade
    t = play(g, 55, 0, 1.0, t); // toca o Sol afinado
    final v = g.view(55, t)!;
    expect(v.avgCents.abs(), lessThan(5), reason: 'média ${v.avgCents}');
    expect(v.plays, 2);
  });

  test('nota repetida em seguida (sem pausa) continua mediada em ~3 s', () {
    final g = PitchGrid(history: HistoryMode.medium, holdSeconds: null);
    var t = play(g, 57, -12, 2, 0);
    t = play(g, 57, 0, 1, t); // sem pausa: mesma tocada
    final v = g.view(57, t)!;
    expect(v.avgCents, lessThan(-2)); // ainda carrega parte do que veio antes
    expect(v.plays, 1);
  });

  test('memória longa guarda as tocadas anteriores', () {
    final g = PitchGrid(history: HistoryMode.unlimited, holdSeconds: null);
    var t = play(g, 59, -20, 4, 0);
    t += 1.0;
    t = play(g, 59, 0, 4, t);
    final v = g.view(59, t)!;
    expect(v.avgCents, closeTo(-10, 2));
  });
}
