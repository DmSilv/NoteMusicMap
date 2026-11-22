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
  final v = await showDsFormSheet<String>(
    context,
    title: title,
    primaryLabel: action ?? tr('Salvar'),
    onSubmit: (c, setS) => ctl.text,
    body: (c, setS) => TextField(
      controller: ctl,
      inputFormatters: [SafeText(multiline ? kMaxNote : kMaxTitle, multiline: multiline)],
      autofocus: true,
      minLines: multiline ? 4 : 1,
      maxLines: multiline ? 10 : 1,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        // Microfone para ditar (só onde o texto é livre).
        suffixIcon: voice == null ? null : DictationButton(app: voice, controller: ctl),
      ),
    ),
  );
  ctl.dispose();
  return v;
}

/// Confirma uma exclusão que não tem volta: o botão só libera depois de digitar uma palavra simples (EXCLUIR).
Future<bool> confirmDelete(BuildContext context, String title, String text) => showDsConfirm(
      context,
      title: title,
      body: text,
      icon: Icons.delete_outline_rounded,
      danger: true,
      typedWord: tr('EXCLUIR'),
      confirmLabel: tr('Excluir'),
    );

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
            actions: app.fichaNovaOn ? const [] : [
              PopupMenuButton<String>(
                onSelected: (v) => _menu(context, s, v),
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
            child: app.fichaNovaOn ? _novaFicha(context, s, sum, tips) : ListView(
              padding: Ds.screen,
              children: [
                ..._linkNotices(context, s),
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

  /// As ações do menu da barra (e, na ficha nova, das linhas de Combinados).
  Future<void> _menu(BuildContext context, Student s, String v) async {
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
  }

  // ---------------- Ficha nova (chave ficha_nova) ----------------
  // Regras visuais: bloco = contêiner com borda; botão = quadrado com ícone; aviso = faixa colorida com borda;
  // informação = texto cinza com ícone e, se der, um link; linha que abre = contêiner com seta.

  Widget _box({required Widget child, EdgeInsets padding = const EdgeInsets.all(Ds.s12), Color? border, Color? fill}) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: fill ?? AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border ?? AppColors.outline, width: 1),
        ),
        child: child,
      );

  /// Aviso: faixa colorida com ícone, sem cara de botão; a ação (se houver) é uma pílula pequena com ícone.
  Widget _notice({required IconData icon, required String text, required Color color, String? actionLabel, IconData? actionIcon, VoidCallback? onAction}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.65), width: 1),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2))),
        if (onAction != null) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.7))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (actionIcon != null) ...[Icon(actionIcon, size: 16, color: color), const SizedBox(width: 4)],
                Text(actionLabel ?? '', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  /// Informação: texto cinza com ícone pequeno e um link opcional (não é botão nem aviso).
  Widget _infoLine(IconData icon, String text, {String? link, VoidCallback? onLink, Color? color}) {
    final c = color ?? AppColors.textDim;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: c, fontSize: 12.5, height: 1.25))),
        if (link != null)
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: onLink,
            child: Text(link, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }

  /// Linha que abre algo: contêiner com ícone, título, resumo e seta.
  Widget _openLine(IconData icon, String title, String sub, VoidCallback onTap, {bool alert = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: _box(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Icon(icon, size: 22, color: alert ? AppColors.sharp : AppColors.text),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ds.support()),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
        ]),
      ),
    );
  }

  /// "Aula aaaa" quando há uma aula deste aluno por perto; senão null.
  String? _momentLessonText(Student s) {
    final code = s.code;
    if (code == null) return null;
    final now = DateTime.now();
    final o = lessonForAbsence(app.slotsOf(code), now.millisecondsSinceEpoch);
    if (o == null) return null;
    final hm = '${o.start.hour.toString().padLeft(2, '0')}:${o.start.minute.toString().padLeft(2, '0')}';
    final today = o.start.year == now.year && o.start.month == now.month && o.start.day == now.day;
    return today ? tr('Aula de hoje às {0}', [hm]) : tr('Aula às {0}', [hm]);
  }

  /// O que impede a aula de chegar ao aluno: frase curta na ficha e a explicação inteira ao tocar em "Ver por quê".
  ({String short, String full, bool needsCode})? _lessonIssue(Student s) {
    if (s.code == null) {
      final t = tr('Sem o código do aluno, a aula fica só neste aparelho.');
      return (short: t, full: t, needsCode: true);
    }
    if (!app.linkEnabled) {
      return (short: tr('Vínculo online desligado: a aula fica na fila.'), full: tr('O vínculo online está desligado: a aula fica guardada e é enviada quando você ligá-lo (Minha conta).'), needsCode: false);
    }
    if (app.linkUnavailable) {
      return (short: tr('Servidor sem receber aulas: fica na fila.'), full: tr('O servidor ainda não recebe aulas: ela fica guardada e vai quando ficar disponível.'), needsCode: false);
    }
    if (s.linkState != 'active') {
      return (short: tr('Aluno ainda sem vínculo: a aula fica na fila.'), full: tr('O aluno ainda não está vinculado: a aula fica guardada e vai quando ele se vincular.'), needsCode: false);
    }
    if (app.deliveryIssue[s.code] == 'not_ready') {
      return (
        short: tr('O app do aluno não ligou o vínculo: a aula fica na fila.'),
        full: tr('O app de {0} ainda não ligou o "Vínculo online": a aula fica na fila e chega assim que ele ligar. Você pode mandar um convite pela ficha.', [s.name]),
        needsCode: false
      );
    }
    return null;
  }

  Future<void> _explain(BuildContext context, String text) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(text),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Entendi')))],
        ),
      );

  /// O vínculo com este aluno: se ele saiu, "Convidar de novo"; se voltou, oferece reenviar as tarefas em aberto.
  List<Widget> _linkNotices(BuildContext context, Student s) {
    final out = <Widget>[];
    if (s.linkState == 'ended') {
      out.add(_notice(
        icon: Icons.link_off_rounded,
        text: tr('{0} encerrou o vínculo. O histórico é seu.', [s.name]),
        color: AppColors.flat,
        actionLabel: tr('Convidar de novo'),
        actionIcon: Icons.send_rounded,
        onAction: () => shareTeacherInvite(app),
      ));
    }
    final open = app.openTaskCount(s);
    if (app.relinkOffers.contains(s.id) && s.linkState == 'active') {
      out.add(_notice(
        icon: Icons.link_rounded,
        text: open == 0 ? tr('{0} voltou a ser seu aluno.', [s.name]) : tr('{0} voltou. Reenviar as {1} tarefas em aberto?', [s.name, open]),
        color: AppColors.inTune,
        actionLabel: open == 0 ? null : tr('Reenviar'),
        actionIcon: open == 0 ? null : Icons.send_rounded,
        onAction: open == 0 ? null : () => app.say(app.resendOpenTasks(s)),
      ));
      out.add(_infoLine(Icons.close_rounded, tr('Os envios de antes foram apagados quando ele saiu.'), link: tr('Agora não'), onLink: () => app.dismissRelinkOffer(s)));
    }
    return [for (final w in out) Padding(padding: const EdgeInsets.only(bottom: Ds.s8), child: w)];
  }

  Widget _novaFicha(BuildContext context, Student s, StudentSummary sum, List<Insight> tips) {
    final l = app.lesson;
    final mine = l != null && l.studentId == s.id;
    final other = (l != null && !mine) ? app.studentById(l.studentId) : null;
    final awaiting = app.awaitingOf(s);
    final awaitIds = {for (final x in awaiting) x.id};
    final open = [for (final x in s.tasks) if (!x.done && !awaitIds.contains(x.id)) x];
    final done = [for (final x in s.tasks) if (x.done) x];
    final issue = _lessonIssue(s);
    final moment = _momentLessonText(s);
    final waiting = s.lessons.where((r) => r.sent == false).length;
    final deliveryShown = waiting > 0 && s.code != null && s.linkState != 'ended';
    final n = s.lessons.length;
    final notePreview = s.notes.isEmpty ? tr('Anote pontos de atenção, elogios e combinados.') : s.notes.first.text;
    return ListView(
      padding: Ds.screen,
      children: [
        _box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StudentIdentity(app: app, student: s),
            const SizedBox(height: Ds.s12),
            if (mine)
              _LessonCard(app: app, student: s, strip: true, onNewTask: () => _taskDialog(context, s), onNewNote: () => _newNote(context, s))
            else
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _ActBtn(
                  icon: Icons.play_arrow_rounded,
                  label: tr('Aula'),
                  primary: true,
                  onTap: () async {
                    if (other != null) {
                      app.say(tr('Há uma aula em andamento com {0}. Encerre-a para começar outra.', [other.name]));
                      return;
                    }
                    // Primeiro confere o que o aluno marcou como feito desde a última aula.
                    await showValidationDialog(context, app, s);
                    final err = app.startLesson(s);
                    app.say(err ?? tr('Aula começou. As tarefas e observações que você passar agora vão para {0} ao encerrar.', [s.name]));
                  },
                ),
                _ActBtn(icon: Icons.person_off_outlined, label: tr('Faltou'), onTap: () => absenceFlow(context, app, s)),
                _ActBtn(icon: Icons.add_task_rounded, label: tr('Tarefa'), onTap: () => _taskDialog(context, s)),
                _ActBtn(icon: Icons.edit_note_rounded, label: tr('Anotar'), onTap: () => _newNote(context, s)),
              ]),
          ]),
        ),
        if (!mine && other != null) ...[
          const SizedBox(height: Ds.s8),
          _notice(
            icon: Icons.school_outlined,
            text: tr('Há uma aula em andamento com {0}.', [other.name]),
            color: AppColors.flat,
            actionLabel: tr('Ir'),
            actionIcon: Icons.arrow_forward_rounded,
            onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: other.id))),
          ),
        ],
        const SizedBox(height: Ds.s8),
        ..._linkNotices(context, s),
        if (awaiting.isNotEmpty) ...[
          const SizedBox(height: Ds.s8),
          _notice(
            icon: Icons.checklist_rounded,
            text: awaiting.length == 1 ? tr('1 tarefa para avaliar') : tr('{0} tarefas para avaliar', [awaiting.length]),
            color: AppColors.sharp,
            actionLabel: tr('Avaliar'),
            actionIcon: Icons.check_rounded,
            onAction: () => showValidationDialog(context, app, s),
          ),
        ],
        const SizedBox(height: Ds.s8),
        if (!mine && moment != null) _infoLine(Icons.schedule, moment, color: AppColors.info),
        if (issue != null && !mine)
          _infoLine(Icons.info_outline_rounded, issue.short,
              link: issue.needsCode ? tr('Informar') : tr('Ver por quê'),
              onLink: issue.needsCode ? () => editStudentCode(context, app, s) : () => _explain(context, issue.full)),
        if (deliveryShown)
          _infoLine(Icons.cloud_off_outlined, tr('Aguardando envio para {0}', [s.name]),
              link: tr('Ver por quê'),
              onLink: () => showDsSheet(context, title: tr('Envio para {0}', [s.name]), listenable: app, children: (c) => [_deliveryCard(context, s)])),
        if (s.absences.isNotEmpty && !mine)
          _infoLine(Icons.person_off_outlined, tr('{0} falta{1} registrada{2} · última em {3}', [
            s.absences.length,
            s.absences.length == 1 ? '' : 's',
            s.absences.length == 1 ? '' : 's',
            fmtDayMonth(DateTime.fromMillisecondsSinceEpoch(s.absences.first.lessonMs))
          ]),
              link: tr('Desfazer última'),
              onLink: () {
                if (app.undoLastAbsence(s)) app.say(tr('Registro desfeito.'));
              }),
        const SizedBox(height: Ds.s8),
        _openBox(context, s, open),
        if (done.isNotEmpty) ...[const SizedBox(height: Ds.s12), _doneBox(context, s, done)],
        const SizedBox(height: Ds.s12),
        _openLine(Icons.insights_rounded, tr('Desempenho'),
            sum.sessions == 0 ? tr('Ainda sem exercícios') : tr('{0} sessões · média {1}%', [sum.sessions, (sum.recentAverage! * 100).round()]), () => _openPerformance(context, s, sum, tips)),
        const SizedBox(height: Ds.s8),
        _openLine(Icons.edit_note_rounded, tr('Observações'), notePreview, () => _openNotes(context, s)),
        if (n > 0) ...[
          const SizedBox(height: Ds.s8),
          _openLine(Icons.history_rounded, tr('Aulas dadas'), n == 1 ? tr('1 aula') : tr('{0} aulas', [n]), () => _openLessons(context, s), alert: s.lessons.any((r) => r.sent == false)),
        ],
        const SizedBox(height: Ds.s8),
        _openLine(Icons.badge_outlined, tr('Dados do aluno'), tr('Código, instrumento, relatório'),
            () => showDsSheet(context, title: tr('Dados do aluno'), listenable: app, children: (c) => _combinados(context, s))),
        const SizedBox(height: Ds.s16),
      ],
    );
  }

  /// "Em aberto": o que ainda não foi concluído. Mostra 5; "Ver as N" abre o resto na própria lista.
  Widget _openBox(BuildContext context, Student s, List<Assignment> open) {
    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.checklist_rounded, size: 20, color: AppColors.text),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Em aberto · {0}', [open.length]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          _SquareIcon(icon: Icons.add_rounded, tooltip: tr('Nova tarefa'), onTap: () => _taskDialog(context, s)),
        ]),
        if (open.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Ds.s8),
            child: Text(tr('Nenhuma tarefa em aberto. Toque em + para passar escala, lição ou repertório.'), style: Ds.support()),
          )
        else
          _Fold(builder: (all, toggle) {
            final shown = all ? open : open.take(5).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < shown.length; i++) _taskRow(context, s, shown[i], first: i == 0),
              if (open.length > 5)
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 40), padding: EdgeInsets.zero),
                  onPressed: toggle,
                  icon: Icon(all ? Icons.expand_less_rounded : Icons.arrow_forward_rounded, size: 18),
                  label: Text(all ? tr('Mostrar menos') : tr('Ver as {0} em aberto', [open.length])),
                ),
            ]);
          }),
      ]),
    );
  }

  /// "Concluídas": recolhidas, só com o número; abrir mostra as últimas.
  Widget _doneBox(BuildContext context, Student s, List<Assignment> done) {
    return _Fold(builder: (all, toggle) {
      return _box(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: toggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                Icon(Icons.check_circle_outline_rounded, size: 20, color: AppColors.inTune),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('Concluídas · {0}', [done.length]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
                Icon(all ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textDim),
              ]),
            ),
          ),
          if (all)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(children: [for (var i = 0; i < done.length && i < 15; i++) _taskRow(context, s, done[i], first: i == 0)]),
            ),
        ]),
      );
    });
  }

  /// Uma tarefa: ícone do tipo, título e uma frase; à direita, tocar (escala em aberto) ou o estado em ícone. Tocar na linha abre as opções.
  Widget _taskRow(BuildContext context, Student s, Assignment t, {bool first = false}) {
    final st = _statusFor(s, t);
    final play = t.isScale && !t.done;
    return InkWell(
      onTap: () => _taskOptions(context, s, t),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: Ds.tap),
        decoration: first ? null : BoxDecoration(border: Border(top: BorderSide(color: AppColors.outline.withValues(alpha: 0.5)))),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(9)),
            child: Icon(_kindIcon(t.kind), size: 18, color: AppColors.text),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              Text(t.isScale ? tr('Meta {0}% de acerto', [(t.goal * 100).round()]) : t.kind.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ds.support()),
            ]),
          ),
          if (play)
            _SquareIcon(icon: Icons.play_arrow_rounded, tooltip: tr('Iniciar'), onTap: () => _startTask(context, s, t))
          else
            Tooltip(
              message: st?.text ?? (t.done ? tr('validada') : tr('pendente')),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(st?.icon ?? (t.done ? Icons.verified_rounded : Icons.schedule_rounded), size: 20, color: st?.color ?? (t.done ? AppColors.inTune : AppColors.textDim)),
              ),
            ),
        ]),
      ),
    );
  }

  void _taskOptions(BuildContext context, Student s, Assignment t) {
    showDsSheet(context, title: t.title, listenable: app, children: (c) => [
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              DsNavRow(Icons.fact_check_outlined, tr('Ver e avaliar'), t.kind.label, () {
                Navigator.of(c).pop();
                showReviewSheet(context, app, s, t);
              }),
              const Divider(height: 1),
              DsNavRow(Icons.edit_outlined, tr('Editar'), tr('Mudar título, meta ou detalhes'), () {
                Navigator.of(c).pop();
                _taskDialog(context, s, edit: t);
              }),
              const Divider(height: 1),
              DsNavRow(Icons.delete_outline_rounded, tr('Apagar'), tr('Tira a tarefa da ficha'), () {
                Navigator.of(c).pop();
                app.removeAssignment(s, t.id);
              }),
            ]),
          ),
        ]);
  }

  void _openPerformance(BuildContext context, Student s, StudentSummary sum, List<Insight> tips) {
    showDsSheet(context, title: tr('Desempenho'), listenable: app, children: (c) => [
          FramelessScope(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          ),
        ]);
  }

  void _openNotes(BuildContext context, Student s) {
    showDsSheet(context, title: tr('Observações'), listenable: app, children: (c) => [
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
        ]);
  }

  void _openLessons(BuildContext context, Student s) {
    showDsSheet(context, title: tr('Aulas dadas'), listenable: app, children: (c) => [FramelessScope(child: _lessonHistoryBody(s))]);
  }

  List<Widget> _combinados(BuildContext context, Student s) {
    return [
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          DsNavRow(Icons.piano_outlined, tr('Instrumento do aluno'), s.instrument == null ? tr('Escolher') : (teachingById(s.instrument)?.label ?? ''), () => showStudentInstrumentSheet(context, app, s)),
          const Divider(height: 1),
          DsNavRow(Icons.pin_outlined, tr('Código do aluno'), s.code ?? tr('Sem código'), () => _menu(context, s, 'code')),
          const Divider(height: 1),
          DsNavRow(Icons.badge_outlined, tr('Renomear'), app.labelOf(s), () => _menu(context, s, 'rename')),
        ]),
      ),
      const SizedBox(height: Ds.gap),
      Text(tr('Relatórios e dados'), style: Ds.section()),
      const SizedBox(height: Ds.s8),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          DsNavRow(Icons.copy_all_outlined, tr('Copiar relatório'), tr('Para colar numa conversa ou e-mail'), () => _menu(context, s, 'report')),
          const Divider(height: 1),
          DsNavRow(Icons.auto_awesome_outlined, tr('Relatório com IA'), tr('Um texto pronto para enviar'), () => _menu(context, s, 'ai')),
          const Divider(height: 1),
          DsNavRow(Icons.ios_share_outlined, tr('Copiar dados'), tr('Para o outro aparelho: use Importar lá'), () => _menu(context, s, 'data')),
        ]),
      ),
      const SizedBox(height: Ds.gap),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap), foregroundColor: AppColors.sharp),
        onPressed: () => _menu(context, s, 'delete'),
        icon: const Icon(Icons.delete_outline),
        label: Text(tr('Excluir aluno')),
      ),
    ];
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
    if (t.awaitsValidation) return DsStatus(tr('Aluno marcou como feita'), Icons.fact_check_outlined, AppColors.attention);
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
    final t = app.pendingTaskCount(s), o = app.pendingNoteCount(s);
    final n = t + o;
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
          child: Text(
              o == 0
                  ? tr('{0} tarefa{1} ainda não enviada{2} a {3}.', [n, n == 1 ? '' : 's', n == 1 ? '' : 's', s.name])
                  : (t == 0
                      ? (n == 1 ? tr('1 observação ainda não enviada a {0}.', [s.name]) : tr('{0} observações ainda não enviadas a {1}.', [n, s.name]))
                      : tr('{0} itens ainda não enviados a {1}.', [n, s.name])),
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
              '${tr('Aula {0}', [lessonDisplayId(l.id)])}\n${tr('{0} tarefa{1}{2} · {3}', [l.taskCount, l.taskCount == 1 ? '' : 's', l.noteCount > 0 ? tr(', {0} observaç{1}', [l.noteCount, l.noteCount == 1 ? tr('ão') : tr('ões')]) : '', l.sent == true ? tr('enviada ao aluno') : (l.sent == false ? tr('aguardando envio') : tr('só neste aparelho'))])}',
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
    if (t != null) app.say(app.addTeacherNote(s, t));
  }
}

