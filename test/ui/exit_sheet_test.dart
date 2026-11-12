// Testes da pergunta "Já vai embora?" (botão voltar na tela principal): só sai com um toque deliberado em "Sair do app".
import 'package:afina/ui/exit_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool? _resultado;

Future<void> _abre(WidgetTester tester) async {
  _resultado = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => _resultado = await confirmExitApp(context),
              child: const Text('voltar'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('voltar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra a pergunta com o botão de ficar em destaque e o de sair discreto', (tester) async {
    await _abre(tester);
    expect(find.text('Já vai embora?'), findsOneWidget);
    expect(find.text('Continuar no app'), findsOneWidget);
    expect(find.text('Sair do app'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget, reason: 'só "continuar" é o botão cheio');
    expect(_resultado, isNull, reason: 'enquanto pergunta, ninguém saiu');
  });

  testWidgets('"Continuar no app" fica', (tester) async {
    await _abre(tester);
    await tester.tap(find.text('Continuar no app'));
    await tester.pumpAndSettle();
    expect(_resultado, isFalse);
    expect(find.text('Já vai embora?'), findsNothing);
  });

  testWidgets('"Sair do app" é o único jeito de sair', (tester) async {
    await _abre(tester);
    await tester.tap(find.text('Sair do app'));
    await tester.pumpAndSettle();
    expect(_resultado, isTrue);
  });

  testWidgets('apertar voltar de novo, tocar fora ou arrastar para baixo = ficar', (tester) async {
    // voltar de novo
    await _abre(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(_resultado, isFalse);
    expect(find.text('Já vai embora?'), findsNothing);

    // tocar fora (no fundo escuro)
    await _abre(tester);
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(_resultado, isFalse);

    // arrastar para baixo
    await _abre(tester);
    await tester.drag(find.text('Já vai embora?'), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(_resultado, isFalse);
    expect(find.text('Já vai embora?'), findsNothing);
  });
}
