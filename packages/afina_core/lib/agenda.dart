/// Agenda de aulas: o professor marca aulas com os alunos (uma vez ou toda semana) e o
/// aluno vê as suas. Dart puro e testável: o relógio é sempre passado de fora.
///
/// A aula que se repete toda semana é UMA regra só (não uma linha por semana): barata de
/// guardar e de enviar. As datas são calculadas a partir da primeira (de 7 em 7 dias).
library;

import 'identity.dart' show formatShareCode;
import 'input_guard.dart';

const int kMsMinute = 60 * 1000;
const int kMsDay = 24 * 60 * kMsMinute;
const int kMsWeek = 7 * kMsDay;

/// Aula online (recurso liberado por chave): '' = não definido (app antigo ou recurso desligado), 'p' = presencial, 'o' = online.
const String kModeNone = '';
const String kModeInPerson = 'p';
const String kModeOnline = 'o';
const int kMaxMeetLink = 300;

/// Link de sala online aceito (mesma regra do servidor): só https, sem usuário e senha, sem espaços nem
/// aspas, com um domínio de verdade. Devolve o endereço normalizado ou null.
String? meetingUrl(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty || s.length > kMaxMeetLink || RegExp(r'[\s<>"\x27`\\]').hasMatch(s)) return null;
  final u = Uri.tryParse(s);
  if (u == null || u.scheme != 'https' || u.userInfo.isNotEmpty || !u.hasAuthority || !u.host.contains('.')) return null;
  return u.toString();
}

/// Sites de aula online conhecidos (abrem direto; os outros mostram o endereço antes de abrir).
const List<String> kKnownMeetHosts = ['meet.google.com', 'zoom.us', 'teams.microsoft.com', 'teams.live.com', 'whereby.com', 'meet.jit.si'];

/// Domínio do link (para mostrar ao usuário), ou '' se o link não vale.
String meetingHost(String? url) {
  final ok = meetingUrl(url);
  return ok == null ? '' : Uri.parse(ok).host.toLowerCase();
}

/// O link é de um site de aula online conhecido?
bool isKnownMeetingLink(String? url) {
  final h = meetingHost(url);
  return h.isNotEmpty && kKnownMeetHosts.any((k) => h == k || h.endsWith('.$k'));
}

/// Quanto tempo antes da aula chega o lembrete quando o professor não escolheu (padrão).
const int kReminderMinutes = 15;

/// Antecedências que o professor pode escolher para o lembrete de uma aula (minutos). 0 = sem lembrete; 1440 = um dia antes.
const List<int> kRemindOptions = [0, 5, 10, 15, 30, 60, 120, 1440];

/// Texto de uma antecedência: "15 minutos antes", "1 hora antes", "Sem lembrete".
String remindLabel(int minutes) {
  if (minutes <= 0) return 'Sem lembrete';
  if (minutes >= 1440 && minutes % 1440 == 0) {
    final d = minutes ~/ 1440;
    return d == 1 ? '1 dia antes' : '$d dias antes';
  }
  if (minutes >= 60 && minutes % 60 == 0) {
    final h = minutes ~/ 60;
    return h == 1 ? '1 hora antes' : '$h horas antes';
  }
  return '$minutes minutos antes';
}

const int kMinSlotMinutes = 15;
const int kMaxSlotMinutes = 240;
const int kMaxSlotSkips = 30; // ocorrências canceladas uma a uma, por regra
const int kMaxSlotsPerTeacher = 400;
const int kMaxSlotNote = 200;

/// Uma aula marcada (ou uma regra semanal de aulas).
class ClassSlot {
  /// [a-z0-9]{2,40}.
  final String id;

  /// PROFESSOR: código do aluno. ALUNO: vazio (quem manda é [teacherCode]).
  final String studentCode;

  /// ALUNO: código e nome de quem deu a aula marcada. PROFESSOR: vazio.
  final String teacherCode;
  final String teacherName;

  /// Início da primeira aula (ms desde 1970, UTC).
  final int startMs;
  final int durationMin;

  /// Se repete toda semana, no mesmo dia e hora.
  final bool weekly;

  /// Inícios (ms) de aulas desta regra que foram canceladas só naquele dia.
  final List<int> skipped;
  final String note;

  /// Versão (ms da última mudança): quem tem a mais nova vale.
  final int updatedMs;

  /// A regra toda foi cancelada (fica como marca para o outro lado saber).
  final bool canceled;

  /// Aula online: [kModeNone], [kModeInPerson] ou [kModeOnline].
  final String mode;

