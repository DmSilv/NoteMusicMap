import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

const min = 60000;

void main() {
  PomodoroTimer make({bool auto = true, int cycles = 4}) => PomodoroTimer(
      PomodoroConfig(focusMin: 25, shortMin: 5, longMin: 15, cyclesBeforeLong: cycles, autoStart: auto));

  test('começa parado, com 25 min de foco disponíveis', () {
    final t = make();
    expect(t.phase, PomoPhase.idle);
    expect(t.running, isFalse);
    expect(t.remainingMs(0), 25 * min);
  });

  test('iniciar entra em foco e o tempo corre', () {
    final t = make()..start(1000);
    expect(t.phase, PomoPhase.focus);
    expect(t.remainingMs(1000 + 10 * min), 15 * min);
    expect(t.progress(1000 + 5 * min), closeTo(0.2, 1e-9));
  });

  test('pausar congela e retomar continua de onde parou', () {
    final t = make()..start(0);
    t.pause(10 * min);
    expect(t.remainingMs(99 * min), 15 * min); // congelado
    t.start(50 * min);
    expect(t.remainingMs(50 * min), 15 * min);
    expect(t.remainingMs(60 * min), 5 * min);
  });

  test('fim do foco conta pomodoro e vai para pausa curta automaticamente', () {
    final t = make()..start(0);
    expect(t.tick(24 * min), isEmpty);
    final ev = t.tick(25 * min);
    expect(ev.length, 1);
    expect(ev.first.finished, PomoPhase.focus);
    expect(ev.first.next, PomoPhase.shortBreak);
    expect(ev.first.countedPomodoro, isTrue);
    expect(t.phase, PomoPhase.shortBreak);
    expect(t.running, isTrue);
    expect(t.remainingMs(25 * min), 5 * min);
  });

  test('sem iniciar sozinho: espera o usuário na próxima fase', () {
    final t = make(auto: false)..start(0);
    t.tick(25 * min);
    expect(t.phase, PomoPhase.shortBreak);
    expect(t.running, isFalse);
    expect(t.remainingMs(99 * min), 5 * min);
    t.start(30 * min);
    expect(t.running, isTrue);
  });

  test('após 4 focos vem a pausa longa e o ciclo reinicia', () {
    final t = make()..start(0);
    var now = 0;
    final phases = <PomoPhase>[];
    for (var i = 0; i < 8; i++) {
      now += t.remainingMs(now);
      for (final e in t.tick(now)) {
        phases.add(e.next);
      }
    }
    expect(phases, [
      PomoPhase.shortBreak, PomoPhase.focus,
      PomoPhase.shortBreak, PomoPhase.focus,
      PomoPhase.shortBreak, PomoPhase.focus,
      PomoPhase.longBreak, PomoPhase.focus,
    ]);
    expect(t.cycle, 0);
  });

  test('tick depois de muito tempo encadeia as fases sem acumular atraso', () {
    final t = make()..start(0);
    final ev = t.tick(25 * min + 5 * min + 10 * min); // foco, pausa, 10 min do próximo foco
    expect(ev.map((e) => e.finished), [PomoPhase.focus, PomoPhase.shortBreak]);
    expect(t.phase, PomoPhase.focus);
    expect(t.remainingMs(40 * min), 15 * min);
  });

  test('pular um foco não conta pomodoro', () {
    final t = make()..start(0);
    final e = t.skip(5 * min);
    expect(e.finished, PomoPhase.focus);
    expect(e.countedPomodoro, isFalse);
    expect(t.cycle, 0);
    expect(t.phase, PomoPhase.shortBreak);
  });

  test('zerar volta ao início', () {
    final t = make()..start(0);
    t.tick(25 * min);
    t.reset();
    expect(t.phase, PomoPhase.idle);
    expect(t.running, isFalse);
    expect(t.cycle, 0);
  });

  test('salvar e restaurar: rodando e ainda no prazo continua rodando', () {
    final t = make()..start(0);
    final json = t.toJson(10 * min);
    final r = make();
    final expired = r.restore(json, 12 * min);
    expect(expired, isFalse);
    expect(r.running, isTrue);
    expect(r.phase, PomoPhase.focus);
    expect(r.remainingMs(12 * min), 13 * min);
  });

  test('restaurar depois do prazo (app fechado) volta ao início', () {
    final t = make()..start(0);
    final json = t.toJson(10 * min);
    final r = make();
    expect(r.restore(json, 90 * min), isTrue);
    expect(r.phase, PomoPhase.idle);
    expect(r.running, isFalse);
  });

  test('restaurar pausado mantém o tempo restante', () {
    final t = make()..start(0);
    t.pause(10 * min);
    final r = make()..restore(t.toJson(10 * min), 500 * min);
    expect(r.isPaused, isTrue);
    expect(r.remainingMs(500 * min), 15 * min);
  });
}
