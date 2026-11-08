import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';
import 'widgets.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

IconData _kindIcon(TaskKind k) => switch (k) {
      TaskKind.scale => Icons.piano,
      TaskKind.method => Icons.menu_book_outlined,
      TaskKind.repertoire => Icons.library_music_outlined,
      TaskKind.free => Icons.edit_note,
    };

/// Cartão do perfil do aluno: resume as aulas recebidas e leva à tela completa.
class MyLessonsCard extends StatelessWidget {
  final AppState app;
  const MyLessonsCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final open = app.openLessonTasks;
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
            if (open > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$open em aberto', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
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
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => MyLessonsPage(app: app)),
            ),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Ver minhas aulas'),
          ),
        ],
      ),
    );
  }
}

/// Área do aluno: todas as aulas recebidas, com as tarefas de cada uma.
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
        final off = !app.linkEnabled;
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
                  _status(off),
                  const SizedBox(height: 10),
                  if (lessons.isEmpty)
                    AppCard(
                      child: Text(
                        app.myTeachers.isEmpty
                            ? 'Você ainda não tem professor vinculado. Em Meu perfil › Meus professores, leia o QR dele.'
                            : 'Nenhuma aula recebida ainda. Quando seu professor encerrar uma aula, as tarefas '
                                'dela aparecem aqui sozinhas. Para conferir agora, toque em ↻.',
                        style: TextStyle(color: AppColors.textDim),
                      ),
                    ),
                  for (final l in lessons) ...[
                    _lessonCard(l),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _status(bool off) {
    if (off) {
      return AppCard(
        child: Row(children: [
          Icon(Icons.cloud_off_outlined, color: AppColors.textDim),
          const SizedBox(width: 10),
          const Expanded(child: Text('O vínculo online está desligado: ligue em Meu perfil para receber as aulas.')),
        ]),
      );
    }
    if (app.linkUnavailable) {
      return AppCard(
        child: Row(children: [
          Icon(Icons.cloud_off_outlined, color: AppColors.flat),
          const SizedBox(width: 10),
          const Expanded(child: Text('O servidor ainda não está recebendo aulas. Quando ficar disponível, elas chegam aqui.')),
        ]),
      );
    }
    final open = app.openLessonTasks;
    return AppCard(
      child: Row(children: [
        Icon(open == 0 ? Icons.task_alt : Icons.pending_actions, color: open == 0 ? AppColors.inTune : AppColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            open == 0
                ? (app.myLessons.isEmpty ? 'Tudo em dia.' : 'Todas as tarefas feitas. Bom trabalho!')
                : '$open tarefa${open == 1 ? '' : 's'} em aberto.',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (app.linkOnline == false) Text('sem conexão', style: TextStyle(color: AppColors.flat, fontSize: 12.5)),
      ]),
    );
  }

  Widget _lessonCard(SharedLesson l) {
    final done = l.tasks.where((t) => app.lessonTaskDone(l, t)).length;
    final who = l.teacherName.isEmpty ? 'Professor ${l.teacherCode}' : l.teacherName;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Aula de ${_date(l.date)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            Text(l.durationSec > 0 ? fmtLessonDuration(l.durationSec) : '',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ]),
          Text('$who · ${l.tasks.isEmpty ? 'sem tarefas' : '$done de ${l.tasks.length} tarefas feitas'}',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          const SizedBox(height: 4),
          for (final t in l.tasks) _taskTile(l, t),
          if (l.notes.isNotEmpty) ...[
            const Divider(height: 18),
            Text('Observações do professor', style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final n in l.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(n, style: const TextStyle(height: 1.3)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _taskTile(SharedLesson l, Assignment t) {
    final done = app.lessonTaskDone(l, t);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Checkbox(value: done, onChanged: (_) => app.toggleLessonTask(l, t)),
      title: Row(children: [
        Icon(_kindIcon(t.kind), size: 16, color: AppColors.textDim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(t.title, style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
        ),
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
          ? TextButton(onPressed: () => _train(t), child: const Text('Treinar'))
          : null,
    );
  }
}
