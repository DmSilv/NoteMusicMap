/// Matemática de afinação do app.
///
/// Tudo aqui é teoria musical pública (razões de intervalos de 3 e 5 limites,
/// cents, temperamento igual). Nenhum código de terceiros.
///
/// DECISÕES DE PRECISÃO (leia antes de mudar):
///  1. A referência global é o Lá4 (`refA`, padrão 440 Hz). Em TODOS os sistemas
///     o Lá4 sempre vale exatamente `refA` quando `anchor == Anchor.a4`.
///  2. Nos sistemas pitagórico e justo, os alvos são calculados em relação a uma
///     tônica escolhida. Com `Anchor.a4` (padrão) a tônica é ajustada para que o
///     Lá continue em `refA`; com `Anchor.tonic` a tônica fica no temperamento
///     igual e o Lá pode sair do lugar (ex.: em Sol maior justo, Lá = +3,9¢).
///  3. O desvio mostrado ao usuário é sempre contra o ALVO do sistema escolhido,
///     nunca contra o temperamento igual (a menos que ele escolha "igual").
library;

import 'dart:math' as math;
import 'i18n.dart';

enum TuningSystem { equal, pythagorean, just }

enum Anchor { a4, tonic }

final List<String> noteNamesSharp = [
  tr('Dó'), tr('Dó♯'), tr('Ré'), tr('Ré♯'), tr('Mi'), tr('Fá'), tr('Fá♯'), tr('Sol'), tr('Sol♯'), tr('Lá'), tr('Lá♯'), tr('Si')
];
final List<String> noteNamesFlat = [
  tr('Dó'), tr('Ré♭'), tr('Ré'), tr('Mi♭'), tr('Mi'), tr('Fá'), tr('Sol♭'), tr('Sol'), tr('Lá♭'), tr('Lá'), tr('Si♭'), tr('Si')
];

/// Grafia automática das teclas pretas quando não há tonalidade definida: alterna
/// sustenidos e bemóis como se escreve na prática (Dó♯, Mi♭, Fá♯, Lá♭, Si♭), em vez
/// de usar sempre sustenidos.
final List<String> noteNamesAuto = [
  tr('Dó'), tr('Dó♯'), tr('Ré'), tr('Mi♭'), tr('Mi'), tr('Fá'), tr('Fá♯'), tr('Sol'), tr('Lá♭'), tr('Lá'), tr('Si♭'), tr('Si')
];

/// Nomes para [flats]: null = automático; true = só bemóis; false = só sustenidos.
List<String> namesFor(bool? flats) =>
    flats == null ? noteNamesAuto : (flats ? noteNamesFlat : noteNamesSharp);

/// Se a tonalidade com tônica [tonicPc] (0 = Dó) usa bemóis na armadura. Para
/// tonalidades menores vale a relativa maior (Sol menor -> Si♭ maior: bemóis).
bool keyUsesFlats(int tonicPc, {bool minor = false}) {
  final t = ((tonicPc % 12) + 12) % 12;
  if (minor) {
    if (t == 3) return true; // Mi♭ menor (6 bemóis)
    return keyUsesFlats((t + 3) % 12);
  }
  return const {1, 3, 5, 8, 10}.contains(t); // Ré♭, Mi♭, Fá, Lá♭, Si♭ maiores
}

/// Razões acima da tônica, índice = semitons (0..11).
final List<double> pythagoreanRatios = [
  1, 256 / 243, 9 / 8, 32 / 27, 81 / 64, 4 / 3,
  729 / 512, 3 / 2, 128 / 81, 27 / 16, 16 / 9, 243 / 128,
];

/// Entonação justa de 5 limites (escala cromática de Ptolomeu/Ellis).
final List<double> justRatios = [
  1, 16 / 15, 9 / 8, 6 / 5, 5 / 4, 4 / 3,
  45 / 32, 3 / 2, 8 / 5, 5 / 3, 9 / 5, 15 / 8,
];

final double _ln2 = math.ln2;

double _log2(double x) => math.log(x) / _ln2;

/// Frequência em temperamento igual para um número MIDI (A4 = 69).
double etFreq(num midi, double refA) =>
    refA * math.pow(2, (midi - 69) / 12).toDouble();

/// Número MIDI fracionário de uma frequência.
double freqToMidi(double freq, double refA) =>
    69 + 12 * _log2(freq / refA);

