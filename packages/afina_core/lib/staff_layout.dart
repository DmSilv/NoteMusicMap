/// Distribuição da partitura na largura da tela: quebra em linhas (sistemas), espaça as notas,
/// calcula hastes, barras, tercinas e linhas suplementares. Tudo em "espaços de pauta" (1 espaço = a
/// distância entre duas linhas), sem Flutter, para poder ser testado. A tela só multiplica pelo tamanho do espaço em pixels.
///
/// Coordenadas: x cresce para a direita a partir da borda esquerda do sistema; y cresce PARA CIMA a partir
/// da 1ª linha da pauta (a de baixo). A pauta ocupa y de 0 a 4.
library;

import 'dart:math' as math;

import 'staff_notation.dart';

// Medidas (em espaços) tiradas da fonte Leland (leland_metadata.json) e dos padrões de gravação musical.
const double kHeadW = 1.3;
const double kWholeW = 1.5;
const double kAccW = 0.98; // ♯ (o ♭ e o ♮ são mais estreitos, mas o espaço reservado é o mesmo, sem trepidar)
const double kAccGap = 0.28;
const double kAccPre = 0.4; // ar antes do acidente (para não encostar na nota anterior)
const double kStemLen = 3.5;
const double kMinBeamStem = 2.75;
const double kBeamThick = 0.5;
const double kClefW = 2.7;

/// Espaço depois de uma nota, de acordo com a duração (quanto mais longa, mais ar).
double _gapAfter(int ticks) => switch (ticks) { 48 => 5.2, 36 => 4.6, 24 => 3.4, 12 => 2.3, 6 => 1.5, _ => 1.15 };

/// Tamanho (px) do texto do nome das notas para um espaço de pauta de [sp] px.
double staffNameFontSize(double sp) => (sp * 1.45).clamp(11.0, 16.0);

double _keyAdv(int acc) => acc > 0 ? 1.15 : 1.0;

/// Uma nota já posicionada.
class LaidEvent {
  final StaffEvent e;

  /// Borda esquerda da cabeça da nota.
  final double x;

  /// Centro da cabeça (espaços acima da 1ª linha): pos / 2.
  final double y;

  /// Início e fim do espaço da nota (para o cursor e para toques).
  final double slotX0;
  final double slotX1;

  /// Borda esquerda do acidente (se houver).
  final double? accX;
  final bool stemUp;
  final double headW;

  /// Ponta da haste (y), já ajustada pela barra quando a nota está ligada.
  double stemTipY;

  /// Posição x da haste.
  final double stemX;
  LaidEvent(this.e, this.x, this.y, this.slotX0, this.slotX1, this.accX, this.stemUp, this.headW, this.stemX, this.stemTipY);

  List<int> get ledgers => ledgerLines(e.pos);
}

/// Barra que liga um grupo de colcheias (um paralelogramo: a aresta de fora vai de (x1,y1) a (x2,y2)).
class LaidBeam {
  final double x1, y1, x2, y2;
  final bool stemUp;
  const LaidBeam(this.x1, this.y1, this.x2, this.y2, this.stemUp);
}

/// O "3" de uma tercina.
class LaidTuplet {
  final double x; // centro
  final double baselineY;
  const LaidTuplet(this.x, this.baselineY);
}

/// Uma linha da partitura.
class LaidSystem {
  final List<LaidEvent> events;
  final List<LaidBeam> beams;
  final List<LaidTuplet> tuplets;

  /// Posições x das barras de compasso (a última pode ser a barra final).
  final List<double> barlines;
  final bool finalBarline;
  final bool showTime;
  final double headerEnd;
  final double width;

  /// O quanto a linha sobe acima da 1ª linha e desce abaixo dela (espaços), com folga.
  final double top;
  final double bottom;

  /// Onde começa a faixa dos nomes das notas (y, em espaços); só vale quando os nomes estão ligados.
  final double labelTop;

