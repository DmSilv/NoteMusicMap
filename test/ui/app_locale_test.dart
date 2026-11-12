// O app fala português do Brasil ou inglês: seletores de data e hora, botões e nomes de mês saem no idioma escolhido.
import 'package:afina/ui/app_locale.dart';
import 'package:afina_core/afina_core.dart' show AppLang;
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


  testWidgets('em inglês o seletor de data usa os textos do Flutter em inglês', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: localeFor(AppLang.en),
      home: Builder(builder: (context) => Scaffold(body: Center(child: _abreData(context)))),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('November'), findsWidgets, reason: 'nome do mês em inglês');
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Cancelar'), findsNothing);
  });

  test('localeFor: português do Brasil ou inglês', () {
    expect(localeFor(AppLang.pt), const Locale('pt', 'BR'));
    expect(localeFor(AppLang.en), const Locale('en'));
    expect(kSupportedLocales, contains(const Locale('en')));
  });

  testWidgets('controle: sem a configuração do app, o seletor sai em inglês (o teste enxerga a diferença)', (tester) async {
    await tester.pumpWidget(_app(ptBr: false, botao: _abreData));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Cancelar'), findsNothing);
  });
}
