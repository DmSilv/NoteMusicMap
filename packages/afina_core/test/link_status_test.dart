import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 9, 12, 0);
  LinkStatusInfo d({bool enabled = true, bool down = false, bool? online = true, int queued = 0, DateTime? ok}) =>
      describeLink(enabled: enabled, serverUnavailable: down, online: online, queued: queued, lastOkAt: ok, now: now);

  group('estado do vínculo', () {
    test('desligado: explica que nada sai, que os dados ficam no aparelho e não oferece reconectar', () {
      final i = d(enabled: false, online: null);
      expect(i.health, LinkHealth.off);
      expect(i.title, 'Desligado');
      expect(i.text, contains('continuam neste aparelho'));
      expect(i.canReconnect, isFalse);
    });

    test('desligado com itens na fila: avisa que ficam guardados', () {
      expect(d(enabled: false, queued: 3).text, contains('fila fica guardado'));
    });

    test('servidor indisponível vence a internet; sugere reconectar depois', () {
      final i = d(down: true, online: false);
      expect(i.health, LinkHealth.serverDown);
      expect(i.canReconnect, isTrue);
      expect(i.text, contains('Reconectar agora'));
    });

    test('sem conexão: diz o que pode ser e mostra a fila', () {
      final i = d(online: false, queued: 2);
      expect(i.health, LinkHealth.offline);
      expect(i.text, contains('2 itens esperam na fila de envio e vão'));
    });

    test('um item na fila fala no singular', () {
      expect(d(online: false, queued: 1).text, contains('1 item espera na fila de envio e vai'));
    });

    test('ainda sem resposta: conectando', () {
      expect(d(online: null).health, LinkHealth.connecting);
    });

    test('conectado: mostra a última atualização e a fila', () {
      final i = d(ok: now.subtract(const Duration(minutes: 3)), queued: 1);
      expect(i.health, LinkHealth.online);
      expect(i.text, contains('Última atualização há 3 min.'));
      expect(i.text, contains('1 item espera'));
    });

    test('ordem de prioridade: desligado > servidor > sem conexão > conectando > conectado', () {
      expect(d(enabled: false, down: true, online: false).health, LinkHealth.off);
      expect(d(down: true, online: true).health, LinkHealth.serverDown);
      expect(d(online: false).health, LinkHealth.offline);
      expect(d(online: null).health, LinkHealth.connecting);
      expect(d(online: true).health, LinkHealth.online);
    });
  });

  test('"há quanto tempo": agora, minutos, horas e dias', () {
    expect(fmtAgo(const Duration(seconds: 10)), 'agora');
    expect(fmtAgo(const Duration(seconds: 50)), 'há 1 min');
    expect(fmtAgo(const Duration(minutes: 59)), 'há 59 min');
    expect(fmtAgo(const Duration(hours: 5)), 'há 5 h');
    expect(fmtAgo(const Duration(days: 1)), 'há 1 dia');
    expect(fmtAgo(const Duration(days: 4)), 'há 4 dias');
  });
}
