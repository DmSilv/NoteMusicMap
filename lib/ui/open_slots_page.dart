import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'meeting_link.dart';
import 'theme.dart';
import 'widgets.dart';

const _days = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];

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
        title: const Text('Apagar este horário?'),
        content: Text('${describeOpenSlot(s)}\n\nOs alunos deixam de vê-lo. Aulas já marcadas não mudam.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Apagar')),
        ],
      ),
    );
    if (ok == true) app.removeOpenSlot(s.id);
  }

  Future<void> _add() async {
    final slot = await showDialog<ClassSlot>(context: context, builder: (_) => _NewOpenSlotDialog(app: app));
    if (slot == null || !mounted) return;
    final err = app.saveOpenSlot(slot);
    app.say(err ?? 'Horário publicado. Seus alunos já podem pegá-lo.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = app.openSlotsActive;
        return Scaffold(
          appBar: AppBar(title: const Text('Horários livres')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Novo horário'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text(
                'O aluno vinculado escolhe um horário livre e a aula entra na agenda dos dois. O primeiro que pegar leva.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const AppCard(child: Text('Nenhum horário livre agora. Toque em "Novo horário".'))
              else
                for (final s in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: Row(children: [
                        Icon(s.weekly ? Icons.repeat : Icons.event_available_outlined, color: AppColors.accent),
                        const SizedBox(width: 12),
                        Expanded(child: Text(describeOpenSlot(s), style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (s.pending == true) Text('enviando…', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                        IconButton(
                          tooltip: 'Apagar horário',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(s),
                        ),
                      ]),
                    ),
                  ),
            ],
          ),
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
      title: const Text('Novo horário livre'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text('${_days[date.weekday - 1]}, ${_two(date.day)}/${_two(date.month)}/${date.year}'),
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
            title: const Text('Repetir toda semana'),
            subtitle: const Text('Quem pegar fica com esse horário toda semana.'),
            value: weekly,
            onChanged: (v) => setState(() => weekly = v),
          ),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: () {
            final now = DateTime.now();
            final online = widget.app.onlineClassesOn;
            if (online && mode == kModeOnline && link.isNotEmpty && meetingUrl(link) == null) {
              setState(() => error = 'O link da aula não é válido.');
              return;
            }
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
              ),
            );
          },
          icon: const Icon(Icons.publish_rounded, size: 18), label: const Text('Publicar'),
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
      teacher = app.myTeachers.first.code;
      _load();
    }
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
        title: const Text('Pegar este horário?'),
        content: Text('${describeOpenSlot(s)}\n\nA aula entra na sua agenda e seu professor é avisado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.event_available_outlined, size: 18), label: const Text('Pegar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => taking = true);
    final err = await app.takeOpenSlot(teacher!, s);
    if (err == null) {
      app.celebrate('Horário garantido!', detail: describeOpenSlot(s));
    } else {
      app.say(err);
    }
    if (mounted) {
      setState(() => taking = false);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final teachers = app.myTeachers;
    return Scaffold(
      appBar: AppBar(title: const Text('Pegar horário')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (teachers.isEmpty)
            const AppCard(child: Text('Você ainda não tem um professor vinculado. Peça o convite a ele.'))
          else ...[
            if (teachers.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 8, children: [
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
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (failed)
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Não foi possível ver os horários agora.'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Tentar de novo')),
                ]),
              )
            else if ((slots ?? const []).isEmpty)
              const AppCard(child: Text('Seu professor não deixou horários livres no momento.'))
            else
              for (final s in slots!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    child: Row(children: [
                      Icon(s.weekly ? Icons.repeat : Icons.event_available_outlined, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Expanded(child: Text(describeOpenSlot(s), style: const TextStyle(fontWeight: FontWeight.w700))),
                      FilledButton.icon(onPressed: taking ? null : () => _take(s), icon: const Icon(Icons.event_available_outlined, size: 18), label: Text(taking ? 'Enviando…' : 'Pegar')),
                    ]),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
