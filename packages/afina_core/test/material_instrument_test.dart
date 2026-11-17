import 'dart:convert';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('método e peça por instrumento', () {
    test('o instrumento vai e volta pelo JSON; valor estranho é descartado; sem instrumento não ganha campo', () {
      final m = MethodEntry('Czerny', ['Op. 599'], 'piano');
      final back = MethodEntry.tryFrom(jsonDecode(jsonEncode(m.toJson())))!;
      expect(back.instrument, 'piano');
      expect(back.lessons, ['Op. 599']);
      expect(MethodEntry.tryFrom({'name': 'X', 'ins': 'Piano <b>'})!.instrument, '');
      expect(MethodEntry('Y').toJson().containsKey('ins'), isFalse);
      expect(MethodEntry.tryFrom('só o nome')!.instrument, '');
    });

    test('lista colada: um por linha, aceita "Nome: lição; lição" e junta sem repetir', () {
      final found = parseMethodsText('Hanon\nCzerny: Op. 599; Op. 849\n\nhanon');
      final lib = <MethodEntry>[];
      for (final e in found) {
        e.instrument = 'piano';
      }
      final r = mergeMethods(lib, found);
      expect(lib.map((m) => m.name), ['Hanon', 'Czerny']);
      expect(lib.every((m) => m.instrument == 'piano'), isTrue);
      expect(lib[1].lessons, ['Op. 599', 'Op. 849']);
      expect(r.methods, 2);
    });

    test('a lista do professor com instrumento viaja na seção do espelho', () {
      final back = methodsFromSection(methodsToSection([MethodEntry('Suzuki', ['Livro 1'], 'violino')]));
      expect(back.single.instrument, 'violino');
    });
  });
}
