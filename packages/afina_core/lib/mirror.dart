/// Espelho da conta entre aparelhos: as regras de COMO juntar o que dois aparelhos da mesma conta guardam, sem perder nada.
/// O servidor só guarda seções de texto (api/_lib/mirror.js); aqui está a parte que entende o conteúdo. Dart puro e testável.
///
/// Seções: `S:código` ou `S:i:id` (um aluno, com tarefas, observações, aulas e faltas), "AG" (agenda do professor),
/// "OS" (horários livres), "ME" (métodos e lições), "PR" (ajustes da conta) e "SE" (histórico de estudo).
library;

import 'dart:convert';

import 'agenda.dart';
import 'identity.dart' show isDefaultStudentName;
import 'input_guard.dart';
import 'lesson.dart';
import 'methods.dart';
import 'practice_coach.dart';
import 'teacher.dart';
import 'teaching.dart';

// ---------------- identificação e resumo ----------------

/// Nome da seção de um aluno: pelo código (igual nos dois aparelhos) ou, sem código, pelo id.
String studentSection(Student s) => s.code != null && s.code!.isNotEmpty ? 'S:${s.code}' : 'S:i:${s.id}';

/// Resumo curto de um texto (FNV-1a de 32 bits + tamanho): serve para saber se uma seção mudou desde a última troca.
String mirrorHash(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return '${h.toRadixString(36)}.${s.length}';
}

/// Aluno ainda "de fábrica": só o vínculo, sem nada que a pessoa tenha escrito, passado ou marcado. Não vale a pena enviar
/// (o outro aparelho pode ter os dados de verdade) e, se o outro já tem, este lado simplesmente adota.
bool isPristineStudent(Student s) =>
    s.tasks.isEmpty &&
    s.notes.isEmpty &&
    s.sessions.isEmpty &&
    s.lessons.isEmpty &&
    s.absences.isEmpty &&
    s.photo == null &&
    s.instrument == null &&
    (s.code != null && (s.name == (s.remoteName ?? '') || isDefaultStudentName(s.name, s.code!)));

// ---------------- aluno ----------------

/// O aluno como seção. Fora ficam o que depende de cada aparelho: o estado do vínculo e o apelido que o aluno registrou
/// (cada aparelho os recebe do servidor). Cabe em até [kMaxSectionChars].
String studentToSection(Student s) {
  final j = s.toJson()
    ..remove('lk')
    ..remove('rn');
  return jsonEncode(j);
}

/// Limite de uma seção no servidor (api/_lib/mirror.js, 120 mil caracteres): acima disso o aluno não é espelhado inteiro.
const int kMaxSectionChars = 120000;

