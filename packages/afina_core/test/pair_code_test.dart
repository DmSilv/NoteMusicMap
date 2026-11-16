import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('código de pareamento', () {
    test('aceita maiúsculas, minúsculas, espaços e hífen', () {
      expect(normalizePairCode('k7qm-4txd'), 'K7QM-4TXD');
      expect(normalizePairCode(' K7QM 4TXD '), 'K7QM-4TXD');
      expect(normalizePairCode('K7QM4TXD'), 'K7QM-4TXD');
    });

    test('tira o código de um link ?pair=', () {
      expect(normalizePairCode('https://notemusicmap.vercel.app/?pair=k7qm-4txd'), 'K7QM-4TXD');
      expect(normalizePairCode('https://x.app/?a=1&pair=K7QM4TXD&b=2'), 'K7QM-4TXD');
    });

    test('recusa tamanho errado e símbolos fora do alfabeto (0, O, 1, I)', () {
      for (final bad in ['', 'K7QM', 'K7QM-4TXD-9', 'K7QM-4TX0', 'K7QM-4TXO', 'K7QM-4TX1', 'K7QM-4TXI', 'ÃÃÃÃ-ÃÃÃÃ']) {
        expect(normalizePairCode(bad), isNull, reason: bad);
      }
    });
  });
}
