import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  test('faixas de tela', () {
    expect(screenTag(0), '-');
    expect(screenTag(390), 'celular');
    expect(screenTag(599), 'celular');
    expect(screenTag(600), 'tablet');
    expect(screenTag(1023), 'tablet');
    expect(screenTag(1440), 'pc');
  });

  test('idioma reduzido', () {
    expect(langTag('pt-BR'), 'pt');
    expect(langTag('EN-us'), 'en');
    expect(langTag('ja-JP'), 'outro');
    expect(langTag(''), '-');
  });

  test('versão do sistema', () {
    expect(osVersionTag('Mozilla/5.0 (Linux; Android 13; SM-S918B) Chrome/120'), 'a13');
    expect(osVersionTag('Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) Safari'), 'i17');
    expect(osVersionTag('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120'), 'w10');
    expect(osVersionTag('Mozilla/5.0 (Windows NT 6.1) Chrome/49'), 'wold');
    expect(osVersionTag('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'), '-');
    expect(osVersionTag(''), '-');
  });

  test('todos os rótulos cabem no padrão aceito pelo servidor', () {
    final re = RegExp(r'^[a-z0-9-]{1,10}$');
    final all = [
      screenTag(390), screenTag(800), screenTag(1600), screenTag(0),
      langTag('pt-BR'), langTag('xx'), langTag(''),
      osVersionTag('Android 14'), osVersionTag('iPhone OS 18_0'), osVersionTag('Windows NT 10.0'),
      yesNoTag(true), yesNoTag(false), yesNoTag(null),
      notifTag(true, 'granted'), notifTag(true, 'denied'), notifTag(true, 'default'), notifTag(false, 'denied'),
    ];
    for (final t in all) {
      expect(re.hasMatch(t), isTrue, reason: t);
    }
  });

  test('fuso, memória, núcleos, conexão e densidade', () {
    expect(tzTag(-180), 'm3');
    expect(tzTag(0), 'z');
    expect(tzTag(330), 'p5h');
    expect(tzTag(60), 'p1');
    expect(memTag(null), '-');
    expect(memTag(0.5), '1');
    expect(memTag(3), '2');
    expect(memTag(4), '4');
    expect(memTag(16), '8');
    expect(cpuTag(null), '-');
    expect(cpuTag(2), 'c2');
    expect(cpuTag(6), 'c8');
    expect(cpuTag(16), 'c12');
    expect(netTag('4g'), '4g');
    expect(netTag('slow-2g'), 'slow2g');
    expect(netTag('wifi'), '-');
    expect(dprTag(1.0), 'd1');
    expect(dprTag(2.0), 'd2');
    expect(dprTag(3.5), 'd3');
    expect(dprTag(null), '-');
    final re = RegExp(r'^[a-z0-9-]{1,10}$');
    for (final t in [tzTag(-210), tzTag(765), memTag(8), cpuTag(12), netTag('slow-2g'), dprTag(2)]) {
      expect(re.hasMatch(t), isTrue, reason: t);
    }
  });

  test('permissão de notificação', () {
    expect(notifTag(false, 'granted'), 'na');
    expect(notifTag(true, 'granted'), 'sim');
    expect(notifTag(true, 'denied'), 'nao');
    expect(notifTag(true, 'default'), 'nd');
  });
}
