import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Resultado de uma nota já tocada (pinta a cabeça da nota).
enum StaffMark { inTune, flat, sharp }

/// Cores da partitura. Ela é escrita em "tinta" (preto no tema claro, branco no escuro): a cor das notas
/// tocadas só aparece na cabeça da nota, então a leitura não depende de cor e funciona nos dois temas.
class StaffColors {
  /// Fundo da partitura (cartão): branco no claro e PRETO no escuro, para a tinta branca aparecer bem.
  final Color paper;
  final Color ink;
  final Color dim;
  final Color inTune;
  final Color flat;
  final Color sharp;
  const StaffColors({required this.paper, required this.ink, required this.dim, required this.inTune, required this.flat, required this.sharp});

  factory StaffColors.fromTheme() => StaffColors(
        paper: AppColors.dark ? const Color(0xFF000000) : AppColors.surface,
        ink: AppColors.dark ? const Color(0xFFFFFFFF) : AppColors.text,
        dim: AppColors.textDim,
        inTune: AppColors.inTune,
        flat: AppColors.flat,
        sharp: AppColors.sharp,
      );

  Color of(StaffMark m) => switch (m) { StaffMark.inTune => inTune, StaffMark.flat => flat, StaffMark.sharp => sharp };
}

// Glifos SMuFL da fonte Leland (a mesma do MuseScore 4).
const String _gClef = '';
const String _flat = '';
const String _natural = '';
const String _sharp = '';
const String _doubleSharp = '';
const String _doubleFlat = '';
const String _headWhole = '';
const String _headHalf = '';
const String _headBlack = '';
const String _time4 = '';
const String _tuplet3 = '';
const String _dot = '';
const String _parenL = '';
const String _parenR = '';

String _accGlyph(int a) => switch (a) { -2 => _doubleFlat, -1 => _flat, 0 => _natural, 1 => _sharp, _ => _doubleSharp };
double _accWidth(int a) => switch (a) { -2 => 1.4, -1 => 0.81, 0 => 0.68, 1 => 0.98, _ => 1.0 };

/// Partitura (clave de Sol, 4/4) desenhada com a fonte Leland. Mostra só [maxHeight] de altura por vez:
/// se o exercício tem mais linhas do que cabem, vira a "página" sozinha quando a nota atual passa para a próxima.
/// Sem nota atual (prévia na aba Escalas), um toque no "1 / 2" passa para a página seguinte.
class StaffView extends StatefulWidget {
  final StaffScore score;

  /// Índice (no exercício) da nota a tocar agora; ganha um destaque atrás.
  final int? current;

  /// Resultado de cada nota já tocada, por índice.
  final Map<int, StaffMark> marks;
  final StaffNames names;

  /// Altura máxima em pixels; null = mostra tudo.
  final double? maxHeight;
  final String semanticLabel;
  final StaffColors? colors;

  /// Dicas automáticas: reserva a faixa de baixo para o nome de uma nota aguda e, com [hintNow], mostra o nome da nota
  /// atual se ela for aguda (acima da 2ª linha suplementar). Só ela, só quando a pessoa está demorando.
  final bool hints;
  final bool hintNow;

  const StaffView({
    super.key,
    required this.score,
    this.current,
    this.marks = const {},
    this.names = StaffNames.none,
    this.maxHeight,
    this.semanticLabel = '',
    this.colors,
    this.hints = false,
    this.hintNow = false,
  });

  @override
  State<StaffView> createState() => _StaffViewState();
}

