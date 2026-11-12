import 'agenda.dart';

/// Falta do aluno a uma aula, registrada pelo professor (só neste aparelho; faz parte da ficha do aluno).
/// [noShow]: faltou sem avisar. [notified]: avisou que não vem.
enum AbsenceKind { noShow, notified }

class Absence {
  /// Início da aula perdida (ms desde 1970). Sem aula marcada, o início do dia.
  final int lessonMs;
  final AbsenceKind kind;

  /// Quando o professor registrou.
  final int recordedMs;
  const Absence({required this.lessonMs, required this.kind, required this.recordedMs});

  Map<String, dynamic> toJson() => {'l': lessonMs, 'k': kind == AbsenceKind.notified ? 'n' : 'f', 'r': recordedMs};

  static Absence? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final l = (m['l'] as num).toInt();
      if (l < 1577836800000 || l > 4102444800000) return null;
      return Absence(
        lessonMs: l,
        kind: m['k'] == 'n' ? AbsenceKind.notified : AbsenceKind.noShow,
        recordedMs: ((m['r'] as num?)?.toInt() ?? l).clamp(0, 4102444800000),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Quantas faltas guardar por aluno (as mais recentes).
const int kMaxAbsences = 200;

/// Registra [a] na lista [list] (mais recente primeiro). Se já existe uma falta daquela mesma aula, ela é trocada
/// (corrigir "faltou" para "avisou" não conta duas vezes). Devolve a lista nova.
List<Absence> addAbsence(List<Absence> list, Absence a) {
  final out = [a, ...list.where((x) => x.lessonMs != a.lessonMs)];
  out.sort((x, y) => y.lessonMs.compareTo(x.lessonMs));
  return out.length > kMaxAbsences ? out.sublist(0, kMaxAbsences) : out;
}

/// A aula "do momento" do aluno: a de [slots] mais perto de [nowMs] entre 3 h atrás e 12 h à frente
/// (é a que o professor está prestes a dar ou acabou de começar). Null se não há nenhuma.
SlotOccurrence? lessonForAbsence(Iterable<ClassSlot> slots, int nowMs) {
  final near = agendaBetween(slots, nowMs - 180 * kMsMinute, nowMs + 720 * kMsMinute);
  if (near.isEmpty) return null;
  near.sort((a, b) => (a.startMs - nowMs).abs().compareTo((b.startMs - nowMs).abs()));
  return near.first;
}

/// Quantas faltas há em [list] desde [sinceMs] (padrão: todas).
int absencesSince(Iterable<Absence> list, {int sinceMs = 0}) => list.where((a) => a.lessonMs >= sinceMs).length;
