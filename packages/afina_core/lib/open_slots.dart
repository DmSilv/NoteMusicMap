/// Horários disponíveis do professor e o aluno que "pega" um deles. Dart puro e testável.
///
/// Um horário disponível usa o mesmo formato de [ClassSlot] (data, duração, semanal ou avulso).
/// Quando o aluno pega um, o servidor o transforma numa aula marcada com esse aluno: o primeiro
/// que pega leva, sem aprovação. O professor continua podendo mover ou cancelar depois.
library;

import 'agenda.dart';

const int kMaxOpenSlots = 100; // horários disponíveis por professor
const int kMaxPicksPerStudent = 12; // aulas marcadas por um aluno com o mesmo professor
const int kPickLeadMinutes = 60; // antecedência mínima para pegar um horário

/// Por que um horário não pode ser criado ou pego.
enum SlotProblem { canceled, past, tooSoon, conflict, limit }

String slotProblemText(SlotProblem p) => switch (p) {
      SlotProblem.canceled => 'Este horário foi cancelado.',
      SlotProblem.past => 'Este horário já passou.',
      SlotProblem.tooSoon => 'Falta menos de $kPickLeadMinutes min para este horário: peça direto ao professor.',
      SlotProblem.conflict => 'Este horário bate com outra aula marcada.',
      SlotProblem.limit => 'Limite de horários atingido.',
    };

/// PROFESSOR cria um horário disponível: não pode estar no passado nem bater com outro horário
/// disponível ou com uma aula já marcada. Null = pode.
SlotProblem? checkNewOpenSlot(ClassSlot candidate,
    {required Iterable<ClassSlot> open, required Iterable<ClassSlot> classes, required int nowMs}) {
  if (candidate.canceled) return SlotProblem.canceled;
  if (candidate.nextStart(nowMs) == null) return SlotProblem.past;
  if (open.where((o) => !o.canceled && o.id != candidate.id).length >= kMaxOpenSlots) return SlotProblem.limit;
  if (findConflict(candidate, [...open, ...classes], nowMs) != null) return SlotProblem.conflict;
  return null;
}

/// ALUNO pega [openSlot]: confere o horário, a antecedência, o choque com as aulas do professor
/// ([teacherClasses]) e o limite de aulas deste aluno com ele ([studentUpcoming]). Null = pode.
SlotProblem? checkPick(ClassSlot openSlot,
    {required Iterable<ClassSlot> teacherClasses, required int studentUpcoming, required int nowMs}) {
  if (openSlot.canceled) return SlotProblem.canceled;
  if (openSlot.nextStart(nowMs) == null) return SlotProblem.past;
  if (openSlot.nextStart(nowMs + kPickLeadMinutes * kMsMinute) == null) return SlotProblem.tooSoon;
  if (studentUpcoming >= kMaxPicksPerStudent) return SlotProblem.limit;
  if (findConflict(openSlot, teacherClasses, nowMs) != null) return SlotProblem.conflict;
  return null;
}

/// Os horários que o aluno ainda pode pegar, do mais próximo para o mais distante.
List<ClassSlot> pickableSlots(Iterable<ClassSlot> open,
    {Iterable<ClassSlot> teacherClasses = const [], required int nowMs}) {
  final out = [
    for (final o in open)
      if (checkPick(o, teacherClasses: teacherClasses, studentUpcoming: 0, nowMs: nowMs) == null) o
  ];
  out.sort((a, b) => a.nextStart(nowMs)!.compareTo(b.nextStart(nowMs)!));
  return out;
}

/// A aula marcada que nasce quando [studentCode] pega [open] (mesmo dia, hora e duração).
ClassSlot classFromOpen(ClassSlot open, {required String studentCode, required String id, required int nowMs}) =>
    ClassSlot(
      id: id,
      studentCode: studentCode,
      startMs: open.startMs,
      durationMin: open.durationMin,
      weekly: open.weekly,
      skipped: open.skipped,
      note: open.note,
      updatedMs: nowMs,
      pending: false,
    );