Student? studentFromSection(String data) {
  try {
    final j = jsonDecode(data);
    if (j is! Map) return null;
    return Student.tryFrom(j.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

Assignment _mergeTask(Assignment a, Assignment b, bool preferB) {
  final base = preferB ? b : a;
  final other = preferB ? a : b;
  return Assignment(
    id: base.id,
    title: base.title,
    kind: base.kind,
    subject: base.subject,
    detail: base.detail,
    note: base.note,
    scaleTypeIndex: base.scaleTypeIndex,
    tonicPc: base.tonicPc,
    octaves: base.octaves,
    goal: base.goal,
    done: a.done || b.done, // validada em qualquer aparelho vale
    created: a.created.isBefore(b.created) ? a.created : b.created,
    sent: (a.sent == true || b.sent == true) ? true : base.sent ?? other.sent,
    claimedAt: base.claimedAt ?? other.claimedAt,
    reviewed: base.reviewed,
  );
}

/// Junta [other] em [into] (no lugar), sem perder nada: tarefas, observações, sessões, aulas e faltas somam;
/// o que for escolha única (nome, instrumento, foto) fica com [preferOther] ou, se faltar, com o outro lado.
/// O id, o estado do vínculo e o apelido do aluno ficam como estão neste aparelho.
void mergeStudentFrom(Student into, Student other, {required bool preferOther}) {
  if (preferOther) {
    if (other.name.trim().isNotEmpty) into.name = other.name;
    into.instrument = other.instrument ?? into.instrument;
    into.photo = other.photo ?? into.photo;
  } else {
    into.instrument ??= other.instrument;
    into.photo ??= other.photo;
  }
  into.code ??= other.code;

  final tasks = {for (final t in into.tasks) t.id: t};
  for (final t in other.tasks) {
    final cur = tasks[t.id];
    tasks[t.id] = cur == null ? t : _mergeTask(cur, t, preferOther);
  }
  into.tasks
    ..clear()
    ..addAll(tasks.values.toList()..sort((a, b) => a.created.compareTo(b.created)));

  final noteKeys = {for (final n in into.notes) '${n.date.toIso8601String()}|${n.text}'};
  for (final n in other.notes) {
    if (noteKeys.add('${n.date.toIso8601String()}|${n.text}')) into.notes.add(n);
  }
  into.notes.sort((a, b) => b.date.compareTo(a.date));

  mergeSessions(into.sessions, other.sessions);

  final lessons = {for (final l in into.lessons) l.id: l};
  for (final l in other.lessons) {
    final cur = lessons[l.id];
    if (cur == null) {
      lessons[l.id] = l;
    } else if (l.sent == true && cur.sent != true) {
      cur.sent = true;
      cur.wire = null;
    }
  }
  into.lessons
    ..clear()
    ..addAll((lessons.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt))).take(kMaxLessonKept));

  final abs = {for (final a in into.absences) a.lessonMs: a};
  for (final a in other.absences) {
    abs.putIfAbsent(a.lessonMs, () => a);
  }
  into.absences = abs.values.toList()..sort((a, b) => b.lessonMs.compareTo(a.lessonMs));
}

// ---------------- agenda, horários livres, métodos, ajustes, histórico ----------------

/// Aulas e horários: por id, vale a versão mais nova ([ClassSlot.updatedMs]); empate fica com a daqui.
List<ClassSlot> mergeSlotLists(List<ClassSlot> local, List<ClassSlot> remote) {
  final byId = {for (final s in local) s.id: s};
  for (final r in remote) {
    final cur = byId[r.id];
    if (cur == null || r.updatedMs > cur.updatedMs) byId[r.id] = cur == null ? r : r.copyWith(pending: cur.pending);
  }
  return byId.values.toList();
}

/// As aulas como seção. O "falta enviar" é só deste aparelho e não vai junto.
String slotsToSection(List<ClassSlot> slots) => jsonEncode([for (final s in slots) s.copyWith(pending: null).toJson()]);

List<ClassSlot> slotsFromSection(String data) {
  try {
    final j = jsonDecode(data);
    if (j is! List) return const [];
    return [for (final x in j.take(400)) ?ClassSlot.tryFrom(x)];
  } catch (_) {
    return const [];
  }
}

String methodsToSection(List<MethodEntry> lib) => jsonEncode([for (final m in lib) m.toJson()]);

List<MethodEntry> methodsFromSection(String data) {
  try {
    final j = jsonDecode(data);
    if (j is! List) return const [];
    return [for (final x in j.take(kMaxMethods)) ?MethodEntry.tryFrom(x)];
  } catch (_) {
    return const [];
  }
}

/// Ajustes da conta que valem em todos os aparelhos.
class AccountPrefs {
  final List<String> teachInstruments;
  final bool teacherMode;
  const AccountPrefs({this.teachInstruments = const [], this.teacherMode = false});

  bool get isDefault => teachInstruments.isEmpty && !teacherMode;

  String toSection() => jsonEncode({'ti': teachInstruments, if (teacherMode) 'tm': true});

  static AccountPrefs fromSection(String data) {
    try {
      final j = (jsonDecode(data) as Map).cast<String, dynamic>();
      return AccountPrefs(teachInstruments: cleanTeachingIds(j['ti'] as List?), teacherMode: j['tm'] == true);
    } catch (_) {
      return const AccountPrefs();
    }
  }

  /// Soma: os instrumentos dos dois e o modo professor se algum dos dois tem.
  AccountPrefs merge(AccountPrefs o) => AccountPrefs(
      teachInstruments: cleanTeachingIds([...teachInstruments, ...o.teachInstruments]), teacherMode: teacherMode || o.teacherMode);
}

/// O histórico de estudo (as últimas [keep] sessões) como seção.
String sessionsToSection(List<SessionRecord> sessions, {int keep = 300}) =>
    jsonEncode([for (final s in (sessions.length > keep ? sessions.sublist(0, keep) : sessions)) s.toJson()]);

List<SessionRecord> sessionsFromSection(String data) {
  try {
    final j = jsonDecode(data);
    if (j is! List) return const [];
    return [for (final x in j.take(1000)) ?SessionRecord.tryFromJson((x as Map).cast<String, dynamic>())];
  } catch (_) {
    return const [];
  }
}

// ---------------- o que fazer a cada rodada ----------------

/// Uma seção deste aparelho: o texto, o resumo dele e se está "de fábrica" (nada a perder se o outro aparelho tem dados).
class LocalSection {
  final String data;
  final String hash;
  final bool pristine;
  LocalSection(this.data, {this.pristine = false}) : hash = mirrorHash(data);
}

/// O que se sabe de uma seção na última troca: o resumo do que foi enviado/recebido e a versão do servidor.
class MirrorMeta {
  final String hash;
  final int u;
  const MirrorMeta(this.hash, this.u);
}

/// O que o servidor tem de uma seção: versão e se foi apagada.
class RemoteSection {
  final int u;
  final bool deleted;
  const RemoteSection(this.u, {this.deleted = false});
}

enum MirrorOp { push, pull, merge, deleteRemote, deleteLocal }

/// Decide, para cada seção, o que fazer. [merge] = baixar, juntar e enviar o resultado (os dois lados mudaram).
Map<String, MirrorOp> planMirror({
  required Map<String, LocalSection> local,
  required Map<String, MirrorMeta> meta,
  required Map<String, RemoteSection> remote,
}) {
  final ops = <String, MirrorOp>{};
  for (final e in local.entries) {
    final sec = e.key, l = e.value;
    final m = meta[sec], r = remote[sec];
    final dirty = m == null ? !l.pristine : m.hash != l.hash;
    if (r == null) {
      // O servidor não tem: envia se há algo a enviar (de fábrica e nunca enviado fica quieto).
      if (dirty || (m != null && !l.pristine)) ops[sec] = MirrorOp.push;
      continue;
    }
    final known = m?.u ?? 0;
    if (r.deleted) {
      if (m != null && !dirty) {
        ops[sec] = MirrorOp.deleteLocal; // o outro aparelho apagou e aqui nada mudou
      } else if (dirty) {
        ops[sec] = MirrorOp.push; // mexeram aqui depois: a edição vale e a seção volta
      }
      continue;
    }
    if (!dirty) {
      if (r.u > known) ops[sec] = MirrorOp.pull;
    } else if (r.u > known) {
      ops[sec] = MirrorOp.merge;
    } else {
      ops[sec] = MirrorOp.push;
    }
  }
  for (final e in remote.entries) {
    final sec = e.key, r = e.value;
    if (local.containsKey(sec)) continue;
    final m = meta[sec];
    if (r.deleted) continue; // já está apagada aqui
    if (m == null) {
      ops[sec] = MirrorOp.pull; // nova, vinda do outro aparelho
    } else if (r.u > m.u) {
      ops[sec] = MirrorOp.pull; // foi apagada aqui, mas o outro aparelho mexeu depois: fica
    } else {
      ops[sec] = MirrorOp.deleteRemote; // apagada aqui e ninguém mexeu lá: apaga também
    }
  }
  return ops;
}
