import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('qual visão aparece', () {
    test('sem modo professor só existe a visão de aluno, seja qual for a preferência', () {
      expect(resolveHubView(teacherMode: false, preferred: HubView.teacher), HubView.student);
      expect(resolveHubView(teacherMode: false), HubView.student);
    });

    test('com modo professor vale a escolha do alternador; sem escolha, professor', () {
      expect(resolveHubView(teacherMode: true, preferred: HubView.student), HubView.student);
      expect(resolveHubView(teacherMode: true, preferred: HubView.teacher), HubView.teacher);
      expect(resolveHubView(teacherMode: true), HubView.teacher);
    });
  });

  group('separação e sem repetição', () {
    List<HubDest> everything(HubView v, {required bool hasTeacherSide, required bool hasStudents, required bool hasClassStudent}) {
      final l = hubLayout(v, hasTeacherSide: hasTeacherSide);
      final all = [...l.tiles, ...l.tools];
      for (final k in HeroKind.values) {
        all.addAll(heroActions(v, k, hasStudents: hasStudents, hasClassStudent: hasClassStudent));
      }
      return all;
    }

    test('nenhum destino aparece duas vezes na mesma tela (por estado do destaque)', () {
      for (final v in HubView.values) {
        for (final ts in [true, false]) {
          for (final hs in [true, false]) {
            for (final hc in [true, false]) {
              final l = hubLayout(v, hasTeacherSide: ts);
              for (final k in HeroKind.values) {
                final one = [...l.tiles, ...l.tools, ...heroActions(v, k, hasStudents: hs, hasClassStudent: hc)];
                expect(one.toSet().length, one.length, reason: '$v $k ts=$ts hs=$hs hc=$hc: $one');
              }
            }
          }
        }
      }
    });

    test('a visão do aluno nunca mostra destino do professor, e vice-versa', () {
      for (final ts in [true, false]) {
        for (final hs in [true, false]) {
          for (final hc in [true, false]) {
            final s = everything(HubView.student, hasTeacherSide: ts, hasStudents: hs, hasClassStudent: hc);
            final t = everything(HubView.teacher, hasTeacherSide: ts, hasStudents: hs, hasClassStudent: hc);
            expect(s.where(kTeacherOnly.contains), isEmpty, reason: 'aluno ts=$ts');
            expect(t.where(kStudentOnly.contains), isEmpty, reason: 'professor ts=$ts');
          }
        }
      }
    });

    test('no máximo 2 blocos por visão', () {
      for (final v in HubView.values) {
        for (final ts in [true, false]) {
          expect(hubLayout(v, hasTeacherSide: ts).tiles.length, lessThanOrEqualTo(2));
        }
      }
    });
  });

  group('conteúdo de cada visão', () {
    test('professor: só o bloco de alunos (o "para validar" mora nos alunos); agenda, horários livres e ferramentas', () {
      final l = hubLayout(HubView.teacher, hasTeacherSide: true);
      expect(l.tiles, [HubDest.students]);
      expect(l.tools, [HubDest.agendaTeacher, HubDest.openSlots, HubDest.metronome, HubDest.scales]);
    });

    test('aluno com professor: tarefas e agenda do aluno; pegar horário nas ferramentas', () {
      final l = hubLayout(HubView.student, hasTeacherSide: true);
      expect(l.tiles, [HubDest.myTasks, HubDest.agendaStudent]);
      expect(l.tools, [HubDest.pickSlot, HubDest.metronome, HubDest.scales]);
    });

    test('aluno sem professor: nada de blocos vazios, só ferramentas', () {
      final l = hubLayout(HubView.student, hasTeacherSide: false);
      expect(l.tiles, isEmpty);
      expect(l.tools, [HubDest.metronome, HubDest.scales]);
    });
  });

  group('botões do destaque', () {
    test('professor: a próxima aula leva à ficha; sem aula, a começar', () {
      expect(heroActions(HubView.teacher, HeroKind.next, hasStudents: true, hasClassStudent: true), [HubDest.studentFile]);
      expect(heroActions(HubView.teacher, HeroKind.soon, hasStudents: true, hasClassStudent: false), isEmpty);
      expect(heroActions(HubView.teacher, HeroKind.none, hasStudents: true, hasClassStudent: false), [HubDest.markClass]);
      expect(heroActions(HubView.teacher, HeroKind.none, hasStudents: false, hasClassStudent: false), [HubDest.inviteStudent]);
    });

    test('aluno: só pede o QR quando não tem professor; nunca duplica a agenda', () {
      expect(heroActions(HubView.student, HeroKind.noTeacher, hasStudents: false, hasClassStudent: false), [HubDest.scanTeacher]);
      for (final k in [HeroKind.ongoing, HeroKind.soon, HeroKind.next, HeroKind.none]) {
        expect(heroActions(HubView.student, k, hasStudents: false, hasClassStudent: false), isEmpty);
      }
    });
  });

  test('avisos: cada visão tem os seus e não há tipo em duas visões', () {
    final s = kNoticeKindsByView[HubView.student]!, t = kNoticeKindsByView[HubView.teacher]!;
    expect(s.intersection(t), isEmpty);
    expect(s.union(t), {'teacher', 'lesson', 'task', 'done', 'pick'});
  });
}
