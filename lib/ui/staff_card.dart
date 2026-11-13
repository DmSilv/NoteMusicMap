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
  });

  @override
  State<StaffCard> createState() => _StaffCardState();
}

class _StaffCardState extends State<StaffCard> {
  StaffScore? _score;
  String _scoreKey = '';

  StaffScore _build() {
    final w = widget;
    final k = '${w.tonicMidi}|${w.type.name}|${w.sequence.length}|${w.sequence.isEmpty ? 0 : w.sequence.first}|${w.upCount}|${w.rhythm.index}|${w.ottava}';
    if (_score == null || k != _scoreKey) {
      _score = buildStaffScore(tonicMidi: w.tonicMidi, type: w.type, sequence: w.sequence, upCount: w.upCount, rhythm: w.rhythm, ottava: w.ottava);
      _scoreKey = k;
    }
    return _score!;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final cols = StaffColors.fromTheme();
    return Container(
      width: double.infinity,
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
        maxHeight: w.maxHeight,
        semanticLabel: w.semanticLabel,
        colors: cols,
        hints: w.hints,
        hintNow: w.hintNow,
      ),
    );
  }
}
