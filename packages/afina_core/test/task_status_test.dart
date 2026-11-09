import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  verdictEntryTests();
  Assignment task(String id, {bool done = false, DateTime? claimed, int day = 1}) => Assignment(
      id: id, title: 'T$id', created: DateTime(2026, 11, day), done: done, claimedAt: claimed);
  Student student(List<Assignment> t) => Student(id: 's', name: 'Ana', tasks: t);

  group('resumo para o professor', () {
    test('separa para validar, pendentes e concluídas', () {
      final s = summarizeTasks(student([
        task('a', done: true),
        task('b', claimed: DateTime(2026, 11, 8)),
        task('c'),
        task('d', claimed: DateTime(2026, 11, 5)),
      ]));
      expect(s.concluded, 1);
      expect(s.pending.map((t) => t.id), ['c']);
      expect(s.toValidate.map((t) => t.id), ['d', 'b'], reason: 'mais antiga primeiro');
      expect(s.total, 4);
      expect(s.needsAttention, isTrue);
      expect(s.line, '2 para validar · 1 pendente · 1 concluída');
    });

    test('sem tarefas: vazio e sem texto; só concluídas não pede atenção', () {
      final e = summarizeTasks(student([]));
      expect(e.isEmpty, isTrue);
      expect(e.line, '');
      final d = summarizeTasks(student([task('a', done: true), task('b', done: true)]));
      expect(d.needsAttention, isFalse);
      expect(d.line, '2 concluídas');
    });

    test('tarefa feita e também marcada conta só como concluída', () {
      final s = summarizeTasks(student([task('a', done: true, claimed: DateTime(2026, 11, 2))]));
      expect(s.concluded, 1);
      expect(s.toValidate, isEmpty);
    });

    test('pendentes em ordem de criação', () {
      final s = summarizeTasks(student([task('x', day: 9), task('y', day: 2)]));
      expect(s.pending.map((t) => t.id), ['y', 'x']);
      expect(s.line, '2 pendentes');
    });
  });

  group('status oficial visto pelo aluno', () {
    test('sem decisão: pendente ou aguardando', () {
      expect(studentTaskState(claimed: false), StudentTaskState.pending);
      expect(studentTaskState(claimed: true), StudentTaskState.claimed);
    });
    test('o professor manda: validada ou devolvida', () {
      expect(studentTaskState(claimed: false, verdict: Verdict.ok), StudentTaskState.validated);
      expect(studentTaskState(claimed: true, verdict: Verdict.ok), StudentTaskState.validated);
      expect(studentTaskState(claimed: true, verdict: Verdict.back), StudentTaskState.returned);
    });
    test('devolvida e marcada de novo depois: volta a aguardar', () {
      expect(studentTaskState(claimed: true, verdict: Verdict.back, claimedAfterVerdict: true), StudentTaskState.claimed);
    });
    test('textos e código do servidor', () {
      expect(studentTaskLabel(StudentTaskState.returned), 'Refazer (devolvida)');
      expect(verdictWire(Verdict.ok), 'ok');
      expect(verdictFromWire('back'), Verdict.back);
      expect(verdictFromWire('x'), isNull);
      expect(verdictFromWire(null), isNull);
    });
  });
}

void verdictEntryTests() {
  group('decisão vinda do servidor', () {
    test('lê o formato do servidor e monta a chave', () {
      final e = VerdictEntry.tryFromWire({'te': 'K7QM-4TXK', 'l': 'aula0001', 'k': 'k1', 'v': 'ok', 't': 5});
      final f = VerdictEntry.tryFromWire({'te': 'K7QM-4TXK', 'l': 'aula0001', 'k': 'k1', 'v': 'back'});
      expect(f!.key, 'K7QM-4TXK:aula0001:k1');
      expect(f.verdict, Verdict.back);
      expect(e!.verdict, Verdict.ok);
    });
    test('recusa lixo', () {
      expect(VerdictEntry.tryFromWire(null), isNull);
      expect(VerdictEntry.tryFromWire({'te': 'x', 'l': 'a', 'k': 'k', 'v': 'ok'}), isNull);
      expect(VerdictEntry.tryFromWire({'te': 'K7QM-4TXK', 'l': 'AULA', 'k': 'k1', 'v': 'ok'}), isNull);
      expect(VerdictEntry.tryFromWire({'te': 'K7QM-4TXK', 'l': 'aula0001', 'k': 'k 1', 'v': 'ok'}), isNull);
      expect(VerdictEntry.tryFromWire({'te': 'K7QM-4TXK', 'l': 'aula0001', 'k': 'k1', 'v': 'x'}), isNull);
    });
  });
}
