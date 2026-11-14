// Apresentação do primeiro acesso: 4 telas, "Pular" leva às portas, cada porta devolve sua escolha.
import 'package:afina/ui/welcome_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TourChoice?> _abre(
  WidgetTester tester,
  Future<void> Function() depois, {
  Size size = const Size(390, 844),
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.reset);
  TourChoice? r;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => r = await showWelcomeTour(c),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  await depois();
  return r;
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('abre na promessa, sem pedir nada, com Continuar e Pular', (
    tester,
  ) async {
    await _abre(tester, () async {
      expect(find.textContaining('Tocou a nota e ficou'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(find.text('Pular'), findsOneWidget);
      expect(find.textContaining('Sem cadastro'), findsOneWidget);
    });
  });

  testWidgets(
    'Continuar passa pelas 3 primeiras telas e mostra as três portas',
    (tester) async {
      await _abre(tester, () async {
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Uma caixa de ferramentas'), findsOneWidget);
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(
          find.text('Sou professor'),
          findsOneWidget,
        ); // o seletor da tela 3
        await tester.tap(find.text('Sou professor'));
        await tester.pumpAndSettle();
        expect(find.textContaining('sem planilha'), findsOneWidget);
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.text('Quero estudar'), findsOneWidget);
        expect(find.text('Tenho professor'), findsOneWidget);
        expect(find.text('Só quero olhar'), findsOneWidget);
        expect(
          find.text('Continuar'),
          findsNothing,
        ); // na última tela a escolha é pelas portas
      });
    },
  );

  testWidgets('Pular vai direto às portas e cada porta devolve a sua escolha', (
    tester,
  ) async {
    for (final (texto, esperado) in [
      ('Quero estudar', TourChoice.study),
      ('Tenho professor', TourChoice.hasTeacher),
      ('Sou professor', TourChoice.teacher),
      ('Só quero olhar', TourChoice.look),
    ]) {
      final r = await _abre(tester, () async {
        await tester.tap(find.text('Pular'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(texto));
        await tester.pumpAndSettle();
      });
      expect(r, esperado, reason: texto);
    }
  });

  testWidgets(
    'celular bem baixo (320 × 568): continua sem estouro e esconde só o apoio',
    (tester) async {
      await _abre(tester, () async {
        expect(find.textContaining('Tocou a nota e ficou'), findsOneWidget);
        expect(find.textContaining('Sem cadastro'), findsNothing);
        await tester.tap(find.text('Pular'));
        await tester.pumpAndSettle();
        expect(find.text('Quero estudar'), findsOneWidget);
        expect(find.text('Sem cadastro'), findsOneWidget);
      }, size: const Size(320, 568));
    },
  );

  testWidgets('voltar na primeira tela conta como "só olhar"', (tester) async {
    final r = await _abre(tester, () async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    });
    expect(r, TourChoice.look);
  });
}
