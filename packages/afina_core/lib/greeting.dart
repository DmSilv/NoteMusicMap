/// Saudação conforme a hora do dia (relógio local do aparelho).
///
/// 5h às 11h59: "Bom dia" · 12h às 17h59: "Boa tarde" · o resto: "Boa noite".
enum DayPart { morning, afternoon, night }

DayPart dayPartFor(int hour) {
  final h = hour % 24;
  if (h >= 5 && h < 12) return DayPart.morning;
  if (h >= 12 && h < 18) return DayPart.afternoon;
  return DayPart.night;
}

String greetingFor(int hour) => switch (dayPartFor(hour)) {
      DayPart.morning => 'Bom dia',
      DayPart.afternoon => 'Boa tarde',
      DayPart.night => 'Boa noite',
    };

/// "Boa tarde, Daniel" (ou só "Boa tarde" sem apelido). Usa só a primeira palavra
/// do nome, para a saudação ficar curta.
String greetingLine(int hour, String? name) {
  var first = (name ?? '').trim().split(RegExp(r'\s+')).first;
  if (first.isNotEmpty) first = first[0].toUpperCase() + first.substring(1);
  final g = greetingFor(hour);
  return first.isEmpty ? g : '$g, $first';
}
