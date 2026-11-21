import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

/// Toca [midi] por [seconds] com o desvio em [center] cents e um vibrato de [amp] cents a 5,5 Hz (quadros de 20 ms).
List<StepResult> play(ScaleExercise e, int? midi, double seconds, {double center = 0, double amp = 0}) {
  final out = <StepResult>[];
  final n = (seconds / 0.02).round();
  for (var i = 0; i < n; i++) {
    final c = center + amp * math.sin(2 * math.pi * 5.5 * i * 0.02);
    final r = e.feed(midi: midi, cents: c, clarity: 0.95, dt: 0.02);
    if (r != null) out.add(r);
  }
  return out;
}

ScaleExercise make(ScaleTolerance tol) => ScaleExercise(
      tonicMidi: 67,
      type: ScaleType.major,
      octaves: 1,
      zone: tol.cents,
      arrivalSeconds: tol.arrivalSeconds,
      arrivalSpread: tol.spread,
      noSlide: true,
      direction: ScaleDirection.up,
    );

void main() {
  group('níveis de tolerância', () {
    test('os valores dos níveis e o padrão', () {
      expect(ScaleTolerance.strict.cents, 10);
      expect(ScaleTolerance.standard.cents, 20);
      expect(ScaleTolerance.easy.cents, 30);
      expect(ScaleTolerance.byName('easy'), ScaleTolerance.easy);
      expect(ScaleTolerance.byName(null), ScaleTolerance.standard);
      expect(ScaleTolerance.byName('lixo'), ScaleTolerance.standard);
    });

    test('chegar 14 cents alto: rigoroso trava ("alto"); padrão aceita', () {
      final r = make(ScaleTolerance.strict);
      play(r, 67, 1.0);
      play(r, 69, 1.0, center: 14);
      expect(r.replayNeeded, isTrue);
      expect(r.lockReason, LockReason.sharp);
      expect(r.lockCents, closeTo(14, 1));
      final s = make(ScaleTolerance.standard);
      play(s, 67, 1.0);
      final got = play(s, 69, 1.2, center: 14);
      expect(got, isNotEmpty);
      expect(s.replayNeeded, isFalse);
      expect(s.index, 2);
    });

    test('vibrato de ±9 cents no centro certo: rigoroso reprova ("instável"), padrão aceita', () {
      final r = make(ScaleTolerance.strict);
      play(r, 67, 1.0);
      play(r, 69, 1.0, amp: 9);
      expect(r.replayNeeded, isTrue);
      expect(r.lockReason, LockReason.unstable);
      final s = make(ScaleTolerance.standard);
      play(s, 67, 1.0);
      expect(play(s, 69, 1.2, amp: 9), isNotEmpty);
      expect(s.replayNeeded, isFalse);
    });

    test('chegar baixo diz "baixo"; trocar o nível durante o exercício vale na hora', () {
      final e = make(ScaleTolerance.strict);
      play(e, 67, 1.0);
      play(e, 69, 1.0, center: -16);
      expect(e.lockReason, LockReason.flat);
      expect(e.slipsFlat, 1);
      e.applyTolerance(ScaleTolerance.standard);
      expect(e.zone, 20);
      expect(e.arrivalSpread, 2.0);
    });

    test('nota errada trava com motivo próprio e sem medida de chegada', () {
      final e = make(ScaleTolerance.standard);
      play(e, 67, 1.0);
      play(e, 72, 0.4); // saiu do Sol direto para uma nota errada
      expect(e.replayNeeded, isTrue);
      expect(e.lockReason, LockReason.wrongNote);
      expect(e.lockWrongMidi, 72);
    });
  });

  group('o que a tela mostra por um instante', () {
    test('a última chegada fica disponível por ~2,5 s e depois some', () {
      final e = make(ScaleTolerance.strict);
      play(e, 67, 1.0);
      play(e, 69, 0.5, center: 14);
      final a = e.recentArrival;
      expect(a, isNotNull);
      expect(a!.ok, isFalse);
      expect(a.cents, closeTo(14, 1));
      play(e, null, 3.0);
      expect(e.recentArrival, isNull);
    });

    test('chegada boa também é registrada (ok)', () {
      final e = make(ScaleTolerance.standard);
      play(e, 67, 0.6, center: 3);
      expect(e.recentArrival?.ok, isTrue);
    });

    test('largar a nota antes de a barra encher marca "segure mais"', () {
      final e = make(ScaleTolerance.standard);
      expect(e.recentShort, isFalse);
      play(e, 67, 0.3);
      play(e, null, 0.3);
      expect(e.recentShort, isTrue);
      play(e, null, 3.0);
      expect(e.recentShort, isFalse);
    });

    test('segurar até o fim não conta como "curta"', () {
      final e = make(ScaleTolerance.standard);
      play(e, 67, 1.0);
      play(e, null, 0.5);
      expect(e.recentShort, isFalse);
    });
  });

  group('voltar à nota anterior, de forma mais gentil', () {
    ScaleExercise lockedOnce() {
      final e = make(ScaleTolerance.strict);
      play(e, 67, 1.0);
      play(e, 69, 1.0, center: 16); // trava (alto)
      expect(e.replayNeeded, isTrue);
      return e;
    }

    test('a nota anterior destrava com folga de 1,5x a zona (14 cents no rigoroso)', () {
      final e = lockedOnce();
      play(e, 67, 0.6, center: 14);
      expect(e.replayNeeded, isFalse);
    });

    test('mas não com mais que isso (18 cents no rigoroso)', () {
      final e = lockedOnce();
      play(e, 67, 0.8, center: 18);
      expect(e.replayNeeded, isTrue);
    });

    test('só na segunda trava na mesma nota aparece "tentar de novo sem voltar"', () {
      final e = lockedOnce();
      expect(e.canSkipReplay, isFalse);
      play(e, 67, 0.6); // volta e destrava
      play(e, null, 0.3);
      play(e, 69, 1.0, center: 16); // trava de novo
      expect(e.replayNeeded, isTrue);
      expect(e.canSkipReplay, isTrue);
      e.skipReplay();
      expect(e.replayNeeded, isFalse);
      expect(e.skippedReplays, 1);
      expect(e.lockReason, isNull);
      // acertando a nota agora, avança e o contador zera
      play(e, null, 0.3);
      expect(play(e, 69, 1.0), isNotEmpty);
      expect(e.index, 2);
      expect(e.canSkipReplay, isFalse);
    });
  });
}
