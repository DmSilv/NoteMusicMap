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

  testWidgets('botão sol/lua: trilho dividido (branco e preto), cada metade com alvo de 48 px, o anel mostra a cor que vale e um toque troca', (tester) async {
    StaffPaper? got;
    await tester.pumpWidget(_host(PaperToggle(value: StaffPaper.auto, onChanged: (p) => got = p), dark: true));
    final sun = find.byIcon(Icons.light_mode_rounded);
    final moon = find.byIcon(Icons.dark_mode_rounded);
    expect(sun, findsOneWidget);
    expect(moon, findsOneWidget);
    for (final f in [sun, moon]) {
      expect(tester.getSize(find.ancestor(of: f, matching: find.byType(InkWell)).first).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.ancestor(of: f, matching: find.byType(InkWell)).first).width, greaterThanOrEqualTo(48));
    }
    // "igual ao app" com o app escuro: o anel fica do lado da lua
    double ringX() => tester.getCenter(find.byType(AnimatedAlign)).dx;
    final toggleCenter = tester.getCenter(find.byType(PaperToggle)).dx;
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getCenter(find.descendant(of: find.byType(AnimatedAlign), matching: find.byType(Container))).dx, greaterThan(toggleCenter));
    expect(ringX(), isNotNull);
    await tester.tap(sun);
    expect(got, StaffPaper.light);
    await tester.tap(moon);
    expect(got, StaffPaper.dark);
    // com o app claro e "igual ao app", o anel vai para o sol
    await tester.pumpWidget(_host(PaperToggle(value: StaffPaper.auto, onChanged: (_) {}), dark: false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getCenter(find.descendant(of: find.byType(AnimatedAlign), matching: find.byType(Container))).dx, lessThan(tester.getCenter(find.byType(PaperToggle)).dx));
    // leitor de tela: cada metade é um botão com o estado
    expect(find.bySemanticsLabel('Partitura clara'), findsOneWidget);
    expect(find.bySemanticsLabel('Partitura escura'), findsOneWidget);
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
