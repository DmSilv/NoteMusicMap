/// Partitura de escalas e arpejos (clave de Sol, compasso 4/4, como no "sistema de escalas" de Flesch).
///
/// Esta parte é só MÚSICA, em Dart puro e testável: posição da nota na pauta, armadura de clave, quando
/// aparece ♯ ♭ ♮ (e o acidente de precaução), ritmo (semínimas, mínimas, colcheias e tercinas) e a divisão
/// em compassos. Quem DESENHA (`staff_layout.dart` e a tela) nunca decide o nome de uma nota: só desenha
/// o que este modelo entrega. Assim os testes aqui já garantem que a partitura não erra a nota.
library;

import 'pitch_grid.dart';
import 'scale_spelling.dart';

/// A partir desta posição (Dó6: 2ª linha suplementar acima) a nota é difícil de achar na pauta; só essas ganham dica.
const int kHighNotePos = 12;

/// Notas a partir daqui (Sol6: 4ª linha suplementar acima) podem ser escritas uma oitava abaixo, sob o sinal 8va.
const int kOttavaPos = 16;

/// A oitava são 7 posições na pauta.
const int kOttavaShift = 7;

/// Quanto tempo (s) a nota difícil precisa esperar, sem ser tocada, para a dica aparecer.
const double kHintAfterSeconds = 4;

/// Um compasso 4/4 tem 48 "ticks": semínima = 12, colcheia = 6, colcheia de tercina = 4.
const int kBarTicks = 48;

const List<int> _pcOfLetter = [0, 2, 4, 5, 7, 9, 11];

/// Posição da nota na pauta de clave de Sol, em meios espaços a partir da 1ª linha (Mi4):
/// 0 = 1ª linha, 1 = 1º espaço, 2 = 2ª linha ... 8 = 5ª linha (Fá5). Dó4 = -2 (linha suplementar), Lá5 = 12.
int staffPos(SpelledNote n) => n.octave * 7 + n.letter - 30;

/// Nota MIDI de uma nota escrita (inverso de `ScaleSpeller.spell`).
int midiOfSpelled(SpelledNote n) => 12 * (n.octave + 1) + _pcOfLetter[n.letter] + n.accidental;

/// Nota escrita que está numa posição da pauta, com um acidente.
SpelledNote noteAtStaffPos(int pos, int accidental) {
  final d = pos + 30;
  return SpelledNote(d % 7, accidental, d ~/ 7);
}

/// Posições (pares) das linhas suplementares que a nota precisa, de dentro para fora.
/// Ex.: Dó4 (-2) -> [-2]; Lá5 (12) -> [10, 12]; Si5 (13) -> [10, 12].
List<int> ledgerLines(int pos) {
  final out = <int>[];
  if (pos <= -2) {
    for (var p = -2; p >= pos; p -= 2) {
      out.add(p);
    }
  } else if (pos >= 10) {
    for (var p = 10; p <= pos; p += 2) {
      out.add(p);
    }
  }
  return out;
}

/// Um sinal da armadura: letra (0 = Dó), posição na pauta e acidente (1 = ♯, -1 = ♭).
class KeySymbol {
  final int letter;
  final int pos;
  final int accidental;
  const KeySymbol(this.letter, this.pos, this.accidental);
}

/// Armadura de clave: [fifths] > 0 são sustenidos, < 0 são bemóis (de -7 a 7).
class KeySignature {
  final int fifths;
  const KeySignature(this.fifths);

  static const List<int> _sharpLetters = [3, 0, 4, 1, 5, 2, 6]; // Fá Dó Sol Ré Lá Mi Si
  static const List<int> _flatLetters = [6, 2, 5, 1, 4, 0, 3]; // Si Mi Lá Ré Sol Dó Fá
  static const List<int> _sharpPos = [8, 5, 9, 6, 3, 7, 4]; // clave de Sol: Fá5 Dó5 Sol5 Ré5 Lá4 Mi5 Si4
  static const List<int> _flatPos = [4, 7, 3, 6, 2, 5, 1]; // Si4 Mi5 Lá4 Ré5 Sol4 Dó5 Fá4

