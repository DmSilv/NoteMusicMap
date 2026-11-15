/// Dias seguidos de estudo (com perdão de 1 dia) e o resumo da semana. Dart puro: o app passa o mapa
/// "dia (AAAA-MM-DD) -> segundos estudados" e a data de hoje; aqui sai o que mostrar.
library;

/// Segundos mínimos num dia para ele contar como "dia de estudo".
const double kStudyDayMinSeconds = 60;

/// Chave do dia, no mesmo formato do app (AAAA-MM-DD).
String studyDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Resultado dos dias seguidos: [days] dias estudados na sequência e se um dia de folga foi perdoado nela.
class StudyStreak {
  final int days;
  final bool forgave;
  const StudyStreak(this.days, this.forgave);
}

/// Dias seguidos até hoje. Regras:
/// - hoje ainda pode estar zerado (o dia não acabou): não quebra nada;
/// - um único dia sem estudar **não quebra** a sequência (perdão de 1 dia), desde que o dia anterior a ele tenha sido estudado;
/// - dois dias sem estudar seguidos quebram;
/// - o perdão vale uma vez a cada 7 dias (depois de perdoar, a pessoa precisa de mais 6 dias para ter outro).
/// Só os dias estudados entram na conta (o dia perdoado não soma).
StudyStreak studyStreak(Map<String, double> secs, DateTime today) {
  bool studied(int back) => (secs[studyDayKey(today.subtract(Duration(days: back)))] ?? 0) >= kStudyDayMinSeconds;
  var days = 0;
  var forgave = false;
  int? lastForgiven; // índice (dias atrás) do último perdão
  for (var i = 0; i <= 800; i++) {
    if (studied(i)) {
      days++;
      continue;
    }
    if (i == 0) continue; // hoje ainda pode estudar
    // dia vazio: perdoa se o seguinte (mais antigo) foi estudado e o último perdão já passou de 6 dias
    final canForgive = studied(i + 1) && (lastForgiven == null || i - lastForgiven >= 7);
    if (!canForgive) break;
    lastForgiven = i;
    forgave = true;
  }
  return StudyStreak(days, forgave);
}

/// Resumo dos últimos 7 dias (incluindo hoje) e comparação com os 7 dias antes deles.
class WeekSummary {
  final int minutes; // total de minutos nos 7 dias
  final int previousMinutes; // total nos 7 dias anteriores
  final int daysStudied; // dias com pelo menos 1 min
  final int goalDays; // dias que bateram a meta
  final int bestDayMinutes;
  const WeekSummary(this.minutes, this.previousMinutes, this.daysStudied, this.goalDays, this.bestDayMinutes);

  /// Diferença em minutos para a semana anterior (positiva = estudou mais).
  int get delta => minutes - previousMinutes;

  /// A semana está vazia?
  bool get empty => minutes == 0 && previousMinutes == 0;
}

WeekSummary weekSummary(Map<String, double> secs, DateTime today, double goalMinutes) {
  double dayMin(int back) => (secs[studyDayKey(today.subtract(Duration(days: back)))] ?? 0) / 60;
  var total = 0.0, prev = 0.0, best = 0.0;
  var studiedDays = 0, goalDays = 0;
  for (var i = 0; i < 7; i++) {
    final m = dayMin(i);
    total += m;
    if (m >= 1) studiedDays++;
    if (m >= goalMinutes) goalDays++;
    if (m > best) best = m;
    prev += dayMin(i + 7);
  }
  return WeekSummary(total.round(), prev.round(), studiedDays, goalDays, best.round());
}
