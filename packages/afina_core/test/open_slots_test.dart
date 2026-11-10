import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 9, 10, 0).millisecondsSinceEpoch;
  int at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;
  ClassSlot slot(String id, int start, {int min = 60, bool weekly = false, bool canceled = false, String sc = ''}) =>
      ClassSlot(id: id, studentCode: sc, startMs: start, durationMin: min, weekly: weekly, canceled: canceled, updatedMs: 1);

  group('professor cria horário disponível', () {
    test('livre: pode', () {
      expect(checkNewOpenSlot(slot('a1', at(11, 15)), open: [], classes: [], nowMs: now), isNull);
    });
    test('passado, cancelado e choque', () {
      expect(checkNewOpenSlot(slot('a1', at(8, 15)), open: [], classes: [], nowMs: now), SlotProblem.past);
      expect(checkNewOpenSlot(slot('a1', at(11, 15), canceled: true), open: [], classes: [], nowMs: now), SlotProblem.canceled);
      final aula = slot('c1', at(11, 15), sc: 'K7QM-4TXK');
      expect(checkNewOpenSlot(slot('a1', at(11, 15, 30)), open: [], classes: [aula], nowMs: now), SlotProblem.conflict);
      expect(checkNewOpenSlot(slot('a1', at(11, 16)), open: [], classes: [aula], nowMs: now), isNull, reason: 'encosta no fim: livre');
      final outro = slot('a2', at(11, 9));
      expect(checkNewOpenSlot(slot('a1', at(11, 9, 30)), open: [outro], classes: [], nowMs: now), SlotProblem.conflict);
    });
    test('semanal bate com aula de outra semana na mesma hora', () {
      final aula = slot('c1', at(18, 15), sc: 'K7QM-4TXK');
      expect(checkNewOpenSlot(slot('a1', at(11, 15), weekly: true), open: [], classes: [aula], nowMs: now), SlotProblem.conflict);
    });
    test('limite por professor; editar o mesmo horário não conta duas vezes', () {
      final many = [for (var i = 0; i < kMaxOpenSlots; i++) slot('o${i + 10}', at(11, 8) + i * 2 * kMsDay)];
      expect(checkNewOpenSlot(slot('novo1', at(11, 15)), open: many, classes: [], nowMs: now), SlotProblem.limit);
      expect(checkNewOpenSlot(many.first.copyWith(note: 'x'), open: many, classes: [], nowMs: now), isNull);
    });
  });

  group('aluno pega um horário', () {
    final open = slot('a1', at(11, 15));
    test('pode', () {
      expect(checkPick(open, teacherClasses: [], studentUpcoming: 0, nowMs: now), isNull);
    });
    test('passado e perto demais', () {
      expect(checkPick(slot('a1', at(9, 9)), teacherClasses: [], studentUpcoming: 0, nowMs: now), SlotProblem.past);
      expect(checkPick(slot('a1', at(9, 10, 40)), teacherClasses: [], studentUpcoming: 0, nowMs: now), SlotProblem.tooSoon);
      expect(checkPick(slot('a1', at(9, 11)), teacherClasses: [], studentUpcoming: 0, nowMs: now), isNull, reason: 'exatamente 60 min');
    });
    test('choque com aula do professor e limite do aluno', () {
      final aula = slot('c1', at(11, 14, 30));
      expect(checkPick(open, teacherClasses: [aula], studentUpcoming: 0, nowMs: now), SlotProblem.conflict);
      expect(checkPick(open, teacherClasses: [], studentUpcoming: kMaxPicksPerStudent, nowMs: now), SlotProblem.limit);
      expect(checkPick(open, teacherClasses: [aula.copyWith(canceled: true)], studentUpcoming: 0, nowMs: now), isNull);
    });
    test('lista só o que dá para pegar, do mais próximo ao mais distante', () {
      final l = pickableSlots([
        slot('z', at(13, 9)),
        slot('p', at(8, 9)),
        slot('c', at(11, 15), canceled: true),
        slot('b', at(11, 15)),
        slot('x', at(11, 16)),
      ], teacherClasses: [slot('k', at(11, 16), sc: 'K7QM-4TXK')], nowMs: now);
      expect(l.map((s) => s.id), ['b', 'z']);
    });
  });

  test('aula criada herda dia, hora, duração e repetição; já nasce enviada', () {
    final c = classFromOpen(slot('a1', at(11, 15), min: 45, weekly: true), studentCode: 'K7QM-4TXK', id: 'novaaula', nowMs: now);
    expect(c.id, 'novaaula');
    expect(c.studentCode, 'K7QM-4TXK');
    expect([c.startMs, c.durationMin, c.weekly], [at(11, 15), 45, true]);
    expect(c.updatedMs, now);
    expect(c.pending, isFalse);
  });

  test('textos dos motivos', () {
    for (final p in SlotProblem.values) {
      expect(slotProblemText(p), isNotEmpty);
    }
  });
}
