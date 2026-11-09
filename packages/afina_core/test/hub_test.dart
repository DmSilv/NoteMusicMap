import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 9, 14, 0).millisecondsSinceEpoch; // segunda 14:00
  int at(int h, int m, [int day = 9]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;
  HubClass cls(int startMs, {int min = 60, String who = 'Ana'}) => HubClass(startMs, startMs + min * kMsMinute, who);
  HubHero hero({HubClass? next, bool teacher = false, bool hasTeacher = true, int today = 0, bool students = true}) =>
      buildHero(nowMs: now, isTeacher: teacher, hasTeacher: hasTeacher, next: next, todayCount: today, hasStudents: students);

  group('destaque do topo', () {
    test('aula em andamento: vale do início até o fim (fim não conta)', () {
      expect(hero(next: cls(at(13, 30))).kind, HeroKind.ongoing);
      expect(hero(next: cls(at(14, 0))).kind, HeroKind.ongoing, reason: 'no instante do início');
      // a aula das 13:00 (60 min) acaba às 14:00: no instante do fim já não é "em andamento"
      expect(buildHero(nowMs: at(14, 0), isTeacher: false, hasTeacher: true, next: cls(at(13, 0))).kind, isNot(HeroKind.ongoing));
    });

    test('começa em até 15 min: "soon", com os minutos arredondados para cima', () {
      final a = hero(next: cls(at(14, 12)));
      expect(a.kind, HeroKind.soon);
      expect(a.kicker, 'Começa em 12 min');
      expect(a.subtitle, 'Às 14:12');
      expect(hero(next: cls(at(14, 15))).kind, HeroKind.soon, reason: 'exatamente 15 min');
      expect(hero(next: cls(at(14, 16))).kind, HeroKind.next, reason: '16 min já é "próxima aula"');
      expect(buildHero(nowMs: at(14, 14) + 30000, isTeacher: false, hasTeacher: true, next: cls(at(14, 15))).kicker, 'Começa em 1 min');
    });

    test('próxima aula: dia e hora, com quem e quanto falta (aluno e professor)', () {
      final s = hero(next: cls(at(15, 0, 11), who: 'Marina'));
      expect(s.kind, HeroKind.next);
      expect(s.kicker, 'Sua próxima aula');
      expect(s.title, 'Quarta, 11/11, 15:00');
      expect(s.subtitle, 'Com Marina · em 2 dias');
      final t = hero(next: cls(at(16, 30)), teacher: true, today: 3);
      expect(t.kicker, 'Hoje · 3 aulas');
      expect(t.subtitle, 'Com Ana · em 2 h');
      expect(hero(next: cls(at(16, 30)), teacher: true, today: 1).kicker, 'Hoje · 1 aula');
      expect(hero(next: cls(at(15, 0, 12)), teacher: true).kicker, 'Próxima aula');
    });

    test('sem nome, usa "seu professor" / "seu aluno"', () {
      expect(hero(next: cls(at(14, 5), who: '')).title, 'Aula com seu professor');
      expect(hero(next: cls(at(14, 5), who: ' '), teacher: true).title, 'Aula com seu aluno');
    });

    test('sem aula: cada papel recebe o que fazer', () {
      final alu = hero();
      expect(alu.kind, HeroKind.none);
      expect(alu.title, 'Você ainda não tem aula marcada');
      expect(hero(hasTeacher: false).kind, HeroKind.noTeacher);
      expect(hero(teacher: true).title, 'Sem aulas marcadas');
      expect(hero(teacher: true, students: false).title, 'Sem alunos ainda');
    });

    test('aula que já passou não vira destaque', () {
      final h = hero(next: cls(at(9, 0)));
      expect(h.kind, HeroKind.none);
    });
  });

  group('blocos menores', () {
    test('tarefas: vazio, em dia e pendentes (com progresso e ação)', () {
      final vazio = tasksTile(open: 0, total: 0);
      expect(vazio.headline, 'Nenhuma tarefa');
      expect(vazio.needsAction, isFalse);
      final ok = tasksTile(open: 0, total: 4);
      expect(ok.headline, 'Tudo em dia');
      expect(ok.progress, 1);
      expect(ok.caption, contains('4 tarefas'));
      final p = tasksTile(open: 3, total: 4);
      expect(p.headline, '3 pendentes');
      expect(p.progress, closeTo(0.25, 1e-9));
      expect(p.needsAction, isTrue);
      expect(tasksTile(open: 1, total: 1).headline, '1 pendente');
    });

    test('para validar e alunos: números só quando há ação ou conteúdo', () {
      expect(validateTile(0).needsAction, isFalse);
      expect(validateTile(0).headline, 'Nada a validar');
      expect(validateTile(1).headline, '1 tarefa');
      expect(validateTile(4).needsAction, isTrue);
      expect(studentsTile(0).headline, 'Nenhum ainda');
      expect(studentsTile(1).headline, '1 aluno');
      expect(studentsTile(12).headline, '12 alunos');
      expect(studentsTile(12).needsAction, isFalse);
    });

    test('agenda do aluno', () {
      expect(agendaTile(nextText: null).headline, 'Sem aulas marcadas');
      expect(agendaTile(nextText: 'terça, 15:00').caption, 'próxima aula');
    });
  });

  test('"quanto falta": minutos, horas e dias', () {
    expect(fmtUntil(const Duration(seconds: 20)), 'agora');
    expect(fmtUntil(const Duration(minutes: 40)), 'em 40 min');
    expect(fmtUntil(const Duration(hours: 3, minutes: 10)), 'em 3 h');
    expect(fmtUntil(const Duration(days: 1, hours: 2)), 'em 1 dia');
    expect(fmtUntil(const Duration(days: 5)), 'em 5 dias');
  });
}
