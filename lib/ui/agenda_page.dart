import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'meeting_link.dart';
import 'reminder_card.dart';
import 'slot_form_page.dart';
import 'teacher_page.dart' show StudentPage;
import 'theme.dart';
import 'widgets.dart';

String _two(int n) => n.toString().padLeft(2, '0');
const _dow = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
const _dowShort = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
const _months = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
];

String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
DateTime _day0(DateTime d) => DateTime(d.year, d.month, d.day);

/// Agenda do PROFESSOR: as aulas marcadas, por semana ou por mês. Marcar, mudar, cancelar uma
/// aula (ou só um dia de uma aula semanal) e ligar o lembrete de 15 minutos.
class AgendaPage extends StatefulWidget {
  final AppState app;
  const AgendaPage({super.key, required this.app});

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  AppState get app => widget.app;
  bool _month = false;
  DateTime _anchor = _day0(DateTime.now()); // semana/mês mostrado
  DateTime _picked = _day0(DateTime.now()); // dia escolhido na visão mensal

  @override
  void initState() {
    super.initState();
    app.watchLinks(); // aula marcada pendente sai assim que o vínculo confirma
    app.markTab('agenda');
  }

  @override
  void dispose() {
    app.unwatchLinks();
    super.dispose();
  }

  void _shift(int dir) => setState(() {
        _anchor = _month
            ? DateTime(_anchor.year, _anchor.month + dir, 1)
            : _anchor.add(Duration(days: 7 * dir));
        if (_month) _picked = DateTime(_anchor.year, _anchor.month, 1);
      });

