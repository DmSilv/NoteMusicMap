import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final t = DateTime(2026, 11, 26);

  Student local(String id, String name, {List<Assignment>? tasks, bool paused = false}) =>
      Student(id: id, name: name, created: t.subtract(const Duration(days: 3)), tasks: tasks, paused: paused);

  Student linked(String name, {List<Assignment>? tasks}) =>
      Student(id: 'vabc', name: name, code: 'ABCD-2345', linkState: 'active', remoteName: name, created: t, tasks: tasks);

  Assignment task(String id) => Assignment(id: id, title: 'Escala de Ré', kind: TaskKind.free, created: t, sent: false);

  group('o aluno entrou pelo convite e já estava cadastrado pelo nome', () {
    test('oferece os cadastros sem código, com o mesmo primeiro nome na frente', () {
      final novo = linked('Ana Souza');
      final c = joinCandidates(novo, [local('1', 'Bruno'), local('2', 'ana'), local('3', 'Carla', paused: true), novo]);
      expect(c.map((s) => s.id), ['2', '1']);
    });

    test('não oferece quando o vinculado já tem trabalho, não está ativo ou não há cadastro pelo nome', () {
      expect(joinCandidates(linked('Ana', tasks: [task('a')]), [local('1', 'Ana')]), isEmpty);
      expect(joinCandidates(linked('Ana')..linkState = 'pending', [local('1', 'Ana')]), isEmpty);
      expect(joinCandidates(linked('Ana'), [Student(id: '9', name: 'Ana', code: 'WXYZ-2345', linkState: 'active')]), isEmpty);
      expect(joinCandidates(local('1', 'Ana'), [local('2', 'Ana')]), isEmpty);
    });

    test('juntar mantém o cadastro do professor e traz o código: a tarefa que esperava continua na fila', () {
      final meu = local('1', 'Aninha', tasks: [task('a')])..whats = '5511912345678';
      adoptLink(meu, linked('Ana Souza'));
      expect(meu.name, 'Aninha');
      expect(meu.code, 'ABCD-2345');
      expect(meu.linkState, 'active');
      expect(meu.remoteName, 'Ana Souza');
      expect(meu.tasks.single.sent, isFalse);
      expect(meu.whats, '5511912345678');
      expect(buildTasksPackage(meu, t, teacherName: 'Prof')!.taskCount, 1);
    });

    test('juntar não apaga o WhatsApp nem os dias de lembrete salvos no cadastro que entrou pelo convite', () {
      final novo = linked('Ana Souza')
        ..whats = '5511912345678'
        ..remindDays = [2, 4]
        ..remindedMs = 123;
      final meu = local('1', 'Ana');
      adoptLink(meu, novo);
      expect(meu.whats, '5511912345678');
      expect(meu.remindDays, [2, 4]);
      expect(meu.remindedMs, 123);
    });

    test('o número que já estava no cadastro do professor prevalece', () {
      final meu = local('1', 'Ana')..whats = '5513900000000';
      adoptLink(meu, linked('Ana')..whats = '5511912345678');
      expect(meu.whats, '5513900000000');
    });
  });
}
