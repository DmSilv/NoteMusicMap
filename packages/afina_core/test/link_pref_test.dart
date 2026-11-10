import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

bool on({String? pref, bool legacy = false, bool teacher = false, bool teachers = false, bool students = false}) =>
    linkShouldBeOn(
        pref: pref, legacyOn: legacy, teacherMode: teacher, hasTeachers: teachers, hasStudentsWithCode: students);

void main() {
  group('vínculo ligado por padrão', () {
    test('professor com modo professor ligado e sem escolha: liga (o caso real do aluno que não notificava)', () {
      expect(on(teacher: true), isTrue);
    });
    test('quem tem professor vinculado ou aluno com código liga sozinho', () {
      expect(on(teachers: true), isTrue);
      expect(on(students: true), isTrue);
    });
    test('quem não tem ninguém continua desligado (nada a sincronizar, sem custo)', () {
      expect(on(), isFalse);
    });
    test('valor antigo ligado continua ligado', () {
      expect(on(legacy: true), isTrue);
    });
    test('escolha explícita de desligar vence tudo', () {
      expect(on(pref: 'off', teacher: true, teachers: true, students: true, legacy: true), isFalse);
    });
    test('escolha explícita de ligar vence a falta de relações', () {
      expect(on(pref: 'on'), isTrue);
    });
  });

  group('aviso de vínculo desligado', () {
    test('desligado com alunos, professores ou modo professor: precisa de atenção', () {
      expect(linkNeedsAttention(enabled: false, teacherMode: true, hasTeachers: false, hasStudentsWithCode: false), isTrue);
      expect(linkNeedsAttention(enabled: false, teacherMode: false, hasTeachers: true, hasStudentsWithCode: false), isTrue);
      expect(linkNeedsAttention(enabled: false, teacherMode: false, hasTeachers: false, hasStudentsWithCode: true), isTrue);
    });
    test('ligado, ou desligado sem ninguém, não avisa', () {
      expect(linkNeedsAttention(enabled: true, teacherMode: true, hasTeachers: true, hasStudentsWithCode: true), isFalse);
      expect(linkNeedsAttention(enabled: false, teacherMode: false, hasTeachers: false, hasStudentsWithCode: false), isFalse);
    });
  });
}
