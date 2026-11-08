import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('cleanText', () {
    test('tira controle, largura zero e inversão de direção', () {
      expect(cleanText('Ana\u0000 Maria\u200B'), 'Ana Maria');
      expect(cleanText('abc\u202Edef'), 'abcdef'); // inversão de sentido
      expect(cleanText('x\u2066y\u2069'), 'xy');
      expect(cleanText('\uFEFFOi'), 'Oi');
      expect(cleanText('a\u007Fb'), 'ab');
    });

    test('arruma espaços e quebras em campo de uma linha', () {
      expect(cleanText('  Suzuki   Livro\t1 \n  Lição  2 '), 'Suzuki Livro 1 Lição 2');
    });

    test('multilinha mantém as quebras e junta linhas em branco repetidas', () {
      expect(cleanText('a\n\n\n\nb\r\n c  d', multiline: true), 'a\n\nb\nc d');
    });

    test('corta pelo número de letras, sem partir emoji', () {
      final s = '🎻' * 100;
      final r = cleanText(s, max: 10);
      expect(r.runes.length, 10);
      expect(r, '🎻' * 10);
      expect(cleanText('a' * 1000, max: kMaxName).length, kMaxName);
    });

    test('null e vazio viram vazio', () {
      expect(cleanText(null), '');
      expect(cleanText('   '), '');
    });

    test('texto normal em português passa intacto', () {
      expect(cleanText('Lição 3 — Sérgio & Cia. (ré♭ maior)'), 'Lição 3 — Sérgio & Cia. (ré♭ maior)');
    });

    test('hasUnsafeChars avisa só quando há algo para tirar', () {
      expect(hasUnsafeChars('Olá'), isFalse);
      expect(hasUnsafeChars('Ol\u202Eá'), isTrue);
      expect(hasUnsafeChars('a\nb'), isTrue);
      expect(hasUnsafeChars('a\nb', multiline: true), isFalse);
    });

    test('stripUnsafe não mexe nos espaços (serve para digitar)', () {
      expect(stripUnsafe('a  b \u200B'), 'a  b ');
      expect(stripUnsafe('x' * 50, max: 5), 'xxxxx');
    });
  });
}
