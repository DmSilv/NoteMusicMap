/// Exporta aulas para o calendário do celular (arquivo .ics, padrão iCalendar). Dart puro e testável: nada vai ao servidor.
library;

import 'agenda.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Data e hora em UTC no formato do iCalendar: 20261124T160000Z.
String icsStamp(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}T${_two(d.hour)}${_two(d.minute)}${_two(d.second)}Z';
}

/// Texto de um campo: barra, ponto e vírgula, vírgula e quebras de linha precisam de escape.
String icsText(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll(RegExp(r'\r\n|\r|\n'), '\\n');

/// Linhas com mais de 75 bytes são "dobradas" (continuam na linha seguinte, começando com um espaço).
List<String> icsFold(String line) {
  final out = <String>[];
  var rest = line;
  var first = true;
  while (true) {
    final limit = first ? 75 : 74;
    if (rest.runes.length <= limit && rest.length <= limit) {
      out.add(first ? rest : ' $rest');
      break;
    }
    var cut = limit;
    // não corta no meio de um par de caracteres (emoji)
    if (cut < rest.length && rest.codeUnitAt(cut - 1) >= 0xD800 && rest.codeUnitAt(cut - 1) <= 0xDBFF) cut--;
    out.add(first ? rest.substring(0, cut) : ' ${rest.substring(0, cut)}');
    rest = rest.substring(cut);
    first = false;
  }
  return out;
}

/// Monta o arquivo .ics com as aulas de [slots] que ainda não foram canceladas.
/// [titleOf] dá o título de cada aula (ex.: "Aula com Ana"); a descrição leva a observação e o link da aula online.
String buildIcs(Iterable<ClassSlot> slots, {required String Function(ClassSlot) titleOf, required int nowMs}) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Notemusic//Agenda//PT',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
  ];
  for (final s in slots) {
    if (s.canceled) continue;
    final first = s.weekly ? s.startMs : s.nextStart(nowMs - kMsDay) ?? s.startMs;
    if (!s.weekly && s.nextStart(nowMs - kMsDay) == null) continue; // aula única que já passou ou foi cancelada
    lines.add('BEGIN:VEVENT');
    lines.add('UID:${s.id}@notemusic');
    lines.add('DTSTAMP:${icsStamp(s.updatedMs > 0 ? s.updatedMs : nowMs)}');
    lines.add('DTSTART:${icsStamp(first)}');
    lines.add('DTEND:${icsStamp(first + s.endOffsetMs)}');
    if (s.weekly) {
      final until = s.endMs != null ? ';UNTIL=${icsStamp(s.endMs! + s.endOffsetMs)}' : '';
      lines.add('RRULE:FREQ=WEEKLY$until');
      for (final x in s.skipped) {
        lines.add('EXDATE:${icsStamp(x)}');
      }
    }
    lines.add('SUMMARY:${icsText(titleOf(s))}');
    final desc = <String>[if (s.note.isNotEmpty) s.note, if (s.hasLink) s.link];
    if (desc.isNotEmpty) lines.add('DESCRIPTION:${icsText(desc.join('\n'))}');
    if (s.hasLink) lines.add('LOCATION:${icsText(s.link)}');
    final lead = s.remindLead;
    if (lead > 0) {
      lines.add('BEGIN:VALARM');
      lines.add('ACTION:DISPLAY');
      lines.add('DESCRIPTION:${icsText(titleOf(s))}');
      lines.add('TRIGGER:-PT${lead}M');
      lines.add('END:VALARM');
    }
    lines.add('END:VEVENT');
  }
  lines.add('END:VCALENDAR');
  return '${[for (final l in lines) ...icsFold(l)].join('\r\n')}\r\n';
}
