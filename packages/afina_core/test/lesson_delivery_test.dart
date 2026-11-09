import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

Assignment task(String id, DateTime created, {bool? sent, String title = 'Escala de Sol'}) =>
    Assignment(id: id, title: title, created: created, sent: sent);

void main() {
  messages();
  final t0 = DateTime(2026, 11, 9, 10, 0);

  group('tarefa: controle de envio (só do professor)', () {
    test('sent vai e volta no disco, mas NUNCA no pacote que sai para o servidor', () {
      final a = task('a1', t0, sent: false);
      expect(a.toJson()['snt'], false);
      expect(Assignment.tryFrom(a.toJson())!.sent, false);
      expect(Assignment.tryFrom(task('a2', t0, sent: true).toJson())!.sent, true);
      // dados antigos (sem a chave) continuam lendo, como "não se aplica"
      final old = a.toJson()..remove('snt');
      expect(Assignment.tryFrom(old)!.sent, isNull);

      final l = SharedLesson(id: 'ls1', atMs: t0.millisecondsSinceEpoch, tasks: [a]);
      final wire = l.toWire();
      expect((wire['tasks'] as List).first.containsKey('snt'), isFalse);
      expect(l.toJson().toString().contains('snt'), isFalse);
    });

    test('copyWith(sent) marca e preserva o resto', () {
      final a = task('a1', t0, sent: false, title: 'Lição 5');
      final b = a.copyWith(sent: true);
      expect(b.sent, true);
      expect(b.title, 'Lição 5');
      expect(a.copyWith(done: true).sent, false);
    });
  });

  group('aula: o que vai ao encerrar', () {
    final lesson = ActiveLesson(id: 'ls1', studentId: 's1', startedAt: t0);
    final end = t0.add(const Duration(minutes: 40));

    test('leva as criadas durante a aula e as que esperavam envio; nunca as já enviadas', () {
      final s = Student(id: 's1', name: 'Ana', tasks: [
        task('dentro', t0.add(const Duration(minutes: 10)), sent: false),
        task('antes_na_fila', t0.subtract(const Duration(days: 2)), sent: false),
        task('antes_enviada', t0.subtract(const Duration(days: 2)), sent: true),
        task('antes_antiga', t0.subtract(const Duration(days: 5))), // dados antigos
        task('depois', end.add(const Duration(hours: 3)), sent: false),
      ]);
      final rec = buildLessonRecord(s, lesson, end);
      final ids = taskIdsOf(rec);
      expect(ids, containsAll(['dentro', 'antes_na_fila', 'depois']));
      expect(ids.contains('antes_enviada'), isFalse);
      expect(ids.contains('antes_antiga'), isFalse);
      expect(rec.taskCount, 3);
    });

    test('tarefa antiga criada dentro da janela (dados sem controle) continua indo', () {
      final s = Student(id: 's1', name: 'Ana', tasks: [task('x', t0.add(const Duration(minutes: 5)))]);
      expect(taskIdsOf(buildLessonRecord(s, lesson, end)), {'x'});
    });
  });

  group('tarefas fora de aula (pacote avulso)', () {
    test('sem pendentes não há pacote', () {
      final s = Student(id: 's1', name: 'Ana', tasks: [task('a', t0, sent: true), task('b', t0)]);
      expect(buildTasksPackage(s, t0), isNull);
    });

    test('só as pendentes, sem duração, sem observações e com id válido para o servidor', () {
      final s = Student(id: 's1', name: 'Ana', tasks: [
        task('n1', t0, sent: false),
        task('n2', t0, sent: false),
        task('ok', t0, sent: true),
      ]);
      final rec = buildTasksPackage(s, t0, teacherName: 'Marina')!;
      expect(rec.durationSec, 0);
      expect(rec.taskCount, 2);
      expect(rec.noteCount, 0);
      expect(taskIdsOf(rec), {'n1', 'n2'});
      expect(RegExp(r'^[a-z0-9]{2,40}$').hasMatch(rec.id), isTrue);
      expect(rec.wire!['d'], 0);
      expect(rec.wire!['tn'], 'Marina');
      expect(rec.wire!['notes'], isEmpty);
    });

    test('respeita o limite de tarefas por pacote', () {
      final s = Student(id: 's1', name: 'Ana', tasks: [
        for (var i = 0; i < 40; i++) task('t$i', t0, sent: false),
      ]);
      expect(buildTasksPackage(s, t0)!.taskCount, kMaxLessonTasks);
    });

    test('o aluno lê o pacote como "Tarefas de…" e não como aula', () {
      final s = Student(id: 's1', name: 'Ana', tasks: [task('n1', t0, sent: false)]);
      final rec = buildTasksPackage(s, t0, teacherName: 'Marina')!;
      final got = SharedLesson.tryFromWire(rec.wire, teacherCode: 'K7QM-4TXD', teacherName: 'Marina')!;
      expect(got.tasksOnly, isTrue);
      expect(got.label, startsWith('Tarefas de '));
      expect(got.teacherLabel, 'Marina · K7QM-4TXD');
      final aula = SharedLesson(id: 'x1', atMs: t0.millisecondsSinceEpoch, durationSec: 1800, tasks: got.tasks);
      expect(aula.tasksOnly, isFalse);
      expect(aula.label, startsWith('Aula de '));
    });

    test('rótulo do professor: nome e código, só o código ou nada', () {
      SharedLesson l(String n, String c) =>
          SharedLesson(id: 'a1', atMs: 0, teacherName: n, teacherCode: c);
      expect(l('Marina', 'K7QM-4TXD').teacherLabel, 'Marina · K7QM-4TXD');
      expect(l('', 'K7QM-4TXD').teacherLabel, 'Professor K7QM-4TXD');
      expect(l('Marina', '').teacherLabel, 'Marina');
      expect(l('', '').teacherLabel, 'Professor');
    });
  });

  group('regra de entrega (precisa estar em aula?)', () {
    TaskDelivery rule(Student s, {bool lesson = false, bool linkOn = true, bool up = true}) =>
        taskDeliveryFor(s, inLessonWithThis: lesson, linkOn: linkOn, serverUp: up);
    Student st({String? code = 'K7QM-4TXD', String? lk = 'active'}) =>
        Student(id: 's1', name: 'Ana', code: code, linkState: lk);

    test('não precisa estar em aula: vinculado recebe na hora', () {
      final d = rule(st());
      expect(d.mode, DeliveryMode.now);
      expect(d.canSend, isTrue);
      expect(d.text, contains('Ana'));
    });

    test('em aula: vai junto ao encerrar (não envia avulso)', () {
      final d = rule(st(), lesson: true);
      expect(d.mode, DeliveryMode.inLesson);
      expect(d.canSend, isFalse);
    });

    test('sem código ou vínculo encerrado: só na ficha, e diz como resolver', () {
      expect(rule(st(code: null, lk: null)).mode, DeliveryMode.localOnly);
      expect(rule(st(code: null, lk: null)).text, contains('Código do aluno'));
      expect(rule(st(lk: 'ended')).mode, DeliveryMode.localOnly);
      expect(rule(st(lk: 'ended')).canSend, isFalse);
    });

    test('vínculo desligado, servidor fora ou aluno ainda não vinculado: fila', () {
      expect(rule(st(), linkOn: false).mode, DeliveryMode.queued);
      expect(rule(st(), up: false).mode, DeliveryMode.queued);
      expect(rule(st(lk: 'pending')).mode, DeliveryMode.queued);
      expect(rule(st(lk: 'pending')).canSend, isTrue);
    });
  });
}

