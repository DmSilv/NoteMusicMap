import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'widgets.dart';

/// Nome curto do sistema de afinação em uso ("Pitagórico").
String tuningSystemName(TuningSystem s) => switch (s) {
      TuningSystem.equal => tr('Igual'),
      TuningSystem.pythagorean => tr('Pitagórico'),
      TuningSystem.just => tr('Justo'),
    };

/// "Pitagórico · Lá 440 Hz": o que está valendo agora, em uma linha.
String tuningSummary(AppState app) {
  final hz = app.refA == app.refA.roundToDouble() ? app.refA.toStringAsFixed(0) : app.refA.toStringAsFixed(1);
  return tr('{0} · Lá {1} Hz', [tuningSystemName(app.system), hz]);
}

/// Explicação honesta do que o sistema atual significa para o instrumento.
String tuningExplain(AppState app) {
  switch (app.system) {
    case TuningSystem.equal:
      return app.instrument.fretted
          ? tr('Temperamento igual: as 12 notas à mesma distância (como no piano e nos instrumentos de trastes).')
          : tr('Temperamento igual nas notas da escala; as cordas soltas ficam em quintas puras, como no afinador de cordas.');
    case TuningSystem.pythagorean:
      return tr('Pitagórico: quintas puras, terças e sensível mais altas. É o mais natural para melodias e escalas em instrumentos de arco.');
    case TuningSystem.just:
      return tr('Justo: terças e quintas puras, sem tremor nos acordes. A terça fica mais baixa que no piano.');
  }
}

/// Abre a escolha do sistema de afinação (a mesma de Configurações, aqui à mão).
/// [tonicPc]: nos sistemas pitagórico e justo as notas são medidas a partir da tônica.
Future<void> pickTuningSystem(BuildContext context, AppState app, {int? tonicPc}) {
  return showOptionSheet<TuningSystem>(
    context,
    title: tr('Sistema de afinação'),
    hint: tr('Define como cada nota da escala é medida. O Lá de referência muda em Configurações › Afinação.'),
    showIcons: false,
    options: [
      OptionItem<TuningSystem>(TuningSystem.equal, tr('Igual (piano, violão, trastes)')),
      OptionItem<TuningSystem>(TuningSystem.pythagorean, tr('Pitagórico (arco, melodia)')),
      OptionItem<TuningSystem>(TuningSystem.just, tr('Justo (acordes, conjunto)')),
    ],
    selected: app.system,
    onPick: (s) => app.setTuning(system: s, tonicPc: s == TuningSystem.equal ? null : tonicPc),
  );
}
