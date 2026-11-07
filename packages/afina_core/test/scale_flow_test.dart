import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

/// Sol maior, 1 oitava.
ScaleExercise make({bool flow = true, double zone = 5}) => ScaleExercise(
    tonicMidi: 55, type: ScaleType.major, octaves: 1, zone: zone, flow: flow);

/// Toca [midi] por [seconds] (quadros de 30 ms). Devolve os resultados novos.
List<StepResult> play(ScaleExercise e, int? midi, double seconds,
    {double cents = 0, double clarity = 0.95}) {
  final out = <StepResult>[];
  for (var t = 0.0; t < seconds - 1e-9; t += 0.03) {
    final r = e.feed(midi: midi, cents: cents, clarity: clarity, dt: 0.03);
    if (r != null) out.add(r);
  }
  return out;
}

void main() {
  group('execução livre (qualquer nota da escala, em qualquer ordem)', () {
    test('toca fora de ordem e o app reconhece e valida todas', () {
      final e = make();
      expect(e.freeNotes, [55, 57, 59, 60, 62, 64, 66, 67]);
      // ordem embaralhada, pulando e voltando
      for (final m in [62, 55, 66, 59, 67, 57, 60, 64]) {
        play(e, m, 0.25, cents: 2);
        play(e, null, 0.3);
      }
      expect(e.allPlayed, isTrue);
      expect(e.board.length, 8);
      expect(e.score.accuracy, 1.0);
      expect(e.finished, isFalse); // quem conclui é o botão
      e.finish();
      expect(e.finished, isTrue);
    });

    test('mostra a afinação de cada nota (desafinada vira "fora")', () {
      final e = make(zone: 5);
      play(e, 55, 0.3, cents: 1);
      play(e, null, 0.3);
      play(e, 59, 0.3, cents: -14);
      play(e, null, 0.3);
      expect(e.board[55]!.cents, closeTo(1, 0.5));
      expect(e.board[59]!.cents, closeTo(-14, 0.5));
      final s = e.score;
      expect(s.inTune, 1);
      expect(s.played, 2);
      expect(s.total, 8);
    });

    test('nota fora da escala é ignorada e gera aviso', () {
      final e = make();
      play(e, 56, 0.5); // Sol♯ não é da escala
      expect(e.board, isEmpty);
      final c = e.cue(56, 10)!;
      expect(c.inScale, isFalse);
      expect(c.expectedMidi, anyOf(55, 57)); // a mais próxima da escala
      expect(e.cue(57, 0), isNull); // nota da escala: sem aviso
    });

    test('nota ouvida por menos que o mínimo não conta', () {
      final e = make();
      play(e, 55, 0.03);
      expect(e.board, isEmpty);
    });

    test('o quadro da nota atualiza ao vivo enquanto ela soa', () {
      final e = make();
      final first = play(e, 60, 0.3, cents: 3);
      expect(first.length, 1); // só a 1ª medida devolve resultado (vibração)
      expect(e.currentFreeMidi, 60);
      expect(e.hearing, isTrue);
      play(e, 60, 0.5, cents: 3); // segurando: não vira outra tentativa
      expect(e.board[60]!.attempts, 1);
    });

    test('tocar de novo depois do silêncio é outra tentativa e vale a última', () {
      final e = make();
      play(e, 62, 0.3, cents: 15);
      play(e, null, 0.4);
      expect(e.board[62]!.cents, closeTo(15, 0.5));
      play(e, 62, 0.4, cents: 1);
      expect(e.board[62]!.attempts, 2);
      expect(e.board[62]!.cents, closeTo(1, 1.5));
      expect(e.score.inTune, 1);
    });

    test('trocar direto de nota (sem silêncio) também fecha a anterior', () {
      final e = make();
      play(e, 55, 0.3, cents: 2);
      play(e, 57, 0.3, cents: -2);
      expect(e.board.keys, containsAll([55, 57]));
      expect(e.currentFreeMidi, 57);
    });

    test('mede pela mediana: arrasto para outra nota não estraga o desvio', () {
      final e = make();
      play(e, 55, 0.45, cents: 3);
      play(e, 55, 0.09, cents: 48);
      expect(e.board[55]!.cents, closeTo(3, 0.5));
    });

    test('a sugestão é a nota mais grave ainda não tocada (sem obrigar ordem)', () {
      final e = make();
      expect(e.expected, 55);
      play(e, 60, 0.3);
      expect(e.expected, 55);
      play(e, null, 0.3);
      play(e, 55, 0.3);
      expect(e.expected, 57);
    });

    test('resultados finais saem em ordem do grave ao agudo, só o que foi tocado', () {
      final e = make();
      play(e, 64, 0.3, cents: 1);
      play(e, null, 0.3);
      play(e, 57, 0.3, cents: -2);
      play(e, null, 0.3);
      expect([for (final r in e.finalResults) r.midi], [57, 64]);
    });

    test('pular não existe no modo livre; trocar de modo recomeça só a nota atual', () {
      final e = make();
      expect(e.skip(), isNull);
      play(e, 55, 0.3);
      e.flow = false;
      expect(e.currentFreeMidi, isNull);
      expect(e.board.containsKey(55), isTrue); // o que já foi medido fica
      expect(e.expected, 55); // guiado: começa na primeira da sequência
    });

    test('arpejo: só as notas do arpejo são alvo', () {
      final e = ScaleExercise(
          tonicMidi: 55, type: ScaleType.majorTriad1, octaves: 1, zone: 5, flow: true);
      expect(e.freeNotes.length, lessThan(8));
      play(e, 57, 0.3); // Lá não é do arpejo de Sol
      expect(e.board, isEmpty);
    });
  });

  group('modo guiado: a nota só muda quando está afinada', () {
    test('fora da faixa a barra não anda e a nota não avança', () {
      final e = make(flow: false);
      play(e, 55, 2.0, cents: 12); // sempre 12 cents alta
      expect(e.index, 0);
      expect(e.holdProgress, 0);
      expect(e.tunedNow, isFalse);
    });

    test('ajustando para dentro da faixa e segurando, avança', () {
      final e = make(flow: false);
      play(e, 55, 0.6, cents: -15); // chegou baixa
      expect(e.index, 0);
      final done = play(e, 55, 0.8, cents: 1); // corrigiu
      expect(done.length, 1);
      expect(e.index, 1);
      expect(e.expected, 57);
    });

    test('a taxa de acerto mede a PRIMEIRA tentativa, não a nota já corrigida', () {
      final e = make(flow: false, zone: 5);
      play(e, 55, 0.6, cents: -15); // primeira tentativa baixa
      play(e, 55, 0.8, cents: 0); // corrigiu e avançou
      play(e, 57, 0.8, cents: 1); // acertou de primeira
      expect(e.results.length, 2);
      expect(e.results[0].cents, closeTo(-15, 1));
      expect(e.results[1].cents, closeTo(1, 1));
      expect(e.score.inTune, 1);
    });

    test('o progresso só cresce afinada e perde um pouco ao desafinar', () {
      final e = make(flow: false);
      play(e, 55, 0.3, cents: 1);
      final a = e.holdProgress;
      expect(a, greaterThan(0.4));
      expect(e.tunedNow, isTrue);
      play(e, 55, 0.2, cents: 20); // desafinou
      expect(e.holdProgress, lessThan(a));
    });

    test('nota errada não conta e gera aviso com direção', () {
      final e = make(flow: false);
      play(e, 54, 0.5, cents: 20);
      expect(e.index, 0);
      final c = e.cue(54, 20)!;
      expect(c.goUp, isTrue); // precisa SUBIR até o Sol
      expect(c.near, isTrue);
    });

    test('pular continua valendo e conta contra a taxa de acerto', () {
      final e = make(flow: false);
      e.skip();
      expect(e.results.single.skipped, isTrue);
      expect(e.index, 1);
    });
  });
}
