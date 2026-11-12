import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

const sr = 48000;

/// Renderiza [seconds] segundos e devolve os eventos de "primeiro tempo" de cada compasso.
List<ClickEvent> bars(MetronomeEngine e, double seconds) {
  final out = <ClickEvent>[];
  var done = 0;
  final total = (sr * seconds).round();
  while (done < total) {
    e.render(2048);
    done += 2048;
    out.addAll(e.takeEvents().where((x) => x.sub == 0 && x.beat == 0));
  }
  return out;
}

MetronomeConfig cfg({TempoTrainer? trainer, double bpm = 240, int countIn = 0}) =>
    MetronomeConfig.signature(4, bpm: bpm).copyWith(trainer: trainer, countInBars: countIn);

void main() {
  group('acelerar aos poucos: por tempo', () {
    test('o aumento entra no primeiro compasso depois do período e respeita o teto', () {
      // 240 BPM em 4/4 = um compasso por segundo; aumenta 10 BPM a cada 2 segundos, até 270.
      final e = MetronomeEngine(sr, cfg(trainer: const TempoTrainer(everySeconds: 2, stepBpm: 10, maxBpm: 270)));
      final b = bars(e, 14);
      final bpmByBar = {for (final x in b) x.bar: x.bpm};
      expect(bpmByBar[0], 240);
      expect(bpmByBar[1], 240);
      expect(bpmByBar[2], 250, reason: 'passaram 2 s: sobe no começo do compasso 2');
      expect(bpmByBar[4], 250, reason: 'só 1,92 s desde o último aumento');
      expect(bpmByBar[5], 260);
      expect(bpmByBar.values.reduce((a, c) => a > c ? a : c), 270, reason: 'nunca passa do teto');
      expect(bpmByBar.values.where((v) => v == 270).length, greaterThanOrEqualTo(2), reason: 'e fica no teto');
    });

    test('o relógio só começa a contar depois da contagem inicial', () {
      final e = MetronomeEngine(sr, cfg(trainer: const TempoTrainer(everySeconds: 2, stepBpm: 10, maxBpm: 300), countIn: 2));
      final b = bars(e, 8);
      for (final x in b.where((x) => x.bar < 0)) {
        expect(x.bpm, 240, reason: 'na contagem não acelera');
        expect(x.trainerLeft, isNull, reason: 'nem mostra contagem regressiva');
      }
      expect(b.firstWhere((x) => x.bar == 0).trainerLeft, closeTo(2.0, 0.05), reason: 'começa a contar 2 s a partir do compasso 0');
    });

    test('quanto falta para o próximo aumento diminui e a tela é avisada do teto', () {
      final e = MetronomeEngine(sr, cfg(trainer: const TempoTrainer(everySeconds: 3, stepBpm: 10, maxBpm: 250)));
      final b = bars(e, 12);
      expect(b[0].trainerByTime, isTrue);
      expect(b[0].trainerLeft, closeTo(3.0, 0.05));
      expect(b[1].trainerLeft, closeTo(2.0, 0.05));
      expect(b[2].trainerLeft, closeTo(1.0, 0.05));
      expect(b.where((x) => x.trainerAtMax).isNotEmpty, isTrue);
      for (final x in b.where((x) => x.trainerAtMax)) {
        expect(x.trainerLeft, isNull);
        expect(x.bpm, 250);
      }
    });
  });

  group('acelerar aos poucos: por compassos (como sempre)', () {
    test('sobe a cada N compassos e conta os compassos que faltam', () {
      final e = MetronomeEngine(sr, cfg(bpm: 240, trainer: const TempoTrainer(everyBars: 4, stepBpm: 10, maxBpm: 300)));
      final b = bars(e, 12);
      final byBar = {for (final x in b) x.bar: x};
      expect(byBar[3]!.bpm, 240);
      expect(byBar[4]!.bpm, 250, reason: 'passaram 4 compassos');
      expect([for (var i = 0; i < 4; i++) byBar[i]!.trainerLeft], [4, 3, 2, 1]);
      expect(byBar[0]!.trainerByTime, isFalse);
    });

    test('sem treino não há contagem regressiva', () {
      final b = bars(MetronomeEngine(sr, cfg()), 3);
      expect(b.every((x) => x.trainerLeft == null && !x.trainerAtMax), isTrue);
    });
  });

  group('mexer no treino com o metrônomo tocando', () {
    test('ligar o treino ou mudar o BPM recomeça a contagem do que está na tela', () {
      final e = MetronomeEngine(sr, cfg());
      bars(e, 3);
      e.update(cfg(trainer: const TempoTrainer(everySeconds: 2, stepBpm: 10, maxBpm: 300)));
      final b = bars(e, 6);
      expect(b.first.bpm, 240);
      expect(b.first.trainerLeft, inInclusiveRange(0.9, 2.05), reason: 'a contagem de 2 s recomeçou ao ligar (o primeiro compasso vem até 1 s depois)');
      expect(b.any((x) => x.bpm == 250), isTrue);
    });
  });

  group('textos e contas em linguagem simples', () {
    test('tempo em palavras', () {
      expect(secondsText(15), '15 segundos');
      expect(secondsText(1), '1 segundo');
      expect(secondsText(60), '1 minuto');
      expect(secondsText(120), '2 minutos');
      expect(secondsText(90), '1 min 30 s');
      expect(shortDuration(45), '45 s');
      expect(shortDuration(180), '3 min');
      expect(shortDuration(210), '3 min 30 s');
    });

    test('quanto tempo leva até o teto', () {
      // por tempo: (120 - 80) / 5 = 8 aumentos de 30 s
      expect(trainerSecondsToMax(const TempoTrainer(everySeconds: 30, stepBpm: 5, maxBpm: 120), 80, 4), 240);
      // por compassos: 4 compassos de 4 tempos a 120, depois a 130 (2 aumentos de 10, até 140)
      expect(trainerSecondsToMax(const TempoTrainer(everyBars: 4, stepBpm: 10, maxBpm: 140), 120, 4), 15);
      expect(trainerSecondsToMax(const TempoTrainer(everySeconds: 30, stepBpm: 5, maxBpm: 80), 80, 4), isNull, reason: 'já está no teto');
    });

    test('o resumo em uma frase', () {
      expect(trainerSummary(const TempoTrainer(everySeconds: 30, stepBpm: 5, maxBpm: 120), 80, 4),
          'Começa em 80 BPM. A cada 30 segundos sobe 5 BPM, até 120 BPM. Chega lá em cerca de 4 min.');
      expect(trainerSummary(const TempoTrainer(everyBars: 1, stepBpm: 2, maxBpm: 100), 90, 4), contains('A cada 1 compasso sobe 2 BPM'));
      expect(trainerSummary(const TempoTrainer(everySeconds: 30, stepBpm: 5, maxBpm: 80), 100, 4), contains('Aumente o teto'));
    });

    test('o que aparece enquanto toca', () {
      expect(trainerLiveText(atMax: true, byTime: true, left: null, stepBpm: 5), 'Chegou ao teto');
      expect(trainerLiveText(atMax: false, byTime: true, left: 12.3, stepBpm: 5), '+5 BPM em 13 s');
      expect(trainerLiveText(atMax: false, byTime: true, left: 0.4, stepBpm: 5), '+5 BPM agora');
      expect(trainerLiveText(atMax: false, byTime: false, left: 3, stepBpm: 5), '+5 BPM em 3 compassos');
      expect(trainerLiveText(atMax: false, byTime: false, left: 1, stepBpm: 5), '+5 BPM no próximo compasso');
      expect(trainerLiveText(atMax: false, byTime: false, left: null, stepBpm: 5), contains('contagem inicial'));
    });

    test('as opções prontas são crescentes e cabem no limite do metrônomo', () {
      for (final l in [kTrainerBarsOptions, kTrainerSecondsOptions, kTrainerStepOptions, kTrainerUpOptions]) {
        final sorted = [...l]..sort();
        expect(l, sorted);
      }
      expect(kTrainerMinBpm, lessThan(kTrainerMaxBpm));
    });

    test('igualdade e cópia do treino', () {
      const a = TempoTrainer(everySeconds: 30, stepBpm: 5, maxBpm: 120);
      expect(a == a.copyWith(), isTrue);
      expect(a.copyWith(stepBpm: 2) == a, isFalse);
      expect(a.byTime, isTrue);
      expect(const TempoTrainer().byTime, isFalse);
    });
  });
}
