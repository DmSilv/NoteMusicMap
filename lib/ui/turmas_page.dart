import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'link_bar.dart' show ensureTeacherLink;
import '../app_state.dart';
import 'design_system.dart';
import 'materials_sheet.dart';
import 'person_avatar.dart';
import 'student_identity.dart' show studentTint;
import 'task_form_page.dart';
import 'teacher_page.dart' show StudentPage;
import 'teaching_ui.dart';
import 'widgets.dart';

/// "Turmas": o lugar onde o professor se organiza quando tem mais de um grupo de alunos (mesmo dentro do mesmo instrumento).
/// Cada turma tem o seu instrumento e os seus alunos; dali ele passa a mesma tarefa para vários de uma vez.
class TurmasPage extends StatelessWidget {
  final AppState app;
  const TurmasPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Turmas'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTurmaEditor(context, app),
        icon: const Icon(Icons.add),
        label: Text(tr('Nova turma'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: DsPageSafe(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final without = app.students.where((s) => s.turma == null || app.turmaOf(s) == null).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s12, Ds.screenPad, 96),
              children: [
                if (app.turmas.isEmpty)
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      DsCardTitle(Icons.workspaces_outline, tr('Organize seus alunos'), subtitle: tr('Crie uma turma para cada grupo: por instrumento, nível ou horário.')),
                      const SizedBox(height: Ds.s12),
                      Text(tr('Em cada turma você vê só os alunos dela e passa a mesma tarefa para todos de uma vez.'), style: Ds.support()),
                    ]),
                  ),
                for (final t in app.turmas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Ds.s8),
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      child: DsNavRow(
                        Icons.workspaces_outline,
                        t.name,
                        [teachingById(t.instrument)?.label ?? tr('Sem instrumento'), _count(app.students.where((s) => s.turma == t.id).length)].join(' · '),
                        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TurmaPage(app: app, turmaId: t.id))),
                      ),
                    ),
                  ),
                if (app.turmas.isNotEmpty && without > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: Ds.s8, left: Ds.s4),
                    child: Text(tr('{0} sem turma', [_count(without)]), style: Ds.support()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _count(int n) => n == 1 ? tr('1 aluno') : tr('{0} alunos', [n]);

/// Uma turma: instrumento, alunos (adicionar e tirar) e a tarefa para todos.
class TurmaPage extends StatefulWidget {
  final AppState app;
  final String turmaId;
  const TurmaPage({super.key, required this.app, required this.turmaId});

  @override
  State<TurmaPage> createState() => _TurmaPageState();
}

class _TurmaPageState extends State<TurmaPage> {
  AppState get app => widget.app;

  Turma? get turma => app.turmas.where((t) => t.id == widget.turmaId).firstOrNull;

  Future<void> _addStudents(Turma t) async {
    final candidates = app.students.where((s) => s.turma != t.id).toList();
    if (candidates.isEmpty) {
      app.say(tr('Todos os seus alunos já estão nesta turma.'));
      return;
    }
    final picked = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(tr('Adicionar alunos')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (final s in candidates)
                CheckboxListTile(
                  value: picked.contains(s.id),
                  onChanged: (v) => setS(() => v == true ? picked.add(s.id) : picked.remove(s.id)),
                  title: Text(app.labelOf(s)),
                  subtitle: app.turmaOf(s) == null ? null : Text(tr('Está em {0}', [app.turmaOf(s)!.name]), style: Ds.support()),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(c, true), child: Text(tr('Adicionar'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    for (final s in app.students.where((s) => picked.contains(s.id))) {
      app.setStudentTurma(s, t.id);
    }
  }

  /// Escolhe quem recebe (todos marcados), monta a tarefa uma vez e passa para cada um.
  Future<void> _assign(Turma t) async {
    final members = app.students.where((s) => s.turma == t.id).toList();
    if (members.isEmpty) {
      app.say(tr('Ponha alunos na turma primeiro.'));
      return;
    }
    final picked = {for (final s in members) s.id};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(tr('Tarefa para {0}', [t.name])),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              Text(tr('Quem recebe? Desmarque quem fica de fora.'), style: Ds.support()),
              for (final s in members)
                CheckboxListTile(
                  value: picked.contains(s.id),
                  onChanged: (v) => setS(() => v == true ? picked.add(s.id) : picked.remove(s.id)),
                  title: Text(app.labelOf(s)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(c, true), child: Text(tr('Escolher a tarefa'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final to = members.where((s) => picked.contains(s.id)).toList();
    final d = await openTaskForm(context, app, to.first);
    if (d == null) return;
    // Sem conexão, pergunta uma vez para a turma inteira. "Agora não" deixa a tarefa na ficha, sem dizer que foi enviada.
    if (d.sendNow && !app.linkEnabled && to.any((s) => app.deliveryFor(s).canSend)) {
      if (mounted) await ensureTeacherLink(context, app, tr('Para a tarefa chegar ao aluno, o app precisa conectar.'));
    }
    var sent = 0;
    for (final s in to) {
      if (d.kind == TaskKind.scale) {
        app.addAssignment(s, title: d.title, scaleTypeIndex: d.scaleType.index, tonicPc: d.tonicPc, octaves: d.octaves, goal: d.goal, note: d.note);
      } else {
        app.addAssignment(s, title: d.title, kind: d.kind, subject: d.subject, detail: d.detail, note: d.note);
      }
      final rule = app.deliveryFor(s);
      if (d.sendNow && app.linkEnabled && rule.canSend && rule.mode != DeliveryMode.inLesson) {
        app.sendPendingTasks(s);
        sent++;
      }
    }
    app.say(to.length == 1
        ? tr('Tarefa passada para 1 aluno.')
        : (sent == to.length ? tr('Tarefa passada e enviada para {0} alunos.', [to.length]) : tr('Tarefa passada para {0} alunos. Quem ainda não recebe fica com ela na ficha.', [to.length])));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = turma;
        if (t == null) return const Scaffold(body: SizedBox.shrink());
        final members = app.students.where((s) => s.turma == t.id).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(t.name),
            actions: [IconButton(tooltip: tr('Editar turma'), icon: const Icon(Icons.edit_outlined), onPressed: () => showTurmaEditor(context, app, existing: t))],
          ),
          body: DsPageSafe(
            child: ListView(
              padding: Ds.screen,
              children: [
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    DsCardTitle(Icons.workspaces_outline, teachingById(t.instrument)?.label ?? tr('Sem instrumento'), subtitle: _count(members.length)),
                    const SizedBox(height: Ds.s16),
                    SizedBox(
                      height: Ds.primaryHeight,
                      child: FilledButton.icon(
                        onPressed: members.isEmpty ? null : () => _assign(t),
                        icon: const Icon(Icons.assignment_add),
                        label: Text(tr('Passar tarefa para a turma'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: Ds.s8),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap)), onPressed: () => _addStudents(t), icon: const Icon(Icons.person_add_alt_1, size: 18), label: Text(tr('Alunos')))),
                      const SizedBox(width: Ds.s8),
                      Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap)), onPressed: () => showMaterialsSheet(context, app, instrument: t.instrument.isEmpty ? null : t.instrument), icon: const Icon(Icons.library_books_outlined, size: 18), label: Text(tr('Métodos')))),
                    ]),
                  ]),
                ),
                const SizedBox(height: Ds.gap),
                if (members.isEmpty)
                  Padding(padding: const EdgeInsets.all(Ds.s16), child: Text(tr('Nenhum aluno nesta turma ainda. Toque em "Alunos" para adicionar.'), textAlign: TextAlign.center, style: Ds.support())),
                for (final s in members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Ds.s8),
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: PersonAvatar(name: s.name, photo: app.photoOfStudent(s), tint: studentTint(s), radius: 20),
                        title: Text(app.labelOf(s), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(app.awaitingOf(s).isEmpty ? tr('{0} em aberto', [s.tasks.where((x) => !x.done).length]) : tr('{0} para validar', [app.awaitingOf(s).length]), style: Ds.support()),
                        trailing: PopupMenuButton<String>(
                          tooltip: tr('Opções'),
                          onSelected: (v) {
                            if (v == 'open') Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: s.id)));
                            if (v == 'out') app.setStudentTurma(s, null);
                          },
                          itemBuilder: (c) => [
                            PopupMenuItem(value: 'open', child: Text(tr('Abrir a ficha'))),
                            PopupMenuItem(value: 'out', child: Text(tr('Tirar da turma'))),
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: s.id))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
