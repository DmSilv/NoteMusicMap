import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  test('texto simples: um método por linha', () {
    final r = parseMethodsText('Suzuki\nŠevčík\n\nKayser');
    expect(r.map((m) => m.name), ['Suzuki', 'Ševčík', 'Kayser']);
    expect(r.every((m) => m.lessons.isEmpty), isTrue);
  });

  test('"Método: lição; lição" na mesma linha', () {
    final r = parseMethodsText('Suzuki Livro 1: Lição 1; Lição 2 ;Lição 3');
    expect(r.single.name, 'Suzuki Livro 1');
    expect(r.single.lessons, ['Lição 1', 'Lição 2', 'Lição 3']);
  });

  test('lições nas linhas seguintes (marcadores, números ou recuo)', () {
    final r = parseMethodsText('Wohlfahrt Op. 45\n- Estudo 1\n• Estudo 2\n3) Estudo 3\n    Estudo 4\nMazas\n* Estudo 1');
    expect(r.length, 2);
    expect(r[0].name, 'Wohlfahrt Op. 45');
    expect(r[0].lessons, ['Estudo 1', 'Estudo 2', 'Estudo 3', 'Estudo 4']);
    expect(r[1].lessons, ['Estudo 1']);
  });

  test('JSON exportado volta igual; lista de nomes e objetos também são aceitos', () {
    final lib = [MethodEntry('Suzuki', ['Lição 1', 'Lição 2']), MethodEntry('Kayser')];
    final back = parseMethodsText(exportMethodsJson(lib));
    expect(back.map((m) => m.name), ['Suzuki', 'Kayser']);
    expect(back[0].lessons, ['Lição 1', 'Lição 2']);
    expect(parseMethodsText('["A","B"]').map((m) => m.name), ['A', 'B']);
    expect(parseMethodsText('[{"nome":"X","licoes":["1","2"]}]').single.lessons, ['1', '2']);
  });

  test('texto exportado legível volta pelo leitor de texto', () {
    final lib = [MethodEntry('Suzuki', ['Lição 1', 'Lição 2']), MethodEntry('Mazas', ['Estudo 3'])];
    final back = parseMethodsText(exportMethodsText(lib));
    expect(back.map((m) => m.name), ['Suzuki', 'Mazas']);
    expect(back[0].lessons, ['Lição 1', 'Lição 2']);
  });

  test('juntar não duplica (ignora maiúsculas) e conta o que entrou', () {
    final lib = [MethodEntry('Suzuki', ['Lição 1'])];
    final r = mergeMethods(lib, [MethodEntry('suzuki', ['lição 1', 'Lição 2']), MethodEntry('Kayser', ['E1'])]);
    expect(r.methods, 1);
    expect(r.lessons, 2); // Lição 2 e E1
    expect(lib.length, 2);
    expect(lib[0].lessons, ['Lição 1', 'Lição 2']);
    expect(mergeMethods(lib, [MethodEntry('SUZUKI', ['LIÇÃO 2'])]).nothing, isTrue);
  });

  test('aprender com a tarefa: cria o método e a lição, sem repetir', () {
    final lib = <MethodEntry>[];
    expect(learnMethod(lib, 'Hanon', 'Nº 1').methods, 1);
    expect(learnMethod(lib, 'hanon', 'nº 1').nothing, isTrue);
    expect(learnMethod(lib, 'Hanon', '').nothing, isTrue);
    expect(findMethod(lib, ' HANON ')!.lessons, ['Nº 1']);
  });

  test('entradas vazias ou inválidas não quebram', () {
    expect(parseMethodsText(''), isEmpty);
    expect(parseMethodsText('   \n  '), isEmpty);
    expect(parseMethodsText('[{"sem":"nome"}]'), isEmpty);
    expect(parseMethodsText('{ não é json'), isNotEmpty); // vira texto, uma linha
  });
}
