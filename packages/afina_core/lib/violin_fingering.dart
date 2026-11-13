/// Dedilhado do violino para as escalas do "sistema de escalas" de Carl Flesch, lido das páginas do método.
///
/// O Flesch NÃO numera todas as notas: só os pontos de mudança (começo de posição, nota no alto, uso do 4º dedo no lugar
/// da corda solta na subida e da corda solta na descida). Por isso a tabela é esparsa: índice da nota na sequência
/// do exercício "subindo e descendo" -> número do dedo (0 = corda solta). Só números em cima das notas.
///
/// Cada escala entra depois de conferida com a página (veja `violin_fingering_test.dart`: toda corda solta cai numa corda
/// solta do violino, e os índices cabem na sequência).
library;

import 'pitch_grid.dart';
import 'scale_exercise.dart';

class _Entry {
  final int tonicPc;
  final ScaleType type;
  final int octaves;
  final Map<int, String> marks;
  const _Entry(this.tonicPc, this.type, this.octaves, this.marks);
}

const List<_Entry> _violin = [
  // Flesch nº 5, 3 oitavas, Si♭ maior (2 bemóis), a partir do Si♭3 (corda Sol, 2º dedo).
  // Subindo usa o 4º dedo no Ré4 e no Lá4 (em vez das cordas soltas) e muda de posição com o 1º dedo; descendo usa as
  // cordas soltas Lá4 e Ré4.
  _Entry(10, ScaleType.major, 3, {2: '4', 6: '4', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3', 36: '0', 40: '0'}),
];

/// Há dedilhado do Flesch para esta escala?
bool hasViolinFingering(int tonicMidi, ScaleType type, int octaves) => _find(tonicMidi, type, octaves) != null;

_Entry? _find(int tonicMidi, ScaleType type, int octaves) {
  for (final e in _violin) {
    if (e.tonicPc == tonicMidi % 12 && e.type == type && e.octaves == octaves) return e;
  }
  return null;
}

/// Dedilhado de cada nota da sequência do exercício (mesma ordem de `scaleSequence`), ou null se esta escala ainda não
/// tem tabela. Em "só descendo" a sequência começa na nota mais aguda; os índices acompanham.
List<String?>? violinFingering({required int tonicMidi, required ScaleType type, required int octaves, required ScaleDirection direction}) {
  final e = _find(tonicMidi, type, octaves);
  if (e == null) return null;
  final upLen = scaleMidis(tonicMidi, type, octaves: octaves).length;
  final seq = scaleSequence(tonicMidi, type, octaves: octaves, direction: direction);
  final offset = direction == ScaleDirection.down ? upLen - 1 : 0;
  return [for (var i = 0; i < seq.length; i++) e.marks[i + offset]];
}

/// Para os testes: as entradas da tabela.
List<({int tonicPc, ScaleType type, int octaves, Map<int, String> marks})> violinFingeringEntries() =>
    [for (final e in _violin) (tonicPc: e.tonicPc, type: e.type, octaves: e.octaves, marks: e.marks)];
