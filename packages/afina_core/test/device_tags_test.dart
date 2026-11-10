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

  test('permissão de notificação', () {
    expect(notifTag(false, 'granted'), 'na');
    expect(notifTag(true, 'granted'), 'sim');
    expect(notifTag(true, 'denied'), 'nao');
    expect(notifTag(true, 'default'), 'nd');
  });
}
