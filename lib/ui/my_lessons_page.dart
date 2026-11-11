import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'library_page.dart';
import 'theme.dart';
import 'widgets.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

IconData taskKindIcon(TaskKind k) => switch (k) {
      TaskKind.scale => Icons.piano,
      TaskKind.method => Icons.menu_book_outlined,
      TaskKind.repertoire => Icons.library_music_outlined,
      TaskKind.free => Icons.edit_note,
      TaskKind.material => Icons.folder_open_rounded,
    };

void openMyLessons(BuildContext context, AppState app) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MyLessonsPage(app: app)),
    );

/// Cartão do perfil do aluno: resume as aulas recebidas e leva à tela completa.
class MyLessonsCard extends StatelessWidget {
  final AppState app;
  const MyLessonsCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final plan = buildWeekPlan(app.myLessons, app.lessonTasksDone, DateTime.now());
    final n = app.myLessons.length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.checklist_rtl, color: AppColors.accent),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Minhas aulas e tarefas', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            if (plan.open > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${plan.open} em aberto', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            app.myTeachers.isEmpty
                ? 'Vincule-se a um professor para receber aqui as tarefas de cada aula.'
                : (n == 0
                    ? 'Quando seu professor encerrar uma aula, as tarefas dela aparecem aqui.'
                    : '$n aula${n == 1 ? '' : 's'} recebida${n == 1 ? '' : 's'}.'),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => openMyLessons(context, app),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Ver minhas aulas'),
          ),
        ],
      ),
    );
  }
}

/// Área do aluno: o que fazer esta semana e todas as aulas recebidas.
class MyLessonsPage extends StatefulWidget {
  final AppState app;
  const MyLessonsPage({super.key, required this.app});

  @override
  State<MyLessonsPage> createState() => _MyLessonsPageState();
}

