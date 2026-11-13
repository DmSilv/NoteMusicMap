import 'package:afina/ui/paper_picker.dart';
import 'package:afina/ui/staff_card.dart';
import 'package:afina/ui/theme.dart';
import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool dark = true}) {
  AppColors.dark = dark;
  return MaterialApp(home: Scaffold(backgroundColor: AppColors.bg, body: Padding(padding: const EdgeInsets.all(16), child: child)));
}

void main() {
  testWidgets('seletor da cor: três amostras (clara, escura, igual ao app), a escolhida tem destaque e o toque troca', (tester) async {
    StaffPaper? got;
    await tester.pumpWidget(_host(PaperPicker(value: StaffPaper.dark, onChanged: (p) => got = p)));
    expect(find.text('Clara'), findsOneWidget);
    expect(find.text('Escura'), findsOneWidget);
    expect(find.text('Igual ao app'), findsOneWidget);
    // a escolhida avisa o leitor de tela
    final sem = tester.getSemantics(find.bySemanticsLabel('Escura'));
    expect(sem.flagsCollection.isSelected, isNotNull);
    await tester.tap(find.text('Clara'));
    expect(got, StaffPaper.light);
    await tester.tap(find.text('Igual ao app'));
    expect(got, StaffPaper.auto);
    // alvos de toque grandes (>= 48 px)
    for (final t in ['Clara', 'Escura', 'Igual ao app']) {
      final box = tester.getSize(find.ancestor(of: find.text(t), matching: find.byType(InkWell)).first);
      expect(box.height, greaterThanOrEqualTo(48), reason: t);
    }
  });

  testWidgets('botão sol/lua: duas amostras (branca e preta), alvo de 48 px, mostra a cor que vale e troca num toque', (tester) async {
    StaffPaper? got;
    await tester.pumpWidget(_host(PaperToggle(value: StaffPaper.auto, onChanged: (p) => got = p), dark: true));
    // "igual ao app" com o app escuro: a lua é a que vale
    final sun = find.byIcon(Icons.light_mode_rounded);
    final moon = find.byIcon(Icons.dark_mode_rounded);
    expect(sun, findsOneWidget);
    expect(moon, findsOneWidget);
    for (final f in [sun, moon]) {
      expect(tester.getSize(find.ancestor(of: f, matching: find.byType(InkWell)).first).height, greaterThanOrEqualTo(48));
    }
    BoxDecoration deco(Finder icon) => tester.widget<Container>(find.ancestor(of: icon, matching: find.byType(Container)).first).decoration as BoxDecoration;
    expect(deco(sun).color, const Color(0xFFFFFFFF));
    expect(deco(moon).color, const Color(0xFF000000));
    expect((deco(moon).border as Border).top.width, 3); // a que vale tem borda grossa
    expect((deco(sun).border as Border).top.width, 1);
    await tester.tap(sun);
    expect(got, StaffPaper.light);
    await tester.tap(moon);
    expect(got, StaffPaper.dark);
    // com o app claro e "igual ao app", o sol é que vale
    await tester.pumpWidget(_host(PaperToggle(value: StaffPaper.auto, onChanged: (_) {}), dark: false));
    expect((deco(sun).border as Border).top.width, 3);
  });

  test('paperIsDark: igual ao app segue o tema; clara e escura não', () {
    AppColors.dark = true;
    expect(paperIsDark(StaffPaper.auto), isTrue);
    expect(paperIsDark(StaffPaper.light), isFalse);
    AppColors.dark = false;
    expect(paperIsDark(StaffPaper.auto), isFalse);
    expect(paperIsDark(StaffPaper.dark), isTrue);
  });

  testWidgets('cartão com onPaper mostra o botão sol/lua; sem onPaper não mostra', (tester) async {
    final seq = scaleSequence(55, ScaleType.major);
    Widget card({ValueChanged<StaffPaper>? on}) => _host(StaffCard(tonicMidi: 55, type: ScaleType.major, sequence: seq, upCount: 8, onPaper: on));
    await tester.pumpWidget(card());
    expect(find.byIcon(Icons.dark_mode_rounded), findsNothing);
    StaffPaper? got;
    await tester.pumpWidget(card(on: (p) => got = p));
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.light_mode_rounded));
    expect(got, StaffPaper.light);
  });
}
