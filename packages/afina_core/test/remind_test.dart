import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final seg = DateTime(2026, 11, 9, 15).millisecondsSinceEpoch;
  ClassSlot slot({int? r, bool weekly = false}) => ClassSlot(
        id: 'aula1',
        studentCode: 'K7QM-4TXK',
        startMs: seg,
        durationMin: 60,
        weekly: weekly,
        updatedMs: 1,
        remindMin: r,
      );

  group('lembrete escolhido pelo professor', () {
    test('sem escolha vale o padrão de 15 minutos', () {
      expect(slot().remindMin, isNull);
      expect(slot().remindLead, 15);
      expect(slot(r: 30).remindLead, 30);
      expect(slot(r: 0).remindLead, 0, reason: '0 = sem lembrete, não "padrão"');
    });

    test('as opções são as do servidor, em ordem', () {
      expect(kRemindOptions, [0, 5, 10, 15, 30, 60, 120, 1440]);
      expect(kRemindOptions.contains(kReminderMinutes), isTrue);
    });

    test('textos das opções', () {
      expect(remindLabel(0), 'Sem lembrete');
      expect(remindLabel(5), '5 minutos antes');
      expect(remindLabel(15), '15 minutos antes');
      expect(remindLabel(60), '1 hora antes');
      expect(remindLabel(120), '2 horas antes');
      expect(remindLabel(1440), '1 dia antes');
      expect(remindLabel(2880), '2 dias antes');
    });

    test('o horário do aviso segue a antecedência', () {
      expect(ClassSlot.reminderAt(seg), seg - 15 * kMsMinute);
      expect(ClassSlot.reminderAt(seg, 60), seg - 60 * kMsMinute);
      expect(ClassSlot.reminderAt(seg, slot(r: 30).remindLead), seg - 30 * kMsMinute);
    });

    test('vai e volta do servidor e do disco; sem escolha não manda o campo', () {
      expect(slot().toWire().containsKey('r'), isFalse);
      expect(slot(r: 60).toWire()['r'], 60);
      expect(slot(r: 0).toWire()['r'], 0, reason: 'sem lembrete também é uma escolha e precisa ir');
      for (final r in [0, 5, 30, 1440]) {
        expect(ClassSlot.tryFrom(slot(r: r).toJson())!.remindMin, r);
      }
      expect(ClassSlot.tryFrom(slot().toJson())!.remindMin, isNull);
    });

    test('valor estranho vindo de fora vira "padrão"', () {
      Map<String, dynamic> com(Object? r) => {...slot().toWire(), 'r': r};
      for (final r in [7, -5, 1441, 'abc', null, 99999]) {
        expect(ClassSlot.tryFrom(com(r))!.remindMin, isNull, reason: 'r=$r');
      }
      expect(ClassSlot.tryFrom(com(30.0))!.remindMin, 30);
    });

    test('copyWith mantém a escolha e troca quando pedido', () {
      expect(slot(r: 30).copyWith(note: 'x').remindMin, 30);
      expect(slot(r: 30).copyWith(remindMin: 120).remindMin, 120);
      expect(slot(r: 30).copyWith(remindMin: 0).remindMin, 0);
    });

    test('remarcar só um dia: a aula nova herda a escolha', () {
      final regra = slot(r: 60, weekly: true);
      final plan = planMoveOccurrence(regra, seg, seg + 2 * kMsDay, newId: 'nova1');
      expect(plan.ok, isTrue);
      final nova = plan.changed.firstWhere((c) => c.id == 'nova1');
      expect(nova.remindMin, 60);
      expect(plan.changed.firstWhere((c) => c.id == 'aula1').remindMin, 60);
    });

    test('horário livre: a aula que nasce herda a escolha', () {
      final livre = slot(r: 120);
      final c = classFromOpen(livre, studentCode: 'K7QM-4TXK', id: 'pega1', nowMs: seg - kMsDay);
      expect(c.remindMin, 120);
    });
  });
}
