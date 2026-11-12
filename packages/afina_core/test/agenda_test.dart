import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

int ms(int y, int m, int d, [int h = 0, int mi = 0]) => DateTime(y, m, d, h, mi).millisecondsSinceEpoch;

ClassSlot slot(String id, int start,
        {int dur = 60, bool weekly = false, List<int> skipped = const [], bool canceled = false, String sc = ''}) =>
    ClassSlot(
        id: id, studentCode: sc, startMs: start, durationMin: dur, weekly: weekly, skipped: skipped, updatedMs: 1, canceled: canceled);

void main() {
  final seg = ms(2026, 11, 9, 15); // segunda 15:00

  group('ocorrências', () {
    test('aula única: só uma vez, e some depois de passar', () {
      final s = slot('a1', seg);
      expect(s.nextStart(seg - 1000), seg);
      expect(s.nextStart(seg), seg);
      expect(s.nextStart(seg + 1), isNull);
      expect(s.occurrencesBetween(seg - kMsDay, seg + kMsDay), [seg]);
    });

    test('semanal: toda segunda, no mesmo horário (uma regra só)', () {
      final s = slot('a1', seg, weekly: true);
      expect(s.nextStart(seg + 1), seg + kMsWeek);
      expect(s.nextStart(seg + 3 * kMsWeek - 5), seg + 3 * kMsWeek);
      expect(s.occurrencesBetween(seg, seg + 4 * kMsWeek), [seg, seg + kMsWeek, seg + 2 * kMsWeek, seg + 3 * kMsWeek]);
      expect(s.nextStart(seg - 5 * kMsDay), seg, reason: 'antes do início, a primeira é a de início');
    });

    test('cancelar só um dia: pula aquele e segue a regra', () {
      final s = slot('a1', seg, weekly: true, skipped: [seg + kMsWeek]);
      expect(s.nextStart(seg + 1), seg + 2 * kMsWeek);
      expect(s.occurrencesBetween(seg, seg + 3 * kMsWeek), [seg, seg + 2 * kMsWeek]);
    });

    test('regra cancelada não tem ocorrência nem em andamento', () {
      final s = slot('a1', seg, weekly: true, canceled: true);
      expect(s.nextStart(seg), isNull);
      expect(s.occurrencesBetween(seg, seg + kMsWeek), isEmpty);
      expect(s.ongoingStart(seg + kMsMinute), isNull);
    });

    test('em andamento: do início até o fim da duração', () {
      final s = slot('a1', seg, dur: 45, weekly: true);
      expect(s.ongoingStart(seg - 1), isNull);
      expect(s.ongoingStart(seg), seg);
      expect(s.ongoingStart(seg + 44 * kMsMinute), seg);
      expect(s.ongoingStart(seg + 45 * kMsMinute), isNull);
      expect(s.ongoingStart(seg + kMsWeek + kMsMinute), seg + kMsWeek);
    });

    test('lembrete é 15 minutos antes do início', () {
      expect(ClassSlot.reminderAt(seg), seg - 15 * kMsMinute);
    });
  });

  group('agenda do professor', () {
    final ana = slot('ana', ms(2026, 11, 9, 15), weekly: true, sc: 'K7QM-4TXK');
    final bia = slot('bia', ms(2026, 11, 10, 9));
    final cel = slot('cel', ms(2026, 11, 9, 8), weekly: true, canceled: true);

    test('um dia: só as aulas dele, em ordem de horário', () {
      expect(agendaDay([bia, ana, cel], DateTime(2026, 11, 9)).map((o) => o.slot.id), ['ana']);
      expect(agendaDay([bia, ana], DateTime(2026, 11, 10)).map((o) => o.slot.id), ['bia']);
      expect(agendaDay([bia, ana], DateTime(2026, 11, 16)).map((o) => o.slot.id), ['ana'], reason: 'a semanal volta');
    });

    test('mês: quantas aulas em cada dia', () {
      final c = agendaMonthCounts([ana, bia], DateTime(2026, 11, 20));
      expect(c[9], 1);
      expect(c[10], 1);
      expect(c[16], 1);
      expect(c[23], 1);
      expect(c[30], 1);
      expect(c[11], isNull);
    });

    test('semana começa na segunda', () {
      expect(weekStart(DateTime(2026, 11, 12)), DateTime(2026, 11, 9));
      expect(weekStart(DateTime(2026, 11, 15)), DateTime(2026, 11, 9));
      expect(weekStart(DateTime(2026, 11, 9)), DateTime(2026, 11, 9));
    });

    test('próxima aula entre várias (ou a que está em andamento)', () {
      expect(nextOccurrence([bia, ana], seg - kMsDay)!.slot.id, 'ana');
      expect(nextOccurrence([bia, ana], seg + 10 * kMsMinute)!.slot.id, 'ana', reason: 'em andamento conta');
      expect(nextOccurrence([bia, ana], seg + 90 * kMsMinute)!.slot.id, 'bia');
      expect(nextOccurrence([cel], seg), isNull);
    });
  });

  group('regra: duas aulas do professor não se sobrepõem', () {
    final now = ms(2026, 11, 1);
    final base = slot('a', ms(2026, 11, 9, 15), dur: 60, weekly: true);

    test('horário livre: sem conflito', () {
      expect(findConflict(slot('b', ms(2026, 11, 9, 16)), [base], now), isNull, reason: 'encosta no fim, não sobrepõe');
      expect(findConflict(slot('b', ms(2026, 11, 9, 13), dur: 60), [base], now), isNull);
    });

    test('sobrepõe parte da aula: conflito', () {
      final c = findConflict(slot('b', ms(2026, 11, 9, 15, 30)), [base], now);
      expect(c, isNotNull);
      expect(c!.slot.id, 'a');
    });

    test('conflito numa semana futura da regra semanal', () {
      expect(findConflict(slot('b', ms(2026, 11, 23, 15, 15), dur: 30), [base], now), isNotNull);
    });

    test('editar a própria aula não conflita com ela mesma; aula cancelada não conta', () {
      expect(findConflict(base.copyWith(note: 'x'), [base], now), isNull);
      expect(findConflict(slot('b', ms(2026, 11, 9, 15)), [base.copyWith(canceled: true)], now), isNull);
    });
  });

  group('leitura segura do servidor/disco', () {
    test('vai e volta, sem os campos de controle no pacote do servidor', () {
      final s = ClassSlot(
          id: 'a1',
          studentCode: 'K7QM-4TXK',
          startMs: seg,
          durationMin: 45,
          weekly: true,
          skipped: [seg + kMsWeek],
          note: 'Trazer o arco',
          updatedMs: 99,
          pending: true);
      final back = ClassSlot.tryFrom(s.toJson())!;
      expect(back.studentCode, 'K7QM-4TXK');
      expect(back.pending, true);
      expect(back.weekly, true);
      expect(back.skipped, [seg + kMsWeek]);
      final wire = s.toWire();
      expect(wire.containsKey('sc'), isFalse);
      expect(wire.containsKey('p'), isFalse);
    });

    test('valores absurdos são limitados ou recusados', () {
      expect(ClassSlot.tryFrom({'id': 'A B', 's': seg}), isNull);
      expect(ClassSlot.tryFrom({'id': 'ok1', 's': 5}), isNull);
      expect(ClassSlot.tryFrom({'id': 'ok1', 's': seg, 'd': 99999})!.durationMin, kMaxSlotMinutes);
      expect(ClassSlot.tryFrom({'id': 'ok1', 's': seg, 'd': 1})!.durationMin, kMinSlotMinutes);
      expect(ClassSlot.tryFrom({'id': 'ok1', 's': seg, 'x': List.generate(100, (i) => i)})!.skipped.length, kMaxSlotSkips);
      expect(ClassSlot.tryFrom({'id': 'ok1', 's': seg, 'n': 'a' * 500})!.note.length, kMaxSlotNote);
      expect(ClassSlot.tryFrom('lixo'), isNull);
    });

    test('o aluno lê com o professor informado pelo servidor', () {
      final got = ClassSlot.tryFrom({'id': 'a1', 's': seg}, teacherCode: 'K7QM-4TXK', teacherName: 'Marina')!;
      expect(got.teacherCode, 'K7QM-4TXK');
      expect(got.teacherName, 'Marina');
    });
  });

  test('texto de quando: hoje, amanhã ou o dia da semana', () {
    final now = DateTime(2026, 11, 9, 10);
    expect(fmtSlotWhen(DateTime(2026, 11, 9, 15), now), 'hoje, 15:00');
    expect(fmtSlotWhen(DateTime(2026, 11, 10, 9, 30), now), 'amanhã, 09:30');
    expect(fmtSlotWhen(DateTime(2026, 11, 12, 15), now), 'quinta, 12/11, 15:00');
  });

  group('texto do horário (aviso de sucesso)', () {
    // 18/11/2026 é quarta-feira.
    final quarta = DateTime(2026, 11, 18, 15).millisecondsSinceEpoch;
    test('toda semana diz "Toda quarta"', () {
      final s = ClassSlot(id: 'a1', startMs: quarta, durationMin: 45, weekly: true, updatedMs: 1);
      expect(describeSlot(s), 'Toda quarta às 15:00 · 45 min');
    });
    test('avulso diz o dia e a data, sem "Toda"', () {
      final s = ClassSlot(id: 'a2', startMs: quarta, durationMin: 45, updatedMs: 1);
      expect(describeSlot(s), 'Quarta, 18/11 às 15:00 · 45 min');
    });
    test('zero à esquerda em hora, dia e mês', () {
      final s = ClassSlot(id: 'a3', startMs: DateTime(2027, 3, 5, 8, 5).millisecondsSinceEpoch, durationMin: 30, updatedMs: 1);
      expect(describeSlot(s), 'Sexta, 05/03 às 08:05 · 30 min');
    });
  });

  test('o texto do horário diz "online" só quando for online', () {
    final on = ClassSlot(id: 'b1', startMs: DateTime(2026, 11, 18, 15).millisecondsSinceEpoch, durationMin: 45, weekly: true, updatedMs: 1, mode: kModeOnline);
    expect(describeSlot(on), 'Toda quarta às 15:00 · 45 min · online');
    expect(describeSlot(on.copyWith(mode: kModeInPerson)), 'Toda quarta às 15:00 · 45 min');
  });

  group('aula online (modo e link)', () {
    test('link: só https de verdade, sem usuário e sem enfeites', () {
      expect(meetingUrl('https://meet.google.com/abc-defg-hij'), 'https://meet.google.com/abc-defg-hij');
      expect(meetingUrl('  https://zoom.us/j/123?pwd=abc  '), isNotNull);
      expect(meetingUrl('http://meet.google.com/abc'), isNull);
      expect(meetingUrl('javascript:alert(1)'), isNull);
      expect(meetingUrl('https://user:pw@meet.google.com/abc'), isNull);
      expect(meetingUrl('https://meet.google.com/abc def'), isNull);
      expect(meetingUrl('https://localhost/sala'), isNull);
      expect(meetingUrl(''), isNull);
      expect(meetingUrl(null), isNull);
      expect(meetingUrl('https://${'a' * 310}.com'), isNull);
    });
    test('sites conhecidos e o domínio mostrado ao usuário', () {
      expect(isKnownMeetingLink('https://meet.google.com/abc'), isTrue);
      expect(isKnownMeetingLink('https://us02web.zoom.us/j/1'), isTrue);
      expect(isKnownMeetingLink('https://meet.google.com.golpe.com/abc'), isFalse);
      expect(isKnownMeetingLink('https://minha-sala.exemplo.com/x'), isFalse);
      expect(meetingHost('https://Minha-Sala.Exemplo.com/x'), 'minha-sala.exemplo.com');
      expect(meetingHost('http://x.com'), '');
    });
    ClassSlot base({String mode = kModeNone, String link = ''}) => ClassSlot(id: 'a1', startMs: 1800000000000, updatedMs: 5, mode: mode, link: link);
    test('aula antiga (sem modo) segue igual no formato do servidor', () {
      final w = base().toWire();
      expect(w.containsKey('m'), isFalse);
      expect(w.containsKey('l'), isFalse);
      expect(ClassSlot.tryFrom(w)!.mode, kModeNone);
    });
    test('online com link vai e volta; presencial não leva link', () {
      final o = ClassSlot.tryFrom(base(mode: kModeOnline, link: 'https://meet.google.com/abc').toWire())!;
      expect(o.online, isTrue);
      expect(o.hasLink, isTrue);
      expect(o.link, 'https://meet.google.com/abc');
      final p = base(mode: kModeInPerson, link: 'https://meet.google.com/abc');
      expect(p.toWire()['m'], 'p');
      expect(p.toWire().containsKey('l'), isFalse);
    });
    test('online sem link é aula online; link ruim vindo de fora é descartado', () {
      final o = ClassSlot.tryFrom(base(mode: kModeOnline).toWire())!;
      expect(o.online, isTrue);
      expect(o.hasLink, isFalse);
      final ruim = ClassSlot.tryFrom({...base(mode: kModeOnline).toWire(), 'l': 'javascript:alert(1)'})!;
      expect(ruim.online, isTrue);
      expect(ruim.link, '');
      final solto = ClassSlot.tryFrom({...base().toWire(), 'l': 'https://meet.google.com/abc'})!; // link sem modo online
      expect(solto.link, '');
    });
    test('copyWith mantém modo e link', () {
      final s = base(mode: kModeOnline, link: 'https://meet.google.com/abc').copyWith(durationMin: 30);
      expect(s.mode, kModeOnline);
      expect(s.link, 'https://meet.google.com/abc');
      expect(s.copyWith(link: '').hasLink, isFalse);
    });
  });
}
