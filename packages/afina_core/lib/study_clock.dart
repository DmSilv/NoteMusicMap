/// Relógios de estudo: CRONÔMETRO (conta para cima) e MINUTERIA (conta para
/// baixo até um tempo escolhido). Dart puro: o relógio de parede é passado de
/// fora (ms), então dá para testar e para retomar depois de fechar o app.
library;

class StudyClock {
  /// null = cronômetro; com valor = minuteria de [countdownMs].
  int? countdownMs;

  bool running = false;
  int _accMs = 0; // tempo acumulado até a última pausa
  int _startMs = 0; // instante em que começou a rodar

  StudyClock({this.countdownMs});

  bool get isCountdown => countdownMs != null;

  /// Tempo decorrido (ms) no instante [nowMs].
  int elapsedMs(int nowMs) {
    final run = running ? (nowMs - _startMs) : 0;
    final e = _accMs + (run < 0 ? 0 : run);
    final t = countdownMs;
    return t == null ? e : e.clamp(0, t);
  }

  /// Minuteria: tempo que falta (ms). No cronômetro, 0.
  int remainingMs(int nowMs) =>
      countdownMs == null ? 0 : (countdownMs! - elapsedMs(nowMs)).clamp(0, countdownMs!);

  /// Minuteria: 0..1 do caminho já percorrido.
  double progress(int nowMs) =>
      countdownMs == null || countdownMs == 0 ? 0 : elapsedMs(nowMs) / countdownMs!;

  /// Minuteria: chegou ao fim.
  bool finished(int nowMs) => countdownMs != null && elapsedMs(nowMs) >= countdownMs!;

  void start(int nowMs) {
    if (running || finished(nowMs)) return;
    running = true;
    _startMs = nowMs;
  }

  void pause(int nowMs) {
    if (!running) return;
    _accMs = elapsedMs(nowMs);
    running = false;
  }

  void reset() {
    running = false;
    _accMs = 0;
    _startMs = 0;
  }

  /// Muda a duração da minuteria (só quando parada) e zera.
  void setCountdown(int ms) {
    countdownMs = ms;
    reset();
  }

  /// Chamado a cada tique: se a minuteria acabou enquanto rodava, para e
  /// devolve true (uma única vez).
  bool tick(int nowMs) {
    if (running && finished(nowMs)) {
      _accMs = countdownMs!;
      running = false;
      return true;
    }
    return false;
  }

  Map<String, dynamic> toJson(int nowMs) => {
        'c': countdownMs,
        'r': running,
        'a': running ? elapsedMs(nowMs) : _accMs,
        's': running ? nowMs : _startMs,
      };

  /// Restaura (ex.: app reaberto). Um relógio que estava rodando continua
  /// contando o tempo em que o app ficou fechado.
  void restore(Map<String, dynamic> j, int nowMs) {
    countdownMs = (j['c'] as num?)?.toInt();
    _accMs = (j['a'] as num?)?.toInt() ?? 0;
    _startMs = (j['s'] as num?)?.toInt() ?? nowMs;
    running = j['r'] == true;
    if (running) {
      // `a` já inclui o tempo até o salvamento; conta a partir dali.
      _startMs = (j['s'] as num?)?.toInt() ?? nowMs;
      if (finished(nowMs)) {
        _accMs = countdownMs ?? _accMs;
        running = false;
      }
    }
  }
}

/// "1:05:09" ou "05:09".
String formatClock(int ms) {
  final s = (ms / 1000).floor();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}
