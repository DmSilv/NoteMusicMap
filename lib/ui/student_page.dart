import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import 'agenda_actions.dart' show absenceFlow;
import 'hub_section.dart' show shareTeacherInvite;
import 'safe_input.dart';
import '../ai/coach_ai.dart';
import 'design_system.dart';
import 'dictation_button.dart';
import 'dart:async';
import 'markdown_lite.dart';
import 'scale_exercise_page.dart';
import 'student_identity.dart';
import 'teaching_ui.dart';
import 'task_form_page.dart';
import 'validation_ui.dart';
import 'theme.dart';
import 'widgets.dart';

// Ficha do aluno e as janelas pequenas que ela compartilha com a lista de alunos (extraído de teacher_page.dart sem mudar o comportamento).

Future<String?> askText(BuildContext context, String title, String label,
    {String initial = '', bool multiline = false, String? action, AppState? voice}) async {
  final ctl = TextEditingController(text: initial);
  final v = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        inputFormatters: [SafeText(multiline ? kMaxNote : kMaxTitle, multiline: multiline)],
        autofocus: true,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          // Microfone para ditar (só onde o texto é livre).
          suffixIcon: voice == null ? null : DictationButton(app: voice, controller: ctl),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancelar'))),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(action ?? tr('Salvar'))),
      ],
    ),
  );
  ctl.dispose();
  return v;
}

Future<bool> confirmDelete(BuildContext context, String title, String text) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.sharp, foregroundColor: readableOn(AppColors.sharp)),
          onPressed: () => Navigator.pop(c, true),
          icon: const Icon(Icons.delete_outline, size: 18), label: Text(tr('Excluir')),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<void> renameStudent(BuildContext context, AppState app, Student s) async {
  final n = await askText(context, tr('Renomear'), tr('Nome'), initial: s.name, voice: app);
  if (n == null || n.trim().isEmpty) return;
  final err = app.checkStudent(n, s.code ?? '', exceptId: s.id).name;
  if (err != null) {
    app.say(err);
    return;
  }
  s.name = n.trim();
  app.setActiveStudent(app.activeStudentId); // salva e atualiza
}

Future<void> editStudentCode(BuildContext context, AppState app, Student s) async {
  final c = await askText(context, tr('Código do aluno'), tr('Código (ex.: K7QM-4TXD)'),
      initial: s.code ?? '', action: tr('Salvar'));
  if (c == null) return;
  final err = app.checkStudentCode(c, exceptId: s.id);
  if (err != null) {
    app.say(err);
  } else {
    app.setStudentCode(s.id, c);
  }
}

