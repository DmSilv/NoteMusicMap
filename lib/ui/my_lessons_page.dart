import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'home_tabs.dart';
import 'library_page.dart';
import 'theme.dart';
import 'widgets.dart';

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
            Expanded(
              child: Text(tr('Minhas aulas e tarefas'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            if (plan.open > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(tr('{0} em aberto', [plan.open]), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            app.myTeachers.isEmpty
                ? tr('Vincule-se a um professor para receber aqui as tarefas de cada aula.')
                : (n == 0
                    ? tr('Quando seu professor encerrar uma aula, as tarefas dela aparecem aqui.')
                    : tr('{0} aula{1} recebida{2}.', [n, n == 1 ? '' : 's', n == 1 ? '' : 's'])),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => openMyLessons(context, app),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(tr('Ver minhas aulas')),
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

  /// 0 = Esta semana (o que estudar agora), 1 = Aulas anteriores (histórico).
  int _tab = 0;

  /// Recados que a pessoa abriu ("aulaId"). Começam recolhidos: a tela mostra primeiro o que estudar.
  final Set<String> _notesToggled = {};

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

  /// Escolhe a escala da tarefa e leva direto à aba Escalas (um toque do "o que estudar" ao estudo).
  void _train(Assignment t) {
    app.setScale(tonicPc: t.tonicPc, type: ScaleType.values[t.scaleTypeIndex % ScaleType.values.length], octaves: t.octaves);
    Navigator.of(context).pop();
    app.goTab?.call(kTabScales);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final lessons = app.myLessons;
        final plan = buildWeekPlan(lessons, app.lessonTasksDone, DateTime.now());
        final weekIds = {for (final g in plan.week) g.lesson.id};
        final older = [for (final l in lessons) if (!weekIds.contains(l.id)) l];
        final lateCount = plan.late.fold<int>(0, (a, g) => a + g.tasks.where((t) => !t.done).length);
        final status = _status();
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('Diário de aula')),
            actions: [
              // O aviso de conexão não ocupa a tela: vira um ícone (toque para ler).
              if (status != null)
                IconButton(
                  tooltip: status.$1,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (c) => AlertDialog(
                      icon: Icon(status.$2, color: status.$3),
                      content: Text(status.$1),
                      actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Fechar')))],
                    ),
                  ),
                  icon: Icon(status.$2, color: status.$3),
                ),
              IconButton(
                tooltip: tr('Buscar aulas novas'),
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
                padding: Ds.screen,
                children: [
                  if (lessons.isEmpty)
                    AppCard(
                      child: Text(
                        app.myTeachers.isEmpty
                            ? tr('Você ainda não tem professor vinculado. Em Minha conta › Meus professores, leia o QR dele.')
                            : tr('Nenhuma aula recebida ainda. Quando seu professor encerrar uma aula, as tarefas dela aparecem aqui sozinhas. Para conferir agora, toque em ↻.'),
                        style: TextStyle(color: AppColors.textDim),
                      ),
                    )
                  else ...[
                    _headline(plan),
                    const SizedBox(height: Ds.s16),
                    _tabs(lateCount),
                    const SizedBox(height: Ds.s16),
                    if (_tab == 0) ...[
                      if (plan.week.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: Ds.s24),
                          child: Center(child: Text(tr('Nenhuma tarefa'), style: Ds.support())),
                        ),
                      for (final g in plan.week) _group(g),
                    ] else ...[
                      if (older.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: Ds.s24),
                          child: Center(child: Text(tr('Nenhuma aula anterior ainda.'), style: Ds.support())),
                        ),
                      for (final l in older) _lessonTile(l),
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

  /// Aviso de conexão (desligado, servidor indisponível, sem internet): texto, ícone e cor; null se está tudo bem.
  (String, IconData, Color)? _status() {
    if (!app.linkEnabled) {
      return (tr('O vínculo online está desligado: ligue em Minha conta › Vínculo online para receber as aulas.'), Icons.cloud_off_outlined, AppColors.textDim);
    }
    if (app.linkUnavailable) {
      return (tr('O servidor ainda não está recebendo aulas. Quando ficar disponível, elas chegam aqui.'), Icons.cloud_off_outlined, AppColors.flat);
    }
    if (app.linkOnline == false) {
      return (tr('Sem conexão agora. O que você já recebeu continua aqui.'), Icons.sync_problem, AppColors.flat);
    }
    return null;
  }

  /// A pergunta que o aluno traz ao abrir: "o que eu preciso estudar?".
  Widget _headline(WeekPlan plan) {
    final String big = plan.isEmpty ? tr('Nenhuma tarefa') : (plan.open == 0 ? tr('Tudo em dia') : tr('{0} para estudar', [plan.open]));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(big, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
        if (!plan.isEmpty && plan.open > 0) Text(tr('de {0} esta semana', [plan.total]), style: Ds.support()),
      ]),
    );
  }

  /// Duas abas: o que estudar agora e o histórico. Um ponto laranja avisa que há tarefa atrasada.
  Widget _tabs(int lateCount) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(minimumSize: const Size(0, Ds.tap)),
          segments: [
            ButtonSegment(value: 0, label: Text(tr('Esta semana'))),
            ButtonSegment(
              value: 1,
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(tr('Aulas anteriores'), overflow: TextOverflow.ellipsis)),
                if (lateCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: AppColors.sharp, shape: BoxShape.circle)),
                ],
              ]),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
      );

  /// Uma aula da semana: uma linha de cabeçalho, o recado do professor (aberto) e as tarefas.
  Widget _group(WeekGroup g) {
    final l = g.lesson;
    final who = l.teacherName.trim().isNotEmpty ? l.teacherName.trim() : l.teacherLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, Ds.s8),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: l.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            TextSpan(text: '  ·  $who', style: Ds.support()),
          ])),
        ),
        if (l.notes.isNotEmpty) ...[_notes(l, openByDefault: false), const SizedBox(height: Ds.s8)],
        for (final t in g.tasks) _taskCard(l, t.task, overdue: t.overdue),
      ]),
    );
  }

  /// Recado do professor: uma linha que abre/fecha o texto.
  Widget _notes(SharedLesson l, {required bool openByDefault}) {
    final toggled = _notesToggled.contains(l.id);
    final open = openByDefault ? !toggled : toggled;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
          onTap: () => setState(() => toggled ? _notesToggled.remove(l.id) : _notesToggled.add(l.id)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Ds.tap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Ds.s12),
              child: Row(children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppColors.accent),
                const SizedBox(width: Ds.s8),
                Expanded(child: Text(tr('Observações do professor'), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent))),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.accent),
              ]),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(Ds.s12, 0, Ds.s12, Ds.s8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final n in l.notes)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(n, style: const TextStyle(fontSize: Ds.fontSupport + 1, height: 1.35))),
            ]),
          ),
      ]),
    );
  }

  /// Uma aula do histórico: recolhida; ao abrir mostra as tarefas e as observações.
  Widget _lessonTile(SharedLesson l) {
    final done = l.tasks.where((t) => app.lessonTaskDone(l, t)).length;
    final who = l.teacherName.trim().isNotEmpty ? l.teacherName.trim() : l.teacherLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s8),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: Ds.s16, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(Ds.s12, 0, Ds.s12, Ds.s12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            subtitle: Text(
              '$who · ${l.tasks.isEmpty ? tr('sem tarefas') : tr('{0} de {1} prontas', [done, l.tasks.length])}',
              style: Ds.support(),
            ),
            children: [
              if (l.notes.isNotEmpty) ...[_notes(l, openByDefault: false), const SizedBox(height: Ds.s8)],
              for (final t in l.tasks) _taskCard(l, t, overdue: !app.lessonTaskDone(l, t)),
            ],
          ),
        ),
      ),
    );
  }

  /// Tarefa "Material do professor": abre o acervo dele já filtrado (item, pasta ou tudo).
  void _openMaterial(SharedLesson l, Assignment t) {
    final ref = MaterialRef.fromTask(t.subject, t.detail);
    openLibrary(context, app, teacher: l.teacherCode, teacherName: l.teacherName, focusTitle: ref.title.isEmpty ? null : ref.title, folder: ref.folder.isEmpty ? null : ref.folder);
  }

  /// Ficha de leitura de uma tarefa: o que é (ícone, título, meta), o que o professor pediu (recado) e UM botão
  /// que leva direto ao estudo (escala → aba Escalas; material → acervo). "Pronta para a aula" é só um aviso
  /// opcional ao professor, discreto no canto: ninguém precisa marcar nada todo dia.
  Widget _taskCard(SharedLesson l, Assignment t, {bool overdue = false}) {
    final ready = app.lessonTaskDone(l, t);
    final st = app.taskStateOf(l, t);
    final meta = t.isScale ? tr('Meta {0}% de acerto', [(t.goal * 100).round()]) : t.kind.label;
    final (String, IconData, Color)? status = switch (st) {
      StudentTaskState.returned => (tr('refazer'), Icons.replay_rounded, AppColors.sharp),
      StudentTaskState.claimed => (tr('aguardando o professor'), Icons.hourglass_top_rounded, AppColors.accent),
      StudentTaskState.validated => (tr('validada'), Icons.verified_rounded, AppColors.inTune),
      _ => overdue && !ready ? (tr('atrasada'), Icons.schedule_rounded, AppColors.sharp) : null,
    };
    final action = t.isScale
        ? FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, Ds.tap)),
            onPressed: () => _train(t),
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: Text(tr('Treinar')))
        : (t.kind == TaskKind.material
            ? FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, Ds.tap)),
                onPressed: () => _openMaterial(l, t),
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                label: Text(tr('Abrir')))
            : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s12),
      child: Container(
        padding: const EdgeInsets.all(Ds.s12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DsIconBadge(taskKindIcon(t.kind), size: 44),
            const SizedBox(width: Ds.s12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, style: const TextStyle(fontSize: 17, height: 1.25, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(meta, style: Ds.support()),
                if (t.note.isNotEmpty) ...[
                  const SizedBox(height: Ds.s8),
                  Text(t.note, style: const TextStyle(fontSize: Ds.fontBody, height: 1.35)),
                ],
              ]),
            ),
          ]),
          if (action != null) ...[const SizedBox(height: Ds.s12), action],
          const SizedBox(height: Ds.s4),
          Row(children: [
            if (status != null) ...[
              Icon(status.$2, size: 16, color: status.$3),
              const SizedBox(width: 6),
              Flexible(child: Text(status.$1, style: TextStyle(fontSize: Ds.fontSupport, fontWeight: FontWeight.w700, color: status.$3))),
            ],
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, Ds.tap), foregroundColor: ready ? AppColors.inTune : AppColors.textDim),
              onPressed: () => app.toggleLessonTask(l, t),
              icon: Icon(ready ? Icons.check_circle_rounded : Icons.outlined_flag_rounded, size: 20),
              label: Text(tr('Pronta para a aula')),
            ),
          ]),
        ]),
      ),
    );
  }
}
