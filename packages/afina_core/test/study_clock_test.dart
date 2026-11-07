import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('cronômetro', () {
    test('conta para cima, pausa e retoma', () {
      final c = StudyClock();
      expect(c.elapsedMs(0), 0);
      c.start(1000);
      expect(c.elapsedMs(6000), 5000);
      c.pause(6000);
      expect(c.elapsedMs(99999), 5000); // parado não anda
      c.start(10000);
      expect(c.elapsedMs(12000), 7000);
    });

    test('não tem fim e zerar volta ao início', () {
      final c = StudyClock()..start(0);
      expect(c.finished(10 * 3600 * 1000), isFalse);
      c.reset();
      expect(c.running, isFalse);
      expect(c.elapsedMs(5), 0);
    });
  });

  group('minuteria (tempo personalizado)', () {
    test('conta para baixo e termina uma única vez', () {
      final c = StudyClock(countdownMs: 30 * 60000)..start(0);
      expect(c.remainingMs(10 * 60000), 20 * 60000);
      expect(c.progress(15 * 60000), closeTo(0.5, 1e-9));
      expect(c.tick(29 * 60000), isFalse);
      expect(c.tick(30 * 60000 + 100), isTrue);
      expect(c.running, isFalse);
      expect(c.finished(31 * 60000), isTrue);
      expect(c.tick(31 * 60000), isFalse); // não repete
      expect(c.remainingMs(31 * 60000), 0);
    });

    test('mudar a duração zera; não reinicia uma sessão terminada sem zerar', () {
      final c = StudyClock(countdownMs: 60000)..start(0);
      c.tick(70000);
      c.start(80000);
      expect(c.running, isFalse);
      c.setCountdown(120000);
      c.start(90000);
      expect(c.running, isTrue);
      expect(c.remainingMs(90000), 120000);
    });
  });

  group('persistência', () {
    test('retoma contando o tempo em que o app ficou fechado', () {
      final c = StudyClock(countdownMs: 60 * 60000)..start(1000);
      final j = c.toJson(11000); // 10 s depois
      final d = StudyClock()..restore(j, 71000); // reaberto 60 s depois do salvamento
      expect(d.running, isTrue);
      expect(d.elapsedMs(71000), 70000);
      expect(d.countdownMs, 60 * 60000);
    });

    test('minuteria que acabou com o app fechado volta terminada', () {
      final c = StudyClock(countdownMs: 60000)..start(0);
      final j = c.toJson(10000);
      final d = StudyClock()..restore(j, 500000);
      expect(d.running, isFalse);
      expect(d.finished(500000), isTrue);
    });

    test('parado mantém o acumulado', () {
      final c = StudyClock()..start(0);
      c.pause(42000);
      final d = StudyClock()..restore(c.toJson(99999), 123456);
      expect(d.running, isFalse);
      expect(d.elapsedMs(123456), 42000);
    });
  });

  test('formatClock mostra mm:ss e h:mm:ss', () {
    expect(formatClock(0), '00:00');
    expect(formatClock(65 * 1000), '01:05');
    expect(formatClock(3725 * 1000), '1:02:05');
  });
}
