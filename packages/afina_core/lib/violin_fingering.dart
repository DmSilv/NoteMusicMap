/// Dedilhado do violino para as escalas do "sistema de escalas" de Carl Flesch, lido das páginas do método.
///
/// O Flesch NÃO numera todas as notas: só os pontos de mudança (começo de posição, nota no alto, uso do 4º dedo no lugar
/// da corda solta na subida e da corda solta na descida). Por isso a tabela é esparsa: índice da nota na sequência
/// do exercício "subindo e descendo" -> número do dedo (0 = corda solta). Só números em cima das notas.
///
/// Cada escala entra depois de conferida com a página (veja `violin_fingering_test.dart`: toda corda solta cai numa corda
/// solta do violino, e os índices cabem na sequência).
library;

import 'dart:convert';

import 'pitch_grid.dart';
import 'scale_exercise.dart';
import 'scale_spelling.dart';

/// O que o livro escreve para uma escala: números dos dedos e onde (se em algum lugar) usa o 8va. Os índices são os da sequência
/// "subindo e descendo" (a primeira nota é 0).
class _Entry {
  final int tonicPc;

  /// Escrita na outra grafia da tônica (Sol♭ em vez de Fá♯).
  final bool alt;
  final ScaleType type;
  final int octaves;
  final Map<int, String> marks;

  /// Primeira e última nota sob o 8va, ou null quando o livro não usa 8va nesta escala.
  final (int, int)? ottava;
  const _Entry(this.tonicPc, this.alt, this.type, this.octaves, this.marks, {this.ottava});
}

/// A escala como o livro escreve, já ajustada à direção pedida (os índices acompanham a sequência do exercício).
class FingeringPlan {
  final List<String?> fingers;

  /// Notas sob o 8va, ou null se o livro não usa 8va aqui.
  final (int, int)? ottava;
  const FingeringPlan(this.fingers, this.ottava);
}

