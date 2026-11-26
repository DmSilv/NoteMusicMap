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
import 'turma.dart';

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
    s.turma == null &&
    (s.code != null && (s.name == (s.remoteName ?? '') || isDefaultStudentName(s.name, s.code!)));

// ---------------- aluno que entrou pelo convite e já estava cadastrado pelo nome ----------------

String _firstName(String s) {
  final t = s.trim().toLowerCase();
  final i = t.indexOf(' ');
  return i < 0 ? t : t.substring(0, i);
}

/// Quem pode ser a MESMA pessoa que [linked] (que acabou de se vincular e ainda está "de fábrica"): os alunos cadastrados só
/// pelo nome, sem código. Os de mesmo primeiro nome vêm primeiro. Quem decide é sempre o professor.
List<Student> joinCandidates(Student linked, Iterable<Student> all) {
  if (linked.code == null || linked.linkState != 'active' || !isPristineStudent(linked)) return const [];
  final first = _firstName(linked.name);
  final out = [for (final s in all) if (s.id != linked.id && s.code == null && !s.paused) s];
  out.sort((a, b) {
    final ra = _firstName(a.name) == first ? 0 : 1;
    final rb = _firstName(b.name) == first ? 0 : 1;
    return ra != rb ? ra.compareTo(rb) : b.created.compareTo(a.created);
  });
  return out;
}

/// Dá a [local] o vínculo de [linked]: fica o cadastro do professor (nome, tarefas, observações, número) com o código do aluno.
/// Quem chama tira [linked] da lista (sem encerrar o vínculo).
void adoptLink(Student local, Student linked) {
  local.code = linked.code;
  local.linkState = linked.linkState;
  local.remoteName = linked.remoteName;
  local.paused = linked.paused;
  local.noPick = linked.noPick;
  local.muted = linked.muted;
  // O que o professor digitou no cadastro que vai sair não se perde (o que já estava no dele prevalece).
  local.whats ??= linked.whats;
  if (local.remindDays.isEmpty) local.remindDays = [...linked.remindDays];
  local.remindedMs ??= linked.remindedMs;
}

// ---------------- aluno ----------------

