import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 11, 10, 10, 0, 0);
  DateTime at(int s) => t0.add(Duration(seconds: s));

  group('ActiveLesson (relógio da aula)', () {
    test('conta o tempo e desconta a pausa', () {
      final l = ActiveLesson(id: 'a1', studentId: 's1', startedAt: t0);
      expect(l.elapsed(at(600)).inSeconds, 600);
      l.pause(at(600)); // 10 min de aula
      expect(l.paused, isTrue);
      expect(l.elapsed(at(900)).inSeconds, 600); // parado: não conta
      l.resume(at(900)); // pausa de 5 min
      expect(l.paused, isFalse);
      expect(l.elapsed(at(1200)).inSeconds, 900); // 10 + 5 min depois da pausa
    });

    test('pausar duas vezes seguidas ou retomar sem pausar não estraga nada', () {
      final l = ActiveLesson(id: 'a1', studentId: 's1', startedAt: t0);
      l.resume(at(10)); // sem pausa: nada acontece
      expect(l.pausedMs, 0);
      l.pause(at(100));
      l.pause(at(200)); // repete: vale o primeiro instante
      l.resume(at(300));
      expect(l.pausedMs, 200000);
    });

    test('guardar e ler preserva (sobrevive a fechar o app), inclusive pausada', () {
      final l = ActiveLesson(id: 'x9', studentId: 's2', startedAt: t0);
      l.pause(at(120));
      final back = ActiveLesson.tryFrom(l.toJson())!;
      expect(back.id, 'x9');
      expect(back.paused, isTrue);
      expect(back.elapsed(at(5000)).inSeconds, 120);
    });

    test('dado estragado vira null', () {
      expect(ActiveLesson.tryFrom({'id': 1}), isNull);
      expect(ActiveLesson.tryFrom('lixo'), isNull);
    });
  });

  group('pacote da aula', () {
    Assignment task(String id, DateTime created, {TaskKind kind = TaskKind.method}) =>
        Assignment(id: id, title: 'Suzuki · Lição $id', kind: kind, subject: 'Suzuki', detail: 'Lição $id', created: created);

    test('leva só o que foi passado DURANTE a aula', () {
      final s = Student(id: 's1', name: 'Ana', tasks: [
        task('antes', t0.subtract(const Duration(days: 2))),
        task('d1', at(300)),
        task('d2', at(900)),
        task('depois', at(4000)),
      ], notes: [
        TeacherNote(t0.subtract(const Duration(days: 1)), 'nota antiga'),
        TeacherNote(at(500), 'cuidar do arco'),
      ]);
      final l = ActiveLesson(id: 'l1', studentId: 's1', startedAt: t0);
      final r = buildLessonRecord(s, l, at(3000), teacherName: 'Profa. Bia');
      expect(r.taskCount, 2);
      expect(r.noteCount, 1);
      expect(r.durationSec, 3000);
      final w = r.wire!;
      expect((w['tasks'] as List).map((x) => (x as Map)['id']), ['d1', 'd2']);
      expect(w['notes'], ['cuidar do arco']);
      expect(w['tn'], 'Profa. Bia');
      expect(r.sent, isNull);
    });

    test('a pausa não entra na duração; aula sem tarefas gera pacote vazio mas válido', () {
      final s = Student(id: 's1', name: 'Ana');
      final l = ActiveLesson(id: 'l2', studentId: 's1', startedAt: t0);
      l.pause(at(600));
      l.resume(at(1200));
      final r = buildLessonRecord(s, l, at(1800));
      expect(r.durationSec, 1200);
      expect(r.taskCount, 0);
      expect(SharedLesson.tryFromWire(r.wire), isNotNull);
    });

    test('há teto de tarefas e de observações', () {
      final s = Student(id: 's1', name: 'Ana', tasks: [
        for (var i = 0; i < 80; i++) task('t$i', at(10 + i)),
      ], notes: [
        for (var i = 0; i < 40; i++) TeacherNote(at(20 + i), 'obs $i'),
      ]);
      final r = buildLessonRecord(s, ActiveLesson(id: 'l3', studentId: 's1', startedAt: t0), at(2000));
      expect(r.taskCount, kMaxLessonTasks);
      expect(r.noteCount, kMaxLessonNotes);
    });
  });

  group('SharedLesson (o que o aluno recebe)', () {
    test('ida e volta pelo formato do servidor', () {
      final s = SharedLesson(
        id: 'ab12',
        atMs: 1700000000000,
        durationSec: 2400,
        tasks: [Assignment(id: 'k1', title: 'Escala de Sol', created: DateTime(2026, 1, 1), goal: 0.9)],
        notes: ['Relaxar o ombro'],
      );
      final back = SharedLesson.tryFromWire(s.toWire(), teacherCode: 'K7QM-4TXD', teacherName: 'Ana')!;
      expect(back.id, 'ab12');
      expect(back.teacherCode, 'K7QM-4TXD');
      expect(back.durationSec, 2400);
      expect(back.tasks.single.title, 'Escala de Sol');
      expect(back.tasks.single.goal, closeTo(0.9, 1e-9));
      expect(back.notes, ['Relaxar o ombro']);
    });

    test('recusa id inválido e limpa textos perigosos e enormes', () {
      expect(SharedLesson.tryFromWire({'id': '<script>', 't': 1}), isNull);
      expect(SharedLesson.tryFromWire({'id': 'ok01'}), isNull); // sem data
      final r = SharedLesson.tryFromWire({
        'id': 'ok02',
        't': 1700000000000,
        'd': 99999999,
        'tasks': [
          {'id': 'x', 'title': 'Lição\u202E 1', 'c': '2026-01-01T00:00:00.000'},
          {'sem': 'id'},
          for (var i = 0; i < 100; i++) {'id': 'm$i', 'title': 't', 'c': '2026-01-01T00:00:00.000'},
        ],
        'notes': ['a\u0000b', 'z' * 5000, '   '],
      })!;
      expect(r.durationSec, 86400);
      expect(r.tasks.length, lessThanOrEqualTo(kMaxLessonTasks));
      expect(r.tasks.length, greaterThan(20));
      expect(r.tasks.first.title, 'Lição 1');
      expect(r.notes.length, 2);
      expect(r.notes.first, 'ab');
      expect(r.notes.last.length, kMaxNote);
    });
  });

  test('duração em texto', () {
    expect(fmtLessonDuration(45), '45 s');
    expect(fmtLessonDuration(200), '3 min 20 s');
    expect(fmtLessonDuration(2520), '42 min');
    expect(fmtLessonDuration(3900), '1 h 05 min');
  });

  test('o histórico de aulas do aluno sobrevive a guardar e ler', () {
    final s = Student(id: 's1', name: 'Ana');
    final r = buildLessonRecord(s, ActiveLesson(id: 'l9', studentId: 's1', startedAt: t0), at(1800));
    r.sent = false;
    s.lessons.add(r);
    final back = Student.tryFrom(s.toJson())!;
    expect(back.lessons.single.id, 'l9');
    expect(back.lessons.single.sent, isFalse);
    expect(back.lessons.single.wire, isNotNull); // ainda a enviar: o pacote fica guardado
    back.lessons.single.sent = true;
    final again = Student.tryFrom(back.toJson())!;
    expect(again.lessons.single.wire, isNull); // enviado: o pacote não precisa mais ficar
  });
}
