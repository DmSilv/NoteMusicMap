import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 22, 10);

  test('o contexto traz o estudo da semana e as tarefas, e só traz observações se vierem', () {
    final secs = {studyDayKey(now): 20 * 60.0, studyDayKey(now.subtract(const Duration(days: 1))): 30 * 60.0};
    final sem = buildStudyContext(studySeconds: secs, now: now, goalMinutes: 20, openTasks: ['Sol maior · 2 oitavas'], lessonsCount: 2);
    expect(sem, contains('50 min'));
    expect(sem, contains('Sol maior'));
    expect(sem, isNot(contains('Observações recentes')));
    final com = buildStudyContext(studySeconds: secs, now: now, goalMinutes: 20, teacherNotes: ['Relaxar o ombro direito']);
    expect(com, contains('Relaxar o ombro direito'));
  });

  test('textos longos são cortados e os limites valem', () {
    final c = buildStudyContext(
      studySeconds: const {},
      now: now,
      goalMinutes: 20,
      openTasks: [for (var i = 0; i < 20; i++) 'tarefa $i ${'x' * 200}'],
      teacherNotes: [for (var i = 0; i < 20; i++) 'nota $i ${'y' * 500}'],
    );
    expect('tarefa '.allMatches(c).length, 8);
    expect('nota '.allMatches(c).length, 5);
    expect(c.length, lessThan(2500));
  });

  test('impressão do contexto: igual para o mesmo texto, diferente se muda', () {
    expect(studyContextFingerprint('abc'), studyContextFingerprint('abc'));
    expect(studyContextFingerprint('abc'), isNot(studyContextFingerprint('abd')));
  });

  test('quando pode pedir plano novo', () {
    DateTime ago(Duration d) => now.subtract(d);
    expect(canAskNewPlan(planAt: null, planFingerprint: null, currentFingerprint: 'a', now: now), isTrue);
    expect(canAskNewPlan(planAt: ago(const Duration(hours: 3)), planFingerprint: 'a', currentFingerprint: 'b', now: now), isFalse);
    expect(canAskNewPlan(planAt: ago(const Duration(days: 2)), planFingerprint: 'a', currentFingerprint: 'a', now: now), isFalse);
    expect(canAskNewPlan(planAt: ago(const Duration(days: 2)), planFingerprint: 'a', currentFingerprint: 'b', now: now), isTrue);
    expect(canAskNewPlan(planAt: ago(const Duration(days: 8)), planFingerprint: 'a', currentFingerprint: 'a', now: now), isTrue);
  });

  test('o pedido de pergunta leva a pergunta primeiro e o contexto depois', () {
    final q = buildQuestionRequest('Por que erro a 5ª nota?', 'Estudo da semana: 10 min', scalesPrompt: 'Sessões: ...');
    expect(q.indexOf('Por que erro'), lessThan(q.indexOf('Estudo da semana')));
    expect(q, contains('Sessões'));
  });
}
