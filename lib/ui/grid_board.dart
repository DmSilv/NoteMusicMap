import 'package:flutter/material.dart';

import '../app_state.dart';
import 'grid_cell.dart';

/// A grade principal, no estilo do Tonemap: 12 colunas (Dó a Si) e uma linha por
/// oitava, com os agudos em cima. Cada quadrado mostra o nome da nota, a cor da
/// última vez que foi tocada, quantas vezes (×3) e, na nota que soa agora, uma borda.
/// Serve tanto na aba Grade quanto na tela cheia.
class GridBoard extends StatelessWidget {
  final AppState app;
  const GridBoard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = app.gridOctaves;
    final scale = app.scaleMode ? app.scaleNotes.toSet() : <int>{};
    final octs = [for (var o = lo; o <= hi; o++) o]; // grave → agudo
    Widget cell(int midi) => Expanded(child: GridCell(app: app, midi: midi, scale: scale));
    return Column(children: [
      for (final o in octs.reversed)
        Expanded(child: Row(children: [for (var p = 0; p < 12; p++) cell(o * 12 + p)])),
    ]);
  }
}
