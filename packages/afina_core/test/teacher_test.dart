import 'dart:math';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

SessionRecord rec(DateTime d, double acc, {String title = 'Sol maior · 1 oitava'}) => SessionRecord(
    date: d,
    title: title,
    octaves: 1,
    zone: 5,
    accuracy: acc,
    meanAbsCents: 6,
    steps: const [StepRecord(55, true, 0, 4)]);

void main() {
  final base = DateTime(2026, 11, 7, 10);

  test('resumo: média das últimas 5, melhor, última data e tendência', () {
    final s = Student(id: 'a', name: 'Ana', sessions: [
      for (var i = 0; i < 6; i++) rec(base.subtract(Duration(days: i)), i < 3 ? 0.9 : 0.5)
    ]);
    final r = summarizeStudent(s);
    expect(r.sessions, 6);
    expect(r.best, 0.9);
    expect(r.last, base);
    expect(r.recentAverage, closeTo((0.9 * 3 + 0.5 * 2) / 5, 1e-9));
    expect(r.trendPoints, closeTo(40, 1e-6));
  });

  test('código do aluno: guarda formatado, ignora inválido e é opcional', () {
    final ok = Student(id: 'k', name: 'Kai', code: formatShareCode('k7qm4txd'));
    // Código com verificação correta, gerado na hora.
    final gen = newShareCode(Random(1));
    final s = Student(id: 'k2', name: 'Kai', code: gen);
    expect(Student.tryFrom(s.toJson())!.code, gen);
    expect(ok.code, isNull); // 'k7qm4txd' não passa na verificação
    final j = s.toJson()..['code'] = 'AAAA-AAAB';
    expect(Student.tryFrom(j)!.code, isNull); // inválido não entra
    expect(Student(id: 'n', name: 'Nina').toJson().containsKey('code'), isFalse);
  });

  test('sem sessões não inventa números', () {
    final r = summarizeStudent(Student(id: 'b', name: 'Bia'));
    expect(r.sessions, 0);
    expect(r.recentAverage, isNull);
    expect(r.trendPoints, isNull);
  });

  test('exportar e importar preserva alunos, tarefas, notas e sessões', () {
    final s = Student(id: 'c', name: 'Caio', sessions: [rec(base, 0.8)], notes: [
      TeacherNote(base, 'Cuidar do Mi')
    ], tasks: [
      Assignment(id: 't1', title: 'Sol maior', scaleTypeIndex: 0, tonicPc: 7, octaves: 2, goal: 0.8, created: base)
    ]);
    final back = importStudent(exportStudent(s))!;
    expect(back.name, 'Caio');
    expect(back.sessions.single.accuracy, closeTo(0.8, 1e-9));
    expect(back.notes.single.text, 'Cuidar do Mi');
    expect(back.tasks.single.octaves, 2);
    expect(back.tasks.single.done, isFalse);
  });

  test('texto inválido é recusado sem quebrar', () {
    expect(importStudent('isso não é json'), isNull);
    expect(importStudent('[1,2]'), isNull);
    expect(importStudent('{"x":1}'), isNull);
  });

  test('juntar sessões não duplica e ordena da mais recente', () {
    final a = [rec(base, 0.7)];
    final n = mergeSessions(a, [rec(base, 0.7), rec(base.add(const Duration(days: 1)), 0.9)]);
    expect(n, 1);
    expect(a.first.accuracy, 0.9);
    expect(a.length, 2);
  });

  test('relatório traz nome, média, tarefas abertas e observações', () {
    final s = Student(id: 'd', name: 'Duda', sessions: [rec(base, 0.75)], notes: [TeacherNote(base, 'Boa postura')], tasks: [
      Assignment(id: 't', title: 'Ré maior', scaleTypeIndex: 0, tonicPc: 2, octaves: 1, goal: 0.8, created: base)
    ]);
    final r = studentReport(s);
    expect(r, contains('Duda'));
    expect(r, contains('75%'));
    expect(r, contains('Ré maior'));
    expect(r, contains('Boa postura'));
  });

  test('PIN: mesmo valor dá o mesmo hash; valor ou sal diferente muda', () {
    expect(hashPin('1234', 's1'), hashPin('1234', 's1'));
    expect(hashPin('1234', 's1'), isNot(hashPin('1235', 's1')));
    expect(hashPin('1234', 's1'), isNot(hashPin('1234', 's2')));
    expect(hashPin('1234', 's1').length, 16);
  });
}
