/// Dados para explicar o "Sistema de afinação" na tela: para a tônica escolhida, qual é
/// o ALVO de cada nota no sistema (igual, pitagórico ou justo) e quanto ele difere do
/// temperamento igual, em Hz. Dart puro e testável.
library;

import 'tuning.dart';
import 'i18n.dart';

/// Papel de cada nota em relação à tônica (0..11 semitons acima).
final List<String> kIntervalRoles = [
  tr('Tônica'),
  tr('2ª menor'),
  tr('2ª maior'),
  tr('3ª menor'),
  tr('3ª maior'),
  tr('4ª justa'),
  tr('Trítono'),
  tr('5ª justa'),
  tr('6ª menor'),
  tr('6ª maior'),
  tr('7ª menor'),
  tr('7ª maior'),
];

/// Os graus da escala maior (semitons acima da tônica): os que mais importam ao estudar.
const List<int> kMajorScaleSteps = [0, 2, 4, 5, 7, 9, 11];

/// Uma linha da tabela "alvo de cada nota".
class SystemRow {
  /// Semitons acima da tônica (0..11).
  final int step;
  final int midi;
  final String name; // "Mi" (com ♯/♭ conforme a grafia)
  final String role; // "3ª maior"

  /// Frequência alvo no sistema escolhido e no igual (Hz).
  final double target;
  final double equal;

  const SystemRow(this.step, this.midi, this.name, this.role, this.target, this.equal);

  /// Alvo menos o igual (Hz): negativo = o alvo é MAIS BAIXO que no igual.
  double get diffHz => target - equal;

  /// Diferença em cents (para quem quiser a medida musical; a tela mostra Hz).
  double get diffCents => centsBetween(target, equal);

  /// A diferença é grande o bastante para ser notada na tela (≥ 0,05 Hz).
  bool get differs => diffHz.abs() >= 0.05;
}

/// As 12 notas a partir da tônica, na oitava 4 (tônica entre Dó4 e Si4).
List<SystemRow> systemRows(TuningConfig cfg) {
  final tonicMidi = 60 + (cfg.tonicPc % 12 + 12) % 12;
  return [
    for (var d = 0; d < 12; d++)
      SystemRow(
        d,
        tonicMidi + d,
        noteName(tonicMidi + d, cfg.copyWith(transpose: 0)),
        kIntervalRoles[d],
        targetFreq(tonicMidi + d, cfg),
        etFreq(tonicMidi + d, cfg.refA),
      ),
  ];
}

/// Quanto o Lá4 se afasta da referência por causa do sistema (Hz); com "Lá fixo" é 0.
double a4ShiftHz(TuningConfig cfg) => targetFreq(69, cfg) - cfg.refA;

/// Intervalo puro (razão entre frequências) de cada passo no Justo, só para explicar.
const Map<int, String> kJustRatioText = {
  0: '1:1',
  2: '9:8',
  4: '5:4',
  5: '4:3',
  7: '3:2',
  9: '5:3',
  11: '15:8',
};
