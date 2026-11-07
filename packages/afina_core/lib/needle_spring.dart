/// Movimento natural de ponteiro: mola amortecida e mapeamento de ângulo.
///
/// Fica no núcleo (Dart puro) para poder ser testado sem a interface.
library;

import 'dart:math' as math;

/// Ponteiro com inércia: uma mola amortecida (massa, mola e amortecedor).
///
/// Em vez de "perseguir" o valor com uma suavização simples, o ponteiro tem
/// velocidade: arranca macio, acelera e assenta sem tranco, como um ponteiro
/// analógico de verdade. A equação é resolvida de forma EXATA (solução
/// analítica), por isso:
///  - é estável para qualquer intervalo entre quadros (30, 60 ou 144 fps);
///  - dá o mesmo resultado independente da taxa de quadros;
///  - nunca "explode", mesmo depois de uma pausa longa.
class NeedleSpring {
  /// Frequência natural (rad/s). Maior = mais rápido. 20 assenta em ~0,25 s.
  final double omega;

  /// Amortecimento: 1 = crítico (nunca ultrapassa); menor ultrapassa um pouco.
  /// Limitado a (0,05..0,999) porque a solução usada é a sub-amortecida.
  final double zeta;

  /// Posição atual (a mesma unidade do alvo, aqui: cents).
  double pos;

  /// Velocidade atual (unidade/s).
  double vel = 0;

  NeedleSpring({this.omega = 20, double zeta = 0.85, this.pos = 0})
      : zeta = math.max(0.05, math.min(0.999, zeta));

  /// Coloca o ponteiro direto em [p], parado (sem varrer o caminho).
  void snap(double p) {
    pos = p;
    vel = 0;
  }

  /// Avança [dt] segundos em direção a [target] e devolve a nova posição.
  /// [dt] <= 0 ou valores não numéricos não mudam nada.
  double step(double dt, double target) {
    if (!(dt > 0) || !target.isFinite || !dt.isFinite) return pos;
    final e0 = pos - target; // distância ao alvo
    final v0 = vel;
    final zw = zeta * omega;
    final wd = omega * math.sqrt(1 - zeta * zeta);
    final decay = math.exp(-zw * dt);
    final c = math.cos(wd * dt);
    final s = math.sin(wd * dt);
    final b = (v0 + zw * e0) / wd;
    pos = target + decay * (e0 * c + b * s);
    vel = decay * ((b * wd - zw * e0) * c - (e0 * wd + zw * b) * s);
    return pos;
  }

  /// true quando já está parado em cima de [target] (dá para parar o relógio).
  bool isSettled(double target, {double posTol = 0.02, double velTol = 0.08}) =>
      (pos - target).abs() <= posTol && vel.abs() <= velTol;
}

/// Ângulo do ponteiro, em graus a partir da vertical (negativo = grave,
/// positivo = agudo), para um desvio em [cents].
///
/// A curva é levemente "esticada" perto do centro (expoente [gamma] < 1): em
/// um quadradinho pequeno, 5 cents já mexem o ponteiro de forma visível, sem
/// perder a ordem (mais desvio, mais ângulo). Passa de [span] cents e o
/// ponteiro fica encostado no fim da escala ([maxDeg]).
double needleAngleDeg(double cents,
    {double maxDeg = 50, double span = 50, double gamma = 0.8}) {
  if (!cents.isFinite) return 0;
  final x = math.min(1.0, cents.abs() / span);
  final a = maxDeg * math.pow(x, gamma);
  return cents < 0 ? -a : a;
}
