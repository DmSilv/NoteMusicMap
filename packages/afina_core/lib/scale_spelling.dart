/// Grafia das notas de uma escala ou arpejo: cada grau ganha a sua LETRA (Dó, Ré, Mi... em sequência), como
/// está escrito na partitura. É o que faz a Dó menor melódica subir com Lá e Si naturais e descer com Si♭ e
/// Lá♭, e a Ré menor (armadura com Si♭) subir com Si natural e Dó♯ (como no "sistema de escalas" de Flesch).
///
/// Dart puro e testável. O nome sai no idioma de hoje (Dó ou C) pelo `tr()`.
library;

import 'i18n.dart';
import 'pitch_grid.dart';

const List<int> _natPc = [0, 2, 4, 5, 7, 9, 11]; // classe de altura de Dó, Ré, Mi, Fá, Sol, Lá, Si

/// Letra (0 = Dó ... 6 = Si) e acidente (-1 = ♭, 1 = ♯) de uma tônica, para tonalidade maior e menor.
const List<(int, int)> _majorTonic = [(0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (3, 1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)];
const List<(int, int)> _minorTonic = [(0, 0), (0, 1), (1, 0), (2, -1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (6, -1), (6, 0)];

/// Distância em letras do grau até a tônica, para cada distância em semitons (0..11).
const Map<int, int> _major = {0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6};
const Map<int, int> _naturalMinor = {0: 0, 2: 1, 3: 2, 5: 3, 7: 4, 8: 5, 10: 6};
const Map<int, int> _harmonicMinor = {0: 0, 2: 1, 3: 2, 5: 3, 7: 4, 8: 5, 11: 6};
const Map<int, int> _melodicUp = {0: 0, 2: 1, 3: 2, 5: 3, 7: 4, 9: 5, 11: 6};
const Map<int, int> _pentatonic = {0: 0, 2: 1, 4: 2, 7: 4, 9: 5};
const Map<int, int> _majorTriad = {0: 0, 4: 2, 7: 4};
const Map<int, int> _minorTriad = {0: 0, 3: 2, 7: 4};
const Map<int, int> _dominant7 = {0: 0, 4: 2, 7: 4, 10: 6};
const Map<int, int> _diminished7 = {0: 0, 3: 2, 6: 4, 9: 5}; // a 7ª diminuta escreve-se como 6ª maior (Dó Mi♭ Sol♭ Lá)

/// A tônica que se escreve com esta letra (0 = Dó ... 6 = Si) e este acidente (-1 ♭, 0, 1 ♯) para o tipo [type], ou null se essa
/// tonalidade não existe (Mi♯ maior, Fá♭ maior...). Devolve a classe de altura (0..11) e se é a "outra grafia" (Sol♭ em vez de Fá♯).
({int pc, bool alt})? tonicForSpelling(int letter, int acc, ScaleType type) {
  final pc = (((_natPc[letter] + acc) % 12) + 12) % 12;
  final midi = 60 + pc;
  if (ScaleSpeller(midi, type).tonicSpelling == (letter, acc)) return (pc: pc, alt: false);
  if (type != ScaleType.chromatic && !type.arpeggio && ScaleSpeller.hasAlt(midi, minor: type.isMinor) && ScaleSpeller(midi, type, alt: true).tonicSpelling == (letter, acc)) {
    return (pc: pc, alt: true);
  }
  return null;
}

/// Uma nota escrita: letra, acidente e oitava (convenção científica: Dó4 = dó central).
class SpelledNote {
  final int letter;
  final int accidental;
  final int octave;
  const SpelledNote(this.letter, this.accidental, this.octave);

  String get _letterName => [tr('Dó'), tr('Ré'), tr('Mi'), tr('Fá'), tr('Sol'), tr('Lá'), tr('Si')][letter];
  String get _accName => switch (accidental) { -2 => '♭♭', -1 => '♭', 1 => '♯', 2 => '♯♯', _ => '' };

  /// "Si♭", ou "Si♭3" com a oitava.
  String name({bool withOctave = false}) => '$_letterName$_accName${withOctave ? octave : ''}';
}

/// Outra grafia da mesma tônica quando as duas tonalidades existem (até 7 acidentes): Fá♯ ↔ Sol♭ (6), Dó♯ ↔ Ré♭... A chave é a classe de altura.
const Map<int, (int, int)> _majorAlt = {1: (0, 1), 6: (4, -1), 11: (0, -1)}; // Dó♯, Sol♭, Dó♭ maiores
const Map<int, (int, int)> _minorAlt = {3: (1, 1), 8: (5, -1), 10: (5, 1)}; // Ré♯, Lá♭, Lá♯ menores

class ScaleSpeller {
  final int tonicMidi;
  final ScaleType type;

  /// Usa a outra grafia da tônica (Sol♭ em vez de Fá♯), quando existe; sem efeito nas demais.
  final bool alt;
  late final int _tonicLetter;

  ScaleSpeller(this.tonicMidi, this.type, {this.alt = false}) {
    _tonicLetter = tonicSpelling.$1;
  }

  /// Esta tônica tem outra grafia (Fá♯ ↔ Sol♭)?
  static bool hasAlt(int tonicMidi, {required bool minor}) => (minor ? _minorAlt : _majorAlt).containsKey(tonicMidi % 12);

  Map<int, int>? _letters(bool ascending) => switch (type) {
        ScaleType.major => _major,
        ScaleType.naturalMinor => _naturalMinor,
        ScaleType.harmonicMinor => _harmonicMinor,
        ScaleType.melodicMinor => ascending ? _melodicUp : _naturalMinor,
        ScaleType.majorPentatonic => _pentatonic,
        ScaleType.chromatic => null,
        ScaleType.majorTriad || ScaleType.majorTriad1 || ScaleType.majorTriad2 => _majorTriad,
        ScaleType.minorTriad || ScaleType.minorTriad1 || ScaleType.minorTriad2 => _minorTriad,
        ScaleType.dominantSeventh => _dominant7,
        ScaleType.diminishedSeventh => _diminished7,
      };

  /// Letra (0 = Dó ... 6 = Si) e acidente da tônica, como se escreve o nome da tonalidade (base da armadura de clave).
  (int, int) get tonicSpelling {
    final pc = tonicMidi % 12;
    // a outra grafia só vale em escalas (não em cromática nem em arpejos, que seguem a grafia usual)
    if (alt && type != ScaleType.chromatic && !type.arpeggio) {
      final a = (type.isMinor ? _minorAlt : _majorAlt)[pc];
      if (a != null) return a;
    }
    return (type.isMinor ? _minorTonic : _majorTonic)[pc];
  }

  /// A nota [midi] escrita como estaria na partitura, subindo ou descendo.
  SpelledNote spell(int midi, {required bool ascending}) {
    final pc = midi % 12;
    int letter, acc;
    final map = _letters(ascending);
    if (map == null) {
      // Cromática: sobe com sustenidos e desce com bemóis (o costume nas escalas de violino).
      const up = [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1), (6, 0)];
      const down = [(0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (4, -1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)];
      (letter, acc) = (ascending ? up : down)[pc];
    } else {
      final off = map[(((midi - tonicMidi) % 12) + 12) % 12];
      if (off == null) {
        // nota fora do mapa (não deve acontecer): cai na grafia comum
        (letter, acc) = (type.isMinor ? _minorTonic : _majorTonic)[pc];
      } else {
        letter = (_tonicLetter + off) % 7;
        acc = ((pc - _natPc[letter] + 6) % 12 + 12) % 12 - 6;
      }
    }
    final octave = ((midi - acc) ~/ 12) - 1;
    return SpelledNote(letter, acc, octave);
  }

  String name(int midi, {required bool ascending, bool withOctave = false}) =>
      spell(midi, ascending: ascending).name(withOctave: withOctave);
}