/// Distância em cents de [freq] até [target] (positivo = mais agudo).
double centsBetween(double freq, double target) =>
    1200 * _log2(freq / target);

int _mod12(int n) => ((n % 12) + 12) % 12;

class TuningConfig {
  final double refA;
  final TuningSystem system;

  /// Classe de altura da tônica, 0 = Dó ... 11 = Si.
  final int tonicPc;
  final Anchor anchor;
  final bool preferFlats;

  /// true = a grafia das teclas pretas é automática (alterna ♯ e ♭, ou segue a
  /// tonalidade em [keyFlats]); false = usa só [preferFlats].
  final bool autoSpelling;

  /// Com grafia automática e uma tonalidade ativa (escala, exercício): true se ela
  /// usa bemóis, false se usa sustenidos; null = sem tonalidade.
  final bool? keyFlats;

  /// Alvos que valem no lugar do sistema para notas específicas (MIDI -> Hz).
  /// Usado para as cordas soltas de instrumentos de arco: o afinador de cordas
  /// afina em quintas puras, então a grade e o cromático medem essas notas pelo
  /// mesmo alvo (senão o Sol afinado aparecia como "baixo").
  final Map<int, double>? targetOverrides;

  /// Semitons somados na leitura escrita (instrumentos transpositores).
  /// Clarinete em Si♭ = +2, sax alto em Mi♭ = +9. Só afeta os NOMES.
  final int transpose;

  const TuningConfig({
    this.refA = 440.0,
    this.system = TuningSystem.equal,
    this.tonicPc = 9,
    this.anchor = Anchor.a4,
    this.preferFlats = false,
    this.transpose = 0,
    this.autoSpelling = false,
    this.keyFlats,
    this.targetOverrides,
  });

  TuningConfig copyWith({
    double? refA,
    TuningSystem? system,
    int? tonicPc,
    Anchor? anchor,
    bool? preferFlats,
    int? transpose,
    bool? autoSpelling,
    Object? keyFlats = _keep,
    Map<int, double>? targetOverrides,
  }) =>
      TuningConfig(
        refA: refA ?? this.refA,
        system: system ?? this.system,
        tonicPc: tonicPc ?? this.tonicPc,
        anchor: anchor ?? this.anchor,
        preferFlats: preferFlats ?? this.preferFlats,
        transpose: transpose ?? this.transpose,
        autoSpelling: autoSpelling ?? this.autoSpelling,
        keyFlats: identical(keyFlats, _keep) ? this.keyFlats : keyFlats as bool?,
        targetOverrides: targetOverrides ?? this.targetOverrides,
      );
}

const Object _keep = Object();

/// Frequência alvo da nota MIDI [midi] (rótulo em temperamento igual) segundo
/// o sistema configurado.
double targetFreq(int midi, TuningConfig c) {
  final o = c.targetOverrides?[midi];
  if (o != null) return o;
  if (c.system == TuningSystem.equal) return etFreq(midi, c.refA);
  final ratios =
      c.system == TuningSystem.pythagorean ? pythagoreanRatios : justRatios;
  final d = _mod12(midi - c.tonicPc);
  final tonicMidi = midi - d;
  double tonicFreq;
  if (c.anchor == Anchor.tonic) {
    tonicFreq = etFreq(tonicMidi, c.refA);
  } else {
    // Ajusta a tônica para o Lá4 valer exatamente refA.
    final dA = _mod12(69 - c.tonicPc);
    final tonicMidiForA = 69 - dA;
    final tonicRef = c.refA / ratios[dA];
    tonicFreq = tonicRef *
        math.pow(2, (tonicMidi - tonicMidiForA) / 12).toDouble();
  }
  return tonicFreq * ratios[d];
}

/// Desvio do alvo do sistema em relação ao temperamento igual, em cents.
double offsetFromEqual(int midi, TuningConfig c) =>
    centsBetween(targetFreq(midi, c), etFreq(midi, c.refA));

String noteName(int midi, TuningConfig c, {bool withOctave = false}) {
  final m = midi + c.transpose;
  final List<String> names;
  if (c.autoSpelling) {
    final kf = c.keyFlats;
    names = kf == null ? noteNamesAuto : (kf ? noteNamesFlat : noteNamesSharp);
  } else {
    names = c.preferFlats ? noteNamesFlat : noteNamesSharp;
  }
  final n = names[_mod12(m)];
  return withOctave ? '$n${(m ~/ 12) - 1}' : n;
}

