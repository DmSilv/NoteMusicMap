/// Temporizador de estudo no estilo Pomodoro: foco, pausa curta e pausa longa.
///
/// Lógica pura (sem relógio próprio): quem usa passa o instante atual em
/// milissegundos. Isso deixa tudo testável e permite retomar depois de o app
/// ser fechado (estado vai e volta em JSON).
library;

import 'dart:math' as math;

enum PomoPhase { idle, focus, shortBreak, longBreak }

class PomodoroConfig {
  final int focusMin;
  final int shortMin;
  final int longMin;

  /// Quantos focos completos até uma pausa longa.
  final int cyclesBeforeLong;

  /// Começa a fase seguinte sozinho ao terminar uma.
  final bool autoStart;

  const PomodoroConfig({
    this.focusMin = 25,
    this.shortMin = 5,
    this.longMin = 15,
    this.cyclesBeforeLong = 4,
    this.autoStart = true,
  });

  PomodoroConfig copyWith({
    int? focusMin,
    int? shortMin,
    int? longMin,
    int? cyclesBeforeLong,
    bool? autoStart,
  }) =>
      PomodoroConfig(
        focusMin: focusMin ?? this.focusMin,
        shortMin: shortMin ?? this.shortMin,
        longMin: longMin ?? this.longMin,
        cyclesBeforeLong: cyclesBeforeLong ?? this.cyclesBeforeLong,
        autoStart: autoStart ?? this.autoStart,
      );

  int msFor(PomoPhase p) => switch (p) {
        PomoPhase.focus || PomoPhase.idle => focusMin * 60000,
        PomoPhase.shortBreak => shortMin * 60000,
        PomoPhase.longBreak => longMin * 60000,
      };
}

/// Algo que aconteceu ao tick: uma fase terminou.
class PomodoroEvent {
  final PomoPhase finished;
  final PomoPhase next;

  /// true quando um período de FOCO foi concluído até o fim (conta como pomodoro).
  final bool countedPomodoro;

  /// Instante em que a fase terminou (ms), útil para datar o pomodoro.
  final int atMs;
  const PomodoroEvent(this.finished, this.next, this.countedPomodoro, this.atMs);
}

class PomodoroTimer {
  PomodoroConfig config;
  PomoPhase phase = PomoPhase.idle;
  bool running = false;

  /// Focos concluídos no conjunto atual (0..cyclesBeforeLong-1).
  int cycle = 0;

  int _endMs = 0;
  int _remainingMs = 0; // valor congelado enquanto pausado

  PomodoroTimer([this.config = const PomodoroConfig()]) {
    _remainingMs = config.msFor(PomoPhase.focus);
  }

  int get totalMs => config.msFor(phase);

  int remainingMs(int nowMs) {
    if (running) return math.max(0, _endMs - nowMs);
    return phase == PomoPhase.idle ? config.msFor(PomoPhase.focus) : _remainingMs;
  }

  /// 0..1 do tempo já decorrido na fase.
  double progress(int nowMs) {
    final t = totalMs;
    if (t <= 0) return 0;
    return (1 - remainingMs(nowMs) / t).clamp(0.0, 1.0);
  }

  bool get isPaused => !running && phase != PomoPhase.idle;

  /// Inicia (do zero) ou retoma (se pausado).
  void start(int nowMs) {
    if (running) return;
    if (phase == PomoPhase.idle) {
      phase = PomoPhase.focus;
      _remainingMs = config.msFor(PomoPhase.focus);
    }
    _endMs = nowMs + _remainingMs;
    running = true;
  }

  void pause(int nowMs) {
    if (!running) return;
    _remainingMs = math.max(0, _endMs - nowMs);
    running = false;
  }

  void reset() {
    phase = PomoPhase.idle;
    running = false;
    cycle = 0;
    _remainingMs = config.msFor(PomoPhase.focus);
  }

  /// Avança para a próxima fase agora. Pular um foco NÃO conta como pomodoro.
  PomodoroEvent skip(int nowMs) {
    if (phase == PomoPhase.idle) {
      start(nowMs);
      return PomodoroEvent(PomoPhase.idle, PomoPhase.focus, false, nowMs);
    }
    return _finish(nowMs, counted: false, forceAuto: running);
  }

  /// Chame periodicamente (ex.: a cada segundo). Devolve as fases concluídas.
  List<PomodoroEvent> tick(int nowMs) {
    final out = <PomodoroEvent>[];
    var guard = 0;
    while (running && nowMs >= _endMs && guard++ < 24) {
      out.add(_finish(_endMs, counted: phase == PomoPhase.focus, forceAuto: true));
    }
    return out;
  }

  PomodoroEvent _finish(int atMs, {required bool counted, required bool forceAuto}) {
    final finished = phase;
    if (finished == PomoPhase.focus && counted) cycle++;
    final PomoPhase next;
    if (finished == PomoPhase.focus) {
      next = (counted && config.cyclesBeforeLong > 0 && cycle >= config.cyclesBeforeLong)
          ? PomoPhase.longBreak
          : PomoPhase.shortBreak;
    } else {
      if (finished == PomoPhase.longBreak) cycle = 0;
      next = PomoPhase.focus;
    }
    phase = next;
    final dur = config.msFor(next);
    if (config.autoStart && forceAuto) {
      running = true;
      _endMs = atMs + dur; // encadeia sem acumular atraso
      _remainingMs = dur;
    } else {
      running = false;
      _remainingMs = dur;
    }
    return PomodoroEvent(finished, next, counted && finished == PomoPhase.focus, atMs);
  }

  // ---------------- Persistência ----------------

  Map<String, dynamic> toJson(int nowMs) => {
        'phase': phase.index,
        'running': running,
        'cycle': cycle,
        'endMs': _endMs,
        'remainingMs': running ? math.max(0, _endMs - nowMs) : _remainingMs,
      };

  /// Restaura o estado salvo. Se estava rodando e o tempo já passou enquanto o
  /// app estava fechado, volta ao início (sem contar pomodoro: não dá para saber
  /// se a pessoa estudou). Devolve true se isso aconteceu.
  bool restore(Map<String, dynamic> j, int nowMs) {
    final p = (j['phase'] as num?)?.toInt() ?? 0;
    phase = PomoPhase.values[p.clamp(0, PomoPhase.values.length - 1)];
    cycle = (j['cycle'] as num?)?.toInt() ?? 0;
    final wasRunning = j['running'] == true;
    _endMs = (j['endMs'] as num?)?.toInt() ?? 0;
    _remainingMs = (j['remainingMs'] as num?)?.toInt() ?? config.msFor(PomoPhase.focus);
    running = false;
    if (phase == PomoPhase.idle) return false;
    if (wasRunning) {
      if (_endMs > nowMs) {
        running = true;
        return false;
      }
      reset();
      return true;
    }
    return false;
  }
}
