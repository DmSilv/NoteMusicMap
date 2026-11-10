import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('trechos em linha', () {
    test('negrito e itálico', () {
      expect(parseInline('Use **Sol** e *cents* hoje'), [
        const InlineRun('Use '),
        const InlineRun('Sol', bold: true),
        const InlineRun(' e '),
        const InlineRun('cents', italic: true),
        const InlineRun(' hoje'),
      ]);
    });

    test('itálico entre parênteses, como a IA escreve', () {
      final r = parseInline('Notas longas. (*10 minutos diários*)');
      expect(r.map((x) => x.text).join(), 'Notas longas. (10 minutos diários)');
      expect(r.any((x) => x.italic && x.text == '10 minutos diários'), isTrue);
    });

    test('asterisco solto some; texto sem marcação não muda', () {
      expect(stripInline('2 * 3 e *aberto'), '2  3 e aberto');
      expect(stripInline('sem marcação'), 'sem marcação');
      expect(parseInline(''), isEmpty);
    });

    test('negrito dentro de frase com itálico', () {
      final r = parseInline('**ouça** o *Lá*');
      expect(r.first, const InlineRun('ouça', bold: true));
      expect(r.last, const InlineRun('Lá', italic: true));
    });
  });

  group('texto puro para copiar', () {
    const md = '## Visão geral\n'
        'Você tocou **0%** dentro de ±5 *cents*.\n\n'
        '## O que os números mostram\n'
        '- Registro de 0% de precisão.\n'
        '- 15 notas puladas.\n'
        '## Plano\n'
        '1. Notas longas (*10 minutos diários*).\n'
        '2. Leitura nota por nota.';

    test('mantém as quebras de linha entre títulos, tópicos e passos', () {
      final p = markdownToPlain(md);
      expect(p.split('\n').length, greaterThan(8));
      expect(p, contains('Visão geral\nVocê tocou 0% dentro de ±5 cents.'));
      expect(p, contains('cents.\n\nO que os números mostram\n• Registro de 0% de precisão.\n• 15 notas puladas.'));
      expect(p, contains('puladas.\n\nPlano\n1. Notas longas (10 minutos diários).\n2. Leitura nota por nota.'));
    });

    test('sem marcação nenhuma sobrando', () {
      final p = markdownToPlain(md);
      expect(p.contains('#'), isFalse);
      expect(p.contains('*'), isFalse);
    });

    test('vazio, só espaços e quebras Windows', () {
      expect(markdownToPlain(''), '');
      expect(markdownToPlain('  \n \n'), '');
      expect(markdownToPlain('## A\r\n- b\r\n'), 'A\n• b');
    });
  });
}