/// Resultado da identificação da nota mais próxima.
class NoteMatch {
  final int midi;
  final double target;
  final double cents;
  const NoteMatch(this.midi, this.target, this.cents);
}

/// Acha a nota cujo ALVO (no sistema escolhido) está mais perto de [freq].
NoteMatch nearestTarget(double freq, TuningConfig c) {
  final base = freqToMidi(freq, c.refA).round();
  NoteMatch? best;
  for (var m = base - 1; m <= base + 1; m++) {
    final t = targetFreq(m, c);
    final cents = centsBetween(freq, t);
    if (best == null || cents.abs() < best.cents.abs()) {
      best = NoteMatch(m, t, cents);
    }
  }
  return best!;
}

// ---------------------------------------------------------------------------
// Instrumentos
// ---------------------------------------------------------------------------

class StringDef {
  final int midi;
  const StringDef(this.midi);
}

class Instrument {
  final String id;
  final String name;

  /// Da corda mais grave para a mais aguda.
  final List<StringDef> strings;

  /// Instrumentos com trastes têm as alturas fixadas: usam temperamento igual.
  final bool fretted;

  const Instrument(this.id, this.name, this.strings, {required this.fretted});

  /// Alvos das cordas soltas (MIDI -> Hz) para instrumentos sem trastes; vazio
  /// nos com trastes (esses usam temperamento igual mesmo).
  Map<int, double> openTargets(double refA) => fretted
      ? const {}
      : {for (var i = 0; i < strings.length; i++) strings[i].midi: stringFreq(i, refA)};

  /// Afinação das cordas soltas.
  /// Sem trastes: quintas/quartas puras ancoradas no Lá (pitagórica, tônica Lá).
  /// Com trastes: temperamento igual.
  double stringFreq(int stringIndex, double refA) {
    final m = strings[stringIndex].midi;
    if (fretted) return etFreq(m, refA);
    return targetFreq(
      m,
      TuningConfig(
        refA: refA,
        system: TuningSystem.pythagorean,
        tonicPc: 9,
        anchor: Anchor.a4,
      ),
    );
  }
}

final List<Instrument> instruments = [
  Instrument('violino', tr('Violino'),
      [StringDef(55), StringDef(62), StringDef(69), StringDef(76)],
      fretted: false),
  Instrument('viola', tr('Viola de arco'),
      [StringDef(48), StringDef(55), StringDef(62), StringDef(69)],
      fretted: false),
  Instrument('violoncelo', tr('Violoncelo'),
      [StringDef(36), StringDef(43), StringDef(50), StringDef(57)],
      fretted: false),
  Instrument('contrabaixo', tr('Contrabaixo acústico'),
      [StringDef(28), StringDef(33), StringDef(38), StringDef(43)],
      fretted: false),
  Instrument(
      'violao',
      tr('Violão / Guitarra'),
      [
        StringDef(40), StringDef(45), StringDef(50),
        StringDef(55), StringDef(59), StringDef(64),
      ],
      fretted: true),
  Instrument(tr('baixo'), tr('Baixo elétrico (4 cordas)'),
      [StringDef(28), StringDef(33), StringDef(38), StringDef(43)],
      fretted: true),
  Instrument('cavaquinho', tr('Cavaquinho'),
      [StringDef(62), StringDef(67), StringDef(71), StringDef(74)],
      fretted: true),
  Instrument('ukulele', tr('Ukulele'),
      [StringDef(67), StringDef(60), StringDef(64), StringDef(69)],
      fretted: true),
  Instrument('bandolim', tr('Bandolim'),
      [StringDef(55), StringDef(62), StringDef(69), StringDef(76)],
      fretted: true),
];

Instrument instrumentById(String id) =>
    instruments.firstWhere((i) => i.id == id);

/// Corda solta mais próxima de [freq] (em cents) para um instrumento.
({int index, double target, double cents}) nearestString(
    double freq, Instrument inst, double refA) {
  var bestI = 0;
  var bestT = inst.stringFreq(0, refA);
  var bestC = centsBetween(freq, bestT);
  for (var i = 1; i < inst.strings.length; i++) {
    final t = inst.stringFreq(i, refA);
    final c = centsBetween(freq, t);
    if (c.abs() < bestC.abs()) {
      bestI = i;
      bestT = t;
      bestC = c;
    }
  }
  return (index: bestI, target: bestT, cents: bestC);
}
