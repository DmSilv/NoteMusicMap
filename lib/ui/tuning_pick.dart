import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'widgets.dart';

/// Nome curto do sistema de afinação em uso ("Pitagórico").
String tuningSystemName(TuningSystem s) => switch (s) {
      TuningSystem.equal => 'Igual',
      TuningSystem.pythagorean => 'Pitagórico',
      TuningSystem.just => 'Justo',
    };

/// "Pitagórico · Lá 440 Hz": o que está valendo agora, em uma linha.
String tuningSummary(AppState app) {
  final hz = app.refA == app.refA.roundToDouble() ? app.refA.toStringAsFixed(0) : app.refA.toStringAsFixed(1);
  return '${tuningSystemName(app.system)} · Lá $hz Hz';
}

/// Explicação honesta do que o sistema atual significa para o instrumento.
String tuningExplain(AppState app) {
  switch (app.system) {
    case TuningSystem.equal:
      return app.instrument.fretted
          ? 'Temperamento igual: as 12 notas à mesma distância (como no piano e nos instrumentos de trastes).'
          : 'Temperamento igual nas notas da escala; as cordas soltas ficam em quintas puras, como no afinador de cordas.';
    case TuningSystem.pythagorean:
      return 'Pitagórico: quintas puras, terças e sensível mais altas. É o mais natural para melodias e escalas em instrumentos de arco.';
    case TuningSystem.just:
      return 'Justo: terças e quintas puras, sem tremor nos acordes. A terça fica mais baixa que no piano.';
  }
}

/// Abre a escolha do sistema de afinação (a mesma de Configurações, aqui à mão).
/// [tonicPc]: nos sistemas pitagórico e justo as notas são medidas a partir da tônica.
Future<void> pickTuningSystem(BuildContext context, AppState app, {int? tonicPc}) {
  return showOptionSheet<TuningSystem>(
    context,
    title: 'Sistema de afinação',
    hint: 'Define como cada nota da escala é medida. O Lá de referência muda em Configurações › Afinação.',
    showIcons: false,
    options: const [
      OptionItem<TuningSystem>(TuningSystem.equal, 'Igual (piano, violão, trastes)'),
      OptionItem<TuningSystem>(TuningSystem.pythagorean, 'Pitagórico (arco, melodia)'),
      OptionItem<TuningSystem>(TuningSystem.just, 'Justo (acordes, conjunto)'),
    ],
    selected: app.system,
    onPick: (s) => app.setTuning(system: s, tonicPc: s == TuningSystem.equal ? null : tonicPc),
  );
}