  /// Link da sala (só com [mode] online; pode ficar vazio e ser posto depois).
  final String link;

  /// Lembrete: quantos minutos antes avisar (um valor de [kRemindOptions]); null = o padrão ([kReminderMinutes]).
  final int? remindMin;

  /// PROFESSOR: ainda precisa ser enviada ao servidor (false = já foi, null = não se aplica).
  final bool? pending;

  const ClassSlot({
    required this.id,
    this.studentCode = '',
    this.teacherCode = '',
    this.teacherName = '',
    required this.startMs,
    this.durationMin = 60,
    this.weekly = false,
    this.skipped = const [],
    this.note = '',
    required this.updatedMs,
    this.canceled = false,
    this.pending,
    this.mode = kModeNone,
    this.link = '',
    this.remindMin,
  });

  /// Antecedência do lembrete desta aula, em minutos (0 = sem lembrete).
  int get remindLead => remindMin ?? kReminderMinutes;

  bool get online => mode == kModeOnline;
  bool get hasLink => online && link.isNotEmpty;

  int get endOffsetMs => durationMin * kMsMinute;

  ClassSlot copyWith({
    String? studentCode,
    int? startMs,
    int? durationMin,
    bool? weekly,
    List<int>? skipped,
    String? note,
    int? updatedMs,
    bool? canceled,
    Object? pending = _keep,
    String? mode,
    String? link,
    int? remindMin,
  }) =>
      ClassSlot(
        id: id,
        studentCode: studentCode ?? this.studentCode,
        teacherCode: teacherCode,
        teacherName: teacherName,
        startMs: startMs ?? this.startMs,
        durationMin: durationMin ?? this.durationMin,
        weekly: weekly ?? this.weekly,
        skipped: skipped ?? this.skipped,
        note: note ?? this.note,
        updatedMs: updatedMs ?? this.updatedMs,
        canceled: canceled ?? this.canceled,
        pending: identical(pending, _keep) ? this.pending : pending as bool?,
        mode: mode ?? this.mode,
        link: link ?? this.link,
        remindMin: remindMin ?? this.remindMin,
      );

  /// Início da primeira ocorrência que começa em [afterMs] ou depois e não foi cancelada.
  /// Null se não há (aula única já passada ou cancelada, ou regra cancelada).
  int? nextStart(int afterMs) {
    if (canceled) return null;
    if (!weekly) {
      return startMs >= afterMs && !skipped.contains(startMs) ? startMs : null;
    }
    var k = afterMs <= startMs ? 0 : ((afterMs - startMs) + kMsWeek - 1) ~/ kMsWeek;
    for (var i = 0; i < kMaxSlotSkips + 2; i++, k++) {
      final s = startMs + k * kMsWeek;
      if (!skipped.contains(s)) return s;
    }
    return null;
  }

  /// A aula que está acontecendo em [nowMs] (começou e ainda não acabou), se houver.
  int? ongoingStart(int nowMs) {
    if (canceled) return null;
    final s = weekly ? _lastStartAtOrBefore(nowMs) : (startMs <= nowMs ? startMs : null);
    if (s == null || skipped.contains(s)) return null;
    return nowMs < s + endOffsetMs ? s : null;
  }

  int? _lastStartAtOrBefore(int ms) {
    if (ms < startMs) return null;
    return startMs + ((ms - startMs) ~/ kMsWeek) * kMsWeek;
  }

  /// Inícios das aulas desta regra em [fromMs, toMs) (até [max]).
  List<int> occurrencesBetween(int fromMs, int toMs, {int max = 400}) {
    if (canceled || toMs <= fromMs) return const [];
    final out = <int>[];
    if (!weekly) {
      if (startMs >= fromMs && startMs < toMs && !skipped.contains(startMs)) out.add(startMs);
      return out;
    }
    var k = fromMs <= startMs ? 0 : ((fromMs - startMs) + kMsWeek - 1) ~/ kMsWeek;
    while (out.length < max) {
      final s = startMs + k * kMsWeek;
      if (s >= toMs) break;
      if (!skipped.contains(s)) out.add(s);
      k++;
    }
    return out;
  }

  /// Quando o lembrete da ocorrência que começa em [startOccurrenceMs] deve chegar ([minutes]: antecedência; padrão 15).
  static int reminderAt(int startOccurrenceMs, [int minutes = kReminderMinutes]) => startOccurrenceMs - minutes * kMsMinute;

