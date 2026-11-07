import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

/// Sol maior, 1 oitava, no modo escolhido.
ScaleExercise make({bool flow = true, double zone = 5}) => ScaleExercise(
    tonicMidi: 55, type: ScaleType.major, octaves: 1, zone: zone, flow: flow);

/// Toca [midi] por [seconds] (quadros de 30 ms). Devolve os resultados concluídos.
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
  group('modo "seguir meu ritmo"', () {
    test('toca a escala sem parar e conclui todas as notas, sem segurar nenhuma', () {
      final e = make();
      // cada nota por só 0,25 s, uma colada na outra (o modo "esperar" exigiria 0,5 s)
      for (final m in e.sequence) {
        play(e, m, 0.25, cents: 2);
      }
      play(e, null, 0.3); // terminou de tocar: a última nota fecha no silêncio
      expect(e.finished, isTrue);
      expect(e.results.length, e.sequence.length);
      expect(e.results.every((r) => !r.skipped), isTrue);
    });

    test('o modo clássico não anda com notas tão curtas (diferença entre os modos)', () {
      final e = make(flow: false);
      for (final m in e.sequence) {
        play(e, m, 0.25, cents: 2);
      }
      expect(e.finished, isFalse);
    });

    test('a nota só vale quando você passa para a próxima da escala', () {
      final e = make();
      expect(play(e, 55, 0.6), isEmpty); // Sol segurado: ainda não fecha
      expect(e.index, 0);
      final done = play(e, 57, 0.1); // chegou no Lá (a próxima)
      expect(done.length, 1);
      expect(done.first.midi, 55);
      expect(e.index, 1);
      expect(e.expected, 57);
    });

    test('o quadro da troca já conta para a nota nova', () {
      final e = make();
      play(e, 55, 0.3);
      e.feed(midi: 57, cents: -4, clarity: 0.9, dt: 0.03);
      expect(e.index, 1);
      expect(e.hearing, isFalse); // ainda abaixo do tempo mínimo
      play(e, 57, 0.2, cents: -4);
      expect(e.hearing, isTrue);
    });

    test('nota errada é ignorada: não avança nem estraga a atual', () {
      final e = make();
      play(e, 55, 0.3, cents: 1);
      play(e, 56, 0.5); // meio-tom errado
      play(e, 59, 0.5); // uma nota longe
      expect(e.index, 0);
      expect(e.results, isEmpty);
    });

    test('nota ouvida por menos que o tempo mínimo não conta', () {
      final e = make();
      play(e, 55, 0.03); // 1 quadro: ruído
      play(e, 57, 0.5); // o Lá não pode fechar o Sol que quase não foi ouvido
      expect(e.index, 0);
    });

    test('silêncio depois da nota a conclui; silêncio curto, não', () {
      final e = make();
      play(e, 55, 0.4);
      play(e, null, 0.12); // respirou
      expect(e.index, 0);
      play(e, 55, 0.2); // continuou na mesma nota
      expect(e.index, 0);
      final r = play(e, null, 0.3); // parou de verdade
      expect(r.length, 1);
      expect(e.index, 1);
    });

    test('a última nota conclui depois de ouvida por um tempo (não há "próxima")', () {
      final e = make();
      for (var i = 0; i < e.sequence.length - 1; i++) {
        play(e, e.sequence[i], 0.25);
      }
      expect(e.finished, isFalse);
      play(e, e.sequence.last, 0.3); // chegou na última (a penúltima fecha agora)
      expect(e.expected, e.sequence.last);
      expect(e.finished, isFalse); // 0,3 s ainda não basta para a última
      play(e, e.sequence.last, 0.3);
      expect(e.finished, isTrue);
    });

    test('mede pela MEDIANA: a transição entre notas não estraga o desvio', () {
      final e = make();
      // 0,45 s afinado em +3 e depois 0,09 s arrastando para a próxima nota (+48)
      play(e, 55, 0.45, cents: 3);
      play(e, 55, 0.09, cents: 48);
      play(e, 57, 0.1);
      expect(e.results.single.cents, closeTo(3, 0.5));
    });

    test('ignora o começo instável da nota', () {
      final e = make();
      play(e, 55, 0.09, cents: -40); // ataque ainda assentando
      play(e, 55, 0.45, cents: 2);
      play(e, 57, 0.1);
      expect(e.results.single.cents, closeTo(2, 0.5));
    });

    test('nota bem curta usa tudo o que ouviu', () {
      final e = make();
      play(e, 55, 0.15, cents: 6);
      play(e, 57, 0.1);
      expect(e.results.single.cents, closeTo(6, 0.5));
    });

    test('a taxa de acerto continua contando só o que ficou dentro da zona', () {
      final e = make(zone: 5);
      var i = 0;
      for (final m in e.sequence) {
        play(e, m, 0.3, cents: i.isEven ? 1 : 12); // metade afinada, metade fora
        i++;
      }
      play(e, null, 0.3);
      final s = e.score;
      expect(s.total, e.sequence.length);
      expect(s.inTune, (e.sequence.length / 2).ceil());
      expect(s.accuracy, closeTo(s.inTune / s.total, 1e-9));
    });

    test('pular nota funciona e conta contra o acerto', () {
      final e = make();
      play(e, 55, 0.3);
      e.skip();
      expect(e.results.last.skipped, isTrue);
      expect(e.expected, 57);
      expect(e.hearing, isFalse);
    });

    test('trocar de modo no meio recomeça só a nota em andamento', () {
      final e = make();
      play(e, 55, 0.3);
      play(e, 57, 0.3);
      expect(e.index, 1);
      e.flow = false;
      expect(e.flow, isFalse);
      play(e, 57, 0.3); // modo clássico: 0,3 s não basta
      expect(e.index, 1);
      play(e, 57, 0.3); // 0,6 s no total: agora vale
      expect(e.index, 2);
    });
  });

  group('aviso leve (a nota ainda não é a esperada)', () {
    test('nada a avisar quando é a nota certa, silêncio ou fim', () {
      final e = make();
      expect(e.cue(55, 10), isNull);
      expect(e.cue(null, 0), isNull);
    });

    test('nota abaixo da esperada: precisa SUBIR', () {
      final e = make(); // espera Sol (55)
      final c = e.cue(54, 20)!; // Fá♯ 20 cents acima = 80 abaixo do Sol
      expect(c.offCents, closeTo(-80, 1e-9));
      expect(c.goUp, isTrue);
      expect(c.near, isTrue);
      expect(c.amount, 1);
    });

    test('nota acima da esperada: precisa DESCER', () {
      final e = make();
      final c = e.cue(56, -30)!; // 70 acima do Sol
      expect(c.goUp, isFalse);
      expect(c.amount, 0); // "um pouco"
    });

    test('longe demais não é "um pouco": perto vira falso', () {
      final e = make();
      expect(e.cue(60, 0)!.near, isFalse);
      expect(e.cue(60, 0)!.amount, 2);
    });

    test('diz se a nota ouvida é da escala ou não', () {
      final e = make(); // Sol maior: Fá♯ é da escala, Fá natural não
      expect(e.cue(66, 0)!.inScale, isTrue); // Fá♯5
      expect(e.cue(65, 0)!.inScale, isFalse); // Fá5
    });

    test('depois de terminar não há mais aviso', () {
      final e = make();
      for (final m in e.sequence) {
        play(e, m, 0.25);
      }
      play(e, null, 0.3);
      expect(e.finished, isTrue);
      expect(e.cue(55, 0), isNull);
    });
  });
}