  int get count => fifths.abs();

  /// Os sinais na ordem em que são escritos, da esquerda para a direita.
  List<KeySymbol> get symbols => [
        for (var i = 0; i < count; i++)
          if (fifths > 0) KeySymbol(_sharpLetters[i], _sharpPos[i], 1) else KeySymbol(_flatLetters[i], _flatPos[i], -1),
      ];

  /// Acidente que a armadura dá a uma letra (0 = natural).
  int accidentalOf(int letter) {
    for (final s in symbols) {
      if (s.letter == letter) return s.accidental;
    }
    return 0;
  }
}

const List<int> _majorFifths = [0, 2, 4, -1, 1, 3, 5]; // Dó Ré Mi Fá Sol Lá Si maiores

/// Armadura da tonalidade de uma escala ou arpejo cuja tônica (raiz) é [tonicMidi].
/// Maiores e menores usam a tonalidade da própria tônica; a 7ª da dominante usa a tonalidade para a qual
/// resolve (uma quinta abaixo); a cromática usa a maior da tônica (e escreve os acidentes que faltarem).
KeySignature keySignatureFor(int tonicMidi, ScaleType type, {bool alt = false}) {
  final sp = ScaleSpeller(tonicMidi, type, alt: alt);
  final (letter, acc) = sp.tonicSpelling;
  final minor = type.isMinor || type == ScaleType.diminishedSeventh;
  var f = _majorFifths[letter] + 7 * acc - (minor ? 3 : 0);
  if (type == ScaleType.dominantSeventh) f -= 1;
  while (f > 7) {
    f -= 12;
  }
  while (f < -7) {
    f += 12;
  }
  return KeySignature(f);
}

/// Como as notas são escritas: valor de cada nota na partitura (não muda o que o exercício pede).
enum StaffRhythm {
  /// Semínimas (uma nota por tempo), o jeito simples de estudar.
  quarter,

  /// Mínimas.
  half,

  /// Colcheias (duas por tempo), ligadas de quatro em quatro.
  eighth,

  /// Colcheias de tercina (três por tempo), como o Flesch costuma escrever.
  triplet,
}

/// Quando escrever o nome das notas embaixo da pauta.
enum StaffNames {
  /// Nunca (só a partitura).
  none,

  /// Só nas notas com linha suplementar, as mais difíceis de ler.
  ledger,

  /// Em todas as notas.
  all,
}

/// Uma nota da partitura, com tudo o que o desenho precisa.
class StaffEvent {
  /// Posição da nota na sequência do exercício (para pintar de acordo com o resultado).
  final int index;
  final SpelledNote note;
  final int midi;
  final bool ascending;

  /// Duração em ticks (48 = semibreve, 36 = mínima pontuada, 24 = mínima, 12 = semínima, 6 = colcheia, 4 = tercina).
  final int ticks;

  /// Posição na pauta (ver [staffPos]).
  final int pos;

  /// Acidente a escrever antes da nota: -1 ♭, 0 ♮, 1 ♯, 2 ♯♯, -2 ♭♭; null = nenhum (a armadura já diz).
  final int? accidental;

  /// O acidente é de precaução (a nota volta ao que a armadura manda depois de ter sido alterada no compasso anterior).
  final bool courtesy;

  /// Notas com o mesmo número formam um grupo ligado por barra; null = sem barra.
  final int? beamGroup;

  /// Notas com o mesmo número formam uma tercina (leva o "3"); null = não é tercina.
  final int? tripletGroup;

  /// Início da nota dentro do exercício, em ticks.
  final int startTick;

  /// Dedilhado escrito em cima da nota ("0".."4"), ou null.
  final String? finger;

  /// A nota está sob o sinal 8va: SOA uma oitava acima do que está escrito na pauta.
  final bool ottava;

