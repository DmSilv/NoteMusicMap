import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import 'agenda_page.dart';
import 'my_lessons_page.dart' show openMyLessons;
import 'notifications_sheet.dart' show openNoticeTarget;
import 'profile_page.dart';
import 'qr_scan_page.dart';
import 'settings_page.dart' show kAppName;
import 'share_sheet.dart' show shareLink;
import 'slot_form_page.dart';
import 'teacher_page.dart';
import 'open_slots_page.dart';
import 'hello_bar.dart';
import 'meeting_link.dart';
import 'tour/start_card.dart';
import 'tour/tour.dart';
import 'design_system.dart';
import 'theme.dart';

/// "Meu espaço": o topo da aba. Um destaque grande (o que importa agora), dois blocos do que pede
/// ação e uma faixa de ferramentas. Muda conforme o papel (aluno, professor ou os dois).
class HubSection extends StatelessWidget {
  final AppState app;
  const HubSection({super.key, required this.app});

  @override
  Widget build(BuildContext context) => _Ticker(builder: _content);

  Widget _content(BuildContext context) {
    final now = DateTime.now();
    final view = app.hubView;
    final isT = view == HubView.teacher;
    final nc = app.nextClassFor(view);
    String whoOf(SlotOccurrence o) {
      final st = o.slot.studentCode.isEmpty ? null : app.studentByCode(o.slot.studentCode);
      return st?.name ?? o.slot.teacherName;
    }

    final cls = nc == null ? null : HubClass(nc.startMs, nc.startMs + nc.slot.endOffsetMs, whoOf(nc));
    final today = isT ? classesToday(app.visibleAgenda, now).count : 0;
    final hero = buildHero(
        nowMs: now.millisecondsSinceEpoch,
        isTeacher: isT,
        hasTeacher: app.hasTeacherSide,
        next: cls,
        todayCount: today,
        hasStudents: app.students.isNotEmpty);
    final layout = hubLayout(view, hasTeacherSide: app.hasTeacherSide);

    // O bloco de agenda do aluno já está no destaque: não repete como cartão.
    final tiles = [for (final d in layout.tiles) if (d != HubDest.agendaStudent) _tileFor(context, d, now)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (app.canSwitchHub) _viewSwitch(view),
      _statusChip(context),
      ..._news(context, view),
      _heroCard(context, hero, nc, view, extra: _agendaExtra(context, view, nc, layout.tools, now)),
      if (isT && StartCard.visibleFor(app)) StartCard(app: app),
      const SizedBox(height: 12),
      if (tiles.length == 2) _pair(tiles[0], tiles[1]) else if (tiles.length == 1) tiles.first,
      if (tiles.isNotEmpty) const SizedBox(height: 12),
    ]);
  }

  /// Alternador Aluno | Professor (só para quem tem os dois papéis).
  Widget _viewSwitch(HubView view) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<HubView>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: HubView.student, icon: Icon(Icons.person_outline, size: 18), label: Text(tr('Aluno'))),
              ButtonSegment(value: HubView.teacher, icon: Icon(Icons.school_outlined, size: 18), label: Text(tr('Professor'))),
            ],
            selected: {view},
            onSelectionChanged: (s) => app.setHubView(s.first),
          ),
        ),
      );

  /// Cada bloco grande do hub, conforme o destino.
  Widget _tileFor(BuildContext context, HubDest d, DateTime now) {
    switch (d) {
      case HubDest.validate:
        return _tile(context, validateTile(app.awaitingTotal), Icons.fact_check_rounded, () => _openValidation(context));
      case HubDest.students:
        return KeyedSubtree(
            key: TourKeys.hubStudents,
            child: _tile(context, studentsTile(app.students.length), Icons.groups_rounded, () => _push(context, TeacherPage(app: app))));
      case HubDest.myTasks:
        final plan = buildWeekPlan(app.myLessons, app.lessonTasksDone, now);
        return _tile(context, tasksTile(open: plan.open, total: plan.total), Icons.checklist_rounded, () => openMyLessons(context, app));
      case HubDest.agendaStudent:
        final next = nextOccurrence(app.myAgenda, now.millisecondsSinceEpoch);
        return _tile(context, agendaTile(nextText: next == null ? null : fmtSlotWhen(next.start, now)), Icons.event_rounded,
            () => _push(context, MyAgendaPage(app: app)));
      default:
        return const SizedBox.shrink();
    }
  }

  /// "Para validar": se só um aluno espera validação, abre a ficha dele; senão a lista de alunos.
  void _openValidation(BuildContext context) {
    final waiting = [for (final s in app.students) if (app.awaitingOf(s).isNotEmpty) s];
    _push(context, waiting.length == 1 ? StudentPage(app: app, studentId: waiting.first.id) : TeacherPage(app: app));
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
              Text(loud ? tr('{0} · toque para ver', [st.title]) : st.title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------- Avisos de novidade ----------------
  List<Widget> _news(BuildContext context, HubView view) {
    final mine = kNoticeKindsByView[view]!;
    final list = app.notices.where((n) => !n.seen && mine.contains(n.kind)).take(1).toList();
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
            TextButton.icon(
              onPressed: () {
                app.dismissNotice(n);
                openNoticeTarget(context, app, n);
              },
              icon: const Icon(Icons.arrow_forward, size: 18), label: Text(tr('Ver')),
            ),
            IconButton(
              tooltip: tr('Dispensar'),
              visualDensity: VisualDensity.compact,
              onPressed: () => app.dismissNotice(n),
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
        ),
    ];
  }

  // ---------------- Destaque ----------------
  Widget _heroCard(BuildContext context, HubHero h, SlotOccurrence? nc, HubView view, {Widget? extra}) {
    final urgent = h.kind == HeroKind.ongoing || h.kind == HeroKind.soon;
    final student = nc == null || nc.slot.studentCode.isEmpty ? null : app.studentByCode(nc.slot.studentCode);
    final buttons = <Widget>[];
    Widget primary(String t, IconData i, VoidCallback f) =>
        FilledButton.icon(onPressed: f, icon: Icon(i, size: 18), label: Text(t));
    Widget soft(String t, IconData i, VoidCallback f) => OutlinedButton.icon(onPressed: f, icon: Icon(i, size: 18), label: Text(t));

    for (final d in heroActions(view, h.kind, hasStudents: app.students.isNotEmpty, hasClassStudent: student != null)) {
      switch (d) {
        case HubDest.studentFile:
          final first = student!.name.split(' ').first;
          buttons.add(primary(urgent ? tr('Abrir ficha') : tr('Ficha de {0}', [first]), Icons.person_outline,
              () => _push(context, StudentPage(app: app, studentId: student.id))));
        case HubDest.markClass:
          buttons.add(primary(tr('Marcar aula'), Icons.add, () => openSlotForm(context, app)));
        case HubDest.inviteStudent:
          buttons.add(primary(tr('Convidar aluno'), Icons.person_add_alt_1, () => shareTeacherInvite(app)));
        case HubDest.scanTeacher:
          buttons.add(primary(tr('Ler QR do professor'), Icons.qr_code_scanner, () => _scanTeacher(context)));
          if (!app.teacherMode) {
            buttons.add(soft(tr('Sou professor'), Icons.school_outlined, () => _push(context, ProfilePage(app: app, initialTab: 1))));
          }
        default:
      }
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
        if (extra != null) ...[
          const SizedBox(height: Ds.s16),
          Divider(height: 1, color: AppColors.accent.withValues(alpha: 0.35)),
          const SizedBox(height: Ds.s12),
          extra,
        ],
      ]),
    );
  }

  /// "Hoje · 18:00", "Amanhã · 14:30", "Dom 15/11 · 12:00" (curto, cabe numa linha).
  String _shortWhen(DateTime d, DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final day = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final wd = [tr('Seg'), tr('Ter'), tr('Qua'), tr('Qui'), tr('Sex'), tr('Sáb'), tr('Dom')];
    final label = day == 0 ? tr('Hoje') : (day == 1 ? tr('Amanhã') : '${wd[d.weekday - 1]} ${fmtDayMonth(d)}');
    return '$label · ${two(d.hour)}:${two(d.minute)}';
  }

  String _whoOf(SlotOccurrence o) {
    final st = o.slot.studentCode.isEmpty ? null : app.studentByCode(o.slot.studentCode);
    return st?.name ?? o.slot.teacherName;
  }

  /// O que vem depois da próxima aula (até 3, nos próximos 14 dias) e os atalhos da agenda.
  Widget? _agendaExtra(BuildContext context, HubView view, SlotOccurrence? nc, List<HubDest> tools, DateTime now) {
    final isT = view == HubView.teacher;
    final slots = isT ? app.visibleAgenda : app.myAgenda;
    final nowMs = now.millisecondsSinceEpoch;
    final later = agendaBetween(slots, nowMs, nowMs + 14 * 86400000)
        .where((o) => nc == null || o.startMs != nc.startMs)
        .take(3)
        .toList();
    Widget act(IconData i, String t, VoidCallback f) => OutlinedButton.icon(onPressed: f, icon: Icon(i, size: 18), label: Text(t));
    final actions = <Widget>[
      if (nc != null && nc.slot.hasLink)
        FilledButton.icon(
          onPressed: () => openMeetingLink(context, app, nc.slot.link),
          icon: const Icon(Icons.videocam, size: 18),
          label: Text(isT ? tr('Abrir a sala da aula online') : tr('Entrar na aula online')),
        ),
      if (isT || app.hasTeacherSide)
        KeyedSubtree(
            key: isT ? TourKeys.hubAgenda : null,
            child: act(Icons.calendar_month_outlined, tr('Agenda completa'),
                () => _push(context, isT ? AgendaPage(app: app) : MyAgendaPage(app: app)))),
      if (tools.contains(HubDest.openSlots))
        KeyedSubtree(key: TourKeys.hubOpenSlots, child: act(Icons.event_available_outlined, tr('Horários livres'), () => _push(context, OpenSlotsPage(app: app)))),
      if (tools.contains(HubDest.pickSlot))
        act(Icons.event_available_outlined, tr('Pegar horário'), () => _push(context, PickSlotPage(app: app))),
    ];
    if (later.isEmpty && actions.isEmpty) return null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (later.isNotEmpty) ...[
        Text(tr('Depois'), style: Ds.section()),
        const SizedBox(height: Ds.s8),
        for (final o in later)
          Padding(
            padding: const EdgeInsets.only(bottom: Ds.s8),
            child: Row(children: [
              const DsIconBadge(Icons.event_rounded, size: 30),
              const SizedBox(width: Ds.s12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_shortWhen(o.start, now), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody)),
                  Text(_whoOf(o), maxLines: 1, overflow: TextOverflow.ellipsis, style: Ds.support()),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: Ds.s4),
      ],
      if (actions.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(height: Ds.s8), actions[i]],
        ]),
    ]);
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
            DsIconBadge(icon, size: 34),
            const SizedBox(width: 10),
            Expanded(child: Text(t.title, style: TextStyle(fontSize: Ds.fontLabel, color: AppColors.textDim, fontWeight: FontWeight.w700))),
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

  Future<void> _scanTeacher(BuildContext context) async {
    if (!await requireNickname(context, app, reason: tr('Para vincular a um professor, ele precisa saber quem você é.'))) return;
    if (!context.mounted) return;
    final s = await scanShareCode(context,
        title: tr('Ler QR do professor'), want: 'professor', check: app.checkTeacherCode, onCamera: app.setCameraStatus);
    if (s == null) return;
    final err = await app.addMyTeacher(s.code);
    if (err != null) app.say(err);
  }
}

/// Envia (ou copia) o link que abre o app já pedindo ao aluno para vincular este professor.
/// Abrir o link também liga o "Vínculo online" no app do aluno.
Future<void> shareTeacherInvite(AppState app) async {
  final link = '${shareLink()}/?professor=${app.profile.shareCode}';
  final text = tr('Sou seu professor no {0}. Abra este link e toque em "Vincular" para eu acompanhar suas tarefas: {1}', [kAppName, link]);
  try {
    await SharePlus.instance.share(ShareParams(text: text, title: kAppName));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    app.say(tr('Convite copiado. Cole numa conversa para enviar.'));
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
