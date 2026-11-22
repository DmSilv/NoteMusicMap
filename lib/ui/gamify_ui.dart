import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'student_page.dart' show StudentPage;
import 'theme.dart';
import 'widgets.dart';

IconData _achIcon(String id) => switch (id) {
      'first' => Icons.flag_outlined,
      'run3' => Icons.local_fire_department_outlined,
      'run7' => Icons.local_fire_department_rounded,
      'run30' => Icons.whatshot_rounded,
      'acc80' => Icons.track_changes_rounded,
      'week' => Icons.emoji_events_outlined,
      'scales10' => Icons.queue_music_rounded,
      'hours10' => Icons.hourglass_bottom_rounded,
      _ => Icons.star_outline_rounded,
    };

/// ALUNO (aba Hoje do Estudo): dias seguidos, meta da semana, conquistas e a opção de mostrar o resumo ao professor.
class GamifyCard extends StatelessWidget {
  final AppState app;
  const GamifyCard({super.key, required this.app});

  Future<void> _toggleShare(BuildContext context, bool v) async {
    if (v) {
      final ok = await showDsConfirm(
        context,
        title: tr('Mostrar meu estudo ao professor?'),
        body: tr('Seu professor vê o tempo de estudo da semana, o acerto nas escalas, as tarefas feitas e até 3 notas que estão desafinadas. Nunca vai áudio. Você pode desligar quando quiser e o resumo some do servidor.'),
        confirmLabel: tr('Mostrar'),
        icon: Icons.visibility_outlined,
      );
      if (!ok) return;
    }
    await app.setShareStudy(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final now = DateTime.now();
        final week = weekSummary(app.studySeconds, now, app.dailyGoalMinutes);
        final goal = weeklyGoalMinutes(app.dailyGoalMinutes);
        final left = (goal - week.minutes).clamp(0, goal);
        final ach = app.achievementList;
        final got = ach.where((a) => a.done).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.flag_outlined, tr('Meta da semana'), subtitle: tr('Os últimos 7 dias, em minutos.')),
              const SizedBox(height: Ds.s12),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${week.minutes}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
                const SizedBox(width: 6),
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(tr('de {0} min', [goal]), style: Ds.support())),
              ]),
              const SizedBox(height: Ds.s8),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: (week.minutes / goal).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: AppColors.surface2,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: Ds.s8),
              Text(left == 0 ? tr('Meta da semana batida. Muito bem!') : tr('Faltam {0} min.', [left]), style: Ds.support()),
            ]),
          ),
          const DsGap(Ds.gap),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.emoji_events_outlined, tr('Conquistas'), subtitle: tr('{0} de {1}', [got, ach.length])),
              const SizedBox(height: Ds.s12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Ds.s8,
                crossAxisSpacing: Ds.s8,
                childAspectRatio: 0.95,
                children: [for (final a in ach) _AchTile(a: a)],
              ),
            ]),
          ),
          if (app.myTeachers.isNotEmpty) ...[
            const DsGap(Ds.gap),
            AppCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                secondary: Icon(Icons.visibility_outlined, color: AppColors.textDim),
                title: Text(tr('Mostrar meu estudo ao professor'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('Só tempo, acerto e tarefas. Nunca áudio. Desligado por padrão.'), style: Ds.support()),
                value: app.shareStudy,
                onChanged: (v) => _toggleShare(context, v),
              ),
            ),
          ],
        ]);
      },
    );
  }
}

class _AchTile extends StatelessWidget {
  final Achievement a;
  const _AchTile({required this.a});

  @override
  Widget build(BuildContext context) {
    final c = a.done ? AppColors.accent : AppColors.textDim;
    return Semantics(
      label: '${a.title}. ${a.done ? tr('Conquistada') : a.hint}',
      child: Container(
        padding: const EdgeInsets.all(Ds.s8),
        decoration: BoxDecoration(
          color: a.done ? AppColors.accent.withValues(alpha: 0.12) : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: a.done ? AppColors.accent.withValues(alpha: 0.5) : AppColors.outline),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_achIcon(a.id), size: 26, color: c),
          const SizedBox(height: 6),
          Text(a.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: a.done ? AppColors.text : AppColors.textDim)),
          if (!a.done) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: a.progress, minHeight: 4, backgroundColor: AppColors.outline, color: AppColors.textDim),
            ),
          ],
        ]),
      ),
    );
  }
}

/// PROFESSOR (início): quem mais estudou na semana, só entre os alunos que escolheram compartilhar.
class StudyRankCard extends StatefulWidget {
  final AppState app;
  const StudyRankCard({super.key, required this.app});

  @override
  State<StudyRankCard> createState() => _StudyRankCardState();
}