  // ---------------- Disco e servidor ----------------
  /// Formato do servidor (e do aluno): sem os campos de controle do professor.
  Map<String, dynamic> toWire() => {
        'id': id,
        's': startMs,
        'd': durationMin,
        if (weekly) 'w': 1,
        if (skipped.isNotEmpty) 'x': skipped,
        if (note.isNotEmpty) 'n': note,
        'u': updatedMs,
        if (canceled) 'c': 1,
        if (mode != kModeNone) 'm': mode,
        if (mode == kModeOnline && link.isNotEmpty) 'l': link,
        if (remindMin != null) 'r': remindMin,
      };

  Map<String, dynamic> toJson() => {
        ...toWire(),
        if (studentCode.isNotEmpty) 'sc': studentCode,
        if (teacherCode.isNotEmpty) 'tc': teacherCode,
        if (teacherName.isNotEmpty) 'tn': teacherName,
        if (pending != null) 'p': pending,
      };

  static final _idRe = RegExp(r'^[a-z0-9]{2,40}$');

  /// Só aceita as antecedências permitidas; qualquer outra coisa vira "padrão" (null).
  static int? _remindFrom(Object? v) {
    final n = v is num ? v.toInt() : null;
    return n != null && kRemindOptions.contains(n) ? n : null;
  }

  /// Lê (do disco ou do servidor) limpando e limitando tudo; null se inválido.
  static ClassSlot? tryFrom(Object? j, {String teacherCode = '', String teacherName = ''}) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final id = '${m['id']}';
      if (!_idRe.hasMatch(id)) return null;
      final start = (m['s'] as num).toInt();
      if (start < 1577836800000 || start > 4102444800000) return null;
      final skipped = <int>[
        for (final x in ((m['x'] as List?) ?? const []).take(kMaxSlotSkips))
          if (x is num) x.toInt()
      ];
      final tc = teacherCode.isNotEmpty ? teacherCode : (formatShareCode((m['tc'] as String?) ?? '') ?? '');
      return ClassSlot(
        id: id,
        studentCode: formatShareCode((m['sc'] as String?) ?? '') ?? '',
        teacherCode: tc,
        teacherName: teacherName.isNotEmpty ? teacherName : cleanText(m['tn'] as String?, max: kMaxName),
        startMs: start,
        durationMin: ((m['d'] as num?)?.toInt() ?? 60).clamp(kMinSlotMinutes, kMaxSlotMinutes),
        weekly: m['w'] == 1 || m['w'] == true,
        skipped: skipped,
        note: cleanText(m['n'] as String?, max: kMaxSlotNote),
        updatedMs: ((m['u'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        canceled: m['c'] == 1 || m['c'] == true,
        pending: m['p'] is bool ? m['p'] as bool : null,
        mode: m['m'] == kModeOnline ? kModeOnline : (m['m'] == kModeInPerson ? kModeInPerson : kModeNone),
        link: m['m'] == kModeOnline ? (meetingUrl(m['l'] as String?) ?? '') : '',
        remindMin: _remindFrom(m['r']),
      );
    } catch (_) {
      return null;
    }
  }
}

const Object _keep = Object();

/// Uma ocorrência concreta (para mostrar na agenda).
class SlotOccurrence {
  final ClassSlot slot;
  final int startMs;
  const SlotOccurrence(this.slot, this.startMs);

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startMs);
  DateTime get end => DateTime.fromMillisecondsSinceEpoch(startMs + slot.endOffsetMs);
}

/// As aulas de [slots] que começam em [fromMs, toMs), em ordem de horário.
List<SlotOccurrence> agendaBetween(Iterable<ClassSlot> slots, int fromMs, int toMs) {
  final out = <SlotOccurrence>[
    for (final s in slots)
      for (final t in s.occurrencesBetween(fromMs, toMs)) SlotOccurrence(s, t)
  ];
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return out;
}

/// As aulas de um dia (no relógio local).
List<SlotOccurrence> agendaDay(Iterable<ClassSlot> slots, DateTime day) {
  final from = DateTime(day.year, day.month, day.day);
  final to = DateTime(day.year, day.month, day.day + 1);
  return agendaBetween(slots, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch);
}

/// Segunda-feira da semana de [d] (às 00:00, relógio local).
DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Quantas aulas há em cada dia do mês de [month] (índice 1..31), para a visão mensal.
Map<int, int> agendaMonthCounts(Iterable<ClassSlot> slots, DateTime month) {
  final from = DateTime(month.year, month.month, 1);
  final to = DateTime(month.year, month.month + 1, 1);
  final counts = <int, int>{};
  for (final o in agendaBetween(slots, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch)) {
    counts[o.start.day] = (counts[o.start.day] ?? 0) + 1;
  }
  return counts;
}