  /// Primeira e última nota (índice no exercício) desta linha.
  final int firstIndex;
  final int lastIndex;
  const LaidSystem(this.events, this.beams, this.tuplets, this.barlines, this.finalBarline, this.showTime, this.headerEnd, this.width, this.top, this.bottom, this.labelTop,
      this.firstIndex, this.lastIndex);

  double get height => top - bottom;
}

class StaffLayout {
  final StaffScore score;

  /// Tamanho de um espaço de pauta em pixels.
  final double sp;

  /// Largura disponível em espaços.
  final double widthSp;
  final List<LaidSystem> systems;
  const StaffLayout(this.score, this.sp, this.widthSp, this.systems);

  /// Linha (sistema) que contém a nota [index] do exercício, ou -1.
  int systemOf(int index) {
    for (var i = 0; i < systems.length; i++) {
      if (index >= systems[i].firstIndex && index <= systems[i].lastIndex) return i;
    }
    return -1;
  }
}

double _headerWidth(KeySignature k, bool time) {
  var w = 0.4 + kClefW + 0.5;
  for (final s in k.symbols) {
    w += _keyAdv(s.accidental);
  }
  if (k.count > 0) w += 0.4;
  if (time) w += 2.2;
  return w + 0.7;
}

double _fixedW(StaffEvent e) {
  final head = e.ticks == 48 ? kWholeW : kHeadW;
  final acc = e.accidental == null ? 0.0 : kAccPre + (e.courtesy ? kAccW + 0.9 : kAccW) + kAccGap;
  final dot = e.dotted ? 0.9 : 0.0;
  return acc + head + dot;
}

/// [g] encolhe só o ar entre as notas (1 = normal).
double _barW(List<StaffEvent> bar, [double g = 1]) => 1.0 + bar.fold(0.0, (a, e) => a + _fixedW(e) + _gapAfter(e.ticks) * g) + 0.5;

/// Quanto o ar entre as notas precisa encolher para o compasso mais largo caber em [cap] espaços (>= 1 = cabe folgado).
double _fitScale(StaffScore s, double cap) {
  var m = 99.0;
  for (var i = 0; i < s.bars.length; i++) {
    final fixed = _headerWidth(s.key, i == 0) + 1.5 + s.bars[i].fold(0.0, (a, e) => a + _fixedW(e));
    final gaps = s.bars[i].fold(0.0, (a, e) => a + _gapAfter(e.ticks));
    m = math.min(m, (cap - fixed) / gaps);
  }
  return m;
}

