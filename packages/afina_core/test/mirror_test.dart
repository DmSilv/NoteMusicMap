import 'dart:convert';
import 'dart:math';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final code1 = newShareCode(Random(1));
  Assignment task(String id, {bool done = false, bool? sent, DateTime? claimed, bool reviewed = false, String title = 'T'}) =>
      Assignment(id: id, title: '$title $id', created: DateTime(2026, 11, 1), done: done, sent: sent, claimedAt: claimed, reviewed: reviewed);
  Student stu(String id, {String? code, String name = 'Ana', List<Assignment>? tasks, List<TeacherNote>? notes}) =>
      Student(id: id, name: name, code: code, tasks: tasks, notes: notes);

  group('seções de aluno', () {
    test('o nome da seção vem do código (igual nos dois aparelhos) ou, sem código, do id', () {
      expect(studentSection(stu('v123', code: code1)), 'S:$code1');
      expect(studentSection(stu('abc')), 'S:i:abc');
      expect(RegExp(r'^[A-Za-z0-9:_.-]{1,64}$').hasMatch(studentSection(stu('v123', code: code1))), isTrue, reason: 'cabe no que o servidor aceita');
    });

    test('vai e volta, sem o que é de cada aparelho (vínculo e apelido do aluno)', () {
      final s = stu('a', code: code1, tasks: [task('t1')], notes: [TeacherNote(DateTime(2026, 11, 2), 'Arco')]);
      s.linkState = 'active';
      s.remoteName = 'Aninha';
      final data = studentToSection(s);
      expect(data.contains('"lk"'), isFalse);
      expect(data.contains('"rn"'), isFalse);
      final back = studentFromSection(data)!;
      expect(back.tasks.single.id, 't1');
      expect(back.notes.single.text, 'Arco');
      expect(back.linkState, isNull);
      expect(studentFromSection('lixo'), isNull);
      expect(studentFromSection('[1,2]'), isNull);
    });

    test('aluno de fábrica (só o vínculo) é reconhecido; com qualquer dado deixa de ser', () {
      final bare = stu('v1', code: code1, name: 'Ana')..remoteName = 'Ana';
      expect(isPristineStudent(bare), isTrue);
      expect(isPristineStudent(stu('v1', code: code1, name: 'Aluno $code1')), isTrue);
      expect(isPristineStudent(stu('v1', code: code1, name: 'Ana Souza')..remoteName = 'Ana'), isFalse, reason: 'o professor renomeou');
      expect(isPristineStudent(stu('v1', code: code1, tasks: [task('a')])..remoteName = 'Ana'), isFalse);
      expect(isPristineStudent(stu('x')), isFalse, reason: 'sem código foi o professor que digitou');
    });
  });

  group('juntar dois lados do mesmo aluno', () {
    test('tarefas e observações dos dois lados somam, sem repetir', () {
      final a = stu('a', code: code1, tasks: [task('t1'), task('t2')], notes: [TeacherNote(DateTime(2026, 11, 2), 'A')]);
      final b = stu('b', code: code1, tasks: [task('t2'), task('t3')], notes: [TeacherNote(DateTime(2026, 11, 2), 'A'), TeacherNote(DateTime(2026, 11, 3), 'B')]);
      mergeStudentFrom(a, b, preferOther: false);
      expect(a.tasks.map((t) => t.id), ['t1', 't2', 't3']);
      expect(a.notes.map((n) => n.text), ['B', 'A']);
      expect(a.id, 'a', reason: 'o id local fica');
    });

    test('tarefa validada em um lado fica validada; a marca do aluno e o envio não se perdem', () {
      final a = stu('a', code: code1, tasks: [task('t1', sent: true)]);
      final b = stu('b', code: code1, tasks: [task('t1', done: true, claimed: DateTime(2026, 11, 5), reviewed: true)]);
      mergeStudentFrom(a, b, preferOther: true);
      final t = a.tasks.single;
      expect(t.done, isTrue);
      expect(t.sent, isTrue);
      expect(t.claimedAt, DateTime(2026, 11, 5));
      expect(t.reviewed, isTrue);
    });

    test('preferOther troca o nome e o instrumento; sem preferir, só preenche o que faltava', () {
      final a = stu('a', code: code1, name: 'Ana');
      final b = stu('b', code: code1, name: 'Ana Souza')..instrument = 'piano';
      final keep = stu('k', code: code1, name: 'Ana');
      mergeStudentFrom(keep, b, preferOther: false);
      expect(keep.name, 'Ana');
      expect(keep.instrument, 'piano');
      mergeStudentFrom(a, b, preferOther: true);
      expect(a.name, 'Ana Souza');
    });

    test('faltas e aulas dadas somam e a aula enviada num lado conta como enviada', () {
      final a = stu('a', code: code1);
      final b = stu('b', code: code1);
      final la = LessonRecord(id: 'L1', startedAt: DateTime(2026, 11, 1, 10), endedAt: DateTime(2026, 11, 1, 11), durationSec: 3600, taskCount: 1, noteCount: 0)..sent = false;
      final lb = LessonRecord(id: 'L1', startedAt: DateTime(2026, 11, 1, 10), endedAt: DateTime(2026, 11, 1, 11), durationSec: 3600, taskCount: 1, noteCount: 0)..sent = true;
      final l2 = LessonRecord(id: 'L2', startedAt: DateTime(2026, 11, 8, 10), endedAt: DateTime(2026, 11, 8, 11), durationSec: 3600, taskCount: 0, noteCount: 1)..sent = true;
      a.lessons.add(la);
      b.lessons.addAll([lb, l2]);
      a.absences = [const Absence(lessonMs: 10, kind: AbsenceKind.notified, recordedMs: 11)];
      b.absences = [const Absence(lessonMs: 10, kind: AbsenceKind.notified, recordedMs: 11), const Absence(lessonMs: 20, kind: AbsenceKind.noShow, recordedMs: 21)];
      mergeStudentFrom(a, b, preferOther: false);
      expect(a.lessons.map((l) => l.id), ['L2', 'L1']);
      expect(a.lessons.firstWhere((l) => l.id == 'L1').sent, isTrue);
      expect(a.absences.map((x) => x.lessonMs), [20, 10]);
    });
  });

  group('agenda, métodos e ajustes', () {
    ClassSlot slot(String id, int updated, {bool canceled = false, bool? pending}) =>
        ClassSlot(id: id, studentCode: code1, startMs: DateTime(2026, 11, 20, 10).millisecondsSinceEpoch, durationMin: 45, updatedMs: updated, canceled: canceled, pending: pending);

    test('aula: vale a versão mais nova de cada uma; aula nova do outro lado entra', () {
      final local = [slot('a1', 10), slot('a2', 50, canceled: true)];
      final remote = [slot('a1', 20), slot('a2', 40), slot('a3', 5)];
      final m = mergeSlotLists(local, remote);
      expect({for (final s in m) s.id: s.updatedMs}, {'a1': 20, 'a2': 50, 'a3': 5});
      expect(m.firstWhere((s) => s.id == 'a2').canceled, isTrue, reason: 'cancelar é marca: não volta');
    });

    test('o "falta enviar" não viaja e não se perde ao trocar de versão', () {
      final data = slotsToSection([slot('a1', 10, pending: true)]);
      expect(jsonDecode(data).first.containsKey('p'), isFalse);
      final m = mergeSlotLists([slot('a1', 10, pending: true)], [slot('a1', 20)]);
      expect(m.single.updatedMs, 20);
      expect(m.single.pending, isTrue);
      expect(slotsFromSection(data).single.id, 'a1');
      expect(slotsFromSection('lixo'), isEmpty);
    });

    test('métodos: ida e volta e união pelo nome', () {
      final lib = [MethodEntry('Suzuki', ['Lição 1'])];
      final back = methodsFromSection(methodsToSection(lib));
      expect(back.single.lessons, ['Lição 1']);
      final into = [MethodEntry('Suzuki', ['Lição 2'])];
      mergeMethods(into, back);
      expect(into.single.lessons, ['Lição 2', 'Lição 1']);
    });

    test('ajustes da conta: instrumentos somam e o modo professor vale se qualquer lado tem', () {
      const a = AccountPrefs(teachInstruments: ['piano']);
      const b = AccountPrefs(teachInstruments: ['violino', 'tuba'], teacherMode: true);
      final m = a.merge(AccountPrefs.fromSection(b.toSection()));
      expect(m.teachInstruments, ['violino', 'piano']);
      expect(m.teacherMode, isTrue);
      expect(const AccountPrefs().isDefault, isTrue);
      expect(AccountPrefs.fromSection('lixo').isDefault, isTrue);
    });
  });

  group('o que fazer a cada rodada', () {
    LocalSection ls(String d, {bool pristine = false}) => LocalSection(d, pristine: pristine);
    MirrorMeta meta(String d, int u) => MirrorMeta(mirrorHash(d), u);

    test('seção nova aqui vai para o servidor; de fábrica e nunca enviada fica quieta', () {
      final ops = planMirror(local: {'AG': ls('[]'), 'S:x': ls('{"a":1}', pristine: true)}, meta: {}, remote: {});
      expect(ops['AG'], MirrorOp.push, reason: 'não é de fábrica: nunca enviada');
      expect(ops.containsKey('S:x'), isFalse);
    });

    test('nada mudou dos dois lados: nada a fazer', () {
      final ops = planMirror(local: {'AG': ls('[1]')}, meta: {'AG': meta('[1]', 10)}, remote: {'AG': const RemoteSection(10)});
      expect(ops, isEmpty);
    });

    test('mudou só aqui: envia; mudou só lá: baixa; mudou nos dois: junta', () {
      final base = {'AG': meta('[1]', 10)};
      expect(planMirror(local: {'AG': ls('[2]')}, meta: base, remote: {'AG': const RemoteSection(10)})['AG'], MirrorOp.push);
      expect(planMirror(local: {'AG': ls('[1]')}, meta: base, remote: {'AG': const RemoteSection(20)})['AG'], MirrorOp.pull);
      expect(planMirror(local: {'AG': ls('[2]')}, meta: base, remote: {'AG': const RemoteSection(20)})['AG'], MirrorOp.merge);
    });

    test('aluno de fábrica aqui e rico no servidor: adota o do servidor, nunca o sobrescreve', () {
      final ops = planMirror(local: {'S:x': ls('{"bare":1}', pristine: true)}, meta: {}, remote: {'S:x': const RemoteSection(50)});
      expect(ops['S:x'], MirrorOp.pull);
    });

    test('aluno com dados aqui, nunca enviado, e o servidor já tem: junta os dois', () {
      final ops = planMirror(local: {'S:x': ls('{"tem":1}')}, meta: {}, remote: {'S:x': const RemoteSection(50)});
      expect(ops['S:x'], MirrorOp.merge);
    });

    test('seção nova só no servidor vem para cá', () {
      expect(planMirror(local: {}, meta: {}, remote: {'S:novo': const RemoteSection(5)})['S:novo'], MirrorOp.pull);
    });

    test('apagada aqui e ninguém mexeu lá: apaga lá; se mexeram lá depois, fica', () {
      final base = {'S:x': meta('{}', 10)};
      expect(planMirror(local: {}, meta: base, remote: {'S:x': const RemoteSection(10)})['S:x'], MirrorOp.deleteRemote);
      expect(planMirror(local: {}, meta: base, remote: {'S:x': const RemoteSection(30)})['S:x'], MirrorOp.pull);
    });

    test('apagada lá: some aqui se nada mudou; se mudou aqui, a edição vale e a seção volta', () {
      final base = {'S:x': meta('{}', 10)};
      expect(planMirror(local: {'S:x': ls('{}')}, meta: base, remote: {'S:x': const RemoteSection(20, deleted: true)})['S:x'], MirrorOp.deleteLocal);
      expect(planMirror(local: {'S:x': ls('{"novo":1}')}, meta: base, remote: {'S:x': const RemoteSection(20, deleted: true)})['S:x'], MirrorOp.push);
    });

    test('marca de apagada que já não existe aqui não faz nada', () {
      expect(planMirror(local: {}, meta: {}, remote: {'S:x': const RemoteSection(20, deleted: true)}), isEmpty);
    });

    test('o servidor perdeu a seção (espelho recomeçou): reenvia o que já era conhecido', () {
      final ops = planMirror(local: {'AG': ls('[1]')}, meta: {'AG': meta('[1]', 10)}, remote: {});
      expect(ops['AG'], MirrorOp.push);
    });
  });
}
