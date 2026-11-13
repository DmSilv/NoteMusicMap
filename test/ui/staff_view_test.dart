import 'dart:io';
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
    await shot('i_narrow_300_dark', StaffView(score: _score(60, ScaleType.melodicMinor, r: StaffRhythm.triplet), current: 0), dark: true, width: 300);
  });
}
