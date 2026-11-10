import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 9, 14, 0).millisecondsSinceEpoch;
  int at(int h, int m, [int day = 9]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;
  ClassSlot slot(String id, int start, {String sc = 'K7QM-4TXK', int min = 60, bool weekly = false, bool canceled = false}) =>
      ClassSlot(id: id, studentCode: sc, startMs: start, durationMin: min, weekly: weekly, canceled: canceled, updatedMs: 1);

  group('fase da aula', () {
    int end(int s) => s + 60 * kMsMinute;
    test('futura, em breve, em andamento e encerrada', () {
      expect(classPhase(at(16, 0), end(at(16, 0)), now), ClassPhase.upcoming);
      expect(classPhase(at(14, 16), end(at(14, 16)), now), ClassPhase.upcoming);
      expect(classPhase(at(14, 15), end(at(14, 15)), now), ClassPhase.soon, reason: 'exatamente 15 min');
      expect(classPhase(at(14, 0), end(at(14, 0)), now), ClassPhase.ongoing, reason: 'no instante do início');
      expect(classPhase(at(13, 0), end(at(13, 0)), now), ClassPhase.finished, reason: 'no instante do fim');
      expect(classPhase(at(13, 30), end(at(13, 30)), now), ClassPhase.ongoing);
    });
    test('rótulos', () {
      expect(classPhaseLabel(ClassPhase.upcoming), '');
      expect(classPhaseLabel(ClassPhase.soon), 'começa em breve');
      expect(classPhaseLabel(ClassPhase.ongoing), 'em andamento');
      expect(classPhaseLabel(ClassPhase.finished), 'encerrada');
    });
  });

  group('permissões', () {
    test('aluno nunca muda nem cancela nem começa', () {
      for (final p in ClassPhase.values) {
        final c = classPermissions(ClassViewer.student, p);
        expect([c.edit, c.cancel, c.start], [false, false, false]);
      }
    });
    test('professor: muda e cancela antes; começa perto do horário; encerrada é histórico', () {
      var c = classPermissions(ClassViewer.teacher, ClassPhase.upcoming);
      expect([c.edit, c.cancel, c.start], [true, true, false]);
      c = classPermissions(ClassViewer.teacher, ClassPhase.soon);
      expect([c.edit, c.cancel, c.start], [true, true, true]);
      c = classPermissions(ClassViewer.teacher, ClassPhase.ongoing);
      expect([c.edit, c.cancel, c.start], [true, false, true], reason: 'já começou: não cancela, só ajusta');
      c = classPermissions(ClassViewer.teacher, ClassPhase.finished);
      expect([c.edit, c.cancel, c.start], [false, false, false]);
    });
  });

  group('agenda visível e resumo do dia', () {
    test('some aula cancelada e de aluno que o professor já não tem', () {
      final v = visibleTeacherSlots([
        slot('a1', at(15, 0)),
        slot('a2', at(16, 0), canceled: true),
        slot('a3', at(17, 0), sc: 'ZZZZ-ZZZZ'),
      ], {'K7QM-4TXK'});
      expect(v.map((s) => s.id), ['a1']);
    });

    test('hub e agenda contam igual: aulas do dia, restantes, em andamento e próxima', () {
      final slots = [slot('m', at(9, 0)), slot('on', at(13, 30)), slot('t1', at(15, 0)), slot('t2', at(18, 0)), slot('amanha', at(15, 0, 10))];
      final d = classesToday(slots, DateTime(2026, 11, 9, 14, 0));
      expect(d.count, 4);
      expect(d.remaining.map((o) => o.slot.id), ['on', 't1', 't2']);
      expect(d.ongoing!.slot.id, 'on');
      expect(d.next!.slot.id, 'on');
    });

    test('aula semanal entra no dia certo; dia sem aula', () {
      final w = slot('w', at(15, 0, 2), weekly: true); // toda segunda
      expect(classesToday([w], DateTime(2026, 11, 9, 8, 0)).count, 1);
      expect(classesToday([w], DateTime(2026, 11, 10, 8, 0)).count, 0);
      final vazio = classesToday([], DateTime(2026, 11, 9));
      expect([vazio.count, vazio.ongoing, vazio.next], [0, null, null]);
    });
  });
}