class _StudyRankCardState extends State<StudyRankCard> {
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.loadStudyShares();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final linked = [for (final s in app.students) if (s.code != null && s.linkState != 'ended') s];
        if (linked.isEmpty) return const SizedBox.shrink();
        final rows = [
          for (final s in linked)
            if (app.studyShareOf(s) != null) (s, app.studyShareOf(s)!)
        ]..sort((a, b) => b.$2.minutes.compareTo(a.$2.minutes));
        final top = rows.isEmpty ? 1 : rows.first.$2.minutes.clamp(1, 6000);
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DsCardTitle(Icons.emoji_events_outlined, tr('Quem mais estudou'), subtitle: tr('Os últimos 7 dias, só de quem compartilha.')),
            const SizedBox(height: Ds.s12),
            if (rows.isEmpty)
              Text(tr('Quando um aluno escolhe mostrar o estudo, o resumo da semana dele aparece aqui.'), style: Ds.support())
            else
              for (var i = 0; i < rows.length.clamp(0, 8); i++)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: rows[i].$1.id))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(children: [
                      SizedBox(
                        width: 22,
                        child: i == 0 && rows[i].$2.minutes > 0 ? Icon(Icons.emoji_events_rounded, size: 18, color: AppColors.info) : Text('${i + 1}', textAlign: TextAlign.center, style: Ds.support()),
                      ),
                      const SizedBox(width: Ds.s8),
                      CircleAvatar(radius: 15, backgroundColor: AppColors.surface2, child: Text(rows[i].$1.name.characters.first.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text))),
                      const SizedBox(width: Ds.s12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(rows[i].$1.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: rows[i].$2.minutes / top, minHeight: 6, backgroundColor: AppColors.surface2, color: AppColors.accent),
                          ),
                        ]),
                      ),
                      const SizedBox(width: Ds.s12),
                      Text(tr('{0} min', [rows[i].$2.minutes]), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
            const SizedBox(height: Ds.s8),
            Row(children: [
              Icon(Icons.visibility_off_outlined, size: 16, color: AppColors.textDim),
              const SizedBox(width: 6),
              Expanded(child: Text(tr('{0} de {1} alunos mostram o estudo.', [rows.length, linked.length]), style: Ds.support())),
            ]),
          ]),
        );
      },
    );
  }
}

/// PROFESSOR (ficha do aluno): como foi a semana dele no app, antes da aula. Só aparece se o aluno compartilha.
class StudyShareCard extends StatefulWidget {
  final AppState app;
  final Student student;
  const StudyShareCard({super.key, required this.app, required this.student});

  @override
  State<StudyShareCard> createState() => _StudyShareCardState();
}

class _StudyShareCardState extends State<StudyShareCard> {
  @override
  void initState() {
    super.initState();
    widget.app.loadStudyShares();
  }

  Widget _num(String v, String label, {Color? color}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: Ds.support()),
        ]),
      );

  Widget _line(IconData icon, Color c, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: Ds.s8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.3))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final sh = widget.app.studyShareOf(widget.student);
        if (sh == null) return const SizedBox.shrink();
        final first = widget.student.name.trim().split(RegExp(r'\s+')).first;
        return Padding(
          padding: const EdgeInsets.only(bottom: Ds.gap),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.insights_rounded, tr('Como foi a semana de {0}', [first]), subtitle: tr('Atualizado em {0}', [fmtDayMonth(sh.at)])),
              const SizedBox(height: Ds.s12),
              Row(children: [
                _num('${sh.minutes}', tr('min de estudo')),
                _num(sh.accuracy < 0 ? '–' : '${sh.accuracy}%', tr('acerto nas escalas'), color: sh.accuracy >= 80 ? AppColors.inTune : null),
                _num(sh.tasksTotal == 0 ? '–' : '${sh.tasksDone}/${sh.tasksTotal}', tr('tarefas feitas')),
              ]),
              const SizedBox(height: Ds.s12),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(value: sh.goal == 0 ? 0 : (sh.minutes / sh.goal).clamp(0, 1).toDouble(), minHeight: 6, backgroundColor: AppColors.surface2, color: AppColors.accent),
              ),
              const SizedBox(height: 4),
              Text(tr('Meta da semana: {0} min', [sh.goal]), style: Ds.support()),
              _line(Icons.calendar_today_outlined, AppColors.info, tr('Estudou {0} de 7 dias · {1} seguidos', [sh.days, sh.streak])),
              if (sh.hasUp) _line(Icons.trending_up_rounded, AppColors.inTune, tr('{0} subiu de {1}% para {2}%', [sh.upTitle, sh.upFrom, sh.upTo])),
              if (sh.weak.isNotEmpty) _line(Icons.error_outline_rounded, AppColors.sharp, tr('Notas mais desafinadas: {0}', [sh.weak.join(', ')])),
            ]),
          ),
        );
      },
    );
  }
}
