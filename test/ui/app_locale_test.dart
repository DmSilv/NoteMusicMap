// O app inteiro em português do Brasil: seletores de data e hora, botões e nomes de mês saem em português.
import 'package:afina/ui/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required bool ptBr, required Widget Function(BuildContext) botao}) {
  return MaterialApp(
    localizationsDelegates: ptBr ? kLocalizationsDelegates : null,
    supportedLocales: ptBr ? kSupportedLocales : const [Locale('en', 'US')],
    locale: ptBr ? kAppLocale : null,
    home: Builder(builder: (context) => Scaffold(body: Center(child: botao(context)))),
  );
}

Widget _abreData(BuildContext context) => ElevatedButton(
      onPressed: () => showDatePicker(
        context: context,
        initialDate: DateTime(2026, 11, 12),
        firstDate: DateTime(2026, 1, 1),
        lastDate: DateTime(2028, 12, 31),
      ),
      child: const Text('abrir'),
    );

Widget _abreHora(BuildContext context) => ElevatedButton(
      onPressed: () => showTimePicker(context: context, initialTime: const TimeOfDay(hour: 18, minute: 30)),
      child: const Text('abrir'),
    );

void main() {
  testWidgets('o idioma do app é português do Brasil', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(ptBr: true, botao: (c) {
      ctx = c;
      return const SizedBox();
    }));
    expect(Localizations.localeOf(ctx), const Locale('pt', 'BR'));
    expect(MaterialLocalizations.of(ctx).cancelButtonLabel.toLowerCase(), 'cancelar');
  });

  testWidgets('seletor de data: mês, botões e dias da semana em português', (tester) async {
    await tester.pumpWidget(_app(ptBr: true, botao: _abreData));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('novembro'), findsWidgets, reason: 'nome do mês em português');
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Select date'), findsNothing);
    expect(find.text('NOVEMBER'), findsNothing);
  });

  testWidgets('seletor de hora: botões e título em português', (tester) async {
    await tester.pumpWidget(_app(ptBr: true, botao: _abreHora));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Select time'), findsNothing);
    expect(find.text('SELECT TIME'), findsNothing);
  });

  testWidgets('controle: sem a configuração do app, o seletor sai em inglês (o teste enxerga a diferença)', (tester) async {
    await tester.pumpWidget(_app(ptBr: false, botao: _abreData));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Cancelar'), findsNothing);
  });
}