/// Monta a distribuição. [widthPx] é a largura disponível; o tamanho do espaço (entre [spMin] e [spMax]) é o
/// maior em que o compasso mais largo ainda cabe numa linha. [names] reserva uma faixa embaixo para os nomes das notas.
StaffLayout layoutStaff(StaffScore score, {required double widthPx, double spMax = 10.5, double spMin = 6.0, bool names = false}) {
  if (score.bars.isEmpty) return StaffLayout(score, spMax, widthPx / spMax, const []);
  final k = score.key;
  // 1) maior tamanho de espaço em que todo compasso cabe numa linha; se nem no menor couber, o ar entre as notas encolhe
  //    (até 70%) e, em último caso, o espaço de pauta diminui um pouco mais.
  var sp = spMin;
  var g = 1.0;
  var found = false;
  // Preferência: dois compassos por linha (menos linhas, partitura mais baixa), se o espaço de pauta ainda fica >= 7 px.
  if (score.bars.length >= 2) {
    for (var s = spMax; s >= 7.0 - 1e-9; s -= 0.25) {
      final cap = widthPx / s;
      var ok = _fitScale(score, cap) >= 1;
      for (var i = 0; ok && i + 1 < score.bars.length; i++) {
        if ((i == 0 ? _headerWidth(k, true) : _headerWidth(k, false)) + _barW(score.bars[i]) + _barW(score.bars[i + 1]) > cap) ok = false;
      }
      if (ok) {
        sp = s;
        found = true;
        break;
      }
    }
  }
  for (var s = spMax; !found && s >= spMin - 1e-9; s -= 0.25) {
    if (_fitScale(score, widthPx / s) >= 1) {
      sp = s;
      found = true;
      break;
    }
  }
  if (!found) {
    for (var s = spMin; s >= 4.0; s -= 0.25) {
      final f = _fitScale(score, widthPx / s);
      if (f >= 0.7 || s <= 4.0 + 1e-9) {
        sp = s;
        g = f.clamp(0.3, 1.0);
        break;
      }
    }
  }
  final cap = widthPx / sp;
  // faixa dos nomes: duas linhas quando as notas estão apertadas (colcheias e tercinas), para os nomes não se atropelarem
  final rows = score.rhythm == StaffRhythm.eighth || score.rhythm == StaffRhythm.triplet ? 2 : 1;
  final labelH = rows * (staffNameFontSize(sp) / sp + 0.2) + 0.5;
  // 2) quebra em linhas
  final groups = <List<int>>[];
  var cur = <int>[];
  var used = 0.0;
  for (var i = 0; i < score.bars.length; i++) {
    final w = _barW(score.bars[i], g);
    if (cur.isNotEmpty && used + w > cap) {
      groups.add(cur);
      cur = [];
      used = 0;
    }
    if (cur.isEmpty) used = _headerWidth(k, i == 0);
    cur.add(i);
    used += w;
  }
  if (cur.isNotEmpty) groups.add(cur);
  // 3) cada linha
  final systems = <LaidSystem>[];
  for (var gi = 0; gi < groups.length; gi++) {
    final grp = groups[gi];
    final isLast = gi == groups.length - 1;
    final first = grp.first == 0;
    final header = _headerWidth(k, first);
    final evs = [for (final b in grp) ...score.bars[b]];
    final natural = header + grp.fold(0.0, (a, b) => a + _barW(score.bars[b], g));
    var add = 0.0;
    if (!(isLast && natural < cap * 0.6) && natural < cap) {
      add = math.min((cap - natural) / evs.length, 2.2);
    }
    systems.add(_layoutSystem(score, grp, header, add, g, isLast, first, names ? labelH : 0, cap));
  }
  return StaffLayout(score, sp, cap, systems);
}