  String _title() {
    if (_month) return '${_months[_anchor.month - 1]} de ${_anchor.year}';
    final a = weekStart(_anchor), b = a.add(const Duration(days: 6));
    return a.month == b.month
        ? '${a.day}–${b.day} de ${_months[a.month - 1]}'
        : '${a.day} ${_months[a.month - 1].substring(0, 3)} – ${b.day} ${_months[b.month - 1].substring(0, 3)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Agenda do professor'),
            actions: [
              TextButton(
                onPressed: () => setState(() {
                  _anchor = _day0(DateTime.now());
                  _picked = _anchor;
                }),
                child: const Text('Hoje'),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => openSlotForm(context, app, day: _month ? _picked : null),
            icon: const Icon(Icons.add),
            label: const Text('Marcar aula'),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
              children: [
                const AgendaBanner(teacher: true),
                const SizedBox(height: 10),
                ReminderCard(app: app),
                const SizedBox(height: 12),
                ChipGrid(
                  labels: const [Text('Semana'), Text('Mês')],
                  selected: _month ? 1 : 0,
                  onSelected: (i) => setState(() => _month = i == 1),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Anterior'),
                  Expanded(
                    child: Text(_title(),
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right), tooltip: 'Próximo'),
                ]),
                if (_month) ..._monthView() else ..._weekView(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------- Semana ----------------
  List<Widget> _weekView() {
    final start = weekStart(_anchor);
    final today = _day0(DateTime.now());
    final out = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final d = start.add(Duration(days: i));
      final list = agendaDay(app.visibleAgenda, d);
      final isToday = d == today;
      out.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Row(children: [
          Text('${_dow[i]}, ${_two(d.day)}/${_two(d.month)}',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: isToday ? AppColors.accent : AppColors.text, fontSize: 14)),
          if (isToday)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
              child: Text('hoje', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent)),
            ),
        ]),
      ));
      if (list.isEmpty) {
        out.add(Text('Sem aulas', style: TextStyle(color: AppColors.textDim, fontSize: 12.5)));
      } else {
        for (final o in list) {
          out.add(_tile(o));
        }
      }
    }
    return out;
  }

  // ---------------- Mês ----------------
  List<Widget> _monthView() {
    final first = DateTime(_anchor.year, _anchor.month, 1);
    final days = DateTime(_anchor.year, _anchor.month + 1, 0).day;
    final lead = first.weekday - 1; // células vazias antes do dia 1 (semana começa na segunda)
    final counts = agendaMonthCounts(app.visibleAgenda, first);
    final today = _day0(DateTime.now());
    final cells = <Widget>[
      for (final w in _dowShort)
        Center(child: Text(w, style: TextStyle(color: AppColors.textDim, fontSize: 11.5, fontWeight: FontWeight.w700))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++) _dayCell(DateTime(first.year, first.month, d), counts[d] ?? 0, today),
    ];
    final list = agendaDay(app.visibleAgenda, _picked);
    return [
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 7,
        childAspectRatio: 1.05,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: cells,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text('${_dow[_picked.weekday - 1]}, ${_two(_picked.day)}/${_two(_picked.month)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ),
      if (list.isEmpty)
        Text('Sem aulas neste dia', style: TextStyle(color: AppColors.textDim, fontSize: 12.5))
      else
        for (final o in list) _tile(o),
    ];
  }

  Widget _dayCell(DateTime d, int n, DateTime today) {
    final sel = d == _picked;
    final isToday = d == today;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _picked = d),
      child: Container(
        decoration: BoxDecoration(
          color: sel ? AppColors.accent.withValues(alpha: 0.22) : AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isToday ? AppColors.accent : AppColors.outline, width: isToday ? 1.6 : 1),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${d.day}', style: TextStyle(fontWeight: sel || isToday ? FontWeight.w800 : FontWeight.w600)),
          const SizedBox(height: 2),
          if (n > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
              child: Text('$n', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.onAccent)),
            )
          else
            const SizedBox(height: 14),
        ]),
      ),
    );
  }

  // ---------------- Uma aula ----------------
  Widget _tile(SlotOccurrence o) {
    final s = o.slot;
    final st = app.studentByCode(s.studentCode);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final phase = classPhase(o.startMs, o.startMs + s.endOffsetMs, nowMs);
    final perm = classPermissions(ClassViewer.teacher, phase);
    final past = phase == ClassPhase.finished;
    final queued = s.pending == true;
    final issue = app.deliveryIssue[s.studentCode] == 'not_ready';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Opacity(
        opacity: past ? 0.55 : 1,
        child: Row(children: [
          SizedBox(
            width: 52,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_hm(o.start), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(_hm(o.end), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(st?.name ?? 'Aluno',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (s.weekly) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.repeat, size: 14, color: AppColors.textDim),
                ],
                if (s.online) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.videocam_outlined, size: 15, color: AppColors.accent),
                ],
              ]),
              if (s.online)
                Text(s.hasLink ? 'Online · ${meetingHost(s.link)}' : 'Online · falta o link',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: s.hasLink ? AppColors.textDim : AppColors.flat, fontSize: 12, fontWeight: s.hasLink ? FontWeight.w400 : FontWeight.w700)),
              if (s.note.isNotEmpty)
                Text(s.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              if (phase == ClassPhase.ongoing || phase == ClassPhase.soon)
                Text(classPhaseLabel(phase),
                    style: TextStyle(color: AppColors.accent, fontSize: 11.5, fontWeight: FontWeight.w700)),
              if (queued)
                Text(issue ? 'Aluno ainda não recebeu' : 'A enviar ao aluno',
                    style: TextStyle(color: AppColors.flat, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (!past)
          PopupMenuButton<String>(
            tooltip: 'Opções da aula',
            onSelected: (v) => _menu(v, o),
            itemBuilder: (c) => [
              if (perm.edit) const PopupMenuItem(value: 'edit', child: Text('Editar')),
              if (perm.edit && s.online) PopupMenuItem(value: 'link', child: Text(s.hasLink ? 'Editar link da aula' : 'Adicionar link da aula')),
              if (s.hasLink) const PopupMenuItem(value: 'join', child: Text('Abrir a sala')),
              if (st != null) const PopupMenuItem(value: 'open', child: Text('Abrir ficha do aluno')),
              if (perm.cancel && s.weekly) const PopupMenuItem(value: 'skip', child: Text('Cancelar só esta aula')),
              if (perm.cancel) PopupMenuItem(value: 'cancel', child: Text(s.weekly ? 'Cancelar todas as aulas' : 'Cancelar aula')),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _menu(String v, SlotOccurrence o) async {
    final s = o.slot;
    switch (v) {
      case 'edit':
        await openSlotForm(context, app, edit: s);
      case 'link':
        final r = await showMeetLinkSheet(context, app, initial: s.link);
        if (r != null) {
          final e = app.setSlotLink(s.id, r);
          app.say(e ?? (r.isEmpty ? 'Link removido.' : 'Link da aula salvo. O aluno recebe na hora.'));
        }
      case 'join':
        await openMeetingLink(context, app, s.link);
      case 'open':
        final st = app.studentByCode(s.studentCode);
        if (st != null && mounted) {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: st.id)));
        }
      case 'skip':
        if (await _confirm('Cancelar só esta aula?', 'A aula de ${_dow[o.start.weekday - 1]}, ${_two(o.start.day)}/${_two(o.start.month)} '
            'é cancelada. As outras semanas continuam. O aluno é avisado.')) {
          app.skipOccurrence(s.id, o.startMs);
          app.say('Aula cancelada.');
        }
      case 'cancel':
        if (await _confirm(s.weekly ? 'Cancelar todas as aulas?' : 'Cancelar a aula?',
            s.weekly ? 'A aula semanal deixa de existir daqui para a frente. O aluno é avisado.' : 'O aluno é avisado.')) {
          app.cancelSlot(s.id);
          app.say('Aula cancelada.');
        }
    }
  }

  Future<bool> _confirm(String title, String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.sharp, foregroundColor: readableOn(AppColors.sharp)),
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.event_busy, size: 18), label: const Text('Cancelar aula'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

/// Agenda do ALUNO: as próximas aulas marcadas pelos professores (30 dias) e o lembrete.
class MyAgendaPage extends StatefulWidget {
  final AppState app;
  const MyAgendaPage({super.key, required this.app});

  @override
  State<MyAgendaPage> createState() => _MyAgendaPageState();
}

class _MyAgendaPageState extends State<MyAgendaPage> {
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.watchLinks();
    app.pullAgenda(announce: false);
  }

  @override
  void dispose() {
    app.unwatchLinks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final now = DateTime.now();
        final list = agendaBetween(app.myAgenda, now.millisecondsSinceEpoch - 60 * kMsMinute,
            now.millisecondsSinceEpoch + 30 * kMsDay)
            .where((o) => o.end.isAfter(now))
            .toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Agenda do aluno')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                const AgendaBanner(teacher: false),
                const SizedBox(height: 10),
                ReminderCard(app: app),
                const SizedBox(height: 14),
                Text('Próximas aulas (30 dias)',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (list.isEmpty)
                  AppCard(
                    child: Text(
                      app.myTeachers.isEmpty
                          ? 'Vincule-se a um professor para ver aqui as aulas que ele marcar.'
                          : 'Nenhuma aula marcada por enquanto. Quando seu professor marcar, ela aparece aqui.',
                      style: TextStyle(color: AppColors.textDim),
                    ),
                  ),
                for (final o in list) _row(o, now),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(SlotOccurrence o, DateTime now) {
    final s = o.slot;
    final who = s.teacherName.isNotEmpty ? s.teacherName : 'Professor ${s.teacherCode}';
    final ongoing = !o.start.isAfter(now);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ongoing ? AppColors.accent : AppColors.outline, width: ongoing ? 1.6 : 1),
      ),
      child: Row(children: [
        Icon(s.weekly ? Icons.event_repeat : Icons.event, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${fmtSlotWhen(o.start, now)} – ${_hm(o.end)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(who, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            if (s.note.isNotEmpty) Text(s.note, style: const TextStyle(fontSize: 12.5, height: 1.3)),
            if (s.online)
              Text(s.hasLink ? 'Aula online' : 'Aula online · o professor ainda vai enviar o link',
                  style: TextStyle(color: s.hasLink ? AppColors.accent : AppColors.flat, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (s.hasLink)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilledButton.icon(
              onPressed: () => openMeetingLink(context, app, s.link),
              icon: const Icon(Icons.videocam, size: 18),
              label: const Text('Entrar'),
            ),
          )
        else if (ongoing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
            child: Text('agora', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.accent)),
          ),
      ]),
    );
  }
}

/// Faixa no topo das duas agendas: deixa claro de quem é a agenda que está aberta.
class AgendaBanner extends StatelessWidget {
  final bool teacher;
  const AgendaBanner({super.key, required this.teacher});

  @override
  Widget build(BuildContext context) {
    final color = teacher ? AppColors.accent : AppColors.flat;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(children: [
        Icon(teacher ? Icons.school_outlined : Icons.person_outline, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(teacher ? 'AGENDA DO PROFESSOR' : 'AGENDA DO ALUNO',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color)),
            Text(
              teacher
                  ? 'Aulas que você marca com os seus alunos.'
                  : 'Aulas que o seu professor marcou para você.',
              style: const TextStyle(fontSize: 13, height: 1.25),
            ),
          ]),
        ),
      ]),
    );
  }
}
