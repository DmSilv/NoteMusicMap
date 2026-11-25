import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 27, 18); // sexta

  Assignment task(String id, {int daysAgo = 5, bool done = false, DateTime? claimed}) => Assignment(
      id: id, title: 'Tarefa $id', kind: TaskKind.free, created: now.subtract(Duration(days: daysAgo)), done: done, claimedAt: claimed);

  Student st(String id, {List<Assignment>? tasks, bool paused = false, String? code, List<int>? days, DateTime? reminded}) => Student(
      id: id, name: 'Aluno $id', code: code, tasks: tasks, paused: paused, remindDays: days, remindedMs: reminded?.millisecondsSinceEpoch);

  group('número do WhatsApp', () {
    test('aceita DDD + número e completa o 55; aceita outro país com +', () {
      expect(cleanWhatsNumber('(11) 91234-5678'), '5511912345678');
      expect(cleanWhatsNumber('11 3123 4567'), '551131234567');
      expect(cleanWhatsNumber('5511912345678'), '5511912345678');
      expect(cleanWhatsNumber('+351 912 345 678'), '351912345678');
      expect(whatsLabel('5511912345678'), '+55 11 91234-5678');
      expect(whatsLabel('351912345678'), '+351912345678');
    });

    test('recusa o que não é número', () {
      for (final bad in ['', '123', '91234-5678', '(01) 91234-5678', 'abc 11912345678', '11912345678; rm', '+12']) {
        expect(cleanWhatsNumber(bad), isNull, reason: bad);
      }
    });

    test('o link leva o número e o texto escapado; sem número o WhatsApp pergunta para quem', () {
      expect(whatsUri('5511912345678', 'Oi, Ana! 15 min?').toString(), startsWith('https://wa.me/5511912345678?text=Oi%2C%20Ana!'));
      expect(whatsUri(null, 'a&b').toString(), 'https://wa.me/?text=a%26b');
    });

    test('o número fica no aparelho: não vai na cópia entre aparelhos nem no "Copiar dados"', () {
      final s = st('1', days: [1, 3])
        ..whats = '5511912345678'
        ..remindedMs = 123;
      final back = Student.tryFrom(s.toJson())!;
      expect(back.whats, '5511912345678');
      expect(back.remindDays, [1, 3]);
      for (final out in [studentToSection(s), exportStudent(s)]) {
        expect(out, isNot(contains('5511912345678')));
        expect(out, isNot(contains('"rdw"')));
      }
      expect(Student.tryFrom({'id': 'x', 'name': 'X', 'wa': 'javascript:1'})!.whats, isNull);
    });
  });

  group('mensagens', () {
    test('três opções amigáveis com o nome; com tarefas citam até três', () {
      final com = reminderMessages('Ana', ['Escala de Ré', '  ', 'Lição 4', 'Peça nova', 'Quarta']);
      expect(com.length, 3);
      expect(com.toSet().length, 3);
      for (final m in com) {
        expect(m, contains('Ana'));
        expect(m, contains('Escala de Ré, Lição 4, Peça nova'));
        expect(m, isNot(contains('Quarta')));
      }
      final sem = reminderMessages('Ana', const []);
      expect(sem.length, 3);
      for (final m in sem) {
        expect(m, contains('Ana'));
      }
    });
  });

  group('quem pode precisar de um empurrãozinho', () {
    test('tarefa parada há 3 dias entra; nova, feita ou marcada há pouco não entra', () {
      final r = whoNeedsNudge([
        st('parada', tasks: [task('a', daysAgo: 5)]),
        st('nova', tasks: [task('b', daysAgo: 1)]),
        st('feita', tasks: [task('c', done: true)]),
        st('marcou', tasks: [task('d', daysAgo: 6), task('e', daysAgo: 6, claimed: now.subtract(const Duration(days: 1)))]),
        st('semtarefa'),
      ], now);
      expect(r.map((x) => x.student.id), ['parada']);
      expect(r.first.value, 5);
    });

    test('desativado fica fora; quem foi lembrado há menos de 3 dias descansa', () {
      final r = whoNeedsNudge([
        st('pausado', tasks: [task('a')], paused: true),
        st('lembrado', tasks: [task('b')], reminded: now.subtract(const Duration(days: 2))),
        st('descansou', tasks: [task('c')], reminded: now.subtract(const Duration(days: 4))),
      ], now);
      expect(r.map((x) => x.student.id), ['descansou']);
    });

    test('dia programado vem primeiro e vale uma vez por dia', () {
      final r = whoNeedsNudge([
        st('tarefa', tasks: [task('a')]),
        st('hoje', days: [DateTime.friday]),
        st('jafoi', days: [DateTime.friday], reminded: now.subtract(const Duration(hours: 2))),
        st('outrodia', days: [DateTime.monday]),
      ], now);
      expect(r.map((x) => x.student.id), ['hoje', 'tarefa']);
      expect(r.first.reason, NudgeReason.scheduled);
    });

    test('pouco estudo só conta para quem compartilha, e só a partir de quarta', () {
      final code = 'ABCD-2345';
      final share = StudyShare.tryFrom({'w': '2026-11-23', 'm': 5, 'g': 20, 'd': 1, 'a': -1, 'tk': 0, 'tt': 0, 'n': 0, 'at': now.millisecondsSinceEpoch});
      expect(share, isNotNull);
      final shares = {code: share!};
      expect(whoNeedsNudge([st('x', code: code)], now, shares: shares).single.reason, NudgeReason.study);
      expect(whoNeedsNudge([st('x', code: code)], DateTime(2026, 11, 23, 18), shares: shares), isEmpty, reason: 'segunda: a semana mal começou');
      expect(whoNeedsNudge([st('x', code: code)], now), isEmpty, reason: 'sem compartilhar não aparece');
    });
  });
}