const List<_Entry> _violin = [
  // Flesch nº 5, 3 oitavas, Si♭ maior (2 bemóis), a partir do Si♭3 (corda Sol, 2º dedo).
  // Subindo usa o 4º dedo no Ré4 e no Lá4 (em vez das cordas soltas) e muda de posição com o 1º dedo; descendo usa as
  // cordas soltas Lá4 e Ré4.
  _Entry(10, false, ScaleType.major, 3, {2: '4', 6: '4', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3', 36: '0', 40: '0'}),
  // Flesch nº 5, 3 oitavas, Mi♭ maior (3 bemóis), a partir do Mi♭4 (corda Ré, 2º dedo). Mesmo molde do Si♭ maior nos pontos de
  // mudança (1 1 1, 4 4, 3 3), sem cordas soltas; o livro usa 8va nas 6 notas do topo (Si♭6 a Dó7).
  _Entry(3, false, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3'}, ottava: (18, 23)),
  // Flesch nº 5, 3 oitavas, Sol♭ maior (6 bemóis), a partir do Sol♭4. Mesmo molde do Mi♭ maior; o 8va vai do Si♭6 até o 1º grupo do
  // compasso seguinte (da nota 18 à 26).
  _Entry(6, true, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3'}, ottava: (18, 26)),
  // Flesch nº 5, 3 oitavas, Mi♭ menor melódica (6 bemóis), a partir do Mi♭4 (corda Ré, 1º dedo; o livro escreve 2 em cima). Sobe com Dó♮ e Ré♮ e
  // desce com Ré♭ e Dó♭. 8va nas 6 notas do topo (Si♭6 a Dó♭7). A subida segue o mesmo molde das maiores (notas 9, 15, 17 e 21); a descida
  // é diferente da maior: 3 nas notas 22, 24 e 27 e 2 na 34.
  _Entry(3, false, ScaleType.melodicMinor, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}, ottava: (18, 23)),
];

/// Escalas que o administrador corrigiu ou incluiu no painel (vêm do servidor); valem no lugar das do app.
List<_Entry> _remote = const [];

/// Quantas escalas vieram do servidor.
int get violinFingeringRemoteCount => _remote.length;

/// Lê a resposta de /api/fingering ({"v":1,"items":[...]}) e passa a usá-la. Entrada inválida é ignorada (nunca derruba o app e
/// nunca coloca número fora da sequência). Devolve quantas escalas valeram.
int setViolinFingeringFromJson(String? json) {
  final out = <_Entry>[];
  try {
    final j = jsonDecode(json ?? '{"items":[]}');
    if (j is Map && j['items'] is List) {
      for (final x in j['items'] as List) {
        final e = _parseEntry(x);
        if (e != null) out.add(e);
      }
    }
  } catch (_) {
    out.clear();
  }
  _remote = out;
  return out.length;
}

_Entry? _parseEntry(Object? x) {
  if (x is! Map) return null;
  final pc = x['pc'];
  final oct = x['oct'];
  final type = ScaleType.values.where((t) => t.name == x['type']).firstOrNull;
  if (pc is! int || pc < 0 || pc > 11 || oct is! int || oct < 1 || oct > 4 || type == null) return null;
  final alt = x['alt'] == true;
  if (alt && !ScaleSpeller.hasAlt(pc, minor: type.isMinor)) return null;
  final n = 2 * oct * type.steps.length + 1;
  final marks = <int, String>{};
  final rawMarks = x['marks'];
  if (rawMarks is Map) {
    for (final m in rawMarks.entries) {
      final i = int.tryParse('${m.key}');
      final f = '${m.value}';
      if (i == null || i < 0 || i >= n || !RegExp(r'^[0-4]$').hasMatch(f)) return null;
      marks[i] = f;
    }
  }
  (int, int)? ott;
  final o = x['ottava'];
  if (o is List && o.length == 2) {
    final a = o[0], b = o[1];
    if (a is! int || b is! int || a < 0 || b >= n || a > b) return null;
    ott = (a, b);
  }
  return _Entry(pc, alt, type, oct, marks, ottava: ott);
}

/// Há dedilhado do Flesch para esta escala?
bool hasViolinFingering(int tonicMidi, ScaleType type, int octaves, {bool alt = false}) => _find(tonicMidi, type, octaves, alt) != null;

_Entry? _find(int tonicMidi, ScaleType type, int octaves, bool alt) {
  final useAlt = alt && ScaleSpeller.hasAlt(tonicMidi, minor: type.isMinor);
  for (final e in [..._remote, ..._violin]) {
    if (e.tonicPc == tonicMidi % 12 && e.alt == useAlt && e.type == type && e.octaves == octaves) return e;
  }
  return null;
}

/// Dedilhado de cada nota da sequência do exercício (mesma ordem de `scaleSequence`), ou null se esta escala ainda não
/// tem tabela. Em "só descendo" a sequência começa na nota mais aguda; os índices acompanham.
List<String?>? violinFingering({required int tonicMidi, required ScaleType type, required int octaves, required ScaleDirection direction, bool alt = false}) =>
    violinFingeringPlan(tonicMidi: tonicMidi, type: type, octaves: octaves, direction: direction, alt: alt)?.fingers;

/// Dedilhado e 8va da escala como o livro escreve, ou null se esta escala ainda não tem tabela.
FingeringPlan? violinFingeringPlan({required int tonicMidi, required ScaleType type, required int octaves, required ScaleDirection direction, bool alt = false}) {
  final e = _find(tonicMidi, type, octaves, alt);
  if (e == null) return null;
  final upLen = scaleMidis(tonicMidi, type, octaves: octaves).length;
  final seq = scaleSequence(tonicMidi, type, octaves: octaves, direction: direction);
  final offset = direction == ScaleDirection.down ? upLen - 1 : 0;
  final fingers = <String?>[for (var i = 0; i < seq.length; i++) e.marks[i + offset]];
  (int, int)? ott;
  if (e.ottava != null) {
    final a = (e.ottava!.$1 - offset).clamp(0, seq.length - 1);
    final b = (e.ottava!.$2 - offset).clamp(-1, seq.length - 1);
    if (b >= a && e.ottava!.$2 - offset >= 0 && e.ottava!.$1 - offset <= seq.length - 1) ott = (a, b);
  }
  return FingeringPlan(fingers, ott);
}

/// Para os testes: as entradas da tabela.
List<({int tonicPc, bool alt, ScaleType type, int octaves, Map<int, String> marks, (int, int)? ottava})> violinFingeringEntries() =>
    [for (final e in _violin) (tonicPc: e.tonicPc, alt: e.alt, type: e.type, octaves: e.octaves, marks: e.marks, ottava: e.ottava)];
