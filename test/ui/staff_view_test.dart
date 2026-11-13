import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:afina/ui/staff_card.dart';
import 'package:afina/ui/staff_view.dart';
import 'package:afina/ui/theme.dart';
import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

StaffScore _score(int tonic, ScaleType t, {int octaves = 1, StaffRhythm r = StaffRhythm.quarter, ScaleDirection d = ScaleDirection.both}) {
  final seq = scaleSequence(tonic, t, octaves: octaves, direction: d);
  final up = d == ScaleDirection.down ? 0 : scaleMidis(tonic, t, octaves: octaves).length;
  return buildStaffScore(tonicMidi: tonic, type: t, sequence: seq, upCount: up, rhythm: r);
}

Future<void> _loadFont() async {
  final loader = FontLoader('Leland')..addFont(rootBundle.load('assets/fonts/Leland.otf'));
  await loader.load();
}

Widget _host(Widget child, {required bool dark, double width = 358, Key? key}) {
  AppColors.dark = dark;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: AppColors.bg,
      body: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: Container(width: width, color: AppColors.surface, padding: const EdgeInsets.all(6), child: child),
        ),
      ),
    ),
  );
}

Future<void> _png(WidgetTester tester, Key key, String name) async {
  final dir = Platform.environment['STAFF_PNG_DIR'];
  if (dir == null || dir.isEmpty) return;
  await tester.runAsync(() async {
    final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final img = await b.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
  });
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  setUpAll(_loadFont);

  test('cor da nota tocada: afinada dentro da zona, grave (azul) abaixo, aguda (laranja) acima, pulada sem cor', () {
    expect(staffMarkOf(null, 10), isNull);
    expect(staffMarkOf(0, 10), StaffMark.inTune);
    expect(staffMarkOf(-10, 10), StaffMark.inTune);
    expect(staffMarkOf(10.5, 10), StaffMark.sharp);
    expect(staffMarkOf(-25, 10), StaffMark.flat);
  });

  testWidgets('desenha a partitura sem erro, nos temas claro e escuro', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(_host(StaffView(score: _score(60, ScaleType.melodicMinor, r: StaffRhythm.triplet), current: 3), dark: dark));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(StaffView), findsOneWidget);
    }
  });

  testWidgets('respeita a altura máxima e vira a página quando a nota atual passa', (tester) async {
    final sc = _score(60, ScaleType.major, octaves: 3, r: StaffRhythm.quarter);
    Widget build(int cur) => _host(StaffView(score: sc, current: cur, maxHeight: 190), dark: false);
    await tester.pumpWidget(build(0));
    final h0 = tester.getSize(find.byType(StaffView)).height;
    expect(h0, lessThanOrEqualTo(190 + 30)); // 190 da pauta + rótulo da página
    expect(find.textContaining('1 / '), findsOneWidget);
    await tester.pumpWidget(build(sc.noteCount - 1));
    expect(find.textContaining('1 / '), findsNothing);
    expect(find.textContaining(' / '), findsOneWidget);
  });

  testWidgets('prévia sem nota atual: um toque no 1 / N passa a página (alvo de 48 px)', (tester) async {
    final sc = _score(55, ScaleType.melodicMinor, octaves: 3, r: StaffRhythm.triplet);
    await tester.pumpWidget(_host(StaffView(score: sc, maxHeight: 200), dark: false));
    expect(find.textContaining('1 / '), findsOneWidget);
    final tap = find.byIcon(Icons.chevron_right_rounded);
    expect(tester.getSize(find.ancestor(of: tap, matching: find.byType(ConstrainedBox)).first).height, greaterThanOrEqualTo(48));
    await tester.tap(tap);
    await tester.pump();
    expect(find.textContaining('2 / '), findsOneWidget);
  });

  testWidgets('a dica de nota aguda não muda a altura (a faixa já estava reservada) e só vale para nota aguda', (tester) async {
    final sc = _score(74, ScaleType.major, r: StaffRhythm.quarter); // Ré5 .. Ré6: Dó6 e Ré6 são agudas
    Future<double> h(int cur, bool now) async {
      await tester.pumpWidget(_host(StaffView(score: sc, current: cur, hints: true, hintNow: now), dark: true));
      await tester.pump();
      expect(tester.takeException(), isNull);
      return tester.getSize(find.byType(StaffView)).height;
    }
    final a = await h(6, false);
    final b = await h(6, true);
    final c = await h(1, true); // nota comum: sem dica, mesma altura
    expect(b, a);
    expect(c, a);
    expect(sc.events[6].isHigh, isTrue);
    expect(sc.events[1].isHigh, isFalse);
  });

  testWidgets('sem notas agudas a dica não reserva faixa nenhuma', (tester) async {
    final sc = _score(55, ScaleType.major);
    await tester.pumpWidget(_host(StaffView(score: sc, hints: true), dark: false));
    final h1 = tester.getSize(find.byType(StaffView)).height;
    await tester.pumpWidget(_host(StaffView(score: sc), dark: false));
    expect(tester.getSize(find.byType(StaffView)).height, h1);
  });

  test('a cor da partitura é independente do tema do app: clara ou escura em qualquer tema', () {
    for (final appDark in [false, true]) {
      AppColors.dark = appDark;
      final l = StaffColors.fromTheme(StaffPaper.light);
      final d = StaffColors.fromTheme(StaffPaper.dark);
      expect(l.paper, const Color(0xFFFAFAF6));
      expect(l.ink, const Color(0xFF0E1822));
      expect(d.paper, const Color(0xFF000000));
      expect(d.ink, const Color(0xFFFFFFFF));
      // "igual ao app" segue o tema
      expect(StaffColors.fromTheme().paper, appDark ? d.paper : l.paper);
      // as cores das notas tocadas contrastam com o fundo escolhido (nada de verde claro sobre papel branco)
      expect(_contrast(l.inTune, l.paper), greaterThan(4.0));
      expect(_contrast(l.flat, l.paper), greaterThan(4.0));
      expect(_contrast(l.sharp, l.paper), greaterThan(4.0));
      expect(_contrast(d.inTune, d.paper), greaterThan(7.0));
      expect(_contrast(d.flat, d.paper), greaterThan(5.0));
      expect(_contrast(d.sharp, d.paper), greaterThan(7.0));
      expect(_contrast(l.ink, l.paper), greaterThan(12.0));
      expect(_contrast(d.ink, d.paper), greaterThan(18.0));
    }
  });

  testWidgets('o cartão usa o fundo escolhido, mesmo com o app no outro tema', (tester) async {
    AppColors.dark = true;
    await tester.pumpWidget(_host(StaffCard(tonicMidi: 55, type: ScaleType.major, sequence: scaleSequence(55, ScaleType.major), upCount: 8, paper: StaffPaper.light), dark: true));
    final box = tester.widget<Container>(find.descendant(of: find.byType(StaffCard), matching: find.byType(Container)).first);
    expect((box.decoration as BoxDecoration).color, const Color(0xFFFAFAF6));
    await tester.pumpWidget(_host(StaffCard(tonicMidi: 55, type: ScaleType.major, sequence: scaleSequence(55, ScaleType.major), upCount: 8, paper: StaffPaper.dark), dark: false));
    final box2 = tester.widget<Container>(find.descendant(of: find.byType(StaffCard), matching: find.byType(Container)).first);
    expect((box2.decoration as BoxDecoration).color, const Color(0xFF000000));
  });

  test('o fundo da partitura é preto puro no escuro e a tinta é branca', () {
    AppColors.dark = true;
    final d = StaffColors.fromTheme();
    expect(d.paper, const Color(0xFF000000));
    expect(d.ink, const Color(0xFFFFFFFF));
    AppColors.dark = false;
    final l = StaffColors.fromTheme();
    expect(l.paper, const Color(0xFFFAFAF6));
    expect(l.ink, AppColors.text);
  });

  testWidgets('cabe na largura do celular (sem estourar)', (tester) async {
    for (final w in [300.0, 358.0, 420.0]) {
      await tester.pumpWidget(_host(StaffView(score: _score(66, ScaleType.major, octaves: 2, r: StaffRhythm.eighth)), dark: true, width: w));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StaffView)).width, lessThanOrEqualTo(w));
    }
  });

  testWidgets('prévia em imagem (só quando STAFF_PNG_DIR existe)', (tester) async {
    if ((Platform.environment['STAFF_PNG_DIR'] ?? '').isEmpty) return;
    final k = GlobalKey();
    Future<void> shot(String name, StaffView v, {bool dark = false, double width = 358}) async {
      await tester.pumpWidget(_host(v, dark: dark, width: width, key: k));
      await tester.pump();
      await _png(tester, k, name);
    }

    final cm = _score(60, ScaleType.melodicMinor, r: StaffRhythm.triplet);
    final marks = {0: StaffMark.inTune, 1: StaffMark.inTune, 2: StaffMark.sharp, 3: StaffMark.flat, 4: StaffMark.inTune};
    await shot('a_cm_triplet_light', StaffView(score: cm, current: 5, marks: marks), dark: false);
    await shot('b_cm_triplet_dark', StaffView(score: cm, current: 5, marks: marks), dark: true);
    await shot('c_cm_quarter_light', StaffView(score: _score(60, ScaleType.melodicMinor), current: 6, marks: marks, names: StaffNames.all));
    await shot('d_dm_2oct_eighth_dark', StaffView(score: _score(62, ScaleType.melodicMinor, octaves: 2, r: StaffRhythm.eighth), current: 9, marks: marks, maxHeight: 260), dark: true);
    await shot('e_high_g_quarter_light', StaffView(score: _score(79, ScaleType.major, octaves: 1), current: 4, names: StaffNames.ledger));
    await shot('f_ab_major_half_dark', StaffView(score: _score(68, ScaleType.major, r: StaffRhythm.half), current: 2), dark: true);
    await shot('g_fsharp_eighth_light', StaffView(score: _score(66, ScaleType.major, r: StaffRhythm.eighth), current: 1));
    await shot('h_arpeggio_dim7_triplet_light', StaffView(score: _score(60, ScaleType.diminishedSeventh, octaves: 2, r: StaffRhythm.triplet), current: 2));
    final big = _score(55, ScaleType.melodicMinor, octaves: 3, r: StaffRhythm.triplet);
    await shot('j_3oct_triplet_p1_light', StaffView(score: big, current: 4, marks: marks, maxHeight: 250, names: StaffNames.ledger));
    await shot('k_3oct_triplet_last_dark', StaffView(score: big, current: big.noteCount - 2, maxHeight: 250, names: StaffNames.ledger), dark: true);
    await shot('l_4oct_high_quarter_light', StaffView(score: _score(67, ScaleType.major, octaves: 3, r: StaffRhythm.eighth), current: 20, maxHeight: 250, names: StaffNames.ledger));
    await shot('m_dark_black', StaffView(score: cm, current: 5, marks: marks), dark: true);
    await shot('n_hint_high_dark', StaffView(score: _score(74, ScaleType.major), current: 6, hints: true, hintNow: true), dark: true);
    await shot('n2_hint_high_light', StaffView(score: _score(74, ScaleType.major), current: 7, hints: true, hintNow: true));
    final dm = _score(62, ScaleType.melodicMinor, octaves: 1);
    final fingered = buildStaffScore(tonicMidi: 62, type: ScaleType.melodicMinor, sequence: scaleSequence(62, ScaleType.melodicMinor), upCount: 8, rhythm: StaffRhythm.quarter, fingers: ['0', '1', '2', '3', '4', '1', '2', '3', '4', '3', '2', '1', '0', '4', '2']);
    await shot('o_fingers_quarter_light', StaffView(score: fingered, current: 3));
    final fingeredT = buildStaffScore(tonicMidi: 62, type: ScaleType.melodicMinor, sequence: scaleSequence(62, ScaleType.melodicMinor, octaves: 2), upCount: 15, rhythm: StaffRhythm.triplet, fingers: [for (var i = 0; i < 30; i++) '${i % 5}']);
    await shot('p_fingers_triplet_dark', StaffView(score: fingeredT, current: 3, maxHeight: 330), dark: true);
    expect(dm.noteCount, 15);
    final seq8 = scaleSequence(72, ScaleType.melodicMinor, octaves: 2);
    final s8 = buildStaffScore(tonicMidi: 72, type: ScaleType.melodicMinor, sequence: seq8, upCount: scaleMidis(72, ScaleType.melodicMinor, octaves: 2).length, rhythm: StaffRhythm.triplet, ottava: true, fingers: [for (var i = 0; i < seq8.length; i++) (i % 4 == 0) ? '${1 + (i ~/ 4) % 4}' : null]);
    await shot('q_8va_triplet_light', StaffView(score: s8, current: 17, maxHeight: 420, hints: true));
    await shot('r_8va_triplet_dark', StaffView(score: s8, current: 20, maxHeight: 420, hints: true), dark: true);
    await shot('s_light_paper_in_dark_app', StaffView(score: cm, current: 5, marks: marks, colors: StaffColors.light), dark: true);
    await shot('t_dark_paper_in_light_app', StaffView(score: cm, current: 5, marks: marks, colors: StaffColors.dark), dark: false);
    // as escalas do Flesch como o app mostra (dedilhado e 8va da tabela), 3 oitavas em tercinas
    for (final c in [('u_flesch_a_menor', 57, ScaleType.melodicMinor), ('u_flesch_sol_maior', 55, ScaleType.major), ('u_flesch_si_maior', 59, ScaleType.major), ('u_flesch_fas_menor_8va', 66, ScaleType.melodicMinor), ('u_flesch_do_maior', 60, ScaleType.major)]) {
      final up = scaleMidis(c.$2, c.$3, octaves: 3).length;
      final plan = violinFingeringPlan(tonicMidi: c.$2, type: c.$3, octaves: 3, direction: ScaleDirection.both)!;
      final sc = buildStaffScore(tonicMidi: c.$2, type: c.$3, sequence: scaleSequence(c.$2, c.$3, octaves: 3), upCount: up, rhythm: StaffRhythm.triplet, fingers: plan.fingers, ottava: plan.ottava != null, ottavaRange: plan.ottava);
      await shot(c.$1, StaffView(score: sc, current: 3, maxHeight: 330, names: StaffNames.ledger));
      await shot('${c.$1}_dark', StaffView(score: sc, current: 3, maxHeight: 330, names: StaffNames.ledger), dark: true);
    }
    await shot('i_narrow_300_dark', StaffView(score: _score(60, ScaleType.melodicMinor, r: StaffRhythm.triplet), current: 0), dark: true, width: 300);
  });
}
