// Testes de tela do tutorial guiado: passos, "Pular", passo fora da tela é pulado e nunca trava.
import 'package:afina/ui/tour/tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _a = GlobalKey(debugLabel: 'a');
final _b = GlobalKey(debugLabel: 'b');
final _ausente = GlobalKey(debugLabel: 'ausente');
late BuildContext _ctx;

Future<void> _tela(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          _ctx = context;
          return Scaffold(
            body: Column(
              children: [
                ElevatedButton(
                  key: _a,
                  onPressed: () {},
                  child: const Text('Botão A'),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  key: _b,
                  onPressed: () {},
                  child: const Text('Botão B'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// Avança o relógio o bastante para o passo medir e mostrar a caixinha.
Future<void> _espera(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('passa pelos passos e termina em "Entendi" devolvendo true', (
    tester,
  ) async {
    await _tela(tester);
    bool? resultado;
    runTour(_ctx, [
      TourStep(_a, 'Primeiro', 'Texto do A'),
      TourStep(_b, 'Segundo', 'Texto do B'),
    ]).then((v) => resultado = v);
    await _espera(tester);
    expect(find.text('Primeiro'), findsOneWidget);
    expect(find.text('1 de 2'), findsOneWidget);
    expect(find.text('Próximo'), findsOneWidget);
    expect(resultado, isNull);

    await tester.tap(find.text('Próximo'));
    await _espera(tester);
    expect(find.text('Segundo'), findsOneWidget);
    expect(find.text('2 de 2'), findsOneWidget);
    expect(find.text('Entendi'), findsOneWidget);

    await tester.tap(find.text('Entendi'));
    await _espera(tester);
    expect(resultado, isTrue);
    expect(find.text('Segundo'), findsNothing);
  });

  testWidgets('"Pular" fecha na hora e devolve false', (tester) async {
    await _tela(tester);
    bool? resultado;
    runTour(_ctx, [
      TourStep(_a, 'Primeiro', 'Texto do A'),
      TourStep(_b, 'Segundo', 'Texto do B'),
    ]).then((v) => resultado = v);
    await _espera(tester);
    await tester.tap(find.text('Pular'));
    await _espera(tester);
    expect(resultado, isFalse);
    expect(find.text('Primeiro'), findsNothing);
  });

  testWidgets('um passo cujo botão não está na tela é pulado (não trava)', (
    tester,
  ) async {
    await _tela(tester);
    bool? resultado;
    runTour(_ctx, [
      TourStep(_ausente, 'Sumido', 'Não existe na tela'),
      TourStep(_b, 'Segundo', 'Texto do B'),
    ]).then((v) => resultado = v);
    await _espera(tester);
    expect(find.text('Sumido'), findsNothing);
    expect(find.text('Segundo'), findsOneWidget);
    expect(find.text('2 de 2'), findsOneWidget);
    await tester.tap(find.text('Entendi'));
    await _espera(tester);
    expect(resultado, isTrue);
  });

  testWidgets('nenhum passo cabe na tela: termina com false e sem caixinha', (
    tester,
  ) async {
    await _tela(tester);
    bool? resultado;
    runTour(_ctx, [
      TourStep(_ausente, 'Sumido', 'Não existe'),
    ]).then((v) => resultado = v);
    await _espera(tester);
    expect(resultado, isFalse);
    expect(find.text('Sumido'), findsNothing);
  });

  testWidgets('lista vazia devolve false sem abrir nada', (tester) async {
    await _tela(tester);
    expect(await runTour(_ctx, const []), isFalse);
  });

  testWidgets('o fundo escuro não deixa apertar o botão de trás', (
    tester,
  ) async {
    var apertou = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            _ctx = context;
            return Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ElevatedButton(
                  key: _a,
                  onPressed: () => apertou = true,
                  child: const Text('Botão A'),
                ),
              ),
            );
          },
        ),
      ),
    );
    runTour(_ctx, [TourStep(_a, 'Primeiro', 'Texto do A')]);
    await _espera(tester);
    await tester.tapAt(const Offset(20, 20)); // no fundo escuro, longe da caixinha
    await tester.pump();
    expect(apertou, isFalse);
    await tester.tap(find.text('Pular'));
    await _espera(tester);
  });
}
