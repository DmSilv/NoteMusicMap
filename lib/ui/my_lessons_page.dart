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

  /// Fichas abertas (as outras ficam recolhidas, para caber muitas tarefas na tela).
  final Set<String> _expanded = {};

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
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('Diário de aula')),
            actions: [
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
                  _statusBanner(),
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
                    if (plan.week.isNotEmpty) ...[
                      _section(tr('Esta semana'), trailing: tr('até a próxima aula')),
                      for (final g in plan.week) _group(g),
                    ],
                    if (plan.late.isNotEmpty) ...[
                      _section(tr('Em atraso · aulas anteriores'), color: AppColors.sharp),
                      for (final g in plan.late) _group(g),
                    ],
                    _section(tr('Todas as aulas')),
                    for (final l in lessons) _lessonTile(l),
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
      msg = tr('O vínculo online está desligado: ligue em Minha conta › Vínculo online para receber as aulas.');
    } else if (app.linkUnavailable) {
      msg = tr('O servidor ainda não está recebendo aulas. Quando ficar disponível, elas chegam aqui.');
      color = AppColors.flat;
    } else if (app.linkOnline == false) {
      msg = tr('Sem conexão agora. O que você já recebeu continua aqui.');
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

  /// Título de seção ("Esta semana", "Em atraso"…), com a quantidade à direita.
  Widget _section(String title, {Color? color, String? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(2, Ds.s16, 2, Ds.s8),
        child: Row(children: [
          Expanded(child: Text(title, style: Ds.section().copyWith(color: color ?? AppColors.textDim))),
          if (trailing != null) Text(trailing, style: Ds.support()),
        ]),
      );

  /// Resumo no topo: o estudo de HOJE e a sequência de dias. A marca é por dia e zera no dia seguinte.
  Widget _summary(WeekPlan plan) {
    final now = DateTime.now();
    final (todayDone, todayTotal) = app.practiceToday(plan, now);
    final streak = app.practice.streak(now);
    final lateCount = plan.late.fold<int>(0, (a, g) => a + g.tasks.where((t) => !t.done).length);
    final allToday = todayTotal > 0 && todayDone >= todayTotal;
    final value = plan.isEmpty ? 1.0 : (todayTotal == 0 ? 0.0 : todayDone / todayTotal);
    return AppCard(
      child: Row(children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: AppColors.surface2,
                color: AppColors.inTune,
              ),
            ),
            plan.isEmpty || allToday
                ? Icon(Icons.check_rounded, color: AppColors.inTune, size: 34)
                : Text('$todayDone/$todayTotal', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
              Text(tr('{0} de {1} prontas para a aula', [plan.done, plan.total]), style: Ds.support()),
            ],
            if (lateCount > 0) ...[
              const SizedBox(height: Ds.s8),
              Align(alignment: Alignment.centerLeft, child: _tag(tr('{0} em atraso', [lateCount]), AppColors.sharp, icon: Icons.schedule_rounded)),
            ],
          ]),
        ),
      ]),
    );
  }

  /// Uma aula do plano: cabeçalho (dia, quem, quanto foi feito) e uma ficha para cada tarefa.
  Widget _group(WeekGroup g) {
    final l = g.lesson;
    final who = l.teacherLabel;
    final dur = l.durationSec > 0 ? ' · ${fmtLessonDuration(l.durationSec)}' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, Ds.s8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2)),
                Text('$who$dur', style: Ds.support()),
              ]),
            ),
            const SizedBox(width: Ds.s8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _tag(tr('{0} de {1} prontas', [g.doneCount, g.tasks.length]), g.doneCount == g.tasks.length ? AppColors.inTune : AppColors.textDim),
            ),
          ]),
        ),
        for (final t in g.tasks) _taskCard(l, t.task, today: t.today, overdue: t.overdue),
        if (l.notes.isNotEmpty) _notes(l),
      ]),
    );
  }

  /// Recado do professor: um balão com as observações da aula.
  Widget _notes(SharedLesson l) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.fromLTRB(Ds.s12, Ds.s12, Ds.s12, Ds.s8),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
          border: Border(left: BorderSide(color: AppColors.accent, width: 4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(tr('Observações do professor'), style: TextStyle(fontSize: Ds.fontLabel, fontWeight: FontWeight.w700, color: AppColors.accent)),
          ]),
          const SizedBox(height: 6),
          for (final n in l.notes)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(n, style: const TextStyle(fontSize: Ds.fontSupport + 1, height: 1.35))),
        ]),
      );

  /// Uma aula na lista completa: recolhida; ao abrir mostra as tarefas e as observações.
  Widget _lessonTile(SharedLesson l) {
    final done = l.tasks.where((t) => app.lessonTaskDone(l, t)).length;
    final who = l.teacherLabel;
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
              '$who${l.durationSec > 0 ? ' · ${fmtLessonDuration(l.durationSec)}' : ''} · '
              '${l.tasks.isEmpty ? tr('sem tarefas') : tr('{0} de {1} prontas', [done, l.tasks.length])}',
              style: Ds.support(),
            ),
            children: [
              for (final t in l.tasks) _taskCard(l, t),
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
            width: 52,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 4),
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

  /// Mini fileira dos 7 dias (só para ver): aparece na ficha recolhida, para a pessoa ver a semana de relance.
  Widget _miniDots(SharedLesson l, Assignment t) {
    final days = practiceStrip(DateTime.now(), l.date);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final d in days)
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: !d.enabled
                ? AppColors.surface2.withValues(alpha: 0.5)
                : (app.practicedOn(l, t, d.date) ? AppColors.inTune : Colors.transparent),
            border: d.enabled && !app.practicedOn(l, t, d.date) ? Border.all(color: d.isToday ? AppColors.accent : AppColors.outline, width: 1.5) : null,
          ),
        ),
    ]);
  }

  /// Ficha de uma tarefa do diário. Recolhida: a marca de hoje, o título, a semana em pontinhos e a situação
  /// (cabem muitas tarefas na tela). Aberta: recado, os 7 dias para marcar e as ações (Treinar/Abrir e "pronta para a aula").
  Widget _taskCard(SharedLesson l, Assignment t, {bool today = false, bool overdue = false}) {
    final key = PracticeLog.taskKey(l.id, t.id);
    final open = _expanded.contains(key);
    final ready = app.lessonTaskDone(l, t);
    final st = app.taskStateOf(l, t);
    final now = DateTime.now();
    final doneToday = app.practicedOn(l, t, now);
    final days7 = app.practice.countLast7(key, now);
    final meta = t.isScale ? tr('Meta {0}% de acerto', [(t.goal * 100).round()]) : t.kind.label;
    final tags = <Widget>[
      if (!ready && overdue) _tag(tr('atrasada'), AppColors.sharp, icon: Icons.schedule_rounded),
      if (st == StudentTaskState.validated) _tag(tr('validada'), AppColors.inTune, icon: Icons.verified_rounded),
      if (st == StudentTaskState.claimed) _tag(tr('aguardando o professor'), AppColors.accent, icon: Icons.hourglass_top_rounded),
      if (st == StudentTaskState.returned) _tag(tr('refazer'), AppColors.sharp, icon: Icons.replay_rounded),
    ];
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
          border: Border.all(color: !ready && overdue ? AppColors.sharp.withValues(alpha: 0.5) : AppColors.outline),
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
                      Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textDim),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(taskKindIcon(t.kind), size: 16, color: AppColors.textDim),
                      const SizedBox(width: 6),
                      Expanded(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ds.support())),
                    ]),
                    if (!open) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        _miniDots(l, t),
                        const SizedBox(width: 4),
                        Text('$days7/7', style: Ds.support().copyWith(fontWeight: FontWeight.w700)),
                      ]),
                      if (t.note.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(t.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ds.support()),
                      ],
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: tags),
                    ],
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: !open
                          ? const SizedBox(width: double.infinity)
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (t.note.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(t.note, style: const TextStyle(fontSize: Ds.fontSupport + 1, height: 1.35)),
                              ],
                              const SizedBox(height: Ds.s8),
                              _strip(l, t),
                              Text(tr('{0} de 7 dias', [days7]), style: Ds.support()),
                              const SizedBox(height: 10),
                              Wrap(spacing: 8, runSpacing: 8, children: [?practiceBtn, readyBtn]),
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

  Widget _tag(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color))),
        ]),
      );
}
