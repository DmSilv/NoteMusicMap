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
      expect(find.textContaining('está afinada'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(find.text('Pular'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // a promessa não pede nada
    });
  });

  testWidgets(
    'Continuar passa pelas 3 primeiras telas e mostra as três portas',
    (tester) async {
      await _abre(tester, () async {
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.textContaining('sem bagunça'), findsOneWidget);
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(
          find.text('Sou professor'),
          findsOneWidget,
        ); // o seletor da tela 3
        await tester.tap(find.text('Sou professor'));
        await tester.pumpAndSettle();
        expect(find.textContaining('entre as aulas'), findsOneWidget); // o propósito do lado do professor
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.text('Quero estudar'), findsOneWidget);
        expect(find.text('Tenho professor'), findsOneWidget);
        expect(find.text('Já tenho conta em outro aparelho'), findsOneWidget);
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
    // "Já tenho conta" sai na hora; as três portas abrem um card e só o botão "Seguir" confirma.
    for (final (texto, esperado, botao) in [
      ('Quero estudar', TourChoice.study, 'Começar a estudar'),
      ('Tenho professor', TourChoice.hasTeacher, 'Ler o QR do professor'),
      ('Sou professor', TourChoice.teacher, 'Criar meu perfil de professor'),
      ('Já tenho conta em outro aparelho', TourChoice.hasAccount, null),
    ]) {
      final r = await _abre(tester, () async {
        await tester.tap(find.text('Pular'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(texto));
        await tester.tap(find.text(texto));
        await tester.pumpAndSettle();
        if (botao != null) {
          await tester.ensureVisible(find.text(botao));
          await tester.tap(find.text(botao));
          await tester.pumpAndSettle();
        }
      });
      expect(r, esperado, reason: texto);
    }
  });

  testWidgets('escolher uma porta só abre o card com a explicação e o botão (não sai da tela)', (tester) async {
    final r = await _abre(tester, () async {
      await tester.tap(find.text('Pular'));
      await tester.pumpAndSettle();
      expect(find.text('Começar a estudar'), findsNothing);
      await tester.tap(find.text('Sou professor'));
      await tester.pumpAndSettle();
      expect(find.text('Criar meu perfil de professor'), findsOneWidget);
      await tester.tap(find.text('Quero estudar'));
      await tester.pumpAndSettle();
      expect(find.text('Começar a estudar'), findsOneWidget);
      expect(find.text('Criar meu perfil de professor'), findsNothing);
    });
    expect(r, isNull);
  });

  testWidgets(
    'celular bem baixo (320 × 568): continua sem estouro e esconde só o apoio',
    (tester) async {
      await _abre(tester, () async {
        expect(find.textContaining('está afinada'), findsOneWidget);
        expect(find.textContaining('Sem formulário'), findsNothing);
        await tester.tap(find.text('Pular'));
        await tester.pumpAndSettle();
        expect(find.text('Quero estudar'), findsOneWidget);
        expect(find.textContaining('Sem formulário'), findsNothing); // celular baixo: o texto de apoio some, as portas ficam
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
