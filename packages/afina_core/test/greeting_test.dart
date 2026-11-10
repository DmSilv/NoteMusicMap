import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('saudação por hora', () {
    test('limites de cada período', () {
      expect(greetingFor(4), 'Boa noite');
      expect(greetingFor(5), 'Bom dia');
      expect(greetingFor(11), 'Bom dia');
      expect(greetingFor(12), 'Boa tarde');
      expect(greetingFor(17), 'Boa tarde');
      expect(greetingFor(18), 'Boa noite');
      expect(greetingFor(23), 'Boa noite');
      expect(greetingFor(0), 'Boa noite');
    });

    test('todas as 24 horas têm saudação', () {
      for (var h = 0; h < 24; h++) {
        expect(greetingFor(h), isNotEmpty);
      }
    });

    test('com nome usa só a primeira palavra', () {
      expect(greetingLine(15, 'Daniel Silva'), 'Boa tarde, Daniel');
      expect(greetingLine(8, '  Ana  '), 'Bom dia, Ana');
    });

    test('primeira letra maiúscula', () {
      expect(greetingLine(9, 'daniel'), 'Bom dia, Daniel');
    });

    test('sem nome vem só a saudação', () {
      expect(greetingLine(21, null), 'Boa noite');
      expect(greetingLine(21, '   '), 'Boa noite');
    });
  });
}
