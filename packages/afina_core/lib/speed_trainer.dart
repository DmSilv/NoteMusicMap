import 'metronome_engine.dart';
import 'i18n.dart';

/// Ajudantes do "Acelerar aos poucos": opções prontas, textos em linguagem simples e o tempo até o teto.
/// Dart puro (sem Flutter), testado em test/speed_trainer_test.dart.

/// A cada quantos compassos aumentar.
const List<int> kTrainerBarsOptions = [2, 4, 8, 16];

/// A cada quantos segundos aumentar.
const List<int> kTrainerSecondsOptions = [15, 30, 60, 120];

/// Quanto aumentar (BPM).
const List<int> kTrainerStepOptions = [1, 2, 5, 10];

/// Quanto acima do BPM de partida fica o teto, nos atalhos.
const List<int> kTrainerUpOptions = [20, 40, 60];

const double kTrainerMinBpm = 40;
const double kTrainerMaxBpm = 320;

/// "30 segundos", "1 minuto", "2 minutos", "1 min 30 s".
String secondsText(int s) {
  if (s < 60) return tr('{0} segundo{1}', [s, s == 1 ? '' : 's']);
  final m = s ~/ 60, r = s % 60;
  if (r == 0) return m == 1 ? tr('1 minuto') : tr('{0} minutos', [m]);
  return tr('{0} min {1} s', [m, r]);
}

/// Duração curta para o resumo: "45 s", "3 min", "3 min 30 s".
String shortDuration(int totalSeconds) {
  if (totalSeconds < 60) return '$totalSeconds s';
  final m = totalSeconds ~/ 60, r = totalSeconds % 60;
  return r == 0 ? '$m min' : tr('{0} min {1} s', [m, r]);
}

/// "a cada 30 segundos" ou "a cada 4 compassos".
String trainerEveryText(TempoTrainer t) => t.byTime ? tr('a cada {0}', [secondsText(t.everySeconds)]) : tr('a cada {0} compasso{1}', [t.everyBars, t.everyBars == 1 ? '' : 's']);

/// Quanto tempo, aproximadamente, leva do BPM de partida até o teto (em segundos). Null se já está no teto.
int? trainerSecondsToMax(TempoTrainer t, double startBpm, int beatsPerBar) {
  if (startBpm >= t.maxBpm || t.stepBpm <= 0) return null;
  final steps = ((t.maxBpm - startBpm) / t.stepBpm).ceil();
  if (t.byTime) return steps * t.everySeconds;
  var bpm = startBpm, total = 0.0;
  for (var i = 0; i < steps; i++) {
    total += t.everyBars * beatsPerBar * 60 / bpm;
    bpm = bpm + t.stepBpm > t.maxBpm ? t.maxBpm : bpm + t.stepBpm;
  }
  return total.round();
}

/// O resumo em uma frase: "Começa em 80 BPM. A cada 30 segundos sobe 5 BPM, até 120 BPM. Chega lá em cerca de 4 min."
String trainerSummary(TempoTrainer t, double startBpm, int beatsPerBar) {
  final start = startBpm.round(), up = t.stepBpm.round(), max = t.maxBpm.round();
  if (startBpm >= t.maxBpm) return tr('O teto ({0} BPM) é menor ou igual ao BPM de partida ({1}). Aumente o teto.', [max, start]);
  final secs = trainerSecondsToMax(t, startBpm, beatsPerBar);
  return tr('Começa em {0} BPM. {1}{2} sobe {3} BPM, até {4} BPM.{5}', [start, trainerEveryText(t)[0].toUpperCase(), trainerEveryText(t).substring(1), up, max, secs == null ? '' : tr(' Chega lá em cerca de {0}.', [shortDuration(secs)])]);
}

/// O que a tela mostra enquanto toca: "Próximo aumento em 12 s", "no próximo compasso", "Chegou ao teto".
String trainerLiveText({required bool atMax, required bool byTime, double? left, required double stepBpm}) {
  if (atMax) return tr('Chegou ao teto');
  if (left == null) return tr('Começa a contar depois da contagem inicial');
  final up = tr('+{0} BPM', [stepBpm.round()]);
  if (byTime) {
    final s = left.ceil();
    return s <= 1 ? tr('{0} agora', [up]) : tr('{0} em {1} s', [up, s]);
  }
  final b = left.round();
  return b <= 1 ? tr('{0} no próximo compasso', [up]) : tr('{0} em {1} compassos', [up, b]);
}
