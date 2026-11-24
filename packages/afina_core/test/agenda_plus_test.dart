import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  zoneTests();
  final t0 = DateTime.utc(2026, 11, 30, 19).millisecondsSinceEpoch; // segunda, 19h UTC
  const week = 7 * kMsDay;

  ClassSlot weekly({int? endMs, List<int> skipped = const [], String note = '', String link = '', int? remind}) => ClassSlot(
        id: 'aula1',
        studentCode: 'ABCD-2345',
        startMs: t0,
        durationMin: 60,
        weekly: true,
        updatedMs: t0 - kMsDay,
        endMs: endMs,
        skipped: skipped,
        note: note,
        mode: link.isEmpty ? kModeNone : kModeOnline,
        link: link,
        remindMin: remind,
      );

  group('data final da aula semanal', () {
    test('sem data final a aula continua; com ela, a última aula é a que começa até a data', () {
      final inf = weekly();
      expect(inf.nextStart(t0 + 20 * week), t0 + 20 * week);
      final fim = weekly(endMs: t0 + 2 * week);
      expect(fim.occurrencesBetween(t0, t0 + 10 * week), [t0, t0 + week, t0 + 2 * week]);
      expect(fim.nextStart(t0 + 2 * week + 1), isNull);
      expect(fim.nextStart(t0 + week + 1), t0 + 2 * week);
    });

    test('a aula em andamento depois da data final não existe; conflito respeita a data', () {
      final fim = weekly(endMs: t0 + week);
      expect(fim.ongoingStart(t0 + 2 * week + 10 * kMsMinute), isNull);
      expect(fim.ongoingStart(t0 + week + 10 * kMsMinute), t0 + week);
      final depois = ClassSlot(id: 'outra', startMs: t0 + 3 * week, updatedMs: 1);
      expect(findConflict(depois, [fim], t0 - kMsDay), isNull);
      final dentro = ClassSlot(id: 'dentro', startMs: t0 + week, updatedMs: 1);
      expect(findConflict(dentro, [fim], t0 - kMsDay), isNotNull);
    });

    test('data final inválida (antes do início, aula única, longe demais) é descartada ao ler', () {
      Map<String, dynamic> base(Map<String, dynamic> extra) => {'id': 'aaa1', 's': t0, 'd': 60, 'u': 1, ...extra};
      expect(ClassSlot.tryFrom(base({'w': 1, 'e': t0 - 1}))!.endMs, isNull);
      expect(ClassSlot.tryFrom(base({'e': t0 + week}))!.endMs, isNull, reason: 'só vale para semanal');
      expect(ClassSlot.tryFrom(base({'w': 1, 'e': t0 + 6000 * kMsDay}))!.endMs, isNull);
      expect(ClassSlot.tryFrom(base({'w': 1, 'e': t0 + week}))!.endMs, t0 + week);
    });
  });

  group('campos novos no formato do servidor', () {
    test('"confirmo antes", fuso e data final vão e voltam; o servidor sempre recebe cf e e (0 apaga)', () {
      final s = weekly(endMs: t0 + 4 * week).copyWith(confirmFirst: true, tzMin: -180);
      final back = ClassSlot.tryFrom(s.toJson())!;
      expect(back.confirmFirst, isTrue);
      expect(back.tzMin, -180);
      expect(back.endMs, t0 + 4 * week);
      final limpo = weekly().toWire();
      expect(limpo['cf'], 0);
      expect(limpo['e'], 0);
      expect(limpo.containsKey('z'), isFalse);
    });

    test('copyWith consegue apagar a data final e o fuso', () {
      final s = weekly(endMs: t0 + week).copyWith(tzMin: -180);
      expect(s.copyWith(endMs: null).endMs, isNull);
      expect(s.copyWith(tzMin: null).tzMin, isNull);
      expect(s.copyWith(note: 'x').endMs, t0 + week, reason: 'sem pedir, mantém');
    });

    test('fuso fora do normal é ignorado; aula antiga sem os campos abre igual', () {
      expect(ClassSlot.tryFrom({'id': 'aaa1', 's': t0, 'z': 99999})!.tzMin, isNull);
      expect(ClassSlot.tryFrom({'id': 'aaa1', 's': t0, 'z': -190})!.tzMin, isNull, reason: 'não é múltiplo de 15');
      final velha = ClassSlot.tryFrom({'id': 'aaa1', 's': t0, 'd': 45})!;
      expect(velha.confirmFirst, isFalse);
      expect(velha.endMs, isNull);
    });

    test('a aula que nasce de um horário livre herda fuso e data final', () {
      final livre = weekly(endMs: t0 + 5 * week).copyWith(tzMin: -180);
      final aula = classFromOpen(livre, studentCode: 'WXYZ-2345', id: 'p1', nowMs: t0);
      expect(aula.tzMin, -180);
      expect(aula.endMs, t0 + 5 * week);
    });
  });

  group('arquivo de calendário (.ics)', () {
    String ics(Iterable<ClassSlot> s) => buildIcs(s, titleOf: (x) => 'Aula com Ana', nowMs: t0 - 2 * kMsDay);

    test('aula semanal: regra, data final, datas canceladas e lembrete', () {
      final out = ics([weekly(endMs: t0 + 4 * week, skipped: [t0 + week], remind: 30)]);
      expect(out, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(out, endsWith('END:VCALENDAR\r\n'));
      expect(out, contains('DTSTART:20261130T190000Z'));
      expect(out, contains('DTEND:20261130T200000Z'));
      expect(out, contains('RRULE:FREQ=WEEKLY;UNTIL=20261228T200000Z'));
      expect(out, contains('EXDATE:20261207T190000Z'));
      expect(out, contains('TRIGGER:-PT30M'));
      expect(out, contains('UID:aula1@notemusic'));
    });

    test('texto com vírgula, ponto e vírgula e quebra de linha é escapado; linhas longas são dobradas', () {
      final out = ics([weekly(note: 'Trazer: Bach, Suzuki; livro 2\nobrigado', link: 'https://meet.google.com/abc-defg-hij?authuser=0&pli=1&extra=${'x' * 90}')]);
      expect(out, contains('Trazer: Bach\\, Suzuki\\; livro 2\\nobrigado'));
      for (final l in out.split('\r\n')) {
        expect(l.length, lessThanOrEqualTo(75), reason: l);
      }
    });

    test('aula cancelada e aula única que já passou não entram; sem lembrete não há alarme', () {
      final cancelada = weekly().copyWith(canceled: true);
      final passada = ClassSlot(id: 'velha', startMs: t0 - 30 * kMsDay, updatedMs: 1);
      final futura = ClassSlot(id: 'unica', startMs: t0 + kMsDay, updatedMs: 1, remindMin: 0);
      final out = ics([cancelada, passada, futura]);
      expect(out, isNot(contains('UID:aula1@')));
      expect(out, isNot(contains('UID:velha@')));
      expect(out, contains('UID:unica@notemusic'));
      expect(out, isNot(contains('VALARM')));
      expect(out, isNot(contains('RRULE')));
    });
  });
}

void zoneTests() {
  group('fuso da aula', () {
    test('mostra a hora no fuso de quem marcou só quando é diferente do daqui', () {
      final t0 = DateTime.utc(2026, 11, 30, 19).millisecondsSinceEpoch;
      final s = ClassSlot(id: 'aaa1', startMs: t0, updatedMs: 1, tzMin: -180);
      expect(otherZoneNote(s, localOffsetMin: -180), isNull);
      expect(otherZoneNote(s, localOffsetMin: 0), '16:00 (UTC-3)');
      expect(otherZoneNote(ClassSlot(id: 'aaa1', startMs: t0, updatedMs: 1), localOffsetMin: 0), isNull, reason: 'sem fuso informado');
      expect(tzLabel(330), 'UTC+5:30');
      expect(tzLabel(-180), 'UTC-3');
    });
  });
}