/// O aluno como seção. Fora ficam o que depende de cada aparelho: o estado do vínculo e o apelido que o aluno registrou
/// (cada aparelho os recebe do servidor). Cabe em até [kMaxSectionChars].
String studentToSection(Student s) {
  final j = s.toJson()
    ..remove('lk')
    ..remove('rn')
    // o número do aluno e os lembretes ficam só no aparelho: nunca vão ao servidor
    ..remove('wa')
    ..remove('rdw')
    ..remove('rdm');
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

/// Lápides: o id de uma aula ou horário que foi APAGADO de vez neste aparelho (a lista não guarda mais nem a marca de cancelada) e
/// quando. Sem isso, a junção de dois aparelhos trazia de volta o item que um deles já tinha apagado. Duram [kTombstoneDays] dias.
const int kMaxTombstones = 200;
const int kTombstoneDays = 60;

/// Junta duas listas de lápides (vale a mais nova de cada id), tira as velhas e corta no teto.
Map<String, int> mergeTombstones(Map<String, int> a, Map<String, int> b, {required int nowMs}) {
  final out = <String, int>{...a};
  b.forEach((id, u) {
    if (u > (out[id] ?? 0)) out[id] = u;
  });
  final cut = nowMs - kTombstoneDays * 86400000;
  out.removeWhere((_, u) => u < cut);
  if (out.length <= kMaxTombstones) return out;
  final keep = out.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
  return {for (final e in keep.take(kMaxTombstones)) e.key: e.value};
}

/// Aulas e horários: por id, vale a versão mais nova ([ClassSlot.updatedMs]); empate fica com a daqui. Um item com lápide
/// (apagado) some, a menos que tenha sido mexido DEPOIS de apagado.
List<ClassSlot> mergeSlotLists(List<ClassSlot> local, List<ClassSlot> remote, {Map<String, int> localDeleted = const {}, Map<String, int> remoteDeleted = const {}}) {
  final byId = {for (final s in local) s.id: s};
  for (final r in remote) {
    final cur = byId[r.id];
    if (cur == null || r.updatedMs > cur.updatedMs) byId[r.id] = cur == null ? r : r.copyWith(pending: cur.pending);
  }
  final dead = mergeTombstones(localDeleted, remoteDeleted, nowMs: DateTime.now().millisecondsSinceEpoch);
  byId.removeWhere((id, s) => (dead[id] ?? -1) >= s.updatedMs && dead.containsKey(id));
  return byId.values.toList();
}

/// As aulas como seção. O "falta enviar" é só deste aparelho e não vai junto. As lápides vão como itens `{id, del: 1, u}` no fim da
/// MESMA lista: aparelhos antigos não entendem esses itens (não têm data) e os ignoram, sem estragar nada.
String slotsToSection(List<ClassSlot> slots, {Map<String, int> deleted = const {}}) => jsonEncode([
      for (final s in slots) s.copyWith(pending: null).toJson(),
      for (final e in deleted.entries) {'id': e.key, 'del': 1, 'u': e.value},
    ]);

/// A seção lida: as aulas e as lápides.
class SlotSection {
  final List<ClassSlot> slots;
  final Map<String, int> deleted;
  const SlotSection(this.slots, this.deleted);
}

SlotSection slotsAndTombstonesFromSection(String data) {
  try {
    final j = jsonDecode(data);
    if (j is! List) return const SlotSection([], {});
    final slots = <ClassSlot>[];
    final dead = <String, int>{};
    for (final x in j.take(400 + kMaxTombstones)) {
      if (x is Map && x['del'] == 1) {
        final id = '${x['id']}';
        final u = x['u'];
        if (RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(id) && u is num && dead.length < kMaxTombstones) dead[id] = u.toInt();
        continue;
      }
      final s = ClassSlot.tryFrom(x);
      if (s != null && slots.length < 400) slots.add(s);
    }
    return SlotSection(slots, dead);
  } catch (_) {
    return const SlotSection([], {});
  }
}

List<ClassSlot> slotsFromSection(String data) => slotsAndTombstonesFromSection(data).slots;

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

  /// Instrumentos que o professor criou (com os métodos e o repertório dele) e as turmas.
  final List<TeachingInstrument> custom;
  final List<Turma> turmas;
  const AccountPrefs({this.teachInstruments = const [], this.teacherMode = false, this.custom = const [], this.turmas = const []});

  bool get isDefault => teachInstruments.isEmpty && !teacherMode && custom.isEmpty && turmas.isEmpty;

  String toSection() => jsonEncode({
        'ti': teachInstruments,
        if (teacherMode) 'tm': true,
        if (custom.isNotEmpty) 'ci': [for (final i in custom) i.toJson()],
        if (turmas.isNotEmpty) 'tu': [for (final t in turmas) t.toJson()],
      });

  static AccountPrefs fromSection(String data) {
    try {
      final j = (jsonDecode(data) as Map).cast<String, dynamic>();
      final custom = customInstrumentsFromJson(j['ci']);
      // Os ids dos instrumentos próprios precisam existir para passar pela limpeza.
      final prev = customInstruments;
      customInstruments = custom;
      final ti = cleanTeachingIds(j['ti'] as List?);
      customInstruments = prev;
      return AccountPrefs(teachInstruments: ti, teacherMode: j['tm'] == true, custom: custom, turmas: turmasFromJson(j['tu']));
    } catch (_) {
      return const AccountPrefs();
    }
  }

  /// Soma: os instrumentos, as turmas e os instrumentos próprios dos dois (pelo id; os métodos e peças somam) e o modo
  /// professor se algum dos dois tem.
  AccountPrefs merge(AccountPrefs o) {
    final byId = <String, TeachingInstrument>{for (final i in custom) i.id: i};
    for (final i in o.custom) {
      final cur = byId[i.id];
      byId[i.id] = cur == null
          ? i
          : TeachingInstrument(cur.id, cur.label,
              methods: {...cur.methods, ...i.methods}.toList(), repertoire: {...cur.repertoire, ...i.repertoire}.toList(), custom: true);
    }
    final mergedCustom = byId.values.take(kMaxCustomInstruments).toList();
    final prev = customInstruments;
    customInstruments = mergedCustom;
    final ti = cleanTeachingIds([...teachInstruments, ...o.teachInstruments]);
    customInstruments = prev;
    final tm = <String, Turma>{for (final t in turmas) t.id: t};
    for (final t in o.turmas) {
      tm.putIfAbsent(t.id, () => t);
    }
    return AccountPrefs(teachInstruments: ti, teacherMode: teacherMode || o.teacherMode, custom: mergedCustom, turmas: tm.values.take(kMaxTurmas).toList());
  }
}

/// O histórico de estudo (as últimas [keep] sessões) como seção.
String sessionsToSection(List<SessionRecord> sessions, {int keep = 300, int maxChars = 80000}) {
  var n = sessions.length > keep ? keep : sessions.length;
  var out = jsonEncode([for (final s in sessions.take(n)) s.toJson()]);
  // Cabe no espelho: se passar do teto, tira as mais antigas (a lista vem da mais nova para a mais velha).
  while (out.length > maxChars && n > 1) {
    n = (n * 3) ~/ 4;
    out = jsonEncode([for (final s in sessions.take(n)) s.toJson()]);
  }
  return out;
}

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
