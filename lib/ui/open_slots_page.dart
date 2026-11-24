import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'meeting_link.dart';
import 'remind_field.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart';

List<String> get _days => [tr('segunda'), tr('terça'), tr('quarta'), tr('quinta'), tr('sexta'), tr('sábado'), tr('domingo')];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Terça, 12/11 às 15:00 · 60 min" ou "Toda terça às 15:00 · 60 min".
String describeOpenSlot(ClassSlot s) => describeSlot(s);

/// PROFESSOR: horários que deixa livres para os alunos pegarem.
class OpenSlotsPage extends StatefulWidget {
  final AppState app;
  const OpenSlotsPage({super.key, required this.app});

  @override
  State<OpenSlotsPage> createState() => _OpenSlotsPageState();
}

class _OpenSlotsPageState extends State<OpenSlotsPage> {
  AppState get app => widget.app;

  Future<void> _remove(ClassSlot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Apagar este horário?')),
        content: Text(tr('{0}\n\nOs alunos deixam de vê-lo. Aulas já marcadas não mudam.', [describeOpenSlot(s)])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Voltar'))),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.delete_outline, size: 18), label: Text(tr('Apagar'))),
        ],
      ),
    );
    if (ok == true) app.removeOpenSlot(s.id);
  }

  Future<void> _add() async {
    final slot = await showDialog<ClassSlot>(context: context, builder: (_) => _NewOpenSlotDialog(app: app));
    if (slot == null || !mounted) return;
    final err = app.saveOpenSlot(slot);
    app.say(err ?? tr('Horário publicado. Seus alunos já podem pegá-lo.'));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = app.openSlotsActive;
        return Scaffold(
          appBar: AppBar(title: Text(tr('Horários livres'))),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(tr('Novo horário')),
          ),
          body: DsPageSafe(child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text(
                tr('O aluno vinculado escolhe um horário livre e a aula entra na agenda dos dois. O primeiro que pegar leva.'),
                style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                AppCard(child: Text(tr('Nenhum horário livre agora. Toque em "Novo horário".')))
              else
                for (final s in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: Row(children: [
                        Icon(s.weekly ? Icons.repeat : Icons.event_available_outlined, color: AppColors.accent),
                        const SizedBox(width: 12),
                        Expanded(child: Text(describeOpenSlot(s), style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (s.pending == true) Text(tr('enviando…'), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                        IconButton(
                          tooltip: tr('Apagar horário'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(s),
                        ),
                      ]),
                    ),
                  ),
            ],
          )),
        );
      },
    );
  }
}

class _NewOpenSlotDialog extends StatefulWidget {
  final AppState app;
  const _NewOpenSlotDialog({required this.app});

  @override
  State<_NewOpenSlotDialog> createState() => _NewOpenSlotDialogState();
}

class _NewOpenSlotDialogState extends State<_NewOpenSlotDialog> {
  late DateTime date = () {
    final n = DateTime.now().add(const Duration(days: 1));
    return DateTime(n.year, n.month, n.day, 15);
  }();
  int duration = 60;
  bool weekly = false;
  String mode = kModeNone;
  String link = '';
  late int remind = widget.app.remindDefault;
  String? error;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (d != null) setState(() => date = DateTime(d.year, d.month, d.day, date.hour, date.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: date.hour, minute: date.minute),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) setState(() => date = DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Novo horário livre')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text('${_days[date.weekday - 1]}, ${fmtDayMonthYear(date)}'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickTime,
            icon: const Icon(Icons.schedule, size: 18),
            label: Text('${_two(date.hour)}:${_two(date.minute)}'),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final m in const [30, 45, 60, 90])
              ChoiceChip(label: Text('$m min'), selected: duration == m, onSelected: (_) => setState(() => duration = m)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Repetir toda semana')),
            subtitle: Text(tr('Quem pegar fica com esse horário toda semana.')),
            value: weekly,
            onChanged: (v) => setState(() => weekly = v),
          ),
          if (widget.app.remindChoiceOn) ...[
            const SizedBox(height: 4),
            RemindField(value: remind, onChanged: (v) => setState(() => remind = v)),
          ],
          if (widget.app.onlineClassesOn)
            MeetingEditor(
              app: widget.app,
              mode: kModeInPerson,
              link: '',
              onChanged: (m, l) {
                mode = m;
                link = l;
              },
            ),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: AppColors.sharp))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar'))),
        FilledButton.icon(
          onPressed: () {
            final now = DateTime.now();
            final online = widget.app.onlineClassesOn;
            if (online && mode == kModeOnline && link.isNotEmpty && meetingUrl(link) == null) {
              setState(() => error = tr('O link da aula não é válido.'));
              return;
            }
            if (widget.app.remindChoiceOn) widget.app.setRemindDefault(remind);
            Navigator.pop(
              context,
              ClassSlot(
                id: newSlotId(now),
                startMs: date.millisecondsSinceEpoch,
                durationMin: duration,
                weekly: weekly,
                updatedMs: now.millisecondsSinceEpoch,
                mode: online ? (mode == kModeNone ? kModeInPerson : mode) : kModeNone,
                link: online && mode == kModeOnline ? (meetingUrl(link) ?? '') : '',
                remindMin: widget.app.remindChoiceOn ? remind : null,
              ),
            );
          },
          icon: const Icon(Icons.publish_rounded, size: 18), label: Text(tr('Publicar')),
        ),
      ],
    );
  }
}

/// ALUNO: horários livres de um professor vinculado; toca em "Pegar" e a aula entra na agenda.
class PickSlotPage extends StatefulWidget {
  final AppState app;
  const PickSlotPage({super.key, required this.app});

