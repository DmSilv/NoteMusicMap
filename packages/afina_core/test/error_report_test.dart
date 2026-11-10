import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  AppError err({String where = 'Agenda › Marcar aula', String detail = 'StateError: x', ErrorSeverity s = ErrorSeverity.action}) =>
      AppError(code: 'APP-00', severity: s, where: where, detail: detail, atMs: 1);

  group('modo de envio', () {
    test('graves: só o crítico; todos: tudo menos aviso de conexão; nunca: nada', () {
      for (final s in ErrorSeverity.values) {
        expect(shouldAutoSend(ReportMode.critical, s), s == ErrorSeverity.critical);
        expect(shouldAutoSend(ReportMode.all, s), s != ErrorSeverity.info);
        expect(shouldAutoSend(ReportMode.off, s), isFalse);
      }
    });

    test('rótulos em português', () {
      expect(ReportMode.values.map(reportModeLabel), ['Só os graves', 'Todos os erros', 'Nunca']);
    });
  });

  group('trilha de passos', () {
    test('guarda os últimos 10, sem repetir o passo anterior', () {
      final b = Breadcrumbs();
      for (var i = 0; i < 15; i++) {
        b.add('Passo $i');
      }
      b.add('Passo 14');
      expect(b.items.length, Breadcrumbs.kMax);
      expect(b.items.first, 'Passo 5');
      expect(b.items.last, 'Passo 14');
    });

    test('só nomes simples entram (nada de texto livre longo nem símbolos)', () {
      final b = Breadcrumbs();
      b.add('Meu espaço');
      b.add('Agenda › Marcar aula');
      b.add('<script>alert(1)</script>');
      b.add('x' * 80);
      b.add('');
      b.add('ana@exemplo.com');
      expect(b.items, ['Meu espaço', 'Agenda › Marcar aula']);
    });
  });

  group('pacote do relatório', () {
    const env = ReportEnv(deviceId: 'abcdefghij0123456789', build: 'abc1234', platform: 'android-chrome', install: 'pwa', link: 'online', view: 'teacher');

    test('traz o necessário para agrupar e filtrar', () {
      final r = buildErrorReport(err(), env, ['Meu espaço', 'Agenda']);
      expect(r['id'], 'abcdefghij0123456789');
      expect(r['c'], 'APP-00');
      expect(r['s'], 'action');
      expect(r['w'], 'Agenda › Marcar aula');
      expect(r['v'], 'abc1234');
      expect(r['pl'], 'android-chrome');
      expect(r['in'], 'pwa');
      expect(r['lk'], 'online');
      expect(r['vw'], 'teacher');
      expect(r['bc'], ['Meu espaço', 'Agenda']);
    });

    test('mesmo se o erro chegar sujo, o pacote sai higienizado', () {
      final r = buildErrorReport(err(detail: 'falha K7QM-4TXK ana@exemplo.com', where: 'Aluno K7QM-4TXK'), env, []);
      expect((r['d'] as String).contains('K7QM'), isFalse);
      expect((r['d'] as String).contains('@'), isFalse);
      expect((r['w'] as String).contains('K7QM'), isFalse);
    });

    test('campos vazios não vão; a trilha é cortada em 10', () {
      final r = buildErrorReport(err(), const ReportEnv(deviceId: 'abcdefghij0123456789'), [for (var i = 0; i < 30; i++) 'P$i']);
      expect(r.containsKey('lk'), isFalse);
      expect(r.containsKey('vw'), isFalse);
      expect((r['bc'] as List).length, 10);
    });
  });

  group('freio contra repetição', () {
    test('o mesmo problema só passa de novo depois da janela', () {
      final g = ReportGate();
      final t0 = DateTime(2026, 11, 10, 12);
      expect(g.allow('E-AAAA', t0), isTrue);
      expect(g.allow('E-AAAA', t0.add(const Duration(minutes: 9))), isFalse);
      expect(g.allow('E-BBBB', t0.add(const Duration(minutes: 9))), isTrue, reason: 'outro problema passa');
      expect(g.allow('E-AAAA', t0.add(const Duration(minutes: 10))), isTrue);
    });

    test('teto por sessão', () {
      final g = ReportGate(maxPerSession: 3);
      final t = DateTime(2026, 11, 10);
      expect([for (var i = 0; i < 5; i++) g.allow('E-$i', t)], [true, true, true, false, false]);
    });
  });
}