/// Detalhe de um aluno: evolução, orientações, tarefas e observações.
class StudentPage extends StatelessWidget {
  final AppState app;
  final String studentId;
  const StudentPage({super.key, required this.app, required this.studentId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.studentById(studentId);
        if (s == null) return const Scaffold(body: SizedBox.shrink());
        final sum = summarizeStudent(s);
        final tips = analyzePractice(s.sessions, flats: app.flatsForText).take(4).toList();
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Alunos'), style: TextStyle(fontSize: 12, color: AppColors.textDim, fontWeight: FontWeight.w600)),
              Text(app.labelOf(s), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'report':
                      await Clipboard.setData(ClipboardData(text: studentReport(s, flats: app.flatsForText)));
                      app.say(tr('Relatório copiado: cole numa conversa ou e-mail'));
                    case 'ai':
                      await _aiReport(context, s);
                    case 'data':
                      await Clipboard.setData(ClipboardData(text: exportStudent(s)));
                      app.say(tr('Dados copiados: use "Importar" no outro aparelho'));
                    case 'code':
                      await editStudentCode(context, app, s);
                    case 'rename':
                      await renameStudent(context, app, s);
                    case 'delete':
                      final ok = await confirmDelete(context, tr('Excluir {0}?', [app.labelOf(s)]),
                          tr('Apaga o histórico, as tarefas e as observações deste aluno neste aparelho{0}. Não dá para desfazer.', [app.hasLessonWith(s.id) ? tr(', e descarta a aula em andamento com ele') : '']));
                      if (ok) {
                        app.removeStudent(s.id);
                        app.say(tr('{0} foi excluído.', [s.name]));
                        if (context.mounted) Navigator.of(context).pop();
                      }
                  }
                },
                itemBuilder: (c) => [
                  PopupMenuItem(value: 'report', child: Text(tr('Copiar relatório'))),
                  PopupMenuItem(value: 'ai', child: Text(tr('Relatório com IA'))),
                  PopupMenuItem(value: 'data', child: Text(tr('Copiar dados (para outro aparelho)'))),
                  PopupMenuItem(value: 'code', child: Text(tr('Código do aluno'))),
                  PopupMenuItem(value: 'rename', child: Text(tr('Renomear'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('Excluir aluno'))),
                ],
              ),
            ],
          ),
          body: DsPageSafe(
            child: ListView(
              padding: Ds.screen,
              children: [
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    StudentIdentity(app: app, student: s, large: true),
                    const SizedBox(height: Ds.s12),
                    ActionChip(
                      avatar: const Icon(Icons.piano_outlined, size: 18),
                      label: Text(s.instrument == null ? tr('Instrumento do aluno') : (teachingById(s.instrument)?.label ?? '')),
                      onPressed: () => showStudentInstrumentSheet(context, app, s),
                    ),
                  ]),
                ),
                const SizedBox(height: Ds.gap),
                _LessonCard(
                  app: app,
                  student: s,
                  onNewTask: () => _taskDialog(context, s),
                  onNewNote: () => _newNote(context, s),
                ),
                const SizedBox(height: Ds.gap),
                ValidationCard(app: app, student: s),
                _deliveryCard(context, s),
                _tasks(context, s),
                const SizedBox(height: Ds.gap),
                _more(context, s, sum, tips),
              ],
            ),
          ),
        );
      },
    );
  }

  /// O que não é urgente fica em linhas que abrem num modal: desempenho, observações e aulas dadas.
  Widget _more(BuildContext context, Student s, StudentSummary sum, List<Insight> tips) {
    final notePreview = s.notes.isEmpty ? tr('Anote pontos de atenção, elogios e combinados.') : s.notes.first.text;
    final n = s.lessons.length;
    Widget sheetBody(List<Widget> kids) => FramelessScope(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        DsNavRow(
          Icons.insights_rounded,
          tr('Desempenho'),
          sum.sessions == 0 ? tr('Ainda sem exercícios') : tr('{0} sessões · média {1}%', [sum.sessions, (sum.recentAverage! * 100).round()]),
          () => showDsSheet(context, title: tr('Desempenho'), listenable: app, children: (c) => [
                sheetBody([
                  _summary(sum, s),
                  if (tips.isNotEmpty) ...[
                    const SizedBox(height: Ds.s20),
                    Text(tr('Orientações do treinador'), style: Ds.section()),
                    const SizedBox(height: Ds.s8),
                    for (final t in tips) InsightTile(insight: t),
                  ],
                  const SizedBox(height: Ds.s20),
                  Text(tr('Últimos exercícios'), style: Ds.section()),
                  const SizedBox(height: Ds.s8),
                  _sessionsBody(s),
                ]),
              ]),
        ),
        const Divider(height: 1),
        DsNavRow(
          Icons.edit_note_rounded,
          tr('Observações'),
          notePreview,
          () => showDsSheet(context, title: tr('Observações'), listenable: app, children: (c) => [
                DsPrimaryButton(onPressed: () => _newNote(context, s), icon: Icons.edit_note, label: tr('Anotar')),
                const SizedBox(height: Ds.s20),
                if (s.notes.isEmpty) Text(tr('Anote pontos de atenção, elogios e combinados.'), style: Ds.support()),
                for (final note in s.notes.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Ds.s12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 48, child: Text(fmtDayMonth(note.date), style: Ds.support())),
                      Expanded(child: Text(note.text, style: const TextStyle(fontSize: Ds.fontBody, height: 1.35))),
                    ]),
                  ),
              ]),
        ),
        if (n > 0) ...[
          const Divider(height: 1),
          DsNavRow(
            Icons.history_rounded,
            tr('Aulas dadas'),
            n == 1 ? tr('1 aula') : tr('{0} aulas', [n]),
            () => showDsSheet(context, title: tr('Aulas dadas'), listenable: app, children: (c) => [sheetBody([_lessonHistoryBody(s)])]),
            alert: s.lessons.any((l) => l.sent == false),
          ),
        ],
      ]),
    );
  }

  /// Quando há aula ou tarefas esperando envio, explica POR QUE ainda não chegaram e o que fazer.
  /// A causa mais comum: o aluno ainda não ligou o "Vínculo online" no app dele (vem desligado).
  Widget _deliveryCard(BuildContext context, Student s) {
    final waiting = s.lessons.where((r) => r.sent == false).length;
    if (waiting == 0 || s.code == null || s.linkState == 'ended') return const SizedBox.shrink();
    final issue = app.deliveryIssue[s.code];

    String title = tr('Aguardando envio para {0}', [s.name]);
    String text;
    var showInvite = false;
    var showTurnOn = false;
    if (!app.linkEnabled) {
      text = tr('O vínculo online está desligado no SEU app, por isso nada sai daqui. Ligue para enviar.');
      showTurnOn = true;
    } else if (app.linkUnavailable) {
      text = tr('O servidor ainda não recebe aulas. Elas ficam guardadas e vão quando ele voltar.');
    } else if (issue == 'not_ready') {
      title = tr('{0} ainda não recebeu', [s.name]);
      text = tr('O app de {0} ainda não ligou o "Vínculo online" (ele vem desligado). Sem isso o servidor não entrega nada. Peça para abrir Minha conta › Vínculo online e ligar, ou mande o convite abaixo: ao abrir o link, o vínculo liga sozinho. Quando ele ligar, chega em até 30 segundos.', [s.name]);
      showInvite = true;
    } else if (issue == 'offline' || app.linkOnline == false) {
      text = tr('Sem conexão com o servidor agora. Fica guardado e vai quando a internet voltar.');
    } else if (s.linkState != 'active') {
      text = tr('{0} ainda não está vinculado. Vai assim que o vínculo for confirmado. Se ele nunca abriu o app com o vínculo ligado, mande o convite.', [s.name]);
      showInvite = true;
    } else {
      text = tr('Na fila. O envio é tentado a cada 30 segundos; toque em "Tentar agora" para forçar.');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.gap),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.schedule_send_outlined, color: AppColors.flat),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.3)),
          const SizedBox(height: Ds.gap),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (showTurnOn)
              FilledButton.icon(
                onPressed: () => app.setLinkEnabled(true),
                icon: const Icon(Icons.cloud_outlined, size: 18),
                label: Text(tr('Ligar vínculo online')),
              )
            else ...[
              if (showInvite)
                FilledButton.icon(
                  onPressed: () => shareTeacherInvite(app),
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(tr('Enviar convite')),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  await app.syncLinks();
                  await app.flushLessons();
                  final still = s.lessons.any((r) => r.sent == false);
                  app.say(still ? tr('Ainda não chegou. Veja o motivo no cartão.') : tr('Enviado para {0}.', [s.name]));
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(tr('Tentar agora')),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  /// Relatório pedagógico por IA. Vai só um resumo numérico, SEM nome e SEM observações.
  Future<void> _aiReport(BuildContext context, Student s) async {
    if (s.sessions.isEmpty) {
      app.say(tr('Sem exercícios ainda: faça uma sessão com o aluno primeiro.'));
      return;
    }
    if (!app.ai.consent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Relatório com IA')),
          content: Text(
              tr('O app envia à IA um resumo só com números do aluno (afinação por nota, escalas e taxas de acerto). O nome e as suas observações NÃO são enviados. Nunca vai áudio.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Agora não'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Autorizar'))),
          ],
        ),
      );
      if (ok != true) return;
      await app.ai.setConsent(true);
    }
    // Só números e tipos: texto livre (título, lição, observação) pode ter nomes e não sai do aparelho.
    final anon = Student(id: 'x', name: tr('o aluno'), sessions: s.sessions, tasks: [
      for (final t in s.tasks)
        t.isScale
            ? t.copyWith(note: '')
            : Assignment(id: t.id, title: t.kind.label, kind: t.kind, done: t.done, created: t.created),
    ]);
    app.ai.ask('${studentReport(anon, flats: app.flatsForText)}\n\n${buildAiPrompt(s.sessions, instrument: app.instrument.name, flats: app.flatsForText)}',
        kind: 'teacher_report');
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (c, scroll) => ListenableBuilder(
          listenable: app.ai,
          builder: (c, _) {
            final ai = app.ai;
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(tr('Relatório de {0}', [s.name]), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: Ds.gap),
                if (ai.phase == AiPhase.sending)
                  Row(children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Expanded(child: Text(tr('Preparando o relatório…'))),
                  ])
                else if (ai.phase == AiPhase.queued)
                  Text(ai.queuePosition != null
                      ? tr('Você é o {0}º da fila: sua vez em {1}s.', [ai.queuePosition, ai.queuedSeconds])
                      : tr('Muita gente usando agora: nova tentativa em {0}s.', [ai.queuedSeconds]))
                else if (ai.phase == AiPhase.failed)
                  Text(ai.message ?? tr('Não deu certo agora.'), style: TextStyle(color: AppColors.sharp))
                else if (ai.lastResult != null && ai.lastKind == 'teacher_report') ...[
                  MarkdownLite(ai.lastResult!),
                  const SizedBox(height: 8),
                  Text(tr('Gerado por IA: pode errar. Revise antes de enviar.'),
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  const SizedBox(height: Ds.gap),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: ai.lastResult!));
                      app.say(tr('Relatório copiado'));
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(tr('Copiar relatório')),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summary(StudentSummary sum, Student s) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                sum.sessions == 0 ? tr('Ainda sem exercícios') : tr('{0}% de acerto (média recente)', [(sum.recentAverage! * 100).round()]),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (sum.trendPoints != null)
              Icon(sum.trendPoints! >= 0 ? Icons.trending_up : Icons.trending_down,
                  color: sum.trendPoints! >= 0 ? AppColors.inTune : AppColors.sharp),
          ]),
          if (sum.sessions > 0)
            Text(
              tr('{0} sessões · melhor {1}% · última {2}{3}', [sum.sessions, (sum.best! * 100).round(), fmtDayMonth(sum.last!), sum.trendPoints == null ? '' : tr(' · {0}{1} pts nas últimas 3', [sum.trendPoints! >= 0 ? '+' : '', sum.trendPoints!.round()])]),
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
        ],
      ),
    );
  }

  /// A situação da tarefa para o professor (mesmas cores e palavras do app do aluno).
  DsStatus? _statusFor(Student s, Assignment t) {
    if (t.done) return DsStatus(tr('validada'), Icons.verified_rounded, AppColors.inTune);
    if (t.reviewed) return DsStatus(tr('refazer'), Icons.replay_rounded, AppColors.sharp);
    if (t.awaitsValidation) return DsStatus(tr('Aluno marcou como feita'), Icons.fact_check_outlined, AppColors.accent);
    final canReceive = s.code != null && s.linkState != 'ended';
    if (canReceive && t.sent == false) return DsStatus(tr('A enviar'), Icons.schedule_send_outlined, AppColors.flat);
    if (canReceive && t.sent == true && s.lessons.any((r) => r.sent == false && taskIdsOf(r).contains(t.id))) {
      return DsStatus(tr('Na fila de envio'), Icons.schedule_send_outlined, AppColors.flat);
    }
    return null;
  }

  Widget _tasks(BuildContext context, Student s) {
    final reviewIds = {for (final t in app.awaitingOf(s)) t.id}; // já aparecem em "para avaliar"
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s16, Ds.s8, Ds.s8),
            child: DsCardTitle(
              Icons.checklist_rounded,
              tr('Tarefas'),
              trailing: TextButton.icon(
                onPressed: () => _taskDialog(context, s),
                icon: const Icon(Icons.add),
                label: Text(tr('Nova tarefa')),
              ),
            ),
          ),
          if (s.tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Ds.s16, 0, Ds.s16, Ds.s16),
              child: Text(tr('Nenhuma tarefa. Toque em "Nova tarefa" para passar escala, lição, repertório ou atividade.'), style: Ds.support()),
            ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: Ds.s16), child: _pendingBanner(s)),
          for (final t in s.tasks.where((x) => !reviewIds.contains(x.id)))
            DsTaskRow(
              icon: _kindIcon(t.kind),
              title: t.title,
              support: t.isScale ? tr('Meta {0}% de acerto', [(t.goal * 100).round()]) : t.kind.label,
              status: _statusFor(s, t),
              onTap: () => showReviewSheet(context, app, s, t),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (t.isScale && !t.done)
                  IconButton.filledTonal(
                    tooltip: tr('Iniciar'),
                    style: IconButton.styleFrom(minimumSize: const Size(Ds.tap, Ds.tap)),
                    onPressed: () => _startTask(context, s, t),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                PopupMenuButton<String>(
                  tooltip: tr('Opções da tarefa'),
                  onSelected: (v) {
                    if (v == 'edit') _taskDialog(context, s, edit: t);
                    if (v == 'delete') app.removeAssignment(s, t.id);
                  },
                  itemBuilder: (c) => [
                    PopupMenuItem(value: 'edit', child: Text(tr('Editar'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Apagar'))),
                  ],
                ),
              ]),
            ),
          const SizedBox(height: Ds.s8),
        ],
      ),
    );
  }

  /// "N tarefas ainda não enviadas" com o botão de enviar (fora de aula e com envio possível).
  Widget _pendingBanner(Student s) {
    final n = app.pendingTaskCount(s);
    if (n == 0 || !app.deliveryFor(s).canSend) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.flat.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.schedule_send_outlined, size: 20, color: AppColors.flat),
        const SizedBox(width: 10),
        Expanded(
          child: Text(tr('{0} tarefa{1} ainda não enviada{2} a {3}.', [n, n == 1 ? '' : 's', n == 1 ? '' : 's', s.name]),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        FilledButton.tonal(
          onPressed: () => app.say(app.sendPendingTasks(s)),
          child: Text(tr('Enviar')),
        ),
      ]),
    );
  }

  static IconData _kindIcon(TaskKind k) => switch (k) {
        TaskKind.scale => Icons.piano,
        TaskKind.method => Icons.menu_book_outlined,
        TaskKind.repertoire => Icons.library_music_outlined,
        TaskKind.free => Icons.edit_note,
        TaskKind.material => Icons.folder_open_rounded,
      };

  Future<void> _startTask(BuildContext context, Student s, Assignment t) async {
    // O resultado só entra no histórico do aluno se a aula com ele estiver em andamento.
    if (!app.hasLessonWith(s.id) && app.lesson == null) {
      final start = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Começar a aula com {0}?', [app.labelOf(s)])),
          content: Text(tr('Em aula, o resultado do exercício entra no histórico do aluno. Sem aula, o exercício fica só no seu próprio histórico.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Só treinar'))),
            FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.play_arrow, size: 18), label: Text(tr('Começar a aula'))),
          ],
        ),
      );
      if (start == true) app.startLesson(s);
    }
    if (!context.mounted) return;
    app.setScale(tonicPc: t.tonicPc, type: ScaleType.values[t.scaleTypeIndex], octaves: t.octaves);
    app.startExercise();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScaleExercisePage(app: app)));
  }

  /// Criar ([edit] nulo) ou editar uma tarefa, pelo formulário em tela cheia. Depois de criar,
  /// envia na hora se o professor deixou ligado e a regra de entrega permite (não precisa
  /// estar em aula); em aula, a tarefa vai junto quando a aula for encerrada.
  Future<void> _taskDialog(BuildContext context, Student s, {Assignment? edit}) async {
    final d = await openTaskForm(context, app, s, edit: edit);
    if (d == null) return;
    if (edit != null) {
      app.editAssignment(s, edit.id,
          subject: edit.isScale ? null : d.subject, detail: edit.isScale ? null : d.detail, note: d.note);
      app.say(tr('Tarefa salva.'));
      return;
    }
    final rule = app.deliveryFor(s);
    if (d.kind == TaskKind.scale) {
      app.addAssignment(s,
          title: d.title,
          scaleTypeIndex: d.scaleType.index,
          tonicPc: d.tonicPc,
          octaves: d.octaves,
          goal: d.goal,
          note: d.note);
    } else {
      app.addAssignment(s,
          title: d.title, kind: d.kind, subject: d.subject, detail: d.detail, note: d.note);
    }
    if (rule.mode == DeliveryMode.inLesson) {
      app.say(tr('Tarefa passada. Vai para {0} quando você encerrar a aula.', [s.name]));
    } else if (d.sendNow && rule.canSend) {
      if (rule.mode == DeliveryMode.now) app.celebrateNextDelivery(s.code);
      app.say(app.sendPendingTasks(s));
    } else if (rule.mode == DeliveryMode.localOnly) {
      app.say(tr('Tarefa passada. Fica só na sua ficha: {0} ainda não pode receber.', [s.name]));
    } else {
      app.say(tr('Tarefa passada. Ainda não foi enviada: use "Enviar" na ficha ou ela vai com a próxima aula.'));
    }
  }

  /// Aulas já dadas a este aluno e se foram enviadas.
  Widget _lessonHistoryBody(Student s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in s.lessons.take(8))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              l.sent == true ? Icons.mark_email_read_outlined : (l.sent == false ? Icons.schedule_send_outlined : Icons.phone_android),
              color: l.sent == true ? AppColors.inTune : (l.sent == false ? AppColors.flat : AppColors.textDim),
            ),
            title: Text(l.durationSec == 0
                ? tr('{0} · tarefas enviadas fora de aula', [fmtDayMonth(l.endedAt)])
                : tr('{0} · aula de {1}', [fmtDayMonth(l.endedAt), fmtLessonDuration(l.durationSec)])),
            subtitle: Text(
              tr('{0} tarefa{1}{2} · {3}', [l.taskCount, l.taskCount == 1 ? '' : 's', l.noteCount > 0 ? tr(', {0} observaç{1}', [l.noteCount, l.noteCount == 1 ? tr('ão') : tr('ões')]) : '', l.sent == true ? tr('enviada ao aluno') : (l.sent == false ? tr('aguardando envio') : tr('só neste aparelho'))]),
              style: Ds.support(),
            ),
            trailing: l.sent == false ? TextButton(onPressed: app.flushLessons, child: Text(tr('Enviar'))) : null,
          ),
      ],
    );
  }

  Widget _sessionsBody(Student s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.sessions.isEmpty) Text(tr('Quando este aluno estiver "em aula", os resultados aparecem aqui.'), style: Ds.support()),
        for (final r in s.sessions.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Ds.s8),
            child: Row(children: [
              SizedBox(width: 48, child: Text(fmtDayMonth(r.date), style: Ds.support())),
              Expanded(child: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: (r.accuracy >= 0.8 ? AppColors.inTune : (r.accuracy >= 0.5 ? AppColors.flat : AppColors.sharp)).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${(r.accuracy * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
      ],
    );
  }

  Future<void> _newNote(BuildContext context, Student s) async {
    final t = await askText(context, tr('Nova observação'), tr('O que anotar?'), multiline: true, voice: app);
    if (t != null) app.addTeacherNote(s, t);
  }
}

/// Cartão de aula na ficha do aluno: começar, pausar, retomar e encerrar. Ao encerrar, as
/// tarefas e observações passadas durante a aula vão para o aluno.
class _LessonCard extends StatefulWidget {
  final AppState app;
  final Student student;
  final VoidCallback onNewTask;
  final VoidCallback onNewNote;
  const _LessonCard({required this.app, required this.student, required this.onNewTask, required this.onNewNote});

  @override
  State<_LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<_LessonCard> {
  Timer? _tick;

  AppState get app => widget.app;
  Student get s => widget.student;

  @override
  void initState() {
    super.initState();
    // Relógio da aula: atualiza o tempo a cada segundo enquanto ela corre.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final l = app.lesson;
      if (mounted && l != null && l.studentId == s.id && !l.paused) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _clock(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, sec = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Se algo impede o envio ao aluno (sem código, vínculo desligado…), o texto que explica; no normal, null.
  String? _destinationIssue() {
    if (s.code == null) {
      return tr('Sem o código do aluno, a aula fica só neste aparelho.');
    }
    if (!app.linkEnabled) {
      return tr('O vínculo online está desligado: a aula fica guardada e é enviada quando você ligá-lo (Minha conta).');
    }
    if (app.linkUnavailable) return tr('O servidor ainda não recebe aulas: ela fica guardada e vai quando ficar disponível.');
    if (s.linkState != 'active') {
      return tr('O aluno ainda não está vinculado: a aula fica guardada e vai quando ele se vincular.');
    }
    if (app.deliveryIssue[s.code] == 'not_ready') {
      return tr('O app de {0} ainda não ligou o "Vínculo online": a aula fica na fila e chega assim que ele ligar. Você pode mandar um convite pela ficha.', [s.name]);
    }
    return null;
  }

  /// Para onde a aula vai ao encerrar (usado na confirmação de encerrar).
  String _destination() =>
      _destinationIssue() ?? tr('Ao encerrar, as tarefas e observações desta aula vão para {0}, em Estudo › Tarefas do professor.', [s.name]);

  Future<void> _end() async {
    final tally = app.lessonTally();
    final l = app.lesson;
    if (l == null) return;
    final dur = fmtLessonDuration(l.elapsed(DateTime.now()).inSeconds);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Encerrar a aula?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Duração: {0}', [dur])),
            const SizedBox(height: 6),
            Text(tr('Será enviado ao aluno: {0} tarefa{1} e {2} observaç{3}.', [tally.tasks, tally.tasks == 1 ? '' : 's', tally.notes, tally.notes == 1 ? tr('ão') : tr('ões')])),
            if (tally.tasks == 0) ...[
              const SizedBox(height: 6),
              Text(tr('Nenhuma tarefa foi passada nesta aula. Para passar uma, volte e toque em "Nova tarefa".'),
                  style: TextStyle(color: AppColors.flat)),
            ],
            const SizedBox(height: 8),
            Text(_destination(), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Continuar aula'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Encerrar aula'))),
        ],
      ),
    );
    if (ok != true) return;
    final rec = app.endLesson();
    if (rec == null) return;
    app.say(rec.sent == false
        ? tr('Aula encerrada. Enviando para {0}…', [s.name])
        : tr('Aula encerrada e guardada neste aparelho.'));
  }

  /// "Aula de hoje às 17:00" quando há uma aula deste aluno por perto (a que ele pode estar perdendo); senão null.
  String? _momentLesson() {
    final code = s.code;
    if (code == null) return null;
    final now = DateTime.now();
    final o = lessonForAbsence(app.slotsOf(code), now.millisecondsSinceEpoch);
    if (o == null) return null;
    final hm = '${o.start.hour.toString().padLeft(2, '0')}:${o.start.minute.toString().padLeft(2, '0')}';
    final today = o.start.year == now.year && o.start.month == now.month && o.start.day == now.day;
    return today ? tr('Aula de hoje às {0}', [hm]) : tr('Aula às {0}', [hm]);
  }

  String _absenceSummary() {
    final n = s.absences.length;
    final d = DateTime.fromMillisecondsSinceEpoch(s.absences.first.lessonMs);
    return tr('{0} falta{1} registrada{2} · última em {3}', [n, n == 1 ? '' : 's', n == 1 ? '' : 's', fmtDayMonth(d)]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final l = app.lesson;
        final mine = l != null && l.studentId == s.id;
        if (!mine) {
          final other = l == null ? null : app.studentById(l.studentId);
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.school_outlined, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('Aula'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                ]),
                if (other != null || _destinationIssue() != null) ...[
                  const SizedBox(height: Ds.s8),
                  Text(
                    other != null ? tr('Há uma aula em andamento com {0}. Encerre-a para começar outra.', [other.name]) : _destinationIssue()!,
                    style: Ds.support(),
                  ),
                  // Sem código o aluno não recebe nada: o caminho para resolver fica ali mesmo, sem procurar no menu.
                  if (other == null && s.code == null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(minimumSize: const Size(0, Ds.tap), padding: EdgeInsets.zero),
                        onPressed: () => editStudentCode(context, app, s),
                        icon: const Icon(Icons.pin_outlined, size: 18),
                        label: Text(tr('Informar o código do aluno')),
                      ),
                    ),
                ],
                const SizedBox(height: Ds.s16),
                if (other != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: other.id)),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(tr('Ir para a aula de {0}', [other.name])),
                  )
                else ...[
                  // Duas rotas claras para quando o aluno chega ou não: começar a aula ou registrar que não veio.
                  if (_momentLesson() != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Ds.s12),
                      child: Row(children: [
                        Icon(Icons.schedule, size: 16, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Text(_momentLesson()!, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.accent)),
                      ]),
                    ),
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        onPressed: () async {
                          // Primeiro confere o que o aluno marcou como feito desde a última aula.
                          await showValidationDialog(context, app, s);
                          final err = app.startLesson(s);
                          app.say(err ?? tr('Aula começou. As tarefas e observações que você passar agora vão para {0} ao encerrar.', [s.name]));
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Começar a aula'), style: TextStyle(fontWeight: FontWeight.w800))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        onPressed: () => absenceFlow(context, app, s),
                        icon: const Icon(Icons.person_off_outlined, size: 19),
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Aluno faltou'), style: TextStyle(fontWeight: FontWeight.w700))),
                      ),
                    ),
                  ]),
                  if (s.absences.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(Icons.person_off_outlined, size: 16, color: AppColors.textDim),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_absenceSummary(), style: TextStyle(fontSize: 12.5, color: AppColors.textDim))),
                        TextButton(
                          style: TextButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: () {
                            if (app.undoLastAbsence(s)) app.say(tr('Registro desfeito.'));
                          },
                          child: Text(tr('Desfazer última')),
                        ),
                      ]),
                    ),
                ],
              ],
            ),
          );
        }
        final paused = l.paused;
        final tally = app.lessonTally();
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(paused ? Icons.pause_circle_outline : Icons.fiber_manual_record,
                    color: paused ? AppColors.flat : AppColors.sharp, size: paused ? 22 : 16),
                const SizedBox(width: 8),
                Text(paused ? tr('Aula pausada') : tr('Aula em andamento'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                Text(_clock(l.elapsed(DateTime.now())),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 4),
              Text(
                tr('{0} tarefa{1} e {2} observaç{3} nesta aula até agora.', [tally.tasks, tally.tasks == 1 ? '' : 's', tally.notes, tally.notes == 1 ? tr('ão') : tr('ões')]),
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              // Atalhos: passar tarefa e anotar sem sair do cartão da aula.
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: widget.onNewTask,
                    icon: const Icon(Icons.add_task, size: 18),
                    label: Text(tr('Nova tarefa')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: widget.onNewNote,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(tr('Anotar')),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: paused ? app.resumeLesson : app.pauseLesson,
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                    label: Text(paused ? tr('Retomar') : tr('Pausar')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: AppColors.sharp,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _end,
                    icon: const Icon(Icons.stop),
                    label: Text(tr('Encerrar')),
                  ),
                ),
              ]),
              if (_destinationIssue() != null) ...[
                const SizedBox(height: Ds.s8),
                Text(_destinationIssue()!, style: Ds.support()),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _discard,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(tr('Descartar esta aula')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Descartar a aula?')),
        content: Text(tr('A aula é apagada e nada é enviado ao aluno. As tarefas e observações que você já passou continuam na ficha dele.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Voltar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Descartar'))),
        ],
      ),
    );
    if (ok == true) {
      app.cancelLesson();
      app.say(tr('Aula descartada.'));
    }
  }
}

/// Faixa no topo da área do professor: mostra a aula em andamento (e leva até ela) ou explica
/// onde se começa uma.
class LessonBanner extends StatefulWidget {
  final AppState app;
  const LessonBanner({super.key, required this.app});

  @override
  State<LessonBanner> createState() => LessonBannerState();
}

class LessonBannerState extends State<LessonBanner> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      final l = widget.app.lesson;
      if (mounted && l != null && !l.paused) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final l = app.lesson;
    final s = app.lessonStudent;
    if (l == null || s == null) {
      return AppCard(
        child: Row(children: [
          Icon(Icons.school_outlined, color: AppColors.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr('Para dar uma aula, abra o aluno e toque em "Começar a aula".'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ),
        ]),
      );
    }
    final d = l.elapsed(DateTime.now());
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0'), ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    final clock = d.inHours > 0 ? '${d.inHours}:$mm:$ss' : '$mm:$ss';
    return Material(
      color: AppColors.accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: s.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(l.paused ? Icons.pause_circle_outline : Icons.fiber_manual_record,
                color: l.paused ? AppColors.flat : AppColors.sharp),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('{0} com {1}', [l.paused ? tr('Aula pausada') : tr('Aula em andamento'), app.labelOf(s)]),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Text(clock, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
