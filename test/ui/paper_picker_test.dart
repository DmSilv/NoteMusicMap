import 'package:afina/ui/paper_picker.dart';
import 'package:afina/ui/theme.dart';
import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool dark = true}) {
  AppColors.dark = dark;
  return MaterialApp(home: Scaffold(backgroundColor: AppColors.bg, body: Padding(padding: const EdgeInsets.all(16), child: child)));
}

void main() {
  testWidgets('cor da partitura: seletor padrão do app com ícone e nome (Clara e Escura), a que vale marcada, um toque troca', (tester) async {
    StaffPaper? got;
    await tester.pumpWidget(_host(PaperToggleRow(value: StaffPaper.auto, onChanged: (p) => got = p), dark: true));
    expect(find.text('Cor da partitura'), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    expect(find.text('Clara'), findsOneWidget);
    expect(find.text('Escura'), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    SegmentedButton<bool> sb() => tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(sb().selected, {true}); // "igual ao app" com o app escuro: vale a escura
    await tester.tap(find.text('Clara'));
    expect(got, StaffPaper.light);
    // tocar na que já vale não muda nada; trocando de lado, volta a escura
    await tester.pumpWidget(_host(PaperToggleRow(value: StaffPaper.light, onChanged: (p) => got = p), dark: true));
    await tester.tap(find.text('Escura'));
    expect(got, StaffPaper.dark);
    // com o app claro e "igual ao app", vale a clara
    await tester.pumpWidget(_host(PaperToggleRow(value: StaffPaper.auto, onChanged: (_) {}), dark: false));
    expect(sb().selected, {false});
    // escolha explícita vale mesmo contra o tema do app
    await tester.pumpWidget(_host(PaperToggleRow(value: StaffPaper.light, onChanged: (_) {}), dark: true));
    expect(sb().selected, {false});
    // alvos de toque de pelo menos 40 px de altura
    expect(tester.getSize(find.byType(SegmentedButton<bool>)).height, greaterThanOrEqualTo(40));
  });

  test('paperIsDark: igual ao app segue o tema; clara e escura não', () {
    AppColors.dark = true;
    expect(paperIsDark(StaffPaper.auto), isTrue);
    expect(paperIsDark(StaffPaper.light), isFalse);
    AppColors.dark = false;
    expect(paperIsDark(StaffPaper.auto), isFalse);
    expect(paperIsDark(StaffPaper.dark), isTrue);
  });

}
