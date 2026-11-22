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
import 'teacher_setup_page.dart';
import 'open_slots_page.dart';
import 'hello_bar.dart';
import 'link_bar.dart' show confirmTeacherLink;
import 'meeting_link.dart';
import 'study_hub.dart';
import 'library_page.dart' show openLibrary;
import 'materials_sheet.dart';
import 'turmas_page.dart';
import 'widgets.dart' show AppCard;
import 'tour/first_step_card.dart';
import 'tour/start_card.dart';
import 'tour/tour.dart';
import 'design_system.dart';
import 'theme.dart';
import 'person_avatar.dart';
import 'student_identity.dart' show studentTint;
import 'validation_ui.dart' show ValidationQueuePage;

/// "Meu espaço": o topo da aba. Um destaque grande (o que importa agora), dois blocos do que pede
/// ação e uma faixa de ferramentas. Muda conforme o papel (aluno, professor ou os dois).
class HubSection extends StatelessWidget {
  final AppState app;
  const HubSection({super.key, required this.app});

  @override
  Widget build(BuildContext context) => _LiveWatch(app: app, child: _Ticker(builder: _content));

  Widget _content(BuildContext context) {
    final now = DateTime.now();
    final view = app.hubView;
    final isT = view == HubView.teacher;
    final nc = app.nextClassFor(view);
    String whoOf(SlotOccurrence o) {
      final st = o.slot.studentCode.isEmpty ? null : app.studentByCode(o.slot.studentCode);
      return st == null ? o.slot.teacherName : app.labelOf(st);
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
    if (!isT && hero.kind == HeroKind.noTeacher) return _newcomer(context);

    // O bloco de agenda do aluno já está no destaque: não repete como cartão.
    final tiles = [for (final d in layout.tiles) if (d != HubDest.agendaStudent) _tileFor(context, d, now)];
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _viewSwitch(context, view),
      _statusChip(context),
      ..._news(context, view),
      _heroCard(context, hero, nc, view, extra: _agendaExtra(context, view, nc, layout.tools, now)),
      if (isT && StartCard.visibleFor(app)) StartCard(app: app) else if (isT && StartCard.hiddenFor(app)) StartCardReturn(app: app),
      // Quem chegou sozinho vê aqui o mesmo "Seu primeiro passo" do Afinador (some ao concluir ou ao esconder).
      if (!isT && app.firstStepVisible) Padding(padding: const EdgeInsets.only(top: Ds.s12), child: FirstStepCard(app: app)),
      if (!isT) ...[const SizedBox(height: Ds.s12), StudyHubCard(app: app)],
      const SizedBox(height: Ds.gap),
      // Tela larga (tablet ou computador em pé): o bloco de alunos e a organização ficam lado a lado, em vez de esticar na largura toda.
      if (isT && wide && tiles.length == 1)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 5, child: tiles.first),
            const SizedBox(width: Ds.gap),
            Expanded(flex: 7, child: _organization(context, header: false)),
          ]),
        )
      else ...[
        if (tiles.length == 2) _pair(tiles[0], tiles[1]) else if (tiles.length == 1) tiles.first,
        if (tiles.isNotEmpty) const SizedBox(height: Ds.gap),
        // Atalhos de quem organiza as aulas: a um toque, sem passar por Minha conta nem pelo menu da lista.
        if (isT) _organization(context),
      ],
      if (isT && wide) const SizedBox(height: Ds.gap),
    ]);
  }

  /// O cartão "Organização": métodos e repertório, turmas e acervo, com a mesma aparência.
  Widget _organization(BuildContext context, {bool header = true}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (header) Padding(padding: const EdgeInsets.only(left: Ds.s4, bottom: Ds.s8), child: Text(tr('Organização'), style: Ds.section())),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          DsNavRow(Icons.library_books_outlined, tr('Métodos e repertório'), _materialsSub(), () => showMaterialsSheet(context, app)),
          Divider(height: 1, color: AppColors.outline),
          DsNavRow(Icons.workspaces_outline, tr('Turmas'), app.turmas.isEmpty ? tr('Separe seus alunos por grupo') : (app.turmas.length == 1 ? tr('1 turma') : tr('{0} turmas', [app.turmas.length])), () => _push(context, TurmasPage(app: app))),
          // O acervo (links de métodos e peças) fica junto, com a mesma aparência das outras linhas.
          if (app.libraryOn) ...[
            Divider(height: 1, color: AppColors.outline),
            DsNavRow(Icons.folder_open_rounded, tr('Acervo e repertório'), tr('Seus métodos e peças, com link'), () => openLibrary(context, app)),
          ],
        ]),
      ),
      if (header) const SizedBox(height: Ds.gap),
    ]);
  }

  String _materialsSub() {
    final m = app.methodLibrary.length, p = app.repertoireLibrary.length;
    if (m == 0 && p == 0) return tr('Monte a sua lista de métodos e peças');
    return [m == 1 ? tr('1 método') : tr('{0} métodos', [m]), p == 1 ? tr('1 peça') : tr('{0} peças', [p])].join(' · ');
  }

  /// Meu espaço de quem chegou e ainda não tem professor nem é professor: o que dá para fazer agora (o próximo passo),
  /// o estudo de hoje e, mais abaixo, o convite para ligar a um professor. Antes era só um cartão pedindo o QR do professor.
  Widget _newcomer(BuildContext context) {
    final step = app.firstStepInHub;
    final study = StudyHubCard(app: app);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _viewSwitch(context, HubView.student),
      if (app.linkStatus.health != LinkHealth.off) _statusChip(context), // o selo "Desligado" não diz nada a quem acabou de chegar
      ..._news(context, HubView.student),
      if (step) ...[FirstStepCard(app: app), const SizedBox(height: Ds.gap)],
      study,
      const SizedBox(height: Ds.sectionGap),
      Padding(padding: const EdgeInsets.only(left: Ds.s4, bottom: Ds.s8), child: Text(tr('Aulas com professor'), style: Ds.section())),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          DsNavRow(Icons.qr_code_scanner, tr('Tenho professor'), tr('Leia o QR dele para ver aulas e tarefas.'), () => _scanTeacher(context)),
        ]),
      ),
      const SizedBox(height: Ds.gap),
    ]);
  }

  /// "Sou professor": liga o modo professor direto daqui (como na apresentação), depois de pedir o nome.
  Future<void> _beTeacher(BuildContext context) async {
    // Primeira vez: o cadastro do professor (nome, instrumentos e turmas). Depois: só o nome e a confirmação de antes.
    if (app.teachInstruments.isEmpty && app.turmas.isEmpty) {
      await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => TeacherSetupPage(app: app)));
      return;
    }
    if (!await requireNickname(context, app, reason: tr('Para ser professor, seus alunos precisam ver o seu nome.'))) return;
    if (!context.mounted || !await requireAdult(context, app)) return;
    if (!context.mounted || !await confirmTeacherLink(context, app)) return;
    app.setTeacherMode(true);
  }

  /// Alternador Aluno | Professor, sempre à vista no topo. Escolher "Professor" com o modo professor desligado segue o mesmo
  /// caminho do antigo "Sou professor": pede o nome, confirma que conecta online e liga o modo.
  Widget _viewSwitch(BuildContext context, HubView view) => Padding(
        padding: const EdgeInsets.only(bottom: Ds.s16),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<HubView>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            segments: [
              ButtonSegment(value: HubView.student, icon: const Icon(Icons.person_outline, size: 20), label: Text(tr('Aluno'))),
              ButtonSegment(value: HubView.teacher, icon: const Icon(Icons.school_outlined, size: 20), label: Text(tr('Professor'))),
            ],
            selected: {view},
            onSelectionChanged: (s) async {
              final v = s.first;
              if (v == HubView.teacher && !app.teacherMode) {
                await _beTeacher(context); // pede o nome e a confirmação; se a pessoa desistir, nada muda
                if (app.teacherMode) app.setHubView(HubView.teacher);
                return;
              }
              app.setHubView(v);
            },
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
            child: _tile(context, studentsTile(app.students.length, waiting: app.students.where((s) => app.awaitingOf(s).isNotEmpty).length), Icons.groups_rounded, () => _push(context, TeacherPage(app: app)),
                action: (Icons.person_add_alt_1_rounded, tr('Adicionar aluno'), () => showAddStudent(context, app))));
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

  /// "Para validar": abre a fila com as tarefas de todos os alunos.
  void _openValidation(BuildContext context) => _push(context, ValidationQueuePage(app: app));

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
        padding: const EdgeInsets.only(bottom: Ds.s12),
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
          margin: const EdgeInsets.only(bottom: Ds.gap),
          padding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s8, Ds.s8, Ds.s8),
          decoration: BoxDecoration(
            color: AppColors.attention.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(Ds.radiusCard),
            border: Border.all(color: AppColors.attention.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            Icon(Icons.notifications_active_outlined, size: 20, color: AppColors.attention),
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
    Widget primary(String t, IconData i, VoidCallback f) => FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)), onPressed: f, icon: Icon(i, size: 18), label: Text(t));
    Widget soft(String t, IconData i, VoidCallback f) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)), onPressed: f, icon: Icon(i, size: 18), label: Text(t));

    for (final d in heroActions(view, h.kind, hasStudents: app.students.isNotEmpty, hasClassStudent: student != null)) {
      switch (d) {
        case HubDest.studentFile:
          final shown = app.labelOf(student!);
          final first = shown == student.name ? student.name.split(' ').first : shown;
          buttons.add(primary(urgent ? tr('Abrir ficha') : tr('Ficha de {0}', [first]), Icons.person_outline,
              () => _push(context, StudentPage(app: app, studentId: student.id))));
        case HubDest.markClass:
          buttons.add(primary(tr('Marcar aula'), Icons.add, () => openSlotForm(context, app)));
        case HubDest.inviteStudent:
          buttons.add(primary(tr('Adicionar aluno'), Icons.person_add_alt_1, () => showAddStudent(context, app)));
        case HubDest.scanTeacher:
          buttons.add(primary(tr('Ler QR ou digitar código'), Icons.qr_code_scanner, () => _scanTeacher(context)));
          if (!app.teacherMode) {
            buttons.add(soft(tr('Sou professor'), Icons.school_outlined, () => _push(context, ProfilePage(app: app, initialTab: 1))));
          }
        default:
      }
    }

    // Cartão neutro; só o que está acontecendo agora (ou prestes) ganha o contorno azul de informação.
    final bg = AppColors.surface;
    return Container(
      padding: const EdgeInsets.all(Ds.s20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Ds.radiusCard),
        border: Border.all(color: urgent ? AppColors.info : AppColors.outline, width: urgent ? 1.6 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (urgent) ...[
            Icon(h.kind == HeroKind.ongoing ? Icons.play_circle_outline : Icons.alarm, size: 18, color: AppColors.info),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(h.kicker, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.info)),
          ),
        ]),
        const SizedBox(height: Ds.s8),
        Text(h.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: Ds.s4),
        Text(h.subtitle, style: TextStyle(fontSize: Ds.fontSupport, color: AppColors.textDim, height: 1.3)),
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: Ds.s16),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(height: Ds.s8), buttons[i]],
          ]),
        ],
        if (extra != null) ...[
          const SizedBox(height: Ds.s16),
          extra,
        ],
      ]),
    );
  }

  /// Rótulo do dia, curto: "Hoje", "Amanhã" ou "Qua 18/11".
  String _dayLabel(DateTime d, DateTime now) {
    final day = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final wd = [tr('Seg'), tr('Ter'), tr('Qua'), tr('Qui'), tr('Sex'), tr('Sáb'), tr('Dom')];
    return day == 0 ? tr('Hoje') : (day == 1 ? tr('Amanhã') : '${wd[d.weekday - 1]} ${fmtDayMonth(d)}');
  }

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _whoOf(SlotOccurrence o) {
    final st = o.slot.studentCode.isEmpty ? null : app.studentByCode(o.slot.studentCode);
    return st == null ? o.slot.teacherName : app.labelOf(st);
  }

  /// O que vem depois da próxima aula (até 3, nos próximos 14 dias) e os atalhos da agenda.
  /// "Depois" numa área recuada (hora e dia à esquerda, quem à direita) e os atalhos lado a lado, para o cartão não virar uma pilha de botões.
  Widget? _agendaExtra(BuildContext context, HubView view, SlotOccurrence? nc, List<HubDest> tools, DateTime now) {
    final isT = view == HubView.teacher;
    final slots = isT ? app.visibleAgenda : app.myAgenda;
    final nowMs = now.millisecondsSinceEpoch;
    final later = agendaBetween(slots, nowMs, nowMs + 14 * 86400000)
        .where((o) => nc == null || o.startMs != nc.startMs)
        .take(3)
        .toList();
    Widget act(IconData i, String t, VoidCallback f) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap), padding: const EdgeInsets.symmetric(horizontal: Ds.s8)),
          onPressed: f,
          icon: Icon(i, size: 18),
          label: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    final online = (nc != null && nc.slot.hasLink)
        ? FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            onPressed: () => openMeetingLink(context, app, nc.slot.link),
            icon: const Icon(Icons.videocam, size: 18),
            label: Text(isT ? tr('Abrir a sala da aula online') : tr('Entrar na aula online')),
          )
        : null;
    final shortcuts = <Widget>[
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
    if (later.isEmpty && shortcuts.isEmpty && online == null) return null;
    Widget row(SlotOccurrence o) {
      final name = _whoOf(o);
      final who = o.slot.studentCode.isEmpty ? null : app.studentByCode(o.slot.studentCode);
      final tint = who == null ? AppColors.textDim : studentTint(who);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Ds.s8),
        child: Row(children: [
          SizedBox(
            width: 70,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_hm(o.start), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.1)),
              Text(_dayLabel(o.start, now), style: TextStyle(fontSize: 12.5, color: AppColors.textDim)),
            ]),
          ),
          PersonAvatar(name: name, photo: who == null ? null : app.photoOfStudent(who), tint: tint, radius: 16),
          const SizedBox(width: Ds.s12),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody))),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (later.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s12, Ds.s16, Ds.s4),
          decoration: BoxDecoration(color: AppColors.bg.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(Ds.radiusControl + 4)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Depois'), style: Ds.section()),
            for (var i = 0; i < later.length; i++) ...[
              if (i > 0) Divider(height: 1, color: AppColors.outline.withValues(alpha: 0.5)),
              row(later[i]),
            ],
          ]),
        ),
        const SizedBox(height: Ds.s12),
      ],
      ?online,
      if (online != null && shortcuts.isNotEmpty) const SizedBox(height: Ds.s8),
      if (shortcuts.length == 1) shortcuts.first,
      if (shortcuts.length >= 2)
        Row(children: [
          Expanded(child: shortcuts[0]),
          const SizedBox(width: Ds.s8),
          Expanded(child: shortcuts[1]),
        ]),
    ]);
  }

  // ---------------- Blocos ----------------
  Widget _pair(Widget a, Widget b) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: a),
          const SizedBox(width: Ds.gap),
          Expanded(child: b),
        ]),
      );

  Widget _tile(BuildContext context, HubTile t, IconData icon, VoidCallback? onTap, {(IconData, String, VoidCallback)? action}) {
    final alert = t.needsAction;
    return InkWell(
      borderRadius: BorderRadius.circular(Ds.radiusCard),
      onTap: onTap ?? () => _push(context, TeacherPage(app: app)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 128),
        padding: const EdgeInsets.all(Ds.s16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Ds.radiusCard),
          border: Border.all(color: alert ? AppColors.attention.withValues(alpha: 0.7) : AppColors.outline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            DsIconBadge(icon, size: 36),
            const SizedBox(width: Ds.s12),
            Expanded(child: Text(t.title, style: TextStyle(fontSize: Ds.fontLabel, color: AppColors.textDim, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: Ds.s12),
          // O atalho (ex.: "+" para adicionar aluno) fica embaixo, à direita, para não apertar o título do bloco.
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: alert ? AppColors.attention : AppColors.text, height: 1.2)),
                const SizedBox(height: Ds.s4),
                Text(t.caption, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.25)),
              ]),
            ),
            if (action != null) ...[
              const SizedBox(width: Ds.s8),
              IconButton.filledTonal(
                tooltip: action.$2,
                style: IconButton.styleFrom(minimumSize: const Size(Ds.tap, Ds.tap), padding: EdgeInsets.zero),
                onPressed: action.$3,
                icon: Icon(action.$1, size: 22),
              ),
            ],
          ]),
          if (t.progress != null) ...[
            const SizedBox(height: Ds.s12),
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
        title: tr('Vincular com professor'), want: 'professor', check: app.checkTeacherCode, onCamera: app.setCameraStatus);
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

