// Observação feita FORA de uma aula tem de chegar ao aluno (antes só ia quando uma aula era iniciada e encerrada).
import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  idTests();
  final t0 = DateTime(2026, 11, 10, 10, 0, 0);

  test('observação fora de aula entra no pacote avulso (sem tarefas)', () {
    final s = Student(id: 's1', name: 'Ana', code: 'ABCD-EFGH');
    s.notes.insert(0, TeacherNote(t0, 'Relaxar o ombro direito', sent: false));
    final pkg = buildTasksPackage(s, t0.add(const Duration(minutes: 5)), teacherName: 'Prof');
    expect(pkg, isNotNull);
    expect(pkg!.noteCount, 1);
    expect(pkg.taskCount, 0);
    expect((pkg.wire!['notes'] as List).single, 'Relaxar o ombro direito');
    expect(pkg.wire!['d'], 0); // sem aula: o aluno vê "Observações de ..."
  });

  test('o pacote só de observações aparece como "Observações de ..." para o aluno', () {
    final l = SharedLesson(id: 'x1', atMs: t0.millisecondsSinceEpoch, notes: const ['Cuidar do arco']);
    expect(l.notesOnly, isTrue);
    expect(l.tasksOnly, isFalse);
    expect(l.label, startsWith('Observações'));
  });

  test('a observação já enviada nunca vai de novo; a antiga (sem marca) também não', () {
    final s = Student(id: 's1', name: 'Ana', code: 'ABCD-EFGH');
    s.notes.insert(0, TeacherNote(t0, 'Já foi', sent: true));
    s.notes.insert(0, TeacherNote(t0, 'Dado antigo')); // sem marca: não é reenviada fora de aula
    expect(buildTasksPackage(s, t0), isNull);
    expect(pendingNotes(s), isEmpty);
  });

  test('uma aula posterior leva a observação que ficou esperando, mesmo feita antes de começar', () {
    final s = Student(id: 's1', name: 'Ana', code: 'ABCD-EFGH');
    s.notes.insert(0, TeacherNote(t0, 'Feita antes da aula', sent: false));
    final l = ActiveLesson(id: 'a1', studentId: 's1', startedAt: t0.add(const Duration(hours: 2)));
    final rec = buildLessonRecord(s, l, t0.add(const Duration(hours: 3)));
    expect(rec.noteCount, 1);
    expect((rec.wire!['notes'] as List).single, 'Feita antes da aula');
  });

  test('a observação feita durante a aula continua indo com ela, e a de outro dia já enviada não', () {
    final s = Student(id: 's1', name: 'Ana', code: 'ABCD-EFGH');
    final start = t0.add(const Duration(hours: 1));
    s.notes.insert(0, TeacherNote(start.add(const Duration(minutes: 10)), 'Durante', sent: false));
    s.notes.insert(0, TeacherNote(t0.subtract(const Duration(days: 1)), 'Ontem', sent: true));
    final l = ActiveLesson(id: 'a1', studentId: 's1', startedAt: start);
    final rec = buildLessonRecord(s, l, start.add(const Duration(minutes: 40)));
    expect((rec.wire!['notes'] as List), ['Durante']);
  });

  test('a marca de enviada sobrevive a guardar e ler a ficha', () {
    final s = Student(id: 's1', name: 'Ana');
    s.notes.insert(0, TeacherNote(t0, 'Texto', sent: false));
    final back = TeacherNote.tryFrom(s.notes.first.toJson())!;
    expect(back.sent, isFalse);
    expect(TeacherNote.tryFrom({'d': t0.toIso8601String(), 't': 'Antiga'})!.sent, isNull);
  });
}

void idTests() {
  group('número da aula (ID para conversar sobre ela)', () {
    test('mesmo id, mesmo número nos dois lados; formato XXXX-XXXX', () {
      final a = lessonDisplayId('lz3k9m2p8qr');
      expect(a, matches(RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}$')));
      expect(lessonDisplayId('lz3k9m2p8qr'), a);
    });
    test('aulas diferentes têm números diferentes e id curto é completado', () {
      expect(lessonDisplayId('aaaaaaaaaa1'), isNot(lessonDisplayId('aaaaaaaaaa2')));
      expect(lessonDisplayId('ab'), '0000-00AB');
    });
  });
}