  const StaffEvent({
    required this.index,
    required this.note,
    required this.midi,
    required this.ascending,
    required this.ticks,
    required this.pos,
    required this.accidental,
    required this.courtesy,
    required this.beamGroup,
    required this.tripletGroup,
    required this.startTick,
    this.finger,
    this.ottava = false,
  });

  StaffEvent withOttava(bool o) => StaffEvent(
        index: index,
        note: note,
        midi: midi,
        ascending: ascending,
        ticks: ticks,
        pos: pos,
        accidental: accidental,
        courtesy: courtesy,
        beamGroup: beamGroup,
        tripletGroup: tripletGroup,
        startTick: startTick,
        finger: finger,
        ottava: o,
      );

  /// Onde a nota é DESENHADA: com 8va, uma oitava abaixo da posição real ([pos]).
  int get writtenPos => ottava ? pos - kOttavaShift : pos;

  bool get isHigh => pos >= kHighNotePos;
  bool get hasStem => ticks < 48;
  bool get hollow => ticks >= 24;
  bool get dotted => ticks == 36;
  int get bar => startTick ~/ kBarTicks;
}

/// A partitura inteira: armadura, ritmo e as notas divididas em compassos 4/4.
class StaffScore {
  final KeySignature key;
  final StaffRhythm rhythm;
  final List<List<StaffEvent>> bars;
  const StaffScore(this.key, this.rhythm, this.bars);

  List<StaffEvent> get events => [for (final b in bars) ...b];
  int get noteCount => bars.fold(0, (a, b) => a + b.length);
}

/// Duração (ticks) de cada uma das [n] notas. A última nota é sempre longa e completa o compasso.
List<int> rhythmTicks(int n, StaffRhythm r) {
  if (n <= 0) return const [];
  final base = switch (r) { StaffRhythm.quarter => 12, StaffRhythm.half => 24, StaffRhythm.eighth => 6, StaffRhythm.triplet => 4 };
  final group = switch (r) { StaffRhythm.quarter => 1, StaffRhythm.half => 1, StaffRhythm.eighth => 4, StaffRhythm.triplet => 3 };
  final body = n - 1;
  final full = (body ~/ group) * group;
  final out = <int>[for (var i = 0; i < full; i++) base];
  // Sobra de um grupo incompleto: vira semínima / duas colcheias, para a nota final cair sempre num tempo.
  out.addAll(switch (body - full) { 1 => [12], 2 => [6, 6], 3 => [6, 6, 12], _ => const <int>[] });
  final t = out.fold(0, (a, b) => a + b);
  final r48 = kBarTicks - (t % kBarTicks);
  out.add(r48 >= 48 ? 48 : (r48 >= 36 ? 36 : (r48 >= 24 ? 24 : 12)));
  return out;
}

