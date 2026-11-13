import 'package:afina/ui/undo_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('aviso com Desfazer: aparece com o texto, o botão desfaz e some', (tester) async {
    var undone = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => Center(
            child: ElevatedButton(
              onPressed: () => showUndoSnack(ScaffoldMessenger.of(c), message: 'Cartão escondido.', undoLabel: 'Desfazer', onUndo: () => undone++),
              child: const Text('esconder'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('esconder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Cartão escondido.'), findsOneWidget);
    expect(find.text('Desfazer'), findsOneWidget);
    // alvo de toque do botão >= 48 px de altura
    expect(tester.getSize(find.ancestor(of: find.text('Desfazer'), matching: find.byType(TextButton)).first).height, greaterThanOrEqualTo(40));
    await tester.tap(find.text('Desfazer'));
    await tester.pump();
    expect(undone, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Cartão escondido.'), findsNothing);
  });

  testWidgets('o aviso fica tempo de ler (8 s) e outro aviso troca o anterior', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => Column(children: [
            ElevatedButton(onPressed: () => showUndoSnack(ScaffoldMessenger.of(c), message: 'um', undoLabel: 'Desfazer', onUndo: () {}), child: const Text('a')),
            ElevatedButton(onPressed: () => showUndoSnack(ScaffoldMessenger.of(c), message: 'dois', undoLabel: 'Desfazer', onUndo: () {}), child: const Text('b')),
          ]),
        ),
      ),
    ));
    await tester.tap(find.text('a'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('um'), findsOneWidget); // ainda na tela depois de 6 s
    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('dois'), findsOneWidget);
    expect(find.text('um'), findsNothing);
  });
}
