import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final hoje = DateTime(2026, 11, 14, 15, 30);
  DateTime ha(int n) => DateTime(2026, 11, 14).subtract(Duration(days: n));

  group('marca por dia (zera sozinha no dia seguinte)', () {
    test('marcar hoje não marca amanhã nem ontem', () {
      final p = PracticeLog();
      expect(p.toggle('a:1', hoje), isTrue);
      expect(p.has('a:1', hoje), isTrue);
      expect(p.has('a:1', hoje.add(const Duration(days: 1))), isFalse);
      expect(p.has('a:1', ha(1)), isFalse);
    });

    test('tocar de novo desmarca; a hora do dia não importa', () {
      final p = PracticeLog();
      p.toggle('a:1', DateTime(2026, 11, 14, 8));
      expect(p.has('a:1', DateTime(2026, 11, 14, 23, 59)), isTrue);
      expect(p.toggle('a:1', DateTime(2026, 11, 14, 22)), isFalse);
      expect(p.has('a:1', hoje), isFalse);
      expect(p.totalMarks, 0);
    });

    test('cada tarefa tem o seu diário', () {
      final p = PracticeLog()..toggle('a:1', hoje);
      expect(p.has('a:2', hoje), isFalse);
      expect(p.has('b:1', hoje), isFalse);
    });
  });

  group('semana', () {
    test('conta só os 7 dias que terminam hoje', () {
      final p = PracticeLog();
      for (final n in [0, 1, 3, 6, 7, 10]) {
        p.toggle('a:1', ha(n));
      }
      expect(p.countLast7('a:1', hoje), 4);
      expect(p.countLast7('x:1', hoje), 0);
    });

    test('fileira: 7 dias, hoje por último, dias antes da aula desligados', () {
      final f = practiceStrip(hoje, ha(2));
      expect(f.length, 7);
      expect(f.last.isToday, isTrue);
      expect(f.where((d) => d.enabled).length, 3); // anteontem, ontem e hoje
      expect(f.first.enabled, isFalse);
      expect(f.map((d) => d.date.day).toList(), [8, 9, 10, 11, 12, 13, 14]);
    });

    test('aula de mais de uma semana atrás: tudo ligado', () {
      expect(practiceStrip(hoje, ha(20)).every((d) => d.enabled), isTrue);
    });
  });

  group('dias seguidos', () {
    test('sem nenhuma marca é zero', () => expect(PracticeLog().streak(hoje), 0));

    test('conta hoje e os anteriores sem falha', () {
      final p = PracticeLog();
      for (final n in [0, 1, 2, 4]) {
        p.toggle('a:1', ha(n));
      }
      expect(p.streak(hoje), 3);
    });

    test('hoje ainda sem marca: a sequência de ontem continua', () {
      final p = PracticeLog();
      for (final n in [1, 2]) {
        p.toggle('a:1', ha(n));
      }
      expect(p.streak(hoje), 2);
    });

    test('qualquer tarefa vale para o dia', () {
      final p = PracticeLog()
        ..toggle('a:1', ha(0))
        ..toggle('b:9', ha(1));
      expect(p.streak(hoje), 2);
    });

    test('um dia em branco quebra a sequência', () {
      final p = PracticeLog()
        ..toggle('a:1', ha(0))
        ..toggle('a:1', ha(2));
      expect(p.streak(hoje), 1);
    });
  });

  group('guardar e ler', () {
    test('ida e volta', () {
      final p = PracticeLog()
        ..toggle('a:1', ha(0))
        ..toggle('a:1', ha(3))
        ..toggle('b:2', ha(1));
      final q = PracticeLog.decode(p.encode(now: hoje), now: hoje);
      expect(q.has('a:1', ha(0)), isTrue);
      expect(q.has('a:1', ha(3)), isTrue);
      expect(q.has('b:2', ha(1)), isTrue);
      expect(q.totalMarks, 3);
    });

    test('lixo é ignorado e o que é muito antigo some', () {
      final q = PracticeLog.decode(['a:1|2026-11-14', 'sem-barra', 'a:1|ontem', '|2026-11-14', 'a:1|2025-01-01'], now: hoje);
      expect(q.totalMarks, 1);
      expect(q.has('a:1', hoje), isTrue);
    });
  });
}
