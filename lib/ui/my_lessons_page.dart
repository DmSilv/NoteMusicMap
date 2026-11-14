import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
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

  /// Fichas abertas e recados abertos (o resto fica recolhido: a tela mostra só o essencial).
  final Set<String> _expanded = {};
  final Set<String> _notesOpen = {};

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
    app.say(tr('Escala escolhida. Abra a aba Grade › Escala para treinar.'));
    Navigator.of(context).pop();
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
                    _summary(plan),
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

  /// Resumo curto no topo: o estudo de HOJE e a sequência de dias.
  Widget _summary(WeekPlan plan) {
    final now = DateTime.now();
    final (todayDone, todayTotal) = app.practiceToday(plan, now);
    final streak = app.practice.streak(now);
    final allToday = todayTotal > 0 && todayDone >= todayTotal;
    final value = plan.isEmpty ? 1.0 : (todayTotal == 0 ? 0.0 : todayDone / todayTotal);
    return AppCard(
      padding: const EdgeInsets.all(Ds.s16),
      child: Row(children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 7,
                strokeCap: StrokeCap.round,
                backgroundColor: AppColors.surface2,
                color: AppColors.inTune,
              ),
            ),
            plan.isEmpty || allToday
                ? Icon(Icons.check_rounded, color: AppColors.inTune, size: 30)
                : Text('$todayDone/$todayTotal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: Ds.s16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              plan.isEmpty
                  ? tr('Tudo em dia. Nenhuma tarefa em aberto.')
                  : (todayTotal == 0 ? tr('Diário de aula') : tr('{0} de {1} hoje', [todayDone, todayTotal])),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2, color: allToday ? AppColors.inTune : AppColors.text),
            ),
            if (!plan.isEmpty) ...[
              const SizedBox(height: 2),
              Text(
                streak >= 2 ? tr('{0} dias seguidos', [streak]) : (streak == 1 ? tr('1 dia seguido') : tr('Estude hoje para começar sua sequência')),
                style: TextStyle(fontSize: Ds.fontSupport, height: 1.3, color: streak > 0 ? AppColors.inTune : AppColors.textDim, fontWeight: streak > 0 ? FontWeight.w700 : FontWeight.w400),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  /// Uma aula da semana: uma linha de cabeçalho, as tarefas e (se houver) o recado do professor, recolhido.
  Widget _group(WeekGroup g) {
    final l = g.lesson;
    final who = l.teacherName.trim().isNotEmpty ? l.teacherName.trim() : l.teacherLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, Ds.s8),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: l.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            TextSpan(text: '  ·  $who', style: Ds.support()),
          ])),
        ),
        for (final t in g.tasks) _taskCard(l, t.task, overdue: t.overdue),
        if (l.notes.isNotEmpty) _notes(l),
      ]),
    );
  }

  /// Recado do professor: uma linha que abre o texto (não ocupa a tela até a pessoa querer ler).
  Widget _notes(SharedLesson l) {
    final open = _notesOpen.contains(l.id);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
          onTap: () => setState(() => open ? _notesOpen.remove(l.id) : _notesOpen.add(l.id)),
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
              for (final t in l.tasks) _taskCard(l, t, overdue: !app.lessonTaskDone(l, t)),
              if (l.notes.isNotEmpty) _notes(l),
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

  static List<String> get _wd => [tr('seg'), tr('ter'), tr('qua'), tr('qui'), tr('sex'), tr('sáb'), tr('dom')];

  /// A marca do dia: tocar diz "estudei hoje". Zera sozinha amanhã (outro dia, outra marca).
  Widget _todayCheck(SharedLesson l, Assignment t, bool on) => Semantics(
        button: true,
        checked: on,
        label: on ? tr('Desmarcar estudo de hoje') : tr('Estudei hoje'),
        child: InkResponse(
          onTap: () => app.togglePractice(l, t, DateTime.now()),
          radius: 30,
          child: SizedBox(
            width: 56,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? AppColors.inTune : Colors.transparent,
                  border: Border.all(color: on ? AppColors.inTune : AppColors.textDim, width: 2.5),
                ),
                child: on ? Icon(Icons.check_rounded, size: 24, color: AppColors.onAccent) : null,
              ),
              const SizedBox(height: 2),
              Text(tr('hoje'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? AppColors.inTune : AppColors.textDim)),
            ]),
          ),
        ),
      );

  /// Fileira dos últimos 7 dias: cada bolinha é um dia estudado. Dá para marcar um dia que passou (esqueceu de anotar).
  Widget _strip(SharedLesson l, Assignment t) {
    final days = practiceStrip(DateTime.now(), l.date);
    return Row(children: [
      for (final d in days)
        Expanded(
          child: Semantics(
            button: d.enabled,
            checked: app.practicedOn(l, t, d.date),
            label: '${_wd[d.date.weekday - 1]} ${d.date.day}',
            child: InkResponse(
              onTap: d.enabled ? () => app.togglePractice(l, t, d.date) : null,
              radius: 24,
              child: SizedBox(
                height: Ds.tap,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_wd[d.date.weekday - 1],
                      style: TextStyle(fontSize: 12, fontWeight: d.isToday ? FontWeight.w800 : FontWeight.w500, color: d.isToday ? AppColors.accent : AppColors.textDim)),
                  const SizedBox(height: 4),
                  _dot(app.practicedOn(l, t, d.date), d),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _dot(bool on, PracticeDay d) {
    if (!d.enabled) {
      return Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface2.withValues(alpha: 0.5)));
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? AppColors.inTune : Colors.transparent,
        border: Border.all(color: on ? AppColors.inTune : (d.isToday ? AppColors.accent : AppColors.outline), width: d.isToday && !on ? 2.5 : 2),
      ),
      child: on ? Icon(Icons.check_rounded, size: 15, color: AppColors.onAccent) : null,
    );
  }

  /// Ficha de uma tarefa. Recolhida (o que se vê): a marca de hoje, o título, "3/7" e UMA linha de situação.
  /// Aberta (um toque): recado da tarefa, os 7 dias para marcar e as ações (Treinar/Abrir e "pronta para a aula").
  Widget _taskCard(SharedLesson l, Assignment t, {bool overdue = false}) {
    final key = PracticeLog.taskKey(l.id, t.id);
    final open = _expanded.contains(key);
    final ready = app.lessonTaskDone(l, t);
    final st = app.taskStateOf(l, t);
    final now = DateTime.now();
    final doneToday = app.practicedOn(l, t, now);
    final days7 = app.practice.countLast7(key, now);
    final meta = t.isScale ? tr('Meta {0}% de acerto', [(t.goal * 100).round()]) : t.kind.label;
    // Uma linha só: a situação mais importante; sem situação, o tipo da tarefa.
    final (String line, IconData lineIcon, Color lineColor) = switch (st) {
      StudentTaskState.returned => (tr('refazer'), Icons.replay_rounded, AppColors.sharp),
      StudentTaskState.claimed => (tr('aguardando o professor'), Icons.hourglass_top_rounded, AppColors.accent),
      StudentTaskState.validated => (tr('validada'), Icons.verified_rounded, AppColors.inTune),
      _ => overdue && !ready ? (tr('atrasada'), Icons.schedule_rounded, AppColors.sharp) : (meta, taskKindIcon(t.kind), AppColors.textDim),
    };
    final practiceBtn = t.isScale
        ? FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, Ds.tap)),
            onPressed: () => _train(t),
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: Text(tr('Treinar')))
        : (t.kind == TaskKind.material
            ? FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, Ds.tap)),
                onPressed: () => _openMaterial(l, t),
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                label: Text(tr('Abrir')))
            : null);
    final readyBtn = ready
        ? FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, Ds.tap), backgroundColor: AppColors.inTune.withValues(alpha: 0.2), foregroundColor: AppColors.inTune),
            onPressed: () => app.toggleLessonTask(l, t),
            icon: const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(tr('Pronta para a aula')))
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap)),
            onPressed: () => app.toggleLessonTask(l, t),
            icon: const Icon(Icons.outlined_flag_rounded, size: 20),
            label: Text(tr('Pronta para a aula')));
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s4, 0, Ds.s4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _todayCheck(l, t, doneToday),
          Expanded(
            child: Semantics(
              button: true,
              expanded: open,
              child: InkWell(
                borderRadius: const BorderRadius.only(topRight: Radius.circular(16), bottomRight: Radius.circular(16)),
                onTap: () => setState(() => open ? _expanded.remove(key) : _expanded.add(key)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s8, Ds.s8, Ds.s8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text(t.title, maxLines: open ? 4 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, height: 1.25, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: Ds.s8),
                      Text('$days7/7', style: Ds.support().copyWith(fontWeight: FontWeight.w700)),
                      Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textDim),
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(lineIcon, size: 16, color: lineColor),
                      const SizedBox(width: 6),
                      Expanded(child: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Ds.fontSupport, color: lineColor, fontWeight: lineColor == AppColors.textDim ? FontWeight.w400 : FontWeight.w700))),
                    ]),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: !open
                          ? const SizedBox(width: double.infinity)
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (line != meta) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  Icon(taskKindIcon(t.kind), size: 16, color: AppColors.textDim),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(meta, style: Ds.support())),
                                ]),
                              ],
                              if (t.note.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(t.note, style: const TextStyle(fontSize: Ds.fontSupport + 1, height: 1.35)),
                              ],
                              const SizedBox(height: Ds.s8),
                              _strip(l, t),
                              const SizedBox(height: 6),
                              Wrap(spacing: 8, runSpacing: 8, children: [?practiceBtn, readyBtn]),
                              const SizedBox(height: 4),
                            ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
