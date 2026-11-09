/// Pedal (bordão / drone): várias notas soando ao mesmo tempo para tocar uma melodia por cima
/// ou treinar o ouvido. Dart puro e testável: escolhe as notas, calcula as frequências no
/// sistema de afinação escolhido (Igual, Pitagórico, Justo), o intervalo entre elas e o
/// batimento (o "tremor" quando a afinação não é pura).
library;

import 'dart:math' as math;

import 'system_guide.dart' show kIntervalRoles;
import 'tuning.dart';

/// Quantas notas soam juntas (mais que isso distorce e pesa no navegador).
const int kMaxPedalVoices = 4;

/// Faixa do teclado (Dó2 a Dó7): graves demais não saem no alto-falante do celular.
const int kPedalLowestMidi = 36;
const int kPedalHighestMidi = 96;

/// Liga ou desliga [midi] na lista [notes] (sempre devolve uma lista nova, do grave ao agudo).
/// Se a nota é nova e já há [kMaxPedalVoices], devolve a lista igual e [PedalToggle.full].
({List<int> notes, PedalToggle result}) togglePedalNote(List<int> notes, int midi) {
  if (midi < kPedalLowestMidi || midi > kPedalHighestMidi) {
    return (notes: List.of(notes), result: PedalToggle.outOfRange);
  }
  if (notes.contains(midi)) {
    return (notes: [for (final n in notes) if (n != midi) n], result: PedalToggle.removed);
  }
  if (notes.length >= kMaxPedalVoices) return (notes: List.of(notes), result: PedalToggle.full);
  return (notes: ([...notes, midi]..sort()), result: PedalToggle.added);
}

enum PedalToggle { added, removed, full, outOfRange }

/// Atalhos de notas a partir de uma nota raiz.
enum PedalPreset {
  fifth('Quinta', [0, 7]),
  octave('Oitava', [0, 12]),
  rootFifth('Tônica + 5ª', [0, 7, 12]),
  major('Acorde maior', [0, 4, 7]),
  minor('Acorde menor', [0, 3, 7]);

  final String label;
  final List<int> steps;
  const PedalPreset(this.label, this.steps);
}

/// As notas do atalho [p] com raiz [root] (as que saem da faixa do teclado são descartadas).
List<int> pedalPreset(PedalPreset p, int root) => [
      for (final s in p.steps)
        if (root + s >= kPedalLowestMidi && root + s <= kPedalHighestMidi) root + s
    ];

/// Frequências (Hz) das [midis] no sistema [cfg]. A transposição do instrumento NÃO entra:
/// o teclado do pedal é sempre o som real.
List<double> pedalFrequencies(List<int> midis, TuningConfig cfg) {
  final c = cfg.copyWith(transpose: 0);
  return [for (final m in midis) targetFreq(m, c)];
}

/// Volume de cada nota quando [n] soam juntas: cai com o número de notas para a soma não estourar.
double pedalVoiceGain(int n) => n <= 1 ? 1.0 : 1.0 / math.pow(n, 0.7);

/// Razão pura de cada classe de intervalo (0..11 semitons), como (numerador, denominador).
const List<(int, int)> _pure = [
  (1, 1),
  (16, 15),
  (9, 8),
  (6, 5),
  (5, 4),
  (4, 3),
  (45, 32),
  (3, 2),
  (8, 5),
  (5, 3),
  (9, 5),
  (15, 8),
];

/// Descrição do intervalo entre duas notas.
class PedalInterval {
  final int semitones; // distância (>= 0)
  final String name; // "5ª justa", "oitava"…
  final String ratio; // razão pura: "3:2", "2:1"
  final double cents; // o que realmente soa (cents)
  final double beatHz; // batimento entre os harmônicos, em Hz (0 = sem tremor)

  /// Razão simples (quinta, terça, oitava…): só nela o batimento é audível e vale mostrar.
  final bool simple;

  const PedalInterval(this.semitones, this.name, this.ratio, this.cents, this.beatHz, this.simple);

  /// Soa "pura" (sem tremor perceptível).
  bool get isSmooth => beatHz < 0.3;
}

/// O intervalo entre as notas [lowMidi] e [highMidi] tocadas nas frequências [lowHz] e [highHz].
/// O batimento é o tremor entre o harmônico [q] da nota aguda e o [p] da grave (p:q = razão pura):
/// quanto mais perto da razão pura, mais perto de zero.
PedalInterval pedalInterval(int lowMidi, int highMidi, double lowHz, double highHz) {
  final semis = (highMidi - lowMidi).abs();
  final lo = lowHz <= highHz ? lowHz : highHz;
  final hi = lowHz <= highHz ? highHz : lowHz;
  final octaves = semis ~/ 12;
  final cls = semis % 12;
  final (p, q) = _pure[cls];
  // razão pura levando em conta as oitavas: (p / q) * 2^octaves
  final num = p * math.pow(2, octaves).toInt();
  final beat = (q * hi - num * lo).abs();
  final String name;
  final String ratio;
  if (semis == 0) {
    name = 'uníssono';
    ratio = '1:1';
  } else if (cls == 0) {
    name = octaves == 1 ? 'oitava' : '$octaves oitavas';
    ratio = '${math.pow(2, octaves).toInt()}:1';
  } else {
    name = octaves == 0 ? kIntervalRoles[cls] : '${kIntervalRoles[cls]} + ${octaves == 1 ? 'oitava' : '$octaves oitavas'}';
    ratio = '$num:$q';
  }
  return PedalInterval(semis, name, ratio, centsBetween(hi, lo).abs(), beat, p * q <= 40);
}
