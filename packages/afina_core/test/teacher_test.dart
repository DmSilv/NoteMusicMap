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

  group('regras de cadastro de aluno', () {
    final own = newShareCode(Random(31));
    final teacher = newShareCode(Random(32));
    final other = newShareCode(Random(33));
    final list = [Student(id: 'a', name: 'Ana Souza', code: other), Student(id: 'b', name: 'Bruno')];

    StudentEntryCheck check(String name, String code, {String? ownName, String? teacherCode, String? except}) =>
        checkStudentEntry(
            name: name,
            codeInput: code,
            ownCode: own,
            ownName: ownName,
            teacherCode: teacherCode,
            existing: list,
            exceptId: except);

    test('não deixa cadastrar o próprio código (qualquer forma de escrever)', () {
      for (final v in [own, own.toLowerCase(), own.replaceAll('-', ' ')]) {
        final r = check('Eu mesmo', v);
        expect(r.code, contains('próprio código'));
        expect(r.ok, isFalse);
      }
    });

    test('não deixa cadastrar o próprio nome quando não há código', () {
      expect(check('  maria  LIMA ', '', ownName: 'Maria Lima').name, contains('seu nome'));
      // Com código de outra pessoa, o mesmo nome é permitido (pessoa diferente).
      expect(check('Maria Lima', newShareCode(Random(40)), ownName: 'Maria Lima').ok, isTrue);
      // Sem nome de perfil definido, não há o que comparar.
      expect(check('Maria Lima', '').ok, isTrue);
    });

    test('não deixa o professor do usuário virar aluno', () {
      expect(check('Prof', teacher, teacherCode: teacher).code, contains('seu professor'));
    });

    test('código e nome repetidos', () {
      expect(check('Carla', other).code, 'Este código já é de Ana Souza.');
      expect(check('ana  souza', '').name, contains('Já existe'));
      // Editar o próprio aluno não conta como repetido.
      expect(check('Ana Souza', other, except: 'a').ok, isTrue);
      // Mesmo nome, mas os dois têm códigos diferentes: pessoas distintas.
      expect(check('Ana Souza', newShareCode(Random(41))).ok, isTrue);
      // Mesmo nome e o novo não tem código: bloqueia.
      expect(check('Ana Souza', '').name, isNotNull);
    });

    test('código inválido e nome vazio', () {
      expect(check('Davi', 'ABCD-1234').code, contains('inválido'));
      expect(check('   ', '').name, 'Digite o nome do aluno.');
      expect(check('Davi', '').ok, isTrue);
    });
  });

  group('tipos de tarefa', () {
    test('tarefa de método guarda assunto, detalhe e observação; título junta os dois', () {
      expect(Assignment.titleFor('Suzuki · Livro 2', 'Lição 5'), 'Suzuki · Livro 2 · Lição 5');
      expect(Assignment.titleFor('Mazas', ''), 'Mazas');
      final a = Assignment(
          id: 'm1',
          title: Assignment.titleFor('Suzuki', 'Lição 5'),
          kind: TaskKind.method,
          subject: 'Suzuki',
          detail: 'Lição 5',
          note: 'Cuidar do arco na corda Ré',
          created: DateTime(2026, 11, 8));
      final b = Assignment.tryFrom(a.toJson())!;
      expect(b.kind, TaskKind.method);
      expect(b.isScale, isFalse);
      expect(b.subject, 'Suzuki');
      expect(b.detail, 'Lição 5');
      expect(b.note, 'Cuidar do arco na corda Ré');
      expect(b.title, 'Suzuki · Lição 5');
    });

    test('tarefa de escala antiga (sem tipo) continua lida como escala', () {
      final j = {'id': 'old', 'title': 'Sol maior · 1 oitava', 'st': 0, 'pc': 7, 'oct': 1, 'goal': 0.8, 'done': false, 'c': '2026-10-01T10:00:00.000'};
      final a = Assignment.tryFrom(j)!;
      expect(a.kind, TaskKind.scale);
      expect(a.isScale, isTrue);
      expect(a.tonicPc, 7);
      expect(a.toJson().containsKey('kind'), isFalse); // escala não pesa no JSON
    });

    test('editar muda o título de método, mas não o de escala', () {
      final m = Assignment(id: 'a', title: 'Suzuki', kind: TaskKind.method, subject: 'Suzuki', created: DateTime(2026));
      final m2 = m.copyWith(detail: 'Lição 7');
      expect(m2.title, 'Suzuki · Lição 7');
      final s = Assignment(id: 'b', title: 'Sol maior · 1 oitava', tonicPc: 7, created: DateTime(2026));
      expect(s.copyWith(note: 'devagar').title, 'Sol maior · 1 oitava');
      expect(s.copyWith(note: 'devagar').note, 'devagar');
    });

    test('relatório lista método, lição e observação; escala mostra a meta', () {
      final st = Student(id: 'r', name: 'Rui', tasks: [
        Assignment(id: 't1', title: 'Sol maior · 1 oitava', tonicPc: 7, goal: 0.8, created: DateTime(2026)),
        Assignment(
            id: 't2',
            title: 'Suzuki · Lição 5',
            kind: TaskKind.method,
            subject: 'Suzuki',
            detail: 'Lição 5',
            note: 'Rever o 3º dedo',
            created: DateTime(2026)),
      ]);
      final r = studentReport(st);
      expect(r, contains('Sol maior · 1 oitava (meta 80%)'));
      expect(r, contains('Método e lição: Suzuki · Lição 5'));
      expect(r, contains('Observação: Rever o 3º dedo'));
    });

    test('há sugestões de métodos', () {
      expect(kMethodSuggestions, contains('Suzuki'));
    });
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
