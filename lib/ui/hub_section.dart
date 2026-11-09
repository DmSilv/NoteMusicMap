import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import 'agenda_page.dart';
import 'my_lessons_page.dart' show openMyLessons;
import 'profile_page.dart';
import 'qr_scan_page.dart';
import 'settings_page.dart' show SettingsPage, kAppName;
import 'share_sheet.dart' show shareLink;
import 'slot_form_page.dart';
import 'teacher_page.dart';
import 'theme.dart';

/// "Meu espaço": o topo da aba. Um destaque grande (o que importa agora), dois blocos do que pede
/// ação e uma faixa de ferramentas. Muda conforme o papel (aluno, professor ou os dois).
class HubSection extends StatelessWidget {
  final AppState app;
  const HubSection({super.key, required this.app});

  @override
  Widget build(BuildContext context) => _Ticker(builder: _content);

  bool get _hasTeacher => app.myTeachers.isNotEmpty || app.myLessons.isNotEmpty || app.myAgenda.isNotEmpty;

  Widget _content(BuildContext context) {
    final now = DateTime.now();
    final isT = app.teacherMode;
    final nc = app.nextClass;
    String whoOf(SlotOccurrence o) {
      final st = o.slot.studentCode.isEmpty ? null : app.studentByCode(o.slot.studentCode);
      return st?.name ?? o.slot.teacherName;
    }

    final cls = nc == null ? null : HubClass(nc.startMs, nc.startMs + nc.slot.endOffsetMs, whoOf(nc));
    final today = isT ? agendaDay(app.agenda.where((s) => app.studentByCode(s.studentCode) != null), now).length : 0;
    final hero = buildHero(
        nowMs: now.millisecondsSinceEpoch,
        isTeacher: isT,
        hasTeacher: _hasTeacher,
        next: cls,
        todayCount: today,
        hasStudents: app.students.isNotEmpty);

    final plan = buildWeekPlan(app.myLessons, app.lessonTasksDone, now);
    final nextForStudent = nextOccurrence(app.myAgenda, now.millisecondsSinceEpoch);
    final nextText = nextForStudent == null ? null : fmtSlotWhen(nextForStudent.start, now);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _statusChip(context),
      ..._news(context),
      _heroCard(context, hero, nc),
      const SizedBox(height: 12),
      if (isT)
        _pair(
          _tile(context, validateTile(app.awaitingTotal), Icons.fact_check_outlined, null),
          _tile(context, studentsTile(app.students.length), Icons.groups_outlined, null),
        ),
      if (isT && _hasTeacher) const SizedBox(height: 10),
      if (_hasTeacher)
        _pair(
          _tile(context, tasksTile(open: plan.open, total: plan.total), Icons.checklist_rtl, () => openMyLessons(context, app)),
          _tile(context, agendaTile(nextText: nextText), Icons.event_outlined, () => _push(context, MyAgendaPage(app: app))),
        ),
      const SizedBox(height: 12),
      _tools(context),
      const SizedBox(height: 12),
    ]);
  }

  void _push(BuildContext c, Widget w) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

  // ---------------- Selo de conexão ----------------
  Widget _statusChip(BuildContext context) {
    final st = app.linkStatus;
    final (icon, color) = switch (st.health) {
      LinkHealth.off => (Icons.cloud_off_outlined, AppColors.textDim),
      LinkHealth.connecting => (Icons.sync, AppColors.textDim),
      LinkHealth.online => (Icons.cloud_done_outlined, AppColors.inTune),
      LinkHealth.offline => (Icons.sync_problem, AppColors.flat),
      LinkHealth.serverDown => (Icons.cloud_off_outlined, AppColors.flat),
    };
    // Só chama atenção quando precisa: conectado fica discreto.
    final loud = st.health == LinkHealth.offline || st.health == LinkHealth.serverDown;
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _push(context, ProfilePage(app: app)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: loud ? 0.22 : 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(loud ? '${st.title} · toque para ver' : st.title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------- Avisos de novidade ----------------
  List<Widget> _news(BuildContext context) {
    final list = app.notices.where((n) => !n.seen).take(1).toList();
    return [
      for (final n in list)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.16),
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
                if (n.kind == 'lesson' || n.kind == 'task') openMyLessons(context, app);
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
        ),
    ];
  }

  // ---------------- Destaque ----------------
  Widget _heroCard(BuildContext context, HubHero h, SlotOccurrence? nc) {
    final urgent = h.kind == HeroKind.ongoing || h.kind == HeroKind.soon;
    final student = nc == null || nc.slot.studentCode.isEmpty ? null : app.studentByCode(nc.slot.studentCode);
    final buttons = <Widget>[];
    Widget primary(String t, IconData i, VoidCallback f) =>
        FilledButton.icon(onPressed: f, icon: Icon(i, size: 18), label: Text(t));
    Widget soft(String t, VoidCallback f) => OutlinedButton(onPressed: f, child: Text(t));

    switch (h.kind) {
      case HeroKind.ongoing:
      case HeroKind.soon:
        if (student != null) {
          buttons.add(primary('Abrir ficha', Icons.person_outline, () => _push(context, StudentPage(app: app, studentId: student.id))));
        } else {
          buttons.add(primary('Ver agenda', Icons.event_outlined, () => _push(context, MyAgendaPage(app: app))));
        }
      case HeroKind.next:
        buttons.add(primary(app.teacherMode ? 'Abrir agenda' : 'Ver agenda', Icons.event_outlined,
            () => _push(context, app.teacherMode ? AgendaPage(app: app) : MyAgendaPage(app: app))));
        if (student != null) {
          buttons.add(soft('Ficha de ${student.name.split(' ').first}', () => _push(context, StudentPage(app: app, studentId: student.id))));
        }
      case HeroKind.none:
        if (app.teacherMode) {
          buttons.add(app.students.isEmpty
              ? primary('Convidar aluno', Icons.person_add_alt_1, () => shareTeacherInvite(app))
              : primary('Marcar aula', Icons.add, () => openSlotForm(context, app)));
          buttons.add(soft('Abrir agenda', () => _push(context, AgendaPage(app: app))));
        } else {
          buttons.add(primary('Ver agenda', Icons.event_outlined, () => _push(context, MyAgendaPage(app: app))));
        }
      case HeroKind.noTeacher:
        buttons.add(primary('Ler QR do professor', Icons.qr_code_scanner, () => _scanTeacher(context)));
        buttons.add(soft('Sou professor', () => _push(context, ProfilePage(app: app, initialTab: 1))));
    }

    final bg = urgent ? AppColors.accent.withValues(alpha: 0.24) : AppColors.accent.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: urgent ? 0.8 : 0.4), width: urgent ? 1.6 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (urgent) ...[
            Icon(h.kind == HeroKind.ongoing ? Icons.play_circle_outline : Icons.alarm, size: 18, color: AppColors.accent),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(h.kicker, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.accent)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(h.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: 4),
        Text(h.subtitle, style: TextStyle(fontSize: 13.5, color: AppColors.textDim, height: 1.3)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: buttons),
      ]),
    );
  }

  // ---------------- Blocos ----------------
  Widget _pair(Widget a, Widget b) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: a),
          const SizedBox(width: 10),
          Expanded(child: b),
        ]),
      );

  Widget _tile(BuildContext context, HubTile t, IconData icon, VoidCallback? onTap) {
    final alert = t.needsAction;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap ?? () => _push(context, TeacherPage(app: app)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: alert ? AppColors.flat.withValues(alpha: 0.6) : AppColors.outline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20, color: AppColors.accent),
            const SizedBox(width: 6),
            Expanded(child: Text(t.title, style: TextStyle(fontSize: 12.5, color: AppColors.textDim, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Text(t.headline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: alert ? AppColors.flat : AppColors.text, height: 1.2)),
          const SizedBox(height: 2),
          Text(t.caption, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.25)),
          if (t.progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: t.progress,
                minHeight: 6,
                backgroundColor: AppColors.surface2,
                color: AppColors.inTune,
              ),
            ),
          ],
        ]),
      ),
    );
  }

  // ---------------- Ferramentas ----------------
  Widget _tools(BuildContext context) {
    final items = <(IconData, String, VoidCallback)>[
      if (app.teacherMode) (Icons.calendar_month_outlined, 'Agenda', () => _push(context, AgendaPage(app: app))),
      if (app.teacherMode) (Icons.assessment_outlined, 'Relatórios', () => _push(context, TeacherPage(app: app))),
      (Icons.timer_outlined, 'Metrônomo', () => app.goTab?.call(1)),
      (Icons.piano, 'Escalas', () => app.openGridSection(1)),
      (Icons.badge_outlined, 'Perfil', () => _push(context, ProfilePage(app: app))),
      (Icons.settings_outlined, 'Ajustes', () => _push(context, SettingsPage(app: app))),
    ];
    return LayoutBuilder(builder: (context, box) {
    final cols = items.length > 4 ? 3 : items.length;
    final w = ((box.maxWidth - 22) / cols).floorToDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text('Ferramentas', style: TextStyle(fontSize: 12.5, color: AppColors.textDim, fontWeight: FontWeight.w700)),
        ),
        Wrap(runSpacing: 8, children: [
          for (final it in items)
            SizedBox(
              width: w,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: it.$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                      child: Icon(it.$1, color: AppColors.accent),
                    ),
                    const SizedBox(height: 4),
                    Text(it.$2, style: TextStyle(fontSize: 12, color: AppColors.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ),
            ),
        ]),
      ]),
    );
    });
  }

  Future<void> _scanTeacher(BuildContext context) async {
    final s = await scanShareCode(context,
        title: 'Ler QR do professor', want: 'professor', check: app.checkTeacherCode, onCamera: app.setCameraStatus);
    if (s == null) return;
    final err = await app.addMyTeacher(s.code);
    if (err != null) app.say(err);
  }
}

/// Envia (ou copia) o link que abre o app já pedindo ao aluno para vincular este professor.
/// Abrir o link também liga o "Vínculo online" no app do aluno.
Future<void> shareTeacherInvite(AppState app) async {
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

/// Refaz a tela a cada 30 s para o "começa em N min" andar sozinho.
class _Ticker extends StatefulWidget {
  final WidgetBuilder builder;
  const _Ticker({required this.builder});

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