/// Cartão de aula na ficha do aluno: começar, pausar, retomar e encerrar. Ao encerrar, as
/// tarefas e observações passadas durante a aula vão para o aluno.
class _LessonCard extends StatefulWidget {
  final AppState app;
  final Student student;
  final VoidCallback onNewTask;
  final VoidCallback onNewNote;

  /// Faixa da ficha nova: só o estado da aula e os quatro botões (tarefa, anotar, pausar, encerrar).
  final bool strip;
  const _LessonCard({required this.app, required this.student, required this.onNewTask, required this.onNewNote, this.strip = false});

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
                  Icon(Icons.school_outlined, color: AppColors.textDim),
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
                        Icon(Icons.schedule, size: 16, color: AppColors.info),
                        const SizedBox(width: 6),
                        Text(_momentLesson()!, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.info)),
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
        if (widget.strip) {
          final c = paused ? AppColors.flat : AppColors.inTune;
          final issue = _destinationIssue();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.65))),
              child: Row(children: [
                Icon(paused ? Icons.pause_circle_outline_rounded : Icons.fiber_manual_record, color: c, size: paused ? 22 : 14),
                const SizedBox(width: 8),
                Expanded(child: Text(paused ? tr('Aula pausada') : tr('Aula em andamento'), style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 14.5))),
                Text(_clock(l.elapsed(DateTime.now())), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            ),
            const SizedBox(height: Ds.s12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _ActBtn(icon: Icons.add_task_rounded, label: tally.tasks > 0 ? '${tr('Tarefa')} · ${tally.tasks}' : tr('Tarefa'), onTap: widget.onNewTask),
              _ActBtn(icon: Icons.edit_note_rounded, label: tally.notes > 0 ? '${tr('Anotar')} · ${tally.notes}' : tr('Anotar'), onTap: widget.onNewNote),
              _ActBtn(icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded, label: paused ? tr('Retomar') : tr('Pausar'), onTap: paused ? app.resumeLesson : app.pauseLesson),
              _ActBtn(icon: Icons.stop_rounded, label: tr('Encerrar'), danger: true, onTap: _end),
            ]),
            const SizedBox(height: Ds.s8),
            Row(children: [
              Expanded(
                child: Text(issue ?? tr('As tarefas e observações vão para {0} quando você encerrar.', [s.name]), style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.25)),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: _discard,
                child: Text(tr('Descartar'), style: const TextStyle(fontSize: 12.5)),
              ),
            ]),
          ]);
        }
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

