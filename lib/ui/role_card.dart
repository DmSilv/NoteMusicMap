import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import 'my_lessons_page.dart' show openMyLessons, taskKindIcon;
import 'profile_page.dart';
import 'qr_scan_page.dart';
import 'settings_page.dart' show kAppName;
import 'share_sheet.dart' show shareLink;
import 'teacher_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Cartões da aba Estudo que se adaptam ao jeito de usar:
///  - modo professor LIGADO: "Área do professor" (alunos, tarefas) + convidar aluno;
///  - aluno COM professor (padrão de todo mundo): "Tarefas do professor", com o resumo da
///    semana (feitas, atrasadas), as próximas pendentes (dá para marcar ali mesmo) e o
///    caminho para a tela completa;
///  - aluno ainda SEM professor: convite para vincular (ler o QR ou digitar o código) e um
///    atalho discreto "Sou professor". Pode ser dispensado.
class RoleCard extends StatelessWidget {
  final AppState app;
  const RoleCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final hasTeacher = app.myTeachers.isNotEmpty || app.myLessons.isNotEmpty;
    return Column(children: [
      if (app.teacherMode) _teacher(context),
      if (hasTeacher)
        _tasks(context)
      else if (!app.teacherMode && !app.roleCardHidden)
        _student(context),
    ]);
  }

  // ---------------- Aluno com professor: tarefas pendentes ----------------
  Widget _tasks(BuildContext context) {
    final plan = buildWeekPlan(app.myLessons, app.lessonTasksDone, DateTime.now());
    final open = <WeekTask>[
      for (final g in [...plan.week, ...plan.late]) ...g.tasks.where((t) => !t.done),
    ];
    // Atrasadas primeiro, depois as da semana (já vêm da aula mais recente para a mais antiga).
    final ordered = [...open.where((t) => t.overdue), ...open.where((t) => !t.overdue)];
    final shown = ordered.take(3).toList();
    final late = open.where((t) => t.overdue).length;

    final String sub;
    Color subColor = AppColors.textDim;
    if (app.myLessons.isEmpty) {
      sub = 'Quando seu professor encerrar uma aula, as tarefas dela aparecem aqui.';
    } else if (plan.isEmpty) {
      sub = 'Tudo em dia. Nenhuma tarefa em aberto.';
      subColor = AppColors.inTune;
    } else if (plan.open == 0) {
      sub = 'Todas as ${plan.total} tarefas feitas. Bom trabalho!';
      subColor = AppColors.inTune;
    } else {
      sub = '${plan.done} de ${plan.total} feitas esta semana${late > 0 ? ' · $late em atraso' : ''}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Aviso de novidade do professor ("Marina passou 2 tarefas para você").
            for (final n in app.notices.where((n) => !n.seen && n.kind == 'lesson').take(1))
              _newsStrip(context, n),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => openMyLessons(context, app),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.checklist_rtl, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Tarefas do professor',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(sub, style: TextStyle(color: subColor, fontSize: 12.5)),
                  ]),
                ),
                if (plan.open > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: (late > 0 ? AppColors.sharp : AppColors.accent).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${plan.open} em aberto',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  )
                else
                  Icon(Icons.chevron_right, color: AppColors.textDim),
              ]),
            ),
            if (!plan.isEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: plan.progress,
                  minHeight: 6,
                  backgroundColor: AppColors.surface2,
                  color: AppColors.inTune,
                ),
              ),
            ],
            for (final t in shown) _taskRow(context, t),
            if (ordered.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4),
                child: Text('+ ${ordered.length - shown.length} em aberto',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6), minimumSize: const Size(0, 32)),
                onPressed: () => openMyLessons(context, app),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Ver minhas aulas e tarefas'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _newsStrip(BuildContext context, AppNotice n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(Icons.notifications_active_outlined, size: 20, color: AppColors.accent),
        const SizedBox(width: 10),
        Expanded(child: Text(n.text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.25))),
        TextButton(
          onPressed: () {
            app.dismissNotice(n);
            openMyLessons(context, app);
          },
          child: const Text('Ver'),
        ),
        IconButton(
          tooltip: 'Dispensar',
          visualDensity: VisualDensity.compact,
          onPressed: () => app.dismissNotice(n),
          icon: const Icon(Icons.close, size: 18),
        ),
      ]),
    );
  }

  /// Uma tarefa pendente: marca como feita ali mesmo; tocar no texto abre a tela completa.
  Widget _taskRow(BuildContext context, WeekTask w) {
    final t = w.task;
    final l = w.lesson;
    final tag = w.overdue ? ('atrasada', AppColors.sharp) : (w.today ? ('hoje', AppColors.accent) : null);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        SizedBox(
          width: 36,
          height: 36,
          child: Checkbox(
            value: app.lessonTaskDone(l, t),
            onChanged: (_) => app.toggleLessonTask(l, t),
          ),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => openMyLessons(context, app),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(taskKindIcon(t.kind), size: 15, color: AppColors.textDim),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (tag != null)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: tag.$2.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tag.$1,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tag.$2)),
                    ),
                ]),
                Text('${l.label} · ${l.teacherLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------------- Professor ----------------
  Widget _teacher(BuildContext context) {
    final n = app.students.length;
    final subtitle = app.activeStudent != null
        ? 'Em aula: ${app.activeStudent!.name}'
        : (n == 0 ? 'Nenhum aluno ainda. Convide o primeiro.' : '$n aluno${n > 1 ? 's' : ''} · tarefas e relatórios');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.school_outlined, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Área do professor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(subtitle, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                ]),
              ),
            ]),
            if (!app.linkEnabled) ...[
              const SizedBox(height: 8),
              Text('O vínculo online está desligado: seus alunos só aparecem aqui se ele estiver ligado.',
                  style: TextStyle(color: AppColors.flat, fontSize: 12.5)),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => TeacherPage(app: app))),
                  icon: const Icon(Icons.groups_outlined, size: 18),
                  label: const Text('Abrir'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => app.linkEnabled ? _invite(context) : app.setLinkEnabled(true),
                  icon: Icon(app.linkEnabled ? Icons.person_add_alt_1 : Icons.cloud_outlined, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(app.linkEnabled ? 'Convidar aluno' : 'Ligar vínculo'),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// Envia (ou copia) o link que abre o app já pedindo ao aluno para vincular este professor.
  Future<void> _invite(BuildContext context) async {
    final link = '${shareLink()}/?professor=${app.profile.shareCode}';
    final text = 'Sou seu professor no $kAppName. Abra este link e toque em "Vincular" para eu acompanhar '
        'suas tarefas: $link';
    try {
      await SharePlus.instance.share(ShareParams(text: text, title: kAppName));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      app.say('Convite copiado. Cole numa conversa para enviar.');
    }
  }

  // ---------------- Aluno sem professor ----------------
  Widget _student(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.menu_book_outlined, color: AppColors.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Estuda com um professor?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              InkResponse(
                onTap: () {
                  app.hideRoleCard();
                  app.say('Ok. Para vincular um professor ou ligar o modo professor, toque no ícone de perfil, no topo.');
                },
                radius: 18,
                child: Tooltip(
                  message: 'Dispensar',
                  child: Icon(Icons.close, size: 20, color: AppColors.textDim),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Leia o QR dele (ou digite o código) e as tarefas da semana passam a aparecer aqui.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => _scan(context),
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Ler QR ou digitar código'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6), minimumSize: const Size(0, 32)),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ProfilePage(app: app, initialTab: 1)),
                ),
                child: const Text('Sou professor'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scan(BuildContext context) async {
    final s = await scanShareCode(
      context,
      title: 'Ler QR do professor',
      want: 'professor',
      check: app.checkTeacherCode,
      onCamera: app.setCameraStatus,
    );
    if (s == null) return;
    final err = await app.addMyTeacher(s.code);
    if (err != null) app.say(err);
  }
}