/// A próxima aula (ou a que está em andamento) entre [slots], a partir de [nowMs].
SlotOccurrence? nextOccurrence(Iterable<ClassSlot> slots, int nowMs) {
  SlotOccurrence? best;
  for (final s in slots) {
    final on = s.ongoingStart(nowMs);
    final n = on ?? s.nextStart(nowMs);
    if (n == null) continue;
    if (best == null || n < best.startMs) best = SlotOccurrence(s, n);
  }
  return best;
}

/// Regra do professor: duas aulas dele não podem se sobrepor. Devolve a aula que conflita com
/// [candidate] (olhando [horizonDays] dias à frente de [nowMs]) ou null se está livre.
SlotOccurrence? findConflict(ClassSlot candidate, Iterable<ClassSlot> existing, int nowMs, {int horizonDays = 120}) {
  if (candidate.canceled) return null;
  final to = nowMs + horizonDays * kMsDay;
  final mine = candidate.occurrencesBetween(nowMs - kMsDay, to);
  if (mine.isEmpty) return null;
  for (final other in existing) {
    if (other.id == candidate.id || other.canceled) continue;
    for (final o in other.occurrencesBetween(nowMs - kMsDay, to)) {
      final oEnd = o + other.endOffsetMs;
      for (final m in mine) {
        if (m < oEnd && o < m + candidate.endOffsetMs) return SlotOccurrence(other, o);
      }
    }
  }
  return null;
}

// ---------------- Controle da agenda do professor: remarcar, trocar, pausar ----------------

/// Aulas canceladas de uma regra semanal guardam o início de cada data cancelada. Quando a regra muda de dia ou
/// de hora, essas datas precisam acompanhar a mudança (senão a aula cancelada "ressuscita"). Se só a primeira data
/// andou um número exato de semanas, as datas canceladas continuam as mesmas.
List<int> remapSkipped(int oldStartMs, int newStartMs, List<int> skipped) {
  if (skipped.isEmpty || oldStartMs == newStartMs) return skipped;
  var d = (newStartMs - oldStartMs) % kMsWeek; // sempre 0..semana
  if (d == 0) return skipped;
  if (d > kMsWeek ~/ 2) d -= kMsWeek;
  return [for (final x in skipped) x + d];
}

/// Resultado de um plano de mudanças na agenda: as aulas que mudam (ou nascem) e, se der errado, o motivo.
class SlotPlan {
  final List<ClassSlot> changed;
  final String? error;
  const SlotPlan(this.changed, {this.error});
  const SlotPlan.fail(String message)
      : changed = const [],
        error = message;
  bool get ok => error == null;
}

/// Remarca SÓ uma aula. Numa regra semanal, cancela aquela data e cria uma aula avulsa no horário novo; numa aula
/// avulsa, só muda o horário. [newId] é o id da aula avulsa criada.
SlotPlan planMoveOccurrence(ClassSlot slot, int occurrenceMs, int newStartMs, {required String newId, int? newDurationMin}) {
  if (slot.canceled) return const SlotPlan.fail('Esta aula já foi cancelada.');
  final dur = (newDurationMin ?? slot.durationMin).clamp(kMinSlotMinutes, kMaxSlotMinutes);
  if (!slot.weekly) {
    return SlotPlan([slot.copyWith(startMs: newStartMs, durationMin: dur, skipped: const [])]);
  }
  if (!slot.occurrencesBetween(occurrenceMs, occurrenceMs + 1).contains(occurrenceMs)) {
    return const SlotPlan.fail('Essa data não é uma aula desta regra.');
  }
  if (slot.skipped.length >= kMaxSlotSkips) return const SlotPlan.fail('Esta aula já tem muitas datas canceladas. Edite a regra.');
  return SlotPlan([
    slot.copyWith(skipped: [...slot.skipped, occurrenceMs]),
    ClassSlot(
      id: newId,
      studentCode: slot.studentCode,
      startMs: newStartMs,
      durationMin: dur,
      note: slot.note,
      updatedMs: 0,
      mode: slot.mode,
      link: slot.link,
      remindMin: slot.remindMin,
    ),
  ]);
}