/// Quadrado com ícone e o nome embaixo: o botão de ação da ficha nova (o principal vem cheio, só um por tela).
class _ActBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  const _ActBtn({required this.icon, required this.label, required this.onTap, this.primary = false, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final fill = danger ? AppColors.wrong : (primary ? AppColors.accent : AppColors.surface2);
    final fg = (danger || primary) ? AppColors.onAccent : AppColors.text;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 68,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: (danger || primary) ? Colors.transparent : AppColors.outline, width: 1),
              ),
              child: Icon(icon, size: 26, color: fg),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: primary ? FontWeight.w800 : FontWeight.w600, color: primary ? AppColors.text : AppColors.textDim)),
          ]),
        ),
      ),
    );
  }
}

/// Quadradinho só com ícone (adicionar, tocar): 40 px, com dica de ferramenta.
class _SquareIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _SquareIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.outline, width: 1)),
            child: Icon(icon, size: 22, color: AppColors.text),
          ),
        ),
      );
}

/// Lista que mostra um pedaço e abre o resto no mesmo lugar (o estado de aberto fica aqui).
class _Fold extends StatefulWidget {
  final Widget Function(bool open, VoidCallback toggle) builder;
  const _Fold({required this.builder});

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => widget.builder(_open, () => setState(() => _open = !_open));
}