LaidSystem _layoutSystem(StaffScore score, List<int> barIdx, double header, double add, double gs, bool isLast, bool showTime, double labelH, double cap) {
  final laid = <LaidEvent>[];
  final barlines = <double>[];
  final beams = <LaidBeam>[];
  final tuplets = <LaidTuplet>[];
  var x = header;
  // posição horizontal e vertical de cada nota (ainda sem a direção da haste)
  final pre = <(StaffEvent, double, double, double, double?)>[]; // (evento, x da cabeça, slotX0, slotX1, accX)
  for (var bi = 0; bi < barIdx.length; bi++) {
    x += 1.0;
    for (final e in score.bars[barIdx[bi]]) {
      final slot0 = x;
      double? accX;
      var hx = x;
      if (e.accidental != null) {
        accX = x;
        hx = x + kAccPre + (e.courtesy ? kAccW + 0.9 : kAccW) + kAccGap;
      }
      final head = e.ticks == 48 ? kWholeW : kHeadW;
      final slot1 = hx + head + (e.dotted ? 0.9 : 0.0) + _gapAfter(e.ticks) * gs + add;
      pre.add((e, hx, slot0, slot1, accX));
      x = slot1;
    }
    x += 0.5;
    barlines.add(x);
  }
  // direção das hastes: notas ligadas seguem o grupo; as soltas, a posição (do meio da pauta para cima, haste para baixo)
  final upOf = <int, bool>{}; // índice -> haste para cima?
  final byBeam = <int, List<int>>{};
  for (var i = 0; i < pre.length; i++) {
    final bg = pre[i].$1.beamGroup;
    if (bg != null) byBeam.putIfAbsent(bg * 1000 + pre[i].$1.bar, () => []).add(i);
  }
  for (final idxs in byBeam.values) {
    var maxA = -99.0, maxB = -99.0;
    for (final i in idxs) {
      final y = pre[i].$1.pos / 2;
      maxA = math.max(maxA, y - 2);
      maxB = math.max(maxB, 2 - y);
    }
    final up = maxB > maxA;
    for (final i in idxs) {
      upOf[i] = up;
    }
  }
  for (var i = 0; i < pre.length; i++) {
    upOf.putIfAbsent(i, () => pre[i].$1.pos < 4);
  }
  for (var i = 0; i < pre.length; i++) {
    final (e, hx, s0, s1, accX) = pre[i];
    final y = e.pos / 2;
    final up = upOf[i]!;
    final head = e.ticks == 48 ? kWholeW : kHeadW;
    final stemX = up ? hx + head - 0.05 : hx + 0.05;
    var tip = y;
    if (e.hasStem) {
      tip = up ? math.max(y + kStemLen, 2.0) : math.min(y - kStemLen, 2.0);
    }
    laid.add(LaidEvent(e, hx, y, s0, s1, accX, up, head, stemX, tip));
  }
  // barras e tercinas
  final groups = <int, List<LaidEvent>>{};
  for (final l in laid) {
    final bg = l.e.beamGroup;
    if (bg != null) groups.putIfAbsent(bg * 1000 + l.e.bar, () => []).add(l);
  }
  for (final g in groups.values) {
    final up = g.first.stemUp;
    final dir = up ? 1.0 : -1.0;
    final x0 = g.first.stemX, x1 = g.last.stemX;
    final i0 = g.first.y + dir * kStemLen, i1 = g.last.y + dir * kStemLen;
    final dx = x1 - x0;
    final slope = ((i1 - i0) * 0.5).clamp(-1.25, 1.25);
    final mid = (i0 + i1) / 2;
    final xm = (x0 + x1) / 2;
    double yAt(double xx, double shift) => mid + slope * (xx - xm) / (dx == 0 ? 1 : dx) + dir * shift;
    var shift = 0.0;
    for (final l in g) {
      final stem = dir * (yAt(l.stemX, 0) - l.y);
      shift = math.max(shift, kMinBeamStem - stem);
      shift = math.max(shift, dir * (2 - yAt(l.stemX, 0)));
    }
    for (final l in g) {
      l.stemTipY = yAt(l.stemX, shift);
    }
    final y1 = yAt(x0, shift), y2 = yAt(x1, shift);
    beams.add(LaidBeam(x0, y1, x1, y2, up));
    // "3" das tercinas deste grupo de barra
    if (g.every((l) => l.e.tripletGroup != null) && g.length == 3) {
      final ym = yAt(xm, shift);
      tuplets.add(LaidTuplet(xm, up ? ym + 0.45 : ym - 0.45 - 1.45));
    }
  }
  // extensão vertical
  var top = 5.6; // a clave de Sol sobe até ~5,5
  var bottom = -1.8; // e desce até ~-1,7
  for (final l in laid) {
    top = math.max(top, math.max(l.y + 0.6, l.e.hasStem ? l.stemTipY + 0.2 : 0));
    bottom = math.min(bottom, math.min(l.y - 0.6, l.e.hasStem ? l.stemTipY - 0.2 : 0));
    if (l.e.accidental != null) {
      top = math.max(top, l.y + 1.9);
      bottom = math.min(bottom, l.y - 1.4);
    }
  }
  for (final t in tuplets) {
    top = math.max(top, t.baselineY + 1.6);
    bottom = math.min(bottom, t.baselineY - 0.2);
  }
  top += 0.6;
  bottom -= 0.6;
  final labelTop = bottom;
  bottom -= labelH;
  final width = isLast && barIdx.length == 1 && (header + _barW(score.bars[barIdx.first], gs)) < cap * 0.6 ? x : (add > 0 ? cap : x);
  return LaidSystem(laid, beams, tuplets, barlines, isLast, showTime, header, width, top, bottom, labelTop, laid.first.e.index, laid.last.e.index);
}
