import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'design_system.dart';
import 'staff_view.dart';
import 'theme.dart';

/// Resultado de uma nota tocada (cents de desvio) -> cor da cabeça da nota; null = ainda não tocada ou pulada.
StaffMark? staffMarkOf(double? cents, double zone) {
  if (cents == null) return null;
  if (cents.abs() <= zone) return StaffMark.inTune;
  return cents < 0 ? StaffMark.flat : StaffMark.sharp;
}

/// Cartão com a partitura de um exercício (escala ou arpejo). Guarda a partitura montada para não refazer
/// a conta a cada quadro do microfone.
class StaffCard extends StatefulWidget {
  final int tonicMidi;
  final ScaleType type;
  final List<int> sequence;
  final int upCount;
  final StaffRhythm rhythm;
  final StaffNames names;
  final int? current;
  final Map<int, StaffMark> marks;
  final double? maxHeight;
  final String semanticLabel;
  final bool hints;
  final bool hintNow;
  final bool ottava;
  final (int, int)? ottavaRange;
  final List<String?>? fingers;
  final bool alt;

  /// Cor da partitura (igual ao app, sempre clara ou sempre escura).
  final StaffPaper paper;

  /// Enche a altura que o pai der (e pagina por ela), em vez de ter a altura do que está escrito.
  final bool expand;

  const StaffCard({
    super.key,
    required this.tonicMidi,
    required this.type,
    required this.sequence,
    required this.upCount,
    this.rhythm = StaffRhythm.quarter,
    this.names = StaffNames.ledger,
    this.current,
    this.marks = const {},
    this.maxHeight,
    this.semanticLabel = '',
    this.hints = false,
    this.hintNow = false,
    this.ottava = false,
    this.ottavaRange,
    this.fingers,
    this.alt = false,
    this.paper = StaffPaper.auto,
    this.expand = false,
  });

  @override
  State<StaffCard> createState() => _StaffCardState();
}

class _StaffCardState extends State<StaffCard> {
  StaffScore? _score;
  String _scoreKey = '';

  StaffScore _build() {
    final w = widget;
    final k = '${w.tonicMidi}|${w.type.name}|${w.sequence.length}|${w.sequence.isEmpty ? 0 : w.sequence.first}|${w.upCount}|${w.rhythm.index}|${w.ottava}|${w.ottavaRange}|${w.fingers?.join(',')}|${w.alt}';
    if (_score == null || k != _scoreKey) {
      _score = buildStaffScore(tonicMidi: w.tonicMidi, type: w.type, sequence: w.sequence, upCount: w.upCount, rhythm: w.rhythm, ottava: w.ottava, ottavaRange: w.ottavaRange, fingers: w.fingers, alt: w.alt);
      _scoreKey = k;
    }
    return _score!;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final cols = StaffColors.fromTheme(w.paper);
    Widget card(double? maxH, {double? height}) => Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: cols.paper,
        borderRadius: BorderRadius.circular(Ds.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      child: StaffView(
        score: _build(),
        current: w.current,
        marks: w.marks,
        names: w.names,
        maxHeight: maxH,
        fill: height != null,
        semanticLabel: w.semanticLabel,
        colors: cols,
        hints: w.hints,
        hintNow: w.hintNow,
      ),
    );
    if (!w.expand) return card(w.maxHeight);
    return LayoutBuilder(builder: (context, c) {
      if (!c.maxHeight.isFinite) return card(w.maxHeight);
      // o cartão ocupa toda a altura disponível; sobra para as linhas o que não é margem nem a linha de baixo (botão sol/lua e página)
      final inner = (c.maxHeight - 10 - 8 - 54).clamp(120.0, 2000.0);
      return card(inner, height: c.maxHeight);
    });
  }
}