class _StaffViewState extends State<StaffView> {
  int _manualPage = 0;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final cols = w.colors ?? StaffColors.fromTheme();
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth.isFinite ? c.maxWidth : 340.0;
      final reserve = w.names != StaffNames.none || (w.hints && w.score.events.any((e) => e.isHigh)) || w.score.events.any((e) => e.ottava);
      final layout = layoutStaff(w.score, widthPx: width, names: reserve);
      final sp = layout.sp;
      const gapSp = 1.2;
      // quantas linhas cabem por "página"
      var per = layout.systems.length;
      if (w.maxHeight != null) {
        per = 0;
        var h = 0.0;
        for (final s in layout.systems) {
          final add = s.height * sp + (per == 0 ? 0 : gapSp * sp);
          if (per > 0 && h + add > w.maxHeight!) break;
          h += add;
          per++;
        }
        if (per < 1) per = 1;
      }
      final pages = (layout.systems.length / per).ceil();
      final int page;
      if (w.current != null) {
        page = layout.systemOf(w.current!).clamp(0, layout.systems.length - 1) ~/ per;
      } else {
        page = _manualPage.clamp(0, pages - 1);
      }
      final first = page * per;
      final last = (first + per).clamp(0, layout.systems.length);
      var total = 0.0;
      for (var i = first; i < last; i++) {
        total += layout.systems[i].height * sp + (i > first ? gapSp * sp : 0);
      }
      final painter = _StaffPainter(layout, first, last, w.current, w.marks, w.names, cols, gapSp, w.hintNow);
      final label = Text('${page + 1} / $pages', style: TextStyle(fontSize: 13, color: cols.dim, fontWeight: FontWeight.w700));
      return Semantics(
        label: w.semanticLabel,
        image: true,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ExcludeSemantics(child: CustomPaint(size: Size(width, total), painter: painter)),
          if (pages > 1 && w.current != null)
            Padding(padding: const EdgeInsets.only(top: 4, right: 4), child: Align(alignment: Alignment.centerRight, child: label)),
          if (pages > 1 && w.current == null)
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                label: tr('Próxima página da partitura'),
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _manualPage = (page + 1) % pages),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48, minWidth: 72),
                    child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                      label,
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 20, color: cols.dim),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

class _StaffPainter extends CustomPainter {
  final StaffLayout layout;
  final int from;
  final int to;
  final int? current;
  final Map<int, StaffMark> marks;
  final StaffNames names;
  final StaffColors colors;
  final double gapSp;
  final bool hintNow;
  _StaffPainter(this.layout, this.from, this.to, this.current, this.marks, this.names, this.colors, this.gapSp, this.hintNow);

  double get sp => layout.sp;

  // Cache de glifos (o desenho repete as mesmas formas muitas vezes).
  static final Map<String, TextPainter> _cache = {};
  TextPainter _tp(String glyph, Color color, double fontSize, {String? family = 'Leland', FontWeight? weight}) {
    final key = '$glyph|${color.toARGB32()}|${fontSize.toStringAsFixed(2)}|$family|$weight';
    if (_cache.length > 400) _cache.clear();
    return _cache.putIfAbsent(key, () {
      final p = TextPainter(
        text: TextSpan(text: glyph, style: TextStyle(fontFamily: family, fontSize: fontSize, color: color, height: 1, fontWeight: weight)),
        textDirection: TextDirection.ltr,
      )..layout();
      return p;
    });
  }

  /// Desenha um glifo SMuFL com a origem (esquerda, linha de base) em ([x], [baselineY]) em pixels.
  void _glyph(Canvas c, String g, double x, double baselineY, Color color, {double? size}) {
    final p = _tp(g, color, size ?? sp * 4);
    final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    p.paint(c, Offset(x, baselineY - base));
  }

  /// Nome da nota para escrever embaixo: as letras no texto normal e o ♯ ♭ ♮ com os glifos da Leland (sempre disponíveis;
  /// o texto comum pode cair numa fonte de reserva que ainda não carregou e mostrar um quadradinho).
  double _nameWidth(String name, double fs, FontWeight weight) {
    final (base, accs, oct) = _splitName(name);
    var w = _tp(base, colors.ink, fs, family: null, weight: weight).width;
    if (oct.isNotEmpty) w += _tp(oct, colors.ink, fs, family: null, weight: weight).width;
    for (final a in accs) {
      w += _accAdv(a) * fs * 1.5 / 4 + 1;
    }
    return w;
  }

