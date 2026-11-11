import 'package:flutter/material.dart';

import '../app_state.dart';
import 'agenda_page.dart';
import 'my_lessons_page.dart' show openMyLessons;
import 'profile_page.dart';
import 'teacher_page.dart';
import 'theme.dart';

/// Ícone de cada tipo de aviso.
IconData noticeIcon(String kind) => switch (kind) {
      'lesson' => Icons.event_note_outlined,
      'task' => Icons.fact_check_outlined,
      'done' => Icons.task_alt,
      'pick' => Icons.event_available_outlined,
      'support' => Icons.support_agent,
      _ => Icons.school_outlined,
    };

/// "há 5 min", "ontem", "há 3 d".
String noticeAgo(int atMs, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final m = n.difference(DateTime.fromMillisecondsSinceEpoch(atMs)).inMinutes;
  if (m < 1) return 'agora';
  if (m < 60) return 'há $m min';
  if (m < 60 * 24) return 'há ${m ~/ 60} h';
  final d = m ~/ (60 * 24);
  return d == 1 ? 'ontem' : 'há $d d';
}

/// Leva ao lugar certo conforme o tipo do aviso (e marca como lido).
void openNoticeTarget(BuildContext context, AppState app, AppNotice n) {
  app.dismissNotice(n);
  final nav = Navigator.of(context);
  switch (n.kind) {
    case 'lesson':
    case 'task':
      openMyLessons(context, app);
    case 'pick':
      nav.push(MaterialPageRoute<void>(builder: (_) => AgendaPage(app: app)));
    case 'done':
      nav.push(MaterialPageRoute<void>(builder: (_) => TeacherPage(app: app)));
    default:
      nav.push(MaterialPageRoute<void>(builder: (_) => ProfilePage(app: app)));
  }
}

/// Central de avisos: um painel só com tudo o que chegou, do mais novo ao mais antigo.
Future<void> showNotificationsSheet(BuildContext context, AppState app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (c) => ListenableBuilder(
      listenable: app,
      builder: (c, _) {
        final list = app.notices;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Expanded(child: Text('Avisos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
                  if (app.unseenNotices > 0) TextButton.icon(onPressed: app.markNoticesSeen, icon: const Icon(Icons.done_all, size: 18), label: const Text('Marcar como lidos')),
                  if (list.isNotEmpty) TextButton.icon(onPressed: app.clearNotices, icon: const Icon(Icons.delete_sweep, size: 18), label: const Text('Limpar')),
                ]),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text('Nenhum aviso por enquanto. Aulas novas, tarefas validadas e horários aparecem aqui.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, height: 1.35)),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.outline),
                      itemBuilder: (c, i) {
                        final n = list[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(noticeIcon(n.kind), color: n.seen ? AppColors.textDim : AppColors.accent),
                          title: Text(n.text,
                              style: TextStyle(fontWeight: n.seen ? FontWeight.w500 : FontWeight.w800, height: 1.25)),
                          subtitle: Text(noticeAgo(n.atMs), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                          trailing: n.seen ? null : Icon(Icons.circle, size: 9, color: AppColors.accent),
                          onTap: () {
                            Navigator.of(c).pop();
                            openNoticeTarget(context, app, n);
                          },
                        );
                      },
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    ),
  );
}