/// Aluno → professor: envia (ou copia) o link que abre o app do professor já no cadastro, com o código do aluno preenchido.
/// É o mesmo link do QR do perfil (`?aluno=`), para quando o professor não está ao lado.
Future<void> shareStudentLink(AppState app) async {
  final link = '${shareLink()}/?aluno=${app.profile.shareCode}';
  final name = (app.profile.name ?? '').trim();
  final text = name.isEmpty
      ? tr('Quero ser seu aluno no {0}. Abra este link para me adicionar: {1}', [kAppName, link])
      : tr('Sou {0}, quero ser seu aluno no {1}. Abra este link para me adicionar: {2}', [name, kAppName, link]);
  try {
    await SharePlus.instance.share(ShareParams(text: text, title: kAppName));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    app.say(tr('Link copiado. Cole numa conversa para enviar.'));
  }
}

/// Deixa o Meu espaço do aluno atento ao professor SÓ perto da hora da aula: quando o professor encerra a aula, as tarefas
/// aparecem aqui sem o aluno fazer nada. Fora desse período não consulta sozinho (custo zero); ao abrir, ao voltar ao app
/// e ao puxar a tela para baixo a atualização continua valendo. Ver [lessonLiveMode].
class _LiveWatch extends StatefulWidget {
  final AppState app;
  final Widget child;
  const _LiveWatch({required this.app, required this.child});