class _MyLessonsPageState extends State<MyLessonsPage> {
  AppState get app => widget.app;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    app.watchLinks(); // enquanto a tela está aberta, confere se há aula nova
    WidgetsBinding.instance.addPostFrameCallback((_) => app.markNoticesSeen());
    _pull(announce: false);
  }

  @override
  void dispose() {
    app.unwatchLinks();
    super.dispose();
  }

  Future<void> _pull({bool announce = true}) async {
    if (!app.linkEnabled || app.linkUnavailable) return;
    setState(() => _loading = true);
    await app.pullLessons(announce: announce);
    if (mounted) setState(() => _loading = false);
  }

  void _train(Assignment t) {
    app.setScale(tonicPc: t.tonicPc, type: ScaleType.values[t.scaleTypeIndex % ScaleType.values.length], octaves: t.octaves);
    app.say('Escala escolhida. Abra a aba Grade › Escala para treinar.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final lessons = app.myLessons;
        final plan = buildWeekPlan(lessons, app.lessonTasksDone, DateTime.now());
        return Scaffold(
          appBar: AppBar(
            title: const Text('Minhas aulas'),
            actions: [
              IconButton(
                tooltip: 'Buscar aulas novas',
                onPressed: _loading ? null : _pull,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _pull(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                children: [
                  _statusBanner(),
                  if (lessons.isEmpty)
                    AppCard(
                      child: Text(
                        app.myTeachers.isEmpty
                            ? 'Você ainda não tem professor vinculado. Em Minha conta › Meus professores, leia o QR dele.'
                            : 'Nenhuma aula recebida ainda. Quando seu professor encerrar uma aula, as tarefas '
                                'dela aparecem aqui sozinhas. Para conferir agora, toque em ↻.',
                        style: TextStyle(color: AppColors.textDim),
                      ),
                    )
                  else ...[
                    _weekCard(plan),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
                      child: Text('Todas as aulas',
                          style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    for (final l in lessons) ...[
                      _lessonTile(l),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Avisos de conexão (desligado, servidor indisponível, sem internet).
  Widget _statusBanner() {
    String? msg;
    IconData icon = Icons.cloud_off_outlined;
    Color color = AppColors.textDim;
    if (!app.linkEnabled) {
      msg = 'O vínculo online está desligado: ligue em Minha conta › Vínculo online para receber as aulas.';
    } else if (app.linkUnavailable) {
      msg = 'O servidor ainda não está recebendo aulas. Quando ficar disponível, elas chegam aqui.';
      color = AppColors.flat;
    } else if (app.linkOnline == false) {
      msg = 'Sem conexão agora. O que você já recebeu continua aqui.';
      icon = Icons.sync_problem;
      color = AppColors.flat;
    }
    if (msg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
      ),
    );
  }

  /// "Esta semana": as tarefas das aulas dos últimos 7 dias e as que ficaram em atraso.
  Widget _weekCard(WeekPlan plan) {
    if (plan.isEmpty) {
      return AppCard(
        child: Row(children: [
          Icon(Icons.task_alt, color: AppColors.inTune),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Tudo em dia. Nenhuma tarefa em aberto.', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            const Expanded(
              child: Text('Esta semana', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ),
            Text('até a próxima aula', style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ]),
          const SizedBox(height: 2),
          Text(
            plan.open == 0
                ? 'Todas as ${plan.total} tarefas feitas. Bom trabalho!'
                : '${plan.done} de ${plan.total} tarefas feitas',
            style: TextStyle(color: plan.open == 0 ? AppColors.inTune : AppColors.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: plan.progress,
              minHeight: 6,
              backgroundColor: AppColors.surface2,
              color: AppColors.inTune,
            ),
          ),
          for (final g in plan.week) _weekGroup(g),
          if (plan.late.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Em atraso · aulas anteriores',
                style: TextStyle(color: AppColors.sharp, fontWeight: FontWeight.w800, fontSize: 13)),
            for (final g in plan.late) _weekGroup(g, showDate: true),
          ],
        ],
      ),
    );
  }

  Widget _weekGroup(WeekGroup g, {bool showDate = false}) {
    final l = g.lesson;
    final who = l.teacherLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: l.label,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: '  ·  $who', style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
        ])),
        for (final t in g.tasks) _taskTile(l, t.task, today: t.today, overdue: t.overdue),
      ],
    );
  }

  /// Uma aula na lista completa: recolhida, com as tarefas e as observações dentro.
  Widget _lessonTile(SharedLesson l) {
    final done = l.tasks.where((t) => app.lessonTaskDone(l, t)).length;
    final who = l.teacherLabel;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text('${l.tasksOnly ? 'Tarefas' : 'Aula'} de ${_date(l.date)}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
            '$who${l.durationSec > 0 ? ' · ${fmtLessonDuration(l.durationSec)}' : ''} · '
            '${l.tasks.isEmpty ? 'sem tarefas' : '$done de ${l.tasks.length} feitas'}',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          children: [
            for (final t in l.tasks) _taskTile(l, t),
            if (l.notes.isNotEmpty) ...[
              const Divider(height: 18),
              Text('Observações do professor',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              for (final n in l.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(n, style: const TextStyle(height: 1.3)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Tarefa "Material do professor": abre o acervo dele já filtrado (item, pasta ou tudo).
  void _openMaterial(SharedLesson l, Assignment t) {
    final ref = MaterialRef.fromTask(t.subject, t.detail);
    openLibrary(context, app, teacher: l.teacherCode, teacherName: l.teacherName, focusTitle: ref.title.isEmpty ? null : ref.title, folder: ref.folder.isEmpty ? null : ref.folder);
  }

  Widget _taskTile(SharedLesson l, Assignment t, {bool today = false, bool overdue = false}) {
    final done = app.lessonTaskDone(l, t);
    final st = app.taskStateOf(l, t);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Checkbox(value: done, onChanged: (_) => app.toggleLessonTask(l, t)),
      title: Row(children: [
        Icon(taskKindIcon(t.kind), size: 16, color: AppColors.textDim),
        const SizedBox(width: 6),
        Flexible(
          child: Text(t.title, style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
        ),
        if (!done && overdue) _tag('atrasada', AppColors.sharp),
        if (!done && today && !overdue) _tag('hoje', AppColors.accent),
        if (st == StudentTaskState.validated) _tag('validada', AppColors.inTune),
        if (st == StudentTaskState.claimed) _tag('aguardando o professor', AppColors.accent),
        if (st == StudentTaskState.returned) _tag('refazer', AppColors.sharp),
      ]),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.isScale ? 'Meta ${(t.goal * 100).round()}% de acerto' : t.kind.label,
              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          if (t.note.isNotEmpty) Text(t.note, style: const TextStyle(fontSize: 12.5, height: 1.3)),
        ],
      ),
      trailing: t.isScale
          ? TextButton.icon(onPressed: () => _train(t), icon: const Icon(Icons.play_arrow, size: 18), label: const Text('Treinar'))
          : (t.kind == TaskKind.material
              ? TextButton.icon(onPressed: () => _openMaterial(l, t), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Abrir'))
              : null),
    );
  }

  Widget _tag(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );
}