/// Troca os horários de duas aulas (cada uma vai para o horário da outra; a duração de cada uma continua a sua).
/// Aulas de regra semanal viram avulsas só naquela data.
SlotPlan planSwap(SlotOccurrence a, SlotOccurrence b, {required String newIdA, required String newIdB}) {
  if (a.slot.id == b.slot.id) return const SlotPlan.fail('Escolha duas aulas diferentes.');
  if (a.slot.studentCode == b.slot.studentCode) return const SlotPlan.fail('As duas aulas são do mesmo aluno.');
  final pa = planMoveOccurrence(a.slot, a.startMs, b.startMs, newId: newIdA);
  final pb = planMoveOccurrence(b.slot, b.startMs, a.startMs, newId: newIdB);
  if (!pa.ok) return pa;
  if (!pb.ok) return pb;
  return SlotPlan([...pa.changed, ...pb.changed]);
}

/// Pausa as aulas que começam entre [fromMs] e [toMs] (férias, viagem): datas de regras semanais viram canceladas e
/// aulas avulsas do período são canceladas.
SlotPlan planPause(Iterable<ClassSlot> slots, int fromMs, int toMs) {
  if (toMs <= fromMs) return const SlotPlan.fail('A data final precisa ser depois da inicial.');
  if (toMs - fromMs > 120 * kMsDay) return const SlotPlan.fail('Pause no máximo 120 dias por vez.');
  final out = <ClassSlot>[];
  for (final s in slots) {
    if (s.canceled) continue;
    final hit = s.occurrencesBetween(fromMs, toMs);
    if (hit.isEmpty) continue;
    if (!s.weekly) {
      out.add(s.copyWith(canceled: true));
    } else {
      if (s.skipped.length + hit.length > kMaxSlotSkips) {
        return const SlotPlan.fail('Algumas aulas já têm muitas datas canceladas. Use um período menor.');
      }
      out.add(s.copyWith(skipped: [...s.skipped, ...hit]));
    }
  }
  return SlotPlan(out);
}

/// Confere se as mudanças de [plan] cabem na agenda [current] (ninguém sobrepõe ninguém e nada fica no passado).
/// Devolve o motivo ou null se pode aplicar. A conferência vale para o conjunto todo, de uma vez.
String? validatePlan(SlotPlan plan, List<ClassSlot> current, int nowMs, {String Function(String code)? nameOf}) {
  if (!plan.ok) return plan.error;
  if (plan.changed.isEmpty) return 'Nada para mudar.';
  final merged = <ClassSlot>[...current];
  for (final c in plan.changed) {
    final i = merged.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      merged[i] = c;
    } else {
      merged.add(c);
    }
  }
  for (final c in plan.changed) {
    if (c.canceled) continue;
    final old = current.where((x) => x.id == c.id).firstOrNull;
    if (!c.weekly && c.startMs < nowMs - 5 * kMsMinute && (old == null || old.startMs != c.startMs)) {
      return 'Esse horário já passou.';
    }
    final clash = findConflict(c, merged, nowMs);
    if (clash != null) {
      final who = nameOf?.call(clash.slot.studentCode) ?? 'outro aluno';
      return 'Choca com a aula de $who (${fmtSlotWhen(clash.start, DateTime.fromMillisecondsSinceEpoch(nowMs))}).';
    }
  }
  return null;
}

/// Novo id de aula marcada.
const _kDiasSemana = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];

/// 'Terça, 12/11 às 15:00 · 60 min' (aula avulsa) ou 'Toda terça às 15:00 · 60 min' (toda semana).
/// Usado nas telas e no aviso de sucesso, para dizerem sempre a mesma coisa.
String describeSlot(ClassSlot s) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = DateTime.fromMillisecondsSinceEpoch(s.startMs);
  final hm = '${two(d.hour)}:${two(d.minute)}';
  final day = _kDiasSemana[d.weekday - 1];
  final head = s.weekly ? 'Toda $day às $hm' : '${day[0].toUpperCase()}${day.substring(1)}, ${two(d.day)}/${two(d.month)} às $hm';
  return '$head · ${s.durationMin} min${s.online ? ' · online' : ''}';
}

String newSlotId(DateTime now) => 's${now.microsecondsSinceEpoch.toRadixString(36)}';

/// "terça, 15:00" / "hoje, 15:00" / "amanhã, 09:30".
String fmtSlotWhen(DateTime when, DateTime now) {
  const days = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final hh = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'hoje, $hh';
  if (diff == 1) return 'amanhã, $hh';
  final dd = when.day.toString().padLeft(2, '0'), mm = when.month.toString().padLeft(2, '0');
  return '${days[when.weekday - 1]}, $dd/$mm, $hh';
}