  @override
  State<_LiveWatch> createState() => _LiveWatchState();
}

class _LiveWatchState extends State<_LiveWatch> with WidgetsBindingObserver {
  Timer? _t;
  Timer? _slow;
  int _mode = 0; // 0 parado, 1 consulta normal, 2 consulta rápida
  int _peeks = 0;

  /// Espiada lenta fora do horário de aula: depois de 2 min e de mais 4 min com a tela aberta, e para (2 comandos por visita
  /// no máximo; voltar ao app ou mexer na tela recomeça). Assim uma aula marcada ou tarefa nova aparece sozinha sem pesar.
  static const _peekDelays = [Duration(minutes: 2), Duration(minutes: 4)];

  void _schedulePeek() {
    _slow?.cancel();
    if (_mode != 0 || widget.app.myTeachers.isEmpty || _peeks >= _peekDelays.length) return;
    _slow = Timer(_peekDelays[_peeks], () async {
      _peeks++;
      if (!mounted || _mode != 0) return;
      await widget.app.peekLinks();
      _schedulePeek();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _peeks = 0;
      _schedulePeek();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apply();
    _t = Timer.periodic(const Duration(seconds: 30), (_) => _apply());
    _schedulePeek();
  }

  void _apply() {
    final app = widget.app;
    final m = app.myTeachers.isEmpty ? 0 : lessonLiveMode(app.myAgenda, DateTime.now().millisecondsSinceEpoch);
    if (m == _mode) return;
    if (_mode > 0) app.unwatchLinks(fast: _mode == 2);
    _mode = m;
    if (m > 0) app.watchLinks(fast: m == 2);
    if (m == 0) {
      _peeks = 0;
      _schedulePeek();
    } else {
      _slow?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slow?.cancel();
    _t?.cancel();
    if (_mode > 0) widget.app.unwatchLinks(fast: _mode == 2);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
