import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final aula = DateTime(2026, 11, 16, 17).millisecondsSinceEpoch;
  int at(int h, [int m = 0]) => DateTime(2026, 11, 16, h, m).millisecondsSinceEpoch;
  ClassSlot slot(String id, int start, {bool weekly = false, bool canceled = false}) =>
      ClassSlot(id: id, studentCode: 'K7QM-4TXK', startMs: start, durationMin: 45, weekly: weekly, canceled: canceled, updatedMs: 1);

  group('falta do aluno', () {
    test('vai e volta do disco', () {
      final a = Absence(lessonMs: aula, kind: AbsenceKind.notified, recordedMs: aula + 60000);
      final b = Absence.tryFrom(a.toJson())!;
      expect(b.lessonMs, aula);
      expect(b.kind, AbsenceKind.notified);
      expect(b.recordedMs, aula + 60000);
      expect(Absence.tryFrom({'l': aula, 'k': 'f', 'r': 5})!.kind, AbsenceKind.noShow);
    });

    test('dado estranho é ignorado', () {
      for (final j in [null, 'x', {'l': 'abc'}, {'l': 5}, {'k': 'n'}, <String, dynamic>{}]) {
        expect(Absence.tryFrom(j), isNull, reason: '$j');
      }
    });

    test('o aluno guarda as faltas e um arquivo antigo (sem faltas) continua abrindo', () {
      final s = Student(id: 's1', name: 'Ana');
      expect(s.absences, isEmpty);
      expect(s.toJson().containsKey('abs'), isFalse, reason: 'sem faltas não escreve nada novo');
      s.absences = addAbsence(s.absences, Absence(lessonMs: aula, kind: AbsenceKind.noShow, recordedMs: aula));
      final volta = Student.tryFrom(s.toJson())!;
      expect(volta.absences.length, 1);
      expect(volta.absences.first.lessonMs, aula);
      final antigo = Map<String, dynamic>.from(Student(id: 's2', name: 'Bia').toJson());
      expect(Student.tryFrom(antigo)!.absences, isEmpty);
    });

    test('corrigir a falta da mesma aula troca o registro em vez de contar duas vezes', () {
      var l = addAbsence(const [], Absence(lessonMs: aula, kind: AbsenceKind.noShow, recordedMs: 1));
      l = addAbsence(l, Absence(lessonMs: aula, kind: AbsenceKind.notified, recordedMs: 2));
      expect(l.length, 1);
      expect(l.single.kind, AbsenceKind.notified);
    });

    test('mais recente primeiro e com limite', () {
      var l = <Absence>[];
      for (var i = 0; i < kMaxAbsences + 5; i++) {
        l = addAbsence(l, Absence(lessonMs: aula + i * kMsDay, kind: AbsenceKind.noShow, recordedMs: i));
      }
      expect(l.length, kMaxAbsences);
      expect(l.first.lessonMs, aula + (kMaxAbsences + 4) * kMsDay);
      expect(l.first.lessonMs > l.last.lessonMs, isTrue);
    });

    test('contar desde uma data', () {
      final l = [
        Absence(lessonMs: aula, kind: AbsenceKind.noShow, recordedMs: 1),
        Absence(lessonMs: aula - 40 * kMsDay, kind: AbsenceKind.noShow, recordedMs: 1),
      ];
      expect(absencesSince(l), 2);
      expect(absencesSince(l, sinceMs: aula - 30 * kMsDay), 1);
    });
  });

  group('qual é a aula que o aluno perdeu', () {
    test('a mais perto de agora, entre 3 h atrás e 12 h à frente', () {
      final manha = slot('m', at(9));
      final tarde = slot('t', at(17));
      expect(lessonForAbsence([manha, tarde], at(16, 50))!.slot.id, 't');
      expect(lessonForAbsence([manha, tarde], at(9, 20))!.slot.id, 'm', reason: 'já começou há 20 min');
      expect(lessonForAbsence([manha, tarde], at(14))!.slot.id, 't', reason: '3 h antes da tarde e 5 h depois da manhã (a da manhã já saiu da janela)');
    });

    test('sem aula por perto: nada', () {
      expect(lessonForAbsence([slot('t', at(17))], at(8)), isNotNull, reason: '9 h antes ainda cabe nas 12 h');
      expect(lessonForAbsence([slot('t', at(17))], at(3)), isNull, reason: '14 h antes');
      expect(lessonForAbsence([slot('t', at(8))], at(13)), isNull, reason: 'começou há 5 h');
      expect(lessonForAbsence(const [], at(17)), isNull);
    });

    test('aula cancelada não conta e semanal vale na data de hoje', () {
      expect(lessonForAbsence([slot('c', at(17), canceled: true)], at(17)), isNull);
      final semanal = slot('s', at(17) - 14 * kMsDay, weekly: true);
      expect(lessonForAbsence([semanal], at(17, 10))!.startMs, at(17));
    });
  });
}
