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

  /// Tarefas que o professor levou para uma aula mais nova ("idAula:idTarefa"); atualizado a cada desenho.
  Set<String> _carried = {};

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

  /// Tarefa "Material do professor": abre o acervo dele já filtrado (item, pasta ou tudo).
  void _openMaterial(SharedLesson l, Assignment t) {
    final ref = MaterialRef.fromTask(t.subject, t.detail);
    openLibrary(context, app, teacher: l.teacherCode, teacherName: l.teacherName, focusTitle: ref.title.isEmpty ? null : ref.title, folder: ref.folder.isEmpty ? null : ref.folder);
  }

  /// O que o botão principal da tarefa faz (null = a tarefa não tem atalho no app).
  ({IconData icon, String label, VoidCallback run})? _actionOf(SharedLesson l, Assignment t) {
    if (t.isScale) return (icon: Icons.play_arrow_rounded, label: tr('Treinar'), run: () => _train(t));
    if (t.kind == TaskKind.material) return (icon: Icons.open_in_new_rounded, label: tr('Abrir'), run: () => _openMaterial(l, t));
    return null;
  }

  /// A situação mais importante da tarefa (texto, ícone, cor) ou null.
  /// Quem decide é o professor: o aluno não marca nada. Situações: validada, refazer, levada para a próxima aula
  /// (o professor mandou a mesma tarefa de novo, numa aula mais nova) ou atrasada.
  DsStatus? _statusOf(SharedLesson l, Assignment t, bool overdue) {
    final state = app.taskStateOf(l, t);
    if (state == StudentTaskState.validated) return DsStatus(tr('validada'), Icons.verified_rounded, AppColors.inTune);
    if (state == StudentTaskState.returned) return DsStatus(tr('refazer'), Icons.replay_rounded, AppColors.sharp);
    if (_carried.contains('${l.id}:${t.id}')) return DsStatus(tr('levada para a próxima aula'), Icons.redo_rounded, AppColors.flat);
    if (state == StudentTaskState.claimed) return DsStatus(tr('aguardando o professor'), Icons.hourglass_top_rounded, AppColors.accent);
    return overdue ? DsStatus(tr('atrasada'), Icons.schedule_rounded, AppColors.sharp) : null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final lessons = app.myLessons;
        _carried = carriedTaskKeys(lessons);
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
                      for (var i = 0; i < plan.week.length; i++)
                        _lessonSection(plan.week[i].lesson, [for (final w in plan.week[i].tasks) (w.task, w.overdue)], expanded: i == 0),
                    ] else ...[
                      if (older.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: Ds.s24),
                          child: Center(child: Text(tr('Nenhuma aula anterior ainda.'), style: Ds.support())),
                        ),
                      for (final l in older) _lessonSection(l, [for (final t in l.tasks) (t, !app.lessonTaskDone(l, t) && !_carried.contains('${l.id}:${t.id}'))], expanded: false),
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

  /// Uma aula como lista que abre e fecha: fechada mostra só o dia, o professor e quantas tarefas tem;
  /// aberta mostra as tarefas em linhas simples (e o recado do professor, se houver).
  Widget _lessonSection(SharedLesson l, List<(Assignment, bool)> tasks, {required bool expanded}) {
    final who = l.teacherName.trim().isNotEmpty ? l.teacherName.trim() : l.teacherLabel;
    final n = tasks.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.gap),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('lesson-$_tab-${l.id}'),
            initiallyExpanded: expanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: Ds.s16, vertical: Ds.s8),
            childrenPadding: const EdgeInsets.only(bottom: Ds.s8),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            subtitle: Text('$who · ${n == 0 ? tr('sem tarefas') : (n == 1 ? tr('1 tarefa') : tr('{0} tarefas', [n]))}', style: Ds.support()),
            children: [
              if (l.notes.isNotEmpty) _notesRow(l),
              for (final (t, overdue) in tasks) _taskRow(l, t, overdue),
            ],
          ),
        ),
      ),
    );
  }

  /// "Observações do professor": linha padrão com a primeira frase de prévia; abre o texto todo num modal.
  Widget _notesRow(SharedLesson l) => DsTaskRow(
        icon: Icons.chat_bubble_outline_rounded,
        title: tr('Observações do professor'),
        support: l.notes.first,
        trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
        onTap: () => showDsSheet(
          context,
          title: tr('Observações do professor'),
          listenable: app,
          children: (c) => [
            Text(l.label, style: Ds.section()),
            const SizedBox(height: Ds.s12),
            for (final n in l.notes) Padding(padding: const EdgeInsets.only(bottom: Ds.s12), child: Text(n, style: const TextStyle(fontSize: Ds.fontBody, height: 1.4))),
          ],
        ),
      );

  /// Uma tarefa em linha: ícone do tipo, título, UMA linha de apoio (situação ou meta) e o atalho de estudo.
  /// Tocar na linha abre os detalhes num modal.
  Widget _taskRow(SharedLesson l, Assignment t, bool overdue) {
    final validated = app.taskStateOf(l, t) == StudentTaskState.validated;
    final action = _actionOf(l, t);
    return DsTaskRow(
      icon: taskKindIcon(t.kind),
      title: t.title,
      support: t.isScale ? tr('Meta {0}% de acerto', [(t.goal * 100).round()]) : t.kind.label,
      status: _statusOf(l, t, overdue),
      onTap: () => _openTask(l, t, overdue),
      trailing: action != null && !validated
          ? IconButton.filledTonal(
              tooltip: action.label,
              style: IconButton.styleFrom(minimumSize: const Size(Ds.tap, Ds.tap)),
              onPressed: action.run,
              icon: Icon(action.icon),
            )
          : (validated ? Icon(Icons.check_circle_rounded, color: AppColors.inTune) : Icon(Icons.chevron_right_rounded, color: AppColors.textDim)),
    );
  }

  /// Detalhes da tarefa num modal: o que o professor pediu, o botão que leva ao estudo e o aviso opcional "pronta para a aula".
  void _openTask(SharedLesson l, Assignment t, bool overdue) {
    final meta = t.isScale ? tr('Meta {0}% de acerto', [(t.goal * 100).round()]) : t.kind.label;
    showDsSheet(
      context,
      title: t.title,
      listenable: app,
      children: (c) {
        final status = _statusOf(l, t, overdue);
        final action = _actionOf(l, t);
        return [
          Row(children: [
            DsIconBadge(taskKindIcon(t.kind), size: 40),
            const SizedBox(width: Ds.s12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(meta, style: const TextStyle(fontSize: Ds.fontBody, fontWeight: FontWeight.w700)),
                Text(l.label, style: Ds.support()),
              ]),
            ),
          ]),
          if (t.note.isNotEmpty) ...[
            const SizedBox(height: Ds.s16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Ds.s12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
                border: Border(left: BorderSide(color: AppColors.accent, width: 4)),
              ),
              child: Text(t.note, style: const TextStyle(fontSize: Ds.fontBody, height: 1.4)),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: Ds.s12),
            Row(children: [
              Icon(status.icon, size: 18, color: status.color),
              const SizedBox(width: 6),
              Text(status.text, style: TextStyle(fontSize: Ds.fontSupport, fontWeight: FontWeight.w700, color: status.color)),
            ]),
          ],
          if (action != null) ...[
            const SizedBox(height: Ds.s20),
            DsPrimaryButton(
              icon: action.icon,
              label: action.label,
              onPressed: () {
                Navigator.of(c).pop();
                action.run();
              },
            ),
          ],
        ];
      },
    );
  }
}
