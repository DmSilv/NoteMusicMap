// Cartão de resumo que abre os ajustes: um controle por área, alvos de 48 px e leitor de tela com um item só.
import 'package:afina/ui/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)));

void main() {
  testWidgets('tocar no cartão abre os ajustes', (tester) async {
    var abriu = 0;
    await tester.pumpWidget(_app(DsConfigCard(
      semanticLabel: 'Configurar escala',
      semanticValue: 'Escala de Sol Maior',
      onTap: () => abriu++,
      child: const Text('Escala de Sol Maior'),
    )));
    await tester.tap(find.text('Escala de Sol Maior'));
    expect(abriu, 1);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    expect(abriu, 2, reason: 'o ícone de ajustes também abre');
  });

  testWidgets('o "?" fica fora do cartão: tocar nele não abre os ajustes e vice-versa', (tester) async {
    var abriu = 0, ajuda = 0;
    await tester.pumpWidget(_app(DsConfigCard(
      semanticLabel: 'Configurar escala',
      onTap: () => abriu++,
      extra: IconButton.outlined(onPressed: () => ajuda++, tooltip: 'Ajuda', icon: const Icon(Icons.help_outline)),
      child: const Text('Arpejo maior de Sol'),
    )));
    await tester.tap(find.byIcon(Icons.help_outline));
    expect(ajuda, 1);
    expect(abriu, 0, reason: 'botão dentro de botão: o toque no "?" não pode abrir os ajustes');
    await tester.tap(find.text('Arpejo maior de Sol'));
    expect(abriu, 1);
    expect(ajuda, 1);
    // o "?" não está dentro do InkWell do cartão
    expect(find.descendant(of: find.byType(InkWell).first, matching: find.byIcon(Icons.help_outline)), findsNothing);
  });

  testWidgets('alvos de toque de pelo menos 48 px', (tester) async {
    await tester.pumpWidget(_app(DsConfigCard(
      semanticLabel: 'Configurar escala',
      onTap: () {},
      extra: IconButton.outlined(onPressed: () {}, style: IconButton.styleFrom(minimumSize: const Size(48, 48)), icon: const Icon(Icons.help_outline)),
      child: const Text('Escala'),
    )));
    final cartao = tester.getSize(find.byType(InkWell).first);
    expect(cartao.height, greaterThanOrEqualTo(48));
    final ajuda = tester.getSize(find.byType(IconButton));
    expect(ajuda.width, greaterThanOrEqualTo(48));
    expect(ajuda.height, greaterThanOrEqualTo(48));
  });

  testWidgets('leitor de tela: um botão só, com o rótulo, o resumo e a dica', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(DsConfigCard(
      semanticLabel: 'Configurar escala',
      semanticValue: 'Escala de Sol Maior, 1 oitava',
      onTap: () {},
      child: const Text('Escala de Sol Maior'),
    )));
    final node = tester.getSemantics(find.byType(DsConfigCard));
    expect(node.label, contains('Configurar escala'));
    expect(node.value, 'Escala de Sol Maior, 1 oitava');
    expect(node.hint, isNotEmpty);
    expect(find.bySemanticsLabel('Escala de Sol Maior'), findsNothing, reason: 'o texto de dentro não vira um segundo item');
    handle.dispose();
  });
}
