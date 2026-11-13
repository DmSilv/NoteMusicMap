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

/// O número em cima da 1ª nota é o dedo na corda Sol (IV) e define a POSIÇÃO em que a escala começa: em Dó maior, 2º dedo no Dó4 = 2ª posição; em Fá maior,
/// 2º dedo no Fá4 = 5ª posição (o livro escreve o IV em cima nessas, e o III embaixo é a sugestão do editor, na corda Ré). Escalas que começam em Sol3 a Si♭3
/// não têm número: 1ª posição.
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
  // Flesch nº 5, 3 oitavas, Ré maior (2 sustenidos), a partir do Ré4. O livro escreve 2 em cima da 1ª nota (Flesch: corda Sol, 3ª posição, 2º dedo; o 0 que
  // aparece embaixo é do editor, na corda Ré solta). Sem "4º dedo no lugar da solta" na subida; pontos de mudança do molde das maiores. Sem 8va na página.
  _Entry(2, false, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3'}),
  // Flesch nº 5, 3 oitavas, Mi♭ menor melódica (6 bemóis), a partir do Mi♭4 (corda Ré, 1º dedo; o livro escreve 2 em cima). Sobe com Dó♮ e Ré♮ e
  // desce com Ré♭ e Dó♭. 8va nas 6 notas do topo (Si♭6 a Dó♭7). A subida segue o mesmo molde das maiores (notas 9, 15, 17 e 21); a descida
  // é diferente da maior: 3 nas notas 22, 24 e 27 e 2 na 34.
  _Entry(3, false, ScaleType.melodicMinor, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}, ottava: (18, 23)),

  // ---- As demais escalas do Nº 5 (3 oitavas), lidas do PDF do método (números em cima das notas = dedilhado original do Flesch). ----
  // Maiores
  // Dó maior, a partir do Dó4. Molde das maiores; sem 8va; sem 4º dedo no lugar das cordas soltas (o livro não escreve).
  _Entry(0, false, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3'}),
  // Fá maior, a partir do Fá4. Molde das maiores; 8va nas 6 notas do topo (como Mi♭ maior).
  _Entry(5, false, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3'}, ottava: (18, 23)),
  // Lá♭ maior, a partir do Lá♭3 (corda Sol). Sem cordas soltas na escala. Só um 4 no topo (nota 22; 1º dedo nas notas 10, 16 e 18, contadas cabeça a cabeça) e a nota 29 é 2 (nas outras é 3). Sem 8va.
  _Entry(8, false, ScaleType.major, 3, {10: '1', 16: '1', 18: '1', 22: '4', 26: '3', 29: '2'}),
  // Ré♭ maior, a partir do Ré♭4. Molde das maiores; sem 8va.
  _Entry(1, false, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3'}),
  // Si maior, a partir do Si3 (corda Sol). Só um 4 no topo (nota 22) e corda solta Mi5 na descida (nota 32). Sem 8va.
  _Entry(11, false, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 22: '4', 26: '3', 29: '3', 32: '0'}),
  // Mi maior, a partir do Mi4. Molde das maiores; sem 8va.
  _Entry(4, false, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3'}),
  // Lá maior, a partir do Lá3 (corda Sol): 4º dedo no Ré4 e no Lá4 subindo; descendo 2 na nota 29 e cordas soltas Mi5, Lá4 e Ré4 (31, 35 e 39).
  _Entry(9, false, ScaleType.major, 3, {3: '4', 7: '4', 10: '1', 16: '1', 18: '1', 22: '4', 26: '3', 29: '2', 31: '0', 35: '0', 39: '0'}),
  // Sol maior, a partir do Sol3 (corda Sol solta): 4º dedo no Ré4 e no Lá4 subindo; só um 1 na 2ª oitava (nota 17); 4 na nota 26 e cordas
  // soltas Mi5, Lá4 e Ré4 descendo (30, 34 e 38).
  _Entry(7, false, ScaleType.major, 3, {4: '4', 8: '4', 11: '1', 17: '1', 21: '4', 22: '4', 26: '4', 30: '0', 34: '0', 38: '0'}),
  // Menores (melódicas: sobem com a sexta e a sétima maiores e descem naturais)
  // Lá menor, a partir do Lá3 (corda Sol). Sem os 4 do topo; 3 e 4 na descida (24 e 27) e cordas soltas Mi5, Lá4 e Ré4 (31, 35 e 39).
  _Entry(9, false, ScaleType.melodicMinor, 3, {3: '4', 7: '4', 10: '1', 16: '1', 18: '1', 24: '3', 27: '4', 31: '0', 35: '0', 39: '0'}),
  // Ré menor, a partir do Ré4 (corda Sol, 3ª posição, 2º dedo, como no Ré maior). Molde das menores.
  _Entry(2, false, ScaleType.melodicMinor, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}),
  // Sol menor, a partir do Sol3: 4º dedo no Ré4 e no Lá4 subindo; 2 na nota 23; cordas soltas Lá4 e Ré4 descendo (34 e 38).
  _Entry(7, false, ScaleType.melodicMinor, 3, {4: '4', 8: '4', 11: '1', 17: '1', 21: '4', 22: '3', 23: '2', 24: '3', 27: '3', 34: '0', 38: '0'}),
  // Dó menor, a partir do Dó4. Molde das menores.
  _Entry(0, false, ScaleType.melodicMinor, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}),
  // Fá menor, a partir do Fá4. Molde das menores; 8va nas 6 notas do topo.
  _Entry(5, false, ScaleType.melodicMinor, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}, ottava: (18, 23)),
  // Si♭ menor, a partir do Si♭3 (corda Sol): 4º dedo no Lá4 subindo (o Ré♭4 não é corda solta). Molde das menores.
  _Entry(10, false, ScaleType.melodicMinor, 3, {0: '2', 6: '4', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}),
  // Sol♯ menor, a partir do Sol♯3 (corda Sol). Só um 1 na 2ª oitava (nota 17) e um 2 perto do fim (nota 40). Primeiras notas: o livro escreve
  // números que não deu para ler com segurança (veja o relatório).
  _Entry(8, false, ScaleType.melodicMinor, 3, {0: '1', 1: '2', 2: '2', 11: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 40: '2'}),
  // Dó♯ menor, a partir do Dó♯4. Molde das menores.
  _Entry(1, false, ScaleType.melodicMinor, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}),
  // Fá♯ menor, a partir do Fá♯4. Molde das menores; 8va nas 6 notas do topo.
  _Entry(6, false, ScaleType.melodicMinor, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}, ottava: (18, 23)),
  // Si menor, a partir do Si3 (corda Sol): 4º dedo no Ré4 e no Lá4 subindo; cordas soltas Lá4 e Ré4 descendo (36 e 40).
  _Entry(11, false, ScaleType.melodicMinor, 3, {0: '2', 2: '4', 6: '4', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2', 36: '0', 40: '0'}),
  // Mi menor, a partir do Mi4. Molde das menores.
  _Entry(4, false, ScaleType.melodicMinor, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}),
  // ---- A outra grafia das mesmas escalas (as notas são as mesmas, então o dedilhado e o 8va também): o livro só traz uma grafia de cada. ----
  // Fá♯ maior (mesmas notas do Sol♭ maior).
  _Entry(6, false, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3'}, ottava: (18, 26)),
  // Dó♯ maior (mesmas notas do Ré♭ maior).
  _Entry(1, true, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '4', 26: '3', 29: '3'}),
  // Dó♭ maior (mesmas notas do Si maior).
  _Entry(11, true, ScaleType.major, 3, {0: '2', 9: '1', 15: '1', 17: '1', 22: '4', 26: '3', 29: '3', 32: '0'}),
  // Ré♯ menor melódica (mesmas notas do Mi♭ menor).
  _Entry(3, true, ScaleType.melodicMinor, 3, {0: '2', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}, ottava: (18, 23)),
  // Lá♭ menor melódica (mesmas notas do Sol♯ menor).
  _Entry(8, true, ScaleType.melodicMinor, 3, {0: '1', 1: '2', 2: '2', 11: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 40: '2'}),
  // Lá♯ menor melódica (mesmas notas do Si♭ menor).
  _Entry(10, true, ScaleType.melodicMinor, 3, {0: '2', 6: '4', 9: '1', 15: '1', 17: '1', 21: '4', 22: '3', 24: '3', 27: '3', 34: '2'}),
  // ---- Arpejos do Nº 5 (logo depois da escala), 3 oitavas, em linhas de 3 compassos: cada compasso é um arpejo que sobe 3 oitavas e desce, e o
  // último Dó do exercício é o primeiro do compasso seguinte. Todos começam na mesma nota (a tônica da seção), por isso o acorde pode estar invertido:
  // na seção de Dó há Dó menor, Dó maior, Lá menor com Dó no baixo (Dó Mi Lá), Fá maior com Dó no baixo (Dó Fá Lá) e Fá menor com Dó no baixo.
  // Seção de Dó maior, arpejos de tríade (lidos): 1º dedo no Mi/Fá da 2ª oitava (nota 4) e da 3ª (nota 7) e 4º dedo na descida (nota 12).
  _Entry(0, false, ScaleType.minorTriad, 3, {0: '2', 4: '1', 7: '1', 12: '4'}),
  _Entry(0, false, ScaleType.majorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(9, false, ScaleType.minorTriad1, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(5, false, ScaleType.majorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(5, false, ScaleType.minorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  // Seção de Fá maior: tônica menor, tônica maior, relativa menor invertida, IV maior e IV menor em 2ª inversão.
  _Entry(5, false, ScaleType.minorTriad, 3, {0: '2', 4: '1', 7: '1', 12: '4'}),
  _Entry(5, false, ScaleType.majorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(2, false, ScaleType.minorTriad1, 3, {4: '1', 7: '1', 8: '3', 12: '4'}),
  _Entry(10, false, ScaleType.majorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(10, false, ScaleType.minorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  // Seção de Si♭ maior: tônica menor, tônica maior, relativa menor invertida, IV maior e IV menor em 2ª inversão.
  _Entry(10, false, ScaleType.minorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(10, false, ScaleType.majorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(7, false, ScaleType.minorTriad1, 3, {4: '1', 7: '1', 8: '3', 12: '4'}),
  _Entry(3, false, ScaleType.majorTriad2, 3, {2: '3', 4: '1', 7: '1', 12: '4'}),
  _Entry(3, false, ScaleType.minorTriad2, 3, {2: '3', 4: '1', 7: '1', 12: '4'}),
  // Seção de Mi♭ maior: tônica menor, tônica maior, relativa menor invertida, IV maior e IV menor em 2ª inversão.
  _Entry(3, false, ScaleType.minorTriad, 3, {0: '2', 4: '1', 7: '1', 12: '4'}),
  _Entry(3, false, ScaleType.majorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(0, false, ScaleType.minorTriad1, 3, {4: '1', 7: '1', 8: '3', 12: '4'}),
  _Entry(8, false, ScaleType.majorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(8, false, ScaleType.minorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  // Seção de Ré♭ maior (a nota 8 da 3ª tríade por analogia com as outras seções: o número fica no corte da página): tônica menor, tônica maior, relativa menor invertida, IV maior e IV menor em 2ª inversão.
  _Entry(1, false, ScaleType.minorTriad, 3, {0: '2', 4: '1', 7: '1', 12: '4'}),
  _Entry(1, false, ScaleType.majorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(10, false, ScaleType.minorTriad1, 3, {4: '1', 7: '1', 8: '3', 12: '4'}),
  _Entry(6, false, ScaleType.majorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(6, false, ScaleType.minorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  // Seção de Sol♭ maior: tônica menor, tônica maior, relativa menor invertida, IV maior e IV menor em 2ª inversão.
  _Entry(6, false, ScaleType.minorTriad, 3, {0: '2', 4: '1', 7: '1', 12: '4'}),
  _Entry(6, false, ScaleType.majorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(3, false, ScaleType.minorTriad1, 3, {4: '1', 7: '1', 8: '3', 12: '4'}),
  _Entry(11, false, ScaleType.majorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(11, false, ScaleType.minorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  // Seção de Si maior (começa na corda Sol: 4º dedo na nota 1 da 3ª tríade): tônica menor, tônica maior, relativa menor invertida, IV maior e IV menor em 2ª inversão.
  _Entry(11, false, ScaleType.minorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(11, false, ScaleType.majorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(8, false, ScaleType.minorTriad1, 3, {1: '4', 4: '1', 7: '1', 8: '3', 12: '4'}),
  _Entry(4, false, ScaleType.majorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(4, false, ScaleType.minorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  // Seção de Ré maior: tônica menor, tônica maior, relativa menor invertida, IV maior e IV menor em 2ª inversão.
  _Entry(2, false, ScaleType.minorTriad, 3, {0: '2', 4: '1', 7: '1', 12: '4'}),
  _Entry(2, false, ScaleType.majorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(11, false, ScaleType.minorTriad1, 3, {4: '1', 7: '1', 8: '3', 12: '4'}),
  _Entry(7, false, ScaleType.majorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(7, false, ScaleType.minorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  // Seção de Mi maior: tônica menor, tônica maior, relativa menor invertida, IV maior e IV menor em 2ª inversão.
  _Entry(4, false, ScaleType.minorTriad, 3, {0: '2', 4: '1', 7: '1', 12: '4'}),
  _Entry(4, false, ScaleType.majorTriad, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(1, false, ScaleType.minorTriad1, 3, {4: '1', 7: '1', 8: '3', 12: '4'}),
  _Entry(9, false, ScaleType.majorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  _Entry(9, false, ScaleType.minorTriad2, 3, {4: '1', 7: '1', 12: '4'}),
  // Seção de Lá♭ maior (corda Sol baixa: 1º dedo no começo dos grupos, notas 3 e 6, e na descida nas notas 13 e 16).
  _Entry(8, false, ScaleType.minorTriad, 3, {3: '1', 6: '1', 13: '1', 16: '1'}),
  _Entry(8, false, ScaleType.majorTriad, 3, {3: '1', 6: '1', 13: '1', 16: '1'}),
  _Entry(5, false, ScaleType.minorTriad1, 3, {3: '1', 6: '1', 13: '2', 16: '2'}),
  _Entry(1, false, ScaleType.majorTriad2, 3, {3: '2', 7: '1', 8: '3', 12: '1', 16: '2'}),
  _Entry(1, false, ScaleType.minorTriad2, 3, {3: '2', 7: '1', 12: '1', 16: '2'}),
  // Seção de Lá maior (corda Sol baixa; corda solta Ré4 e Lá4 nos arpejos com Ré).
  _Entry(9, false, ScaleType.minorTriad, 3, {3: '1', 6: '1', 13: '1', 16: '1'}),
  _Entry(9, false, ScaleType.majorTriad, 3, {3: '1', 6: '1', 13: '1', 16: '1'}),
  _Entry(6, false, ScaleType.minorTriad1, 3, {3: '1', 6: '1', 13: '2', 16: '2'}),
  _Entry(2, false, ScaleType.majorTriad2, 3, {1: '0', 4: '1', 7: '1', 12: '1', 15: '0', 16: '2'}),
  _Entry(2, false, ScaleType.minorTriad2, 3, {1: '0', 4: '1', 7: '1', 12: '1', 15: '0', 16: '2'}),
  // Seção de Sol maior (só os dois primeiros arpejos: nos outros três a descida não deu para ler com segurança).
  _Entry(7, false, ScaleType.minorTriad, 3, {3: '1', 6: '1', 13: '1', 16: '0', 17: '2'}),
  _Entry(7, false, ScaleType.majorTriad, 3, {3: '1', 6: '1', 13: '1', 16: '0'}),
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
  // arpejos não têm a "outra grafia" (a raiz se escreve do jeito de sempre)
  final useAlt = !type.arpeggio && alt && ScaleSpeller.hasAlt(tonicMidi, minor: type.isMinor);
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

/// Onde a escala começa no violino, como o livro: sempre na corda Sol (IV) e na posição que o número da 1ª nota dá.
class StartHint {
  /// Corda: 4 = Sol (IV).
  final int string;

  /// Posição (1 a 7).
  final int position;

  /// Dedo da 1ª nota (null = o livro não escreve: 1ª posição).
  final int? finger;
  const StartHint(this.string, this.position, this.finger);
}

/// A corda e a posição em que a escala do livro começa, ou null se não há tabela (ou se a escala começa pelo alto, em "só descendo").
StartHint? violinStartHint({required int tonicMidi, required ScaleType type, required int octaves, required ScaleDirection direction, bool alt = false}) {
  if (direction == ScaleDirection.down) return null;
  final e = _find(tonicMidi, type, octaves, alt);
  if (e == null) return null;
  final first = scaleSequence(tonicMidi, type, octaves: octaves).first;
  // a posição vem da nota na corda Sol: passos de letra acima do Sol3 (Sol=0, Lá=1... Ré4=4) menos o dedo, mais 1
  final n = ScaleSpeller(tonicMidi, type).spell(first, ascending: true);
  final d = n.octave * 7 + n.letter - (3 * 7 + 4);
  final f = int.tryParse(e.marks[0] ?? '');
  // sem número: de Sol3 a Si3 é a 1ª posição; mais agudo, o livro não diz (o dedo vem do arpejo anterior), então não há dica
  if (f == null || f < 1) return first < 60 ? const StartHint(4, 1, null) : null;
  return StartHint(4, (d - f + 1).clamp(1, 7), f);
}

/// Para os testes: as entradas da tabela.
List<({int tonicPc, bool alt, ScaleType type, int octaves, Map<int, String> marks, (int, int)? ottava})> violinFingeringEntries() =>
    [for (final e in _violin) (tonicPc: e.tonicPc, alt: e.alt, type: e.type, octaves: e.octaves, marks: e.marks, ottava: e.ottava)];
