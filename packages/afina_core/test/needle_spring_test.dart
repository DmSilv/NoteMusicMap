import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

/// Simula [seconds] com passos de [dt] e devolve a trajetória (posições).
List<double> run(NeedleSpring s, double target, double seconds, double dt) {
  final out = <double>[];
  final n = (seconds / dt).round();
  for (var i = 0; i < n; i++) {
    out.add(s.step(dt, target));
  }
  return out;
}

void main() {
  group('NeedleSpring', () {
    test('chega ao alvo e assenta (sem NaN)', () {
      final s = NeedleSpring();
      final path = run(s, 30, 1.0, 1 / 60);
      expect(path.every((p) => p.isFinite), isTrue);
      expect(s.pos, closeTo(30, 0.02));
      expect(s.isSettled(30), isTrue);
    });

    test('é ágil: passa da metade do caminho em menos de 0,12 s', () {
      final s = NeedleSpring();
      final path = run(s, 40, 0.12, 1 / 120);
      expect(path.last, greaterThan(20));
    });

    test('assenta a menos de 0,5 cent em até 0,4 s para um salto de 40', () {
      final s = NeedleSpring();
      final path = run(s, 40, 0.4, 1 / 120);
      expect((path.last - 40).abs(), lessThan(0.5));
    });

    test('ultrapassa o alvo menos de 2% (natural, sem "balançar")', () {
      final s = NeedleSpring();
      final path = run(s, 40, 2.0, 1 / 240);
      final peak = path.reduce(math.max);
      expect(peak - 40, lessThan(0.8));
    });

    test('não anda para trás no começo (arranca do repouso sem tranco)', () {
      final s = NeedleSpring();
      final path = run(s, 40, 0.1, 1 / 240);
      for (var i = 1; i < path.length; i++) {
        expect(path[i], greaterThanOrEqualTo(path[i - 1]));
      }
      // Arranque macio: o 1º quadro quase não anda (velocidade começa em zero).
      expect(path.first, lessThan(0.5));
    });

    test('mesmo resultado em 30, 60 e 144 quadros por segundo', () {
      double at(double dt) {
        final s = NeedleSpring();
        run(s, 25, 0.5, dt);
        return s.pos;
      }

      final a = at(1 / 30), b = at(1 / 60), c = at(1 / 144 * 2);
      expect(b, closeTo(a, 1e-9));
      expect(c, closeTo(a, 1e-9));
      // E um único passo de 0,5 s dá o mesmo que 15 passos.
      final one = NeedleSpring()..step(0.5, 25);
      expect(one.pos, closeTo(a, 1e-9));
    });

    test('estável depois de uma pausa enorme', () {
      final s = NeedleSpring();
      s.step(100, 30);
      expect(s.pos, closeTo(30, 1e-9));
      expect(s.vel.abs(), lessThan(1e-9));
    });

    test('passo zero, negativo ou NaN não muda nada', () {
      final s = NeedleSpring(pos: 5);
      s.step(0, 30);
      s.step(-1, 30);
      s.step(double.nan, 30);
      s.step(0.1, double.nan);
      expect(s.pos, 5);
      expect(s.vel, 0);
    });

    test('trocar de alvo no meio do caminho não dá salto de posição', () {
      final s = NeedleSpring();
      run(s, 40, 0.08, 1 / 120);
      final before = s.pos, vBefore = s.vel;
      s.step(1 / 1200, -20); // alvo mudou de repente
      expect((s.pos - before).abs(), lessThan(vBefore.abs() / 1200 + 0.02));
      // e a velocidade muda de forma contínua (inércia), não de uma vez
      expect((s.vel - vBefore).abs(), lessThan(40));
      run(s, -20, 1.0, 1 / 60);
      expect(s.pos, closeTo(-20, 0.05));
    });

    test('snap posiciona direto e zera a velocidade', () {
      final s = NeedleSpring();
      run(s, 40, 0.05, 1 / 120);
      s.snap(-12);
      expect(s.pos, -12);
      expect(s.vel, 0);
    });

    test('filtra ruído: o ponteiro oscila bem menos que a leitura', () {
      final rnd = math.Random(42);
      final s = NeedleSpring();
      final input = <double>[], output = <double>[];
      // leituras a ~30 por segundo com ruído de ±4 cents, redesenho a 60 fps
      var reading = 0.0;
      for (var f = 0; f < 120; f++) {
        if (f % 2 == 0) reading = (rnd.nextDouble() * 2 - 1) * 4;
        s.step(1 / 60, reading);
        if (f > 30) {
          input.add(reading);
          output.add(s.pos);
        }
      }
      double sd(List<double> v) {
        final m = v.reduce((a, b) => a + b) / v.length;
        return math.sqrt(v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length);
      }

      expect(sd(output), lessThan(sd(input) * 0.6));
    });

    test('amortecimento é limitado ao intervalo suportado', () {
      expect(NeedleSpring(zeta: 5).zeta, lessThan(1));
      expect(NeedleSpring(zeta: -1).zeta, greaterThan(0));
      // com valor extremo ainda converge
      final s = NeedleSpring(zeta: 5);
      run(s, 10, 3, 1 / 60);
      expect(s.pos, closeTo(10, 0.05));
    });
  });

  group('needleAngleDeg', () {
    test('zero no centro, simétrico e encostado nos extremos', () {
      expect(needleAngleDeg(0), 0);
      expect(needleAngleDeg(50), closeTo(50, 1e-9));
      expect(needleAngleDeg(-50), closeTo(-50, 1e-9));
      expect(needleAngleDeg(17), closeTo(-needleAngleDeg(-17), 1e-9));
      expect(needleAngleDeg(500), closeTo(50, 1e-9));
      expect(needleAngleDeg(-500), closeTo(-50, 1e-9));
    });

    test('cresce sempre com o desvio (nunca inverte)', () {
      var last = -1.0;
      for (var c = 0.0; c <= 50; c += 0.5) {
        final a = needleAngleDeg(c);
        expect(a, greaterThan(last));
        last = a;
      }
    });

    test('mais sensível perto do centro que uma escala linear', () {
      // linear: 5 cents -> 5 graus; aqui precisa ser maior
      expect(needleAngleDeg(5), greaterThan(5 * 1.4));
      // e respeita o ângulo máximo escolhido
      expect(needleAngleDeg(50, maxDeg: 42), closeTo(42, 1e-9));
    });

    test('valores inválidos viram o centro', () {
      expect(needleAngleDeg(double.nan), 0);
      expect(needleAngleDeg(double.infinity), 0);
    });
  });
}
