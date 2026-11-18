import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

/// Toca [midi] por [seconds], com o desvio indo de [from] a [to] cents (linear), em quadros de 20 ms.
/// Devolve os resultados concluídos nesse trecho.
List<StepResult> play(ScaleExercise e, int? midi, double seconds, {double from = 0, double to = 0}) {
  final out = <StepResult>[];
  final n = (seconds / 0.02).round();
  for (var i = 0; i < n; i++) {
    final c = n <= 1 ? to : from + (to - from) * i / (n - 1);
    final r = e.feed(midi: midi, cents: c, clarity: 0.95, dt: 0.02);
    if (r != null) out.add(r);
  }
  return out;
}

ScaleExercise make({bool noSlide = true}) =>
    ScaleExercise(tonicMidi: 67, type: ScaleType.major, octaves: 1, zone: 10, noSlide: noSlide, direction: ScaleDirection.up);

void main() {
  // Sol maior subindo: 67 Sol, 69 Lá, 71 Si...
  group('guiado sem escorregar', () {
    test('chegando afinada, a nota vale e segue a escala', () {
      final e = make();
      final r = play(e, 67, 1.0);
      expect(r, hasLength(1));
      expect(e.index, 1);
      expect(e.replayNeeded, isFalse);
      expect(e.slips, 0);
    });

    test('chegou desafinada e foi ajustando: NÃO vale; precisa voltar à nota anterior e tocar de novo', () {
      final e = make();
      play(e, 67, 1.0); // Sol ok
      expect(e.expected, 69);
      // Lá chega 30 cents baixo e o dedo corrige até afinar, tudo na mesma tentativa
      var got = play(e, 69, 0.4, from: -30, to: -30);
      got += play(e, 69, 1.0, from: -30, to: 0);
      expect(got, isEmpty);
      expect(e.replayNeeded, isTrue);
      expect(e.replayMidi, 67);
      expect(e.slips, 1);
      // tocar o Lá afinado de novo, sem voltar ao Sol, não adianta
      expect(play(e, 69, 1.0), isEmpty);
      expect(e.index, 1);
      // volta ao Sol afinado e destrava
      expect(play(e, 67, 0.4), isEmpty);
      expect(e.replayNeeded, isFalse);
      // agora o Lá, afinado na chegada, vale
      final r = play(e, 69, 1.0);
      expect(r, hasLength(1));
      expect(r.single.midi, 69);
      expect(e.index, 2);
    });

    test('vir deslizando até a altura (mesmo passando pela faixa) conta como escorregar', () {
      final e = make();
      play(e, 67, 1.0);
      final got = play(e, 69, 1.2, from: -45, to: 5);
      expect(got, isEmpty);
      expect(e.replayNeeded, isTrue);
    });

    test('voltar ao Sol DESAFINADO não destrava', () {
      final e = make();
      play(e, 67, 1.0);
      play(e, 69, 1.0, from: -30, to: -30);
      expect(e.replayNeeded, isTrue);
      play(e, 67, 1.0, from: 25, to: 25);
      expect(e.replayNeeded, isTrue);
      play(e, 67, 0.4);
      expect(e.replayNeeded, isFalse);
    });

    test('primeira nota desafinada: trava sem nota anterior e destrava soltando e tocando de novo', () {
      final e = make();
      play(e, 67, 0.5, from: -35, to: -35);
      expect(e.replayNeeded, isTrue);
      expect(e.replayMidi, isNull);
      expect(play(e, 67, 1.0), isEmpty, reason: 'sem soltar não destrava');
      play(e, null, 0.4);
      expect(e.replayNeeded, isFalse);
      expect(play(e, 67, 1.0), hasLength(1));
    });

    test('uma falha de leitura rápida (menos de 0,12 s) no meio da nota não reinicia a chegada', () {
      final e = make();
      var got = play(e, 67, 0.4);
      got += play(e, null, 0.06);
      got += play(e, 67, 0.4);
      expect(got, hasLength(1));
      expect(e.slips, 0);
    });

    test('desligado, o jeito de antes continua: chegar flat e ajustar ainda vale', () {
      final e = make(noSlide: false);
      play(e, 67, 1.0);
      final got = play(e, 69, 1.5, from: -30, to: 0);
      expect(got, hasLength(1));
      expect(e.replayNeeded, isFalse);
      expect(e.slips, 0);
    });

    test('travado numa nota, pular solta o travamento', () {
      final e = make();
      play(e, 67, 1.0);
      play(e, 69, 0.4, from: -30, to: -30);
      play(e, 69, 1.0, from: -30, to: 0);
      expect(e.replayNeeded, isTrue);
      e.skip();
      expect(e.replayNeeded, isFalse);
    });

    test('desligar no meio do exercício solta quem estava travado', () {
      final e = make();
      play(e, 67, 1.0);
      play(e, 69, 0.4, from: -30, to: -30);
      play(e, 69, 1.0, from: -30, to: 0);
      expect(e.replayNeeded, isTrue);
      e.noSlide = false;
      expect(e.replayNeeded, isFalse);
    });

    test('nota errada logo depois da anterior trava: tem de voltar à nota anterior', () {
      final e = make();
      play(e, 67, 1.0); // Sol ok
      expect(e.expected, 69);
      // em vez do Lá, toca o Si (71): errou o começo
      expect(play(e, 71, 0.3), isEmpty);
      expect(e.replayNeeded, isTrue);
      expect(e.replayMidi, 67);
      expect(e.lockWrongMidi, 71);
      expect(e.wrongStarts, 1);
      // tocar o Lá afinado, sem voltar ao Sol, não adianta
      expect(play(e, 69, 1.0), isEmpty);
      expect(e.index, 1);
      // volta ao Sol e destrava; o motivo some
      play(e, 67, 0.4);
      expect(e.replayNeeded, isFalse);
      expect(e.lockWrongMidi, isNull);
      expect(play(e, 69, 1.0), hasLength(1));
      expect(e.index, 2);
    });

    test('segurar a nota anterior depois de concluir NÃO é erro (o aluno ainda está nela)', () {
      final e = make();
      play(e, 67, 1.0);
      play(e, 67, 0.6); // ainda no Sol
      expect(e.replayNeeded, isFalse);
      expect(e.wrongStarts, 0);
      expect(play(e, 69, 1.0), hasLength(1));
    });

    test('um toque curto numa nota errada (menos de 0,15 s) não trava', () {
      final e = make();
      play(e, 67, 1.0);
      play(e, 66, 0.1);
      expect(e.replayNeeded, isFalse);
      expect(play(e, 69, 1.0), hasLength(1));
    });

    test('a regra vale em todas as notas da escala, também descendo', () {
      final e = ScaleExercise(tonicMidi: 67, type: ScaleType.major, octaves: 1, zone: 10, noSlide: true, direction: ScaleDirection.both);
      for (var i = 0; i < e.sequence.length - 1; i++) {
        final next = e.sequence[i + 1];
        final wrong = next + 3; // uma nota que não é a da vez nem a anterior
        expect(play(e, e.sequence[i], 1.0).length, 1, reason: 'passo $i');
        expect(play(e, wrong == e.sequence[i] ? wrong + 1 : wrong, 0.3), isEmpty);
        expect(e.replayNeeded, isTrue, reason: 'passo $i travou');
        play(e, e.sequence[i], 0.5);
        expect(e.replayNeeded, isFalse, reason: 'passo $i destravou');
      }
    });

    test('na primeira nota não há para onde voltar: nota errada antes dela não trava', () {
      final e = make();
      play(e, 70, 0.5);
      expect(e.replayNeeded, isFalse);
      expect(e.wrongStarts, 0);
      expect(play(e, 67, 1.0), hasLength(1));
    });

    test('pular a nota não trava nada', () {
      final e = make();
      e.skip();
      expect(e.index, 1);
      expect(e.replayNeeded, isFalse);
    });
  });
}