  @override
  State<PickSlotPage> createState() => _PickSlotPageState();
}

class _PickSlotPageState extends State<PickSlotPage> {
  AppState get app => widget.app;
  String? teacher;
  List<ClassSlot>? slots;
  bool loading = false;
  bool failed = false;
  bool taking = false;

  @override
  void initState() {
    super.initState();
    if (app.myTeachers.isNotEmpty) {
      teacher = _defaultTeacher();
      _load();
    }
  }

  /// O professor que abre primeiro: o da aula mais próxima (ou o primeiro que não está pausado).
  String _defaultTeacher() {
    final open = [for (final t in app.myTeachers) if (!t.paused) t];
    final list = open.isEmpty ? app.myTeachers : open;
    final now = DateTime.now().millisecondsSinceEpoch;
    String? best;
    var bestMs = 1 << 62;
    for (final t in list) {
      final o = nextOccurrence([for (final s in app.myAgenda) if (s.teacherCode == t.code) s], now);
      final ms = o?.start.millisecondsSinceEpoch ?? (1 << 61);
      if (ms < bestMs) {
        bestMs = ms;
        best = t.code;
      }
    }
    return best ?? list.first.code;
  }

  Future<void> _load() async {
    final t = teacher;
    if (t == null) return;
    setState(() {
      loading = true;
      failed = false;
    });
    final r = await app.loadOpenSlots(t);
    if (!mounted || t != teacher) return;
    setState(() {
      slots = r;
      failed = r == null;
      loading = false;
    });
  }

  Future<void> _take(ClassSlot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Pegar este horário?')),
        content: Text(tr('{0}\n\nA aula entra na sua agenda e seu professor é avisado.', [describeOpenSlot(s)])),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, Ds.tap)), onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, Ds.tap)), onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.event_available_outlined, size: 18), label: Text(tr('Pegar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => taking = true);
    final err = await app.takeOpenSlot(teacher!, s);
    if (err == null) {
      app.celebrate(tr('Horário garantido!'), detail: describeOpenSlot(s));
    } else {
      app.say(err);
    }
    if (mounted) {
      setState(() => taking = false);
      _load();
    }
  }

  /// Um horário livre: dia e hora em destaque, a duração embaixo e um botão grande para pegar.
  Widget _slotCard(ClassSlot s) {
    final d = DateTime.fromMillisecondsSinceEpoch(s.startMs);
    final days = [tr('segunda'), tr('terça'), tr('quarta'), tr('quinta'), tr('sexta'), tr('sábado'), tr('domingo')];
    final dayName = days[d.weekday - 1][0].toUpperCase() + days[d.weekday - 1].substring(1);
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    // Dia e hora em cima, curtos (cabem numa linha); embaixo, se repete, quanto dura e se é online.
    final title = s.weekly ? '$dayName · $hm' : '${dayName.substring(0, 3)} ${fmtDayMonth(d)} · $hm';
    final support = [s.weekly ? tr('Toda semana') : tr('Só neste dia'), tr('{0} min', [s.durationMin]), if (s.online) tr('online')].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s12),
      child: AppCard(
        padding: const EdgeInsets.all(Ds.s16),
        child: Row(children: [
          DsIconBadge(s.weekly ? Icons.repeat_rounded : Icons.event_available_outlined, size: 44),
          const SizedBox(width: Ds.s16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2)),
              Padding(padding: const EdgeInsets.only(top: Ds.s4), child: Text(support, style: Ds.support())),
            ]),
          ),
          const SizedBox(width: Ds.s12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, Ds.tap)),
            onPressed: taking ? null : () => _take(s),
            child: Text(tr('Pegar'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teachers = app.myTeachers;
    final who = teachers.where((t) => t.code == teacher).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Pegar horário'))),
      body: DsPageSafe(child: ListView(
        padding: Ds.screen,
        children: [
          if (teachers.isEmpty)
            AppCard(child: Text(tr('Você ainda não tem um professor vinculado. Peça o convite a ele.')))
          else ...[
            Text(tr('Escolha um horário'), style: Ds.title()),
            const SizedBox(height: Ds.s4),
            Text(tr('A aula entra na sua agenda e {0} é avisado.', [(who?.name ?? '').isEmpty ? tr('seu professor') : who!.name]), style: Ds.support()),
            const SizedBox(height: Ds.s16),
            if (teachers.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: Ds.s16),
                child: Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
                  for (final t in teachers)
                    ChoiceChip(
                      label: Text(t.name.isEmpty ? t.code : t.name),
                      selected: teacher == t.code,
                      onSelected: (_) {
                        teacher = t.code;
                        _load();
                      },
                    ),
                ]),
              ),
            if (loading)
              const Padding(padding: EdgeInsets.all(Ds.s32), child: Center(child: CircularProgressIndicator()))
            else if (failed)
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Não foi possível ver os horários agora.')),
                  const SizedBox(height: Ds.s12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap)),
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(tr('Tentar de novo')),
                  ),
                ]),
              )
            else if ((slots ?? const []).isEmpty)
              AppCard(
                padding: const EdgeInsets.all(Ds.s24),
                child: Column(children: [
                  Icon(Icons.event_busy_outlined, size: 36, color: AppColors.textDim),
                  const SizedBox(height: Ds.s12),
                  Text(tr('Seu professor não deixou horários livres no momento.'), textAlign: TextAlign.center, style: Ds.support()),
                ]),
              )
            else
              for (final s in slots!) _slotCard(s),
          ],
        ],
      )),
    );
  }
}