void messages() {
  final t0 = DateTime(2026, 11, 9, 10, 0);
  SharedLesson l({String name = 'Marina', int d = 0, int tasks = 2, List<String> notes = const []}) => SharedLesson(
      id: 'a1',
      atMs: t0.millisecondsSinceEpoch,
      teacherName: name,
      durationSec: d,
      notes: notes,
      tasks: [for (var i = 0; i < tasks; i++) Assignment(id: 't$i', title: 'x', created: t0)]);

  group('aviso ao aluno', () {
    test('tarefas avulsas', () {
      expect(newLessonsMessage([l()]), 'Marina passou 2 tarefas para você.');
      expect(newLessonsMessage([l(tasks: 1)]), 'Marina passou 1 tarefa para você.');
    });
    test('aula encerrada', () {
      expect(newLessonsMessage([l(d: 1800)]), 'Marina encerrou a aula e passou 2 tarefas.');
      expect(newLessonsMessage([l(d: 1800, tasks: 0, notes: ['x'])]), 'Marina encerrou a aula e deixou observações.');
      expect(newLessonsMessage([l(d: 1800, tasks: 0)]), 'Marina encerrou a aula.');
    });
    test('sem nome do professor e várias novidades', () {
      expect(newLessonsMessage([l(name: '')]), 'Seu professor passou 2 tarefas para você.');
      expect(newLessonsMessage([l(), l(d: 900, tasks: 1)]), '2 novidades dos seus professores: 3 tarefas novas.');
    });
  });
}