/// Monta a partitura de um exercício: [sequence] são as notas MIDI na ordem em que se toca e as [upCount]
/// primeiras são a subida (as demais, a descida), que é o que decide a grafia (Lá♮ subindo, Lá♭ descendo).
StaffScore buildStaffScore({
  required int tonicMidi,
  required ScaleType type,
  required List<int> sequence,
  required int upCount,
  StaffRhythm rhythm = StaffRhythm.quarter,
  bool courtesy = true,

  /// Dedilhado de cada nota da sequência (mesma ordem de [sequence]); null ou item null = sem número.
  List<String?>? fingers,

  /// Escreve as notas muito agudas uma oitava abaixo, com o sinal 8va (e o nome das notas).
  bool ottava = false,

  /// 8va exatamente como o livro escreve: primeira e última nota (índices da sequência); vale no lugar da regra automática.
  (int, int)? ottavaRange,

  /// Outra grafia da tônica (Sol♭ em vez de Fá♯).
  bool alt = false,
}) {
  final speller = ScaleSpeller(tonicMidi, type, alt: alt);
  final key = keySignatureFor(tonicMidi, type, alt: alt);
  final n = sequence.length;
  final ticks = rhythmTicks(n, rhythm);
  final bars = <List<StaffEvent>>[];
  var t = 0;
  var cur = <int, int>{}; // altura (oitava*7+letra) -> acidente escrito neste compasso
  var prev = <int, int>{};
  var barIdx = -1;
  for (var i = 0; i < n; i++) {
    final asc = i < upCount;
    final sn = speller.spell(sequence[i], ascending: asc);
    final bar = t ~/ kBarTicks;
    if (bar != barIdx) {
      prev = cur;
      cur = {};
      barIdx = bar;
      bars.add([]);
    }
    final pk = sn.octave * 7 + sn.letter;
    final keyAcc = key.accidentalOf(sn.letter);
    final state = cur[pk] ?? keyAcc;
    int? show = sn.accidental != state ? sn.accidental : null;
    var isCourtesy = false;
    if (show == null && courtesy && !cur.containsKey(pk) && prev[pk] != null && prev[pk] != sn.accidental) {
      show = sn.accidental;
      isCourtesy = true;
    }
    cur[pk] = sn.accidental;
    final tk = ticks[i];
    final beamed = tk <= 6 && i < n - 1;
    final window = rhythm == StaffRhythm.triplet ? 12 : 24;
    bars.last.add(StaffEvent(
      index: i,
      note: sn,
      midi: sequence[i],
      ascending: asc,
      ticks: tk,
      pos: staffPos(sn),
      accidental: show,
      courtesy: isCourtesy,
      beamGroup: beamed ? t ~/ window : null,
      tripletGroup: tk == 4 ? t ~/ 12 : null,
      startTick: t,
      finger: fingers != null && i < fingers.length ? fingers[i] : null,
    ));
    t += tk;
  }
  if (ottavaRange != null) {
    var idx = 0;
    for (final b in bars) {
      for (var k = 0; k < b.length; k++) {
        b[k] = b[k].withOttava(idx >= ottavaRange.$1 && idx <= ottavaRange.$2);
        idx++;
      }
    }
  } else if (ottava) {
    _applyOttava(bars);
  }
  return StaffScore(key, rhythm, bars);
}

/// Marca as notas que vão sob o 8va: de Sol6 para cima, com as vizinhas de Mi6 para cima, só em trechos de pelo menos 3
/// notas seguidas (um 8va para uma nota só não vale a pena) e sempre com o grupo de barra inteiro (não se mistura oitava na barra).
void _applyOttava(List<List<StaffEvent>> bars) {
  final all = [for (final b in bars) ...b];
  final n = all.length;
  var flags = [for (final e in all) e.pos >= kOttavaPos];
  final grown = [...flags];
  for (var i = 0; i < n; i++) {
    if (!flags[i] && all[i].pos >= kOttavaPos - 2 && ((i > 0 && flags[i - 1]) || (i < n - 1 && flags[i + 1]))) grown[i] = true;
  }
  flags = grown;
  // trechos curtos não ganham 8va
  var i = 0;
  while (i < n) {
    if (!flags[i]) {
      i++;
      continue;
    }
    var j = i;
    while (j < n && flags[j]) {
      j++;
    }
    if (j - i < 3) {
      for (var k = i; k < j; k++) {
        flags[k] = false;
      }
    }
    i = j;
  }
  // o grupo de barra inteiro
  final groups = <int, List<int>>{};
  for (var k = 0; k < n; k++) {
    final g = all[k].beamGroup;
    if (g != null) groups.putIfAbsent(g * 1000 + all[k].bar, () => []).add(k);
  }
  for (final g in groups.values) {
    if (g.any((k) => flags[k])) {
      for (final k in g) {
        flags[k] = true;
      }
    }
  }
  var idx = 0;
  for (final b in bars) {
    for (var k = 0; k < b.length; k++) {
      b[k] = b[k].withOttava(flags[idx++]);
    }
  }
}
