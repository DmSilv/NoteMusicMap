// Testes de tela do "momento de sucesso" (folha que sobe, mostra o ✓ e some sozinha).
import 'package:afina/ui/success_moment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _abrir(WidgetTester tester, {String detail = ''}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showSuccessMoment(context, 'Horário pego!', detail: detail),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  testWidgets('mostra o título e o detalhe', (tester) async {
    await _abrir(tester, detail: 'Terça, 19:00 com o professor');
    expect(find.text('Horário pego!'), findsOneWidget);
    expect(find.text('Terça, 19:00 com o professor'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // deixa fechar
    await tester.pumpAndSettle();
  });

  testWidgets('sem detalhe, só aparece o título', (tester) async {
    await _abrir(tester);
    expect(find.text('Horário pego!'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(2)); // o botão "abrir" atrás e o título
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('some sozinha depois de uns 2 segundos', (tester) async {
    await _abrir(tester);
    expect(find.text('Horário pego!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();
    expect(find.text('Horário pego!'), findsNothing);
  });

  testWidgets('um toque fecha na hora', (tester) async {
    await _abrir(tester);
    await tester.tap(find.text('Horário pego!'));
    await tester.pumpAndSettle();
    expect(find.text('Horário pego!'), findsNothing);
  });

  testWidgets('com animações desligadas no sistema a folha abre igual', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSuccessMoment(context, 'Pronto'),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pronto'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