  (String, List<String>, String) _splitName(String name) {
    var base = name;
    var oct = '';
    while (base.isNotEmpty && RegExp(r'[0-9]').hasMatch(base[base.length - 1])) {
      oct = base[base.length - 1] + oct;
      base = base.substring(0, base.length - 1);
    }
    final accs = <String>[];
    while (base.isNotEmpty && '♯♭♮'.contains(base[base.length - 1])) {
      accs.insert(0, base[base.length - 1]);
      base = base.substring(0, base.length - 1);
    }
    return (base, accs, oct);
  }

  double _accAdv(String a) => a == '♭' ? 0.81 : (a == '♮' ? 0.68 : 0.98);

  void _drawName(Canvas c, String name, double left, double top, double fs, Color color, FontWeight weight) {
    final (base, accs, oct) = _splitName(name);
    final bp = _tp(base, color, fs, family: null, weight: weight);
    bp.paint(c, Offset(left, top));
    final baseline = top + bp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final em = fs * 1.5;
    var x = left + bp.width + 1;
    for (final a in accs) {
      // o centro do ♯ e do ♮ fica na linha de base do glifo; o do ♭ um pouco acima
      final lift = a == '♭' ? 0.554 * em / 4 : 0.0;
      _glyph(c, a == '♭' ? _flat : (a == '♮' ? _natural : _sharp), x, baseline - 0.36 * fs + lift, color, size: em);
      x += _accAdv(a) * em / 4 + 1;
    }
    if (oct.isNotEmpty) _tp(oct, color, fs, family: null, weight: weight).paint(c, Offset(x, top));
  }

  @override
  void paint(Canvas canvas, Size size) {
    var yTop = 0.0;
    for (var si = from; si < to; si++) {
      final s = layout.systems[si];
      _system(canvas, s, yTop);
      yTop += s.height * sp + gapSp * sp;
    }
  }

  void _system(Canvas canvas, LaidSystem s, double yTop) {
    final ink = colors.ink;
    final yb = yTop + s.top * sp; // y (px) da 1ª linha da pauta
    double px(double x) => x * sp;
    double py(double y) => yb - y * sp;
    final lineW = (0.12 * sp).clamp(1.0, 2.0);
    final stemW = (0.12 * sp).clamp(1.0, 2.2);
    final ledW = (0.17 * sp).clamp(1.2, 2.6);
    final linePaint = Paint()
      ..color = ink
      ..strokeWidth = lineW
      ..style = PaintingStyle.stroke;
    final endX = s.barlines.isEmpty ? s.width : s.barlines.last;
    // cursor (atrás de tudo)
    if (current != null) {
      for (final e in s.events) {
        if (e.e.index != current) continue;
        final r = RRect.fromLTRBR(px(e.slotX0 - 0.1), py(s.top - 0.5), px(e.slotX1 - 0.15), py(s.bottom + 0.5), Radius.circular(sp * 0.7));
        canvas.drawRRect(r, Paint()..color = ink.withValues(alpha: 0.10));
        canvas.drawRRect(
            r,
            Paint()
              ..color = ink.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
    }
    // pauta
    for (var i = 0; i < 5; i++) {
      final y = py(i.toDouble());
      canvas.drawLine(Offset(0, y), Offset(px(endX), y), linePaint);
    }
    // clave, armadura e compasso
    _glyph(canvas, _gClef, px(0.4), py(1), ink);
    var kx = 0.4 + kClefW + 0.5;
    final key = layout.score.key;
    for (final sym in key.symbols) {
      _glyph(canvas, _accGlyph(sym.accidental), px(kx), py(sym.pos / 2), ink);
      kx += sym.accidental > 0 ? 1.15 : 1.0;
    }
    if (key.count > 0) kx += 0.4;
    if (s.showTime) {
      _glyph(canvas, _time4, px(kx), py(3), ink);
      _glyph(canvas, _time4, px(kx), py(1), ink);
    }
    // barras de compasso
    for (var i = 0; i < s.barlines.length; i++) {
      final x = s.barlines[i];
      final isEnd = s.finalBarline && i == s.barlines.length - 1;
      if (!isEnd) {
        canvas.drawLine(Offset(px(x), py(0)), Offset(px(x), py(4)), Paint()..color = ink..strokeWidth = (0.18 * sp).clamp(1.0, 2.2));
      } else {
        canvas.drawLine(Offset(px(x - 0.55), py(0)), Offset(px(x - 0.55), py(4)), Paint()..color = ink..strokeWidth = (0.18 * sp).clamp(1.0, 2.2));
        canvas.drawLine(Offset(px(x - 0.12), py(0)), Offset(px(x - 0.12), py(4)), Paint()..color = ink..strokeWidth = (0.55 * sp).clamp(2.0, 6.0));
      }
    }
    // notas
    for (final e in s.events) {
      final mark = marks[e.e.index];
      final col = mark == null ? ink : colors.of(mark);
      final x0 = px(e.x);
      final y = py(e.y);
      // linhas suplementares
      for (final p in e.ledgers) {
        final ly = py(p / 2);
        canvas.drawLine(Offset(px(e.x - 0.33), ly), Offset(px(e.x + e.headW + 0.33), ly), Paint()..color = ink..strokeWidth = ledW);
      }
      // acidente (encostado na cabeça da nota; de precaução, entre parênteses)
      if (e.e.accidental != null) {
        final a = e.e.accidental!;
        final w = _accWidth(a);
        if (e.e.courtesy) {
          final endAcc = e.x - kAccGap;
          _glyph(canvas, _parenR, px(endAcc - 0.45), y, col);
          _glyph(canvas, _accGlyph(a), px(endAcc - 0.45 - w), y, col);
          _glyph(canvas, _parenL, px(endAcc - 0.45 - w - 0.45), y, col);
        } else {
          _glyph(canvas, _accGlyph(a), px(e.x - kAccGap - w), y, col);
        }
      }
      // haste
      if (e.e.hasStem) {
        final dir = e.stemUp ? 1.0 : -1.0;
        canvas.drawLine(Offset(px(e.stemX), py(e.y + dir * 0.16)), Offset(px(e.stemX), py(e.stemTipY)), Paint()..color = ink..strokeWidth = stemW);
      }
      _glyph(canvas, e.e.ticks == 48 ? _headWhole : (e.e.hollow ? _headHalf : _headBlack), x0, y, col);
      if (e.e.dotted) {
        final wp = e.e.writtenPos;
        final dy = wp.isEven ? (wp + 1) / 2 : wp / 2;
        _glyph(canvas, _dot, px(e.x + e.headW + 0.35), py(dy), col);
      }
    }
    // barras e tercinas
    for (final b in s.beams) {
      final dir = b.stemUp ? 1.0 : -1.0;
      final path = Path()
        ..moveTo(px(b.x1 - 0.05), py(b.y1))
        ..lineTo(px(b.x2 + 0.05), py(b.y2))
        ..lineTo(px(b.x2 + 0.05), py(b.y2 - dir * kBeamThick))
        ..lineTo(px(b.x1 - 0.05), py(b.y1 - dir * kBeamThick))
        ..close();
      canvas.drawPath(path, Paint()..color = ink);
    }
    for (final t in s.tuplets) {
      _glyph(canvas, _tuplet3, px(t.x - 0.55), py(t.baselineY), ink);
    }
    // sinal 8va
    for (final o in s.ottavas) {
      final fs = (sp * 1.7).clamp(11.0, 16.0);
      final tp = _tp('8va', ink, fs, family: null, weight: FontWeight.w700);
      final ty = py(o.y);
      tp.paint(canvas, Offset(px(o.x1), ty - tp.height * 0.85));
      final lineY = ty - tp.height * 0.35;
      final paint = Paint()
        ..color = ink
        ..strokeWidth = 1.2;
      var dx = px(o.x1) + tp.width + 3;
      final end = px(o.x2);
      while (dx < end) {
        canvas.drawLine(Offset(dx, lineY), Offset((dx + sp * 0.55).clamp(0, end), lineY), paint);
        dx += sp * 0.95;
      }
      canvas.drawLine(Offset(end, lineY), Offset(end, lineY + sp * 0.9), paint);
    }
    // número do dedo em cima da nota
    for (final e in s.events) {
      final f = e.e.finger;
      if (f == null || e.fingerY == null) continue;
      final mark = marks[e.e.index];
      final col = mark == null ? ink : colors.of(mark);
      final isDigits = RegExp(r'^[0-5]$').hasMatch(f);
      final cx = px(e.x + e.headW / 2);
      if (isDigits) {
        final g = String.fromCharCode(0xED10 + int.parse(f));
        final p = _tp(g, col, sp * 4 * 0.95);
        _glyph(canvas, g, cx - p.width / 2, py(e.fingerY!), col, size: sp * 4 * 0.95);
      } else {
        final p = _tp(f, col, (sp * 1.5).clamp(10.0, 15.0), family: null, weight: FontWeight.w700);
        p.paint(canvas, Offset(cx - p.width / 2, py(e.fingerY!) - p.height));
      }
    }
    _hint(canvas, s);
    // nomes das notas (em duas linhas alternadas quando as notas estão apertadas; o que ainda assim não cabe, não é escrito)
    if (names != StaffNames.none || s.ottavas.isNotEmpty) {
      final fs = staffNameFontSize(sp);
      final rowH = fs * 1.15;
      var edge0 = -1e9, edge1 = -1e9;
      final twoRows = layout.score.rhythm == StaffRhythm.eighth || layout.score.rhythm == StaffRhythm.triplet;
      for (final e in s.events) {
        final wp = e.e.writtenPos;
        final ledger = wp <= -2 || wp >= 10;
        // sob o 8va o nome aparece sempre (é a ajuda da região aguda); fora dela, como o ajuste pedir
        final show = e.e.ottava || names == StaffNames.all || (names == StaffNames.ledger && ledger);
        if (!show) continue;
        final isCur = e.e.index == current;
        final nm = e.e.note.name();
        final weight = isCur ? FontWeight.w800 : FontWeight.w600;
        final tw = _nameWidth(nm, fs, weight);
        final cx = px(e.x + e.headW / 2);
        final left = cx - tw / 2;
        int row;
        if (left >= edge0 + 2) {
          row = 0;
          edge0 = left + tw;
        } else if (twoRows && left >= edge1 + 2) {
          row = 1;
          edge1 = left + tw;
        } else {
          continue;
        }
        _drawName(canvas, nm, left, py(s.labelTop) + 2 + row * rowH, fs, isCur ? colors.ink : colors.dim, weight);
      }
    }
  }

  /// A dica: o nome da nota atual, numa plaquinha embaixo da pauta, só para notas agudas e só quando a pessoa demora.
  void _hint(Canvas canvas, LaidSystem s) {
    if (!hintNow || current == null) return;
    for (final e in s.events) {
      if (e.e.index != current || !e.e.isHigh) continue;
      final fs = staffNameFontSize(sp);
      final nm = e.e.note.name(withOctave: true);
      final tw = _nameWidth(nm, fs, FontWeight.w800);
      final cx = sp * (e.x + e.headW / 2);
      final top = _yOfSystem(s) + (s.top - s.labelTop) * sp + 2;
      final r = RRect.fromLTRBR(cx - tw / 2 - 6, top - 1, cx + tw / 2 + 6, top + fs * 1.15 + 3, const Radius.circular(8));
      canvas.drawRRect(r, Paint()..color = colors.paper);
      canvas.drawRRect(r, Paint()..color = colors.ink.withValues(alpha: 0.18));
      canvas.drawRRect(
          r,
          Paint()
            ..color = colors.ink.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
      _drawName(canvas, nm, cx - tw / 2, top + 1, fs, colors.ink, FontWeight.w800);
    }
  }

  double _yOfSystem(LaidSystem s) {
    var y = 0.0;
    for (var i = from; i < to; i++) {
      if (identical(layout.systems[i], s)) return y;
      y += layout.systems[i].height * sp + gapSp * sp;
    }
    return y;
  }

  @override
  bool shouldRepaint(covariant _StaffPainter old) => true;
}
