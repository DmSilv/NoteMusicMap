import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'dictation_button.dart';
import 'meeting_link.dart';
import 'open_slots_page.dart' show describeOpenSlot;
import 'safe_input.dart';
import 'student_identity.dart';
import 'theme.dart';
import 'widgets.dart';

String _two(int n) => n.toString().padLeft(2, '0');
const _dow = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];

/// Abre o formulário de aula marcada. Devolve true se salvou.
Future<bool> openSlotForm(BuildContext context, AppState app, {ClassSlot? edit, DateTime? day, String? studentCode}) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
        builder: (_) => SlotFormPage(app: app, edit: edit, day: day, studentCode: studentCode), fullscreenDialog: true),
  );
  return ok == true;
}

/// Marcar (ou mudar) uma aula: aluno, dia, hora, duração, se repete toda semana e observação.
/// A regra de choque (duas aulas ao mesmo tempo) e de horário que já passou é conferida ao salvar.
class SlotFormPage extends StatefulWidget {
  final AppState app;
  final ClassSlot? edit;
  final DateTime? day;
  final String? studentCode;
  const SlotFormPage({super.key, required this.app, this.edit, this.day, this.studentCode});

  @override
  State<SlotFormPage> createState() => _SlotFormPageState();
}

class _SlotFormPageState extends State<SlotFormPage> {
  AppState get app => widget.app;
  bool get isEdit => widget.edit != null;

  late String? code = widget.edit?.studentCode ?? widget.studentCode ?? (_choices.length == 1 ? _choices.first.code : null);
  late DateTime date = () {
    final e = widget.edit;
    if (e != null) return DateTime.fromMillisecondsSinceEpoch(e.startMs);
    final d = widget.day ?? DateTime.now();
    return DateTime(d.year, d.month, d.day, 15);
  }();
  late int duration = widget.edit?.durationMin ?? 60;
  late bool weekly = widget.edit?.weekly ?? false;
  late final note = TextEditingController(text: widget.edit?.note ?? '');
  late String mode = widget.edit?.mode ?? kModeNone;
  late String link = widget.edit?.link ?? '';
  String? error;

  List<Student> get _choices => [for (final s in app.students) if (s.code != null) s];

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  List<int> get _durations {
    final base = [30, 45, 60, 90];
    if (!base.contains(duration)) base.add(duration);
    base.sort();
    return base;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: isEdit ? DateTime(now.year - 1) : DateTime(now.year, now.month, now.day),
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

  void _save() {
    final c = code;
    if (c == null) {
      setState(() => error = 'Escolha o aluno.');
      return;
    }
    final now = DateTime.now();
    final e = widget.edit;
    final online = app.onlineClassesOn;
    if (online && mode == kModeOnline && link.isNotEmpty && meetingUrl(link) == null) {
      setState(() => error = 'O link da aula não é válido. Use um endereço https, como o do Meet ou do Zoom.');
      return;
    }
    final slot = ClassSlot(
      id: e?.id ?? newSlotId(now),
      studentCode: c,
      startMs: date.millisecondsSinceEpoch,
      durationMin: duration,
      weekly: weekly,
      skipped: e?.skipped ?? const [],
      note: note.text.trim(),
      updatedMs: e?.updatedMs ?? now.millisecondsSinceEpoch,
      mode: online ? (mode == kModeNone ? kModeInPerson : mode) : (e?.mode ?? kModeNone),
      link: online ? (mode == kModeOnline ? (meetingUrl(link) ?? '') : '') : (e?.link ?? ''),
    );
    final err = app.saveSlot(slot);
    if (err != null) {
      setState(() => error = err);
      return;
    }
    final st = app.studentByCode(c);
    if (isEdit) {
      app.say('Aula atualizada.');
    } else {
      app.celebrate('Aula marcada!', detail: '${st?.name ?? 'O aluno'} · ${describeOpenSlot(slot)}');
    }
    Navigator.pop(context, true);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
      );

  @override
  Widget build(BuildContext context) {
    final st = code == null ? null : app.studentByCode(code!);
    final end = date.add(Duration(minutes: duration));
    final summary = '${weekly ? 'Toda ${_dow[date.weekday - 1]}' : '${_dow[date.weekday - 1]}, ${_two(date.day)}/${_two(date.month)}'}'
        ' · ${_two(date.hour)}:${_two(date.minute)}–${_two(end.hour)}:${_two(end.minute)}'
        '${st == null ? '' : ' · ${st.name}'}';

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Editar aula' : 'Marcar aula')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
              _label('Aluno'),
              if (_choices.isEmpty)
                Text('Cadastre um aluno com código para marcar aulas (Meu espaço › Alunos › Novo aluno).',
                    style: TextStyle(color: AppColors.flat))
              else if (isEdit && st != null)
                AppCard(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), child: StudentIdentity(app: app, student: st))
              else
                PickerField<String>(
                  label: 'Aluno',
                  value: code ?? '',
                  icon: Icons.person_outline,
                  options: [
                    if (code == null) const OptionItem('', 'Escolha o aluno'),
                    for (final s in _choices) OptionItem(s.code!, s.name, subtitle: 'Código ${s.code}'),
                  ],
                  onChanged: (v) => setState(() {
                    code = v.isEmpty ? null : v;
                    error = null;
                  }),
                ),
              _label(weekly ? 'Primeira aula' : 'Dia e hora'),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('${_dow[date.weekday - 1]}, ${_two(date.day)}/${_two(date.month)}/${date.year}'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('${_two(date.hour)}:${_two(date.minute)}'),
                  ),
                ),
              ]),
              _label('Duração'),
              ChipGrid(
                labels: [for (final m in _durations) Text('$m min')],
                selected: _durations.indexOf(duration),
                onSelected: (i) => setState(() => duration = _durations[i]),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repetir toda semana', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('No mesmo dia e horário, sem precisar marcar de novo. Dá para cancelar só um dia depois.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                value: weekly,
                onChanged: (v) => setState(() => weekly = v),
              ),
              if (app.onlineClassesOn)
                MeetingEditor(
                  app: app,
                  mode: widget.edit?.mode ?? kModeInPerson,
                  link: widget.edit?.link ?? '',
                  onChanged: (m, l) {
                    mode = m;
                    link = l;
                  },
                ),
              _label('Observação (opcional)'),
              TextField(
                controller: note,
                inputFormatters: const [SafeText.line()],
                maxLength: kMaxSlotNote,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ex.: trazer o arco novo',
                  suffixIcon: DictationButton(app: app, controller: note),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.event_available, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(summary, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
              ),
              _label('Como chega ao aluno'),
              _delivery(st),
              if (error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.sharp.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.sharp.withValues(alpha: 0.4)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.error_outline, size: 18, color: AppColors.sharp),
                    const SizedBox(width: 8),
                    Expanded(child: Text(error!, style: const TextStyle(fontSize: 13, height: 1.3))),
                  ]),
                ),
              ],
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.outline))),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: _choices.isEmpty ? null : _save,
                  icon: const Icon(Icons.check, size: 20),
                  label: Text(isEdit ? 'Salvar' : 'Marcar aula', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _delivery(Student? st) {
    if (st == null) {
      return Text('Escolha o aluno para ver como ele será avisado.', style: TextStyle(color: AppColors.textDim, fontSize: 13));
    }
    final String text;
    final Color color;
    if (st.linkState == 'ended') {
      text = '${st.name} encerrou o vínculo: a aula fica só na sua agenda.';
      color = AppColors.flat;
    } else if (!app.linkEnabled) {
      text = 'O vínculo online está desligado: a aula fica na sua agenda e vai para ${st.name} quando você ligá-lo.';
      color = AppColors.flat;
    } else if (app.deliveryIssue[st.code] == 'not_ready') {
      text = 'O app de ${st.name} ainda não ligou o "Vínculo online": a aula fica na fila e chega quando ele ligar.';
      color = AppColors.flat;
    } else if (st.linkState != 'active') {
      text = '${st.name} ainda não está vinculado: a aula vai quando o vínculo for confirmado.';
      color = AppColors.flat;
    } else {
      text = '${st.name} vê a aula na agenda dele. Os dois recebem um lembrete 15 minutos antes (se ativarem as notificações).';
      color = AppColors.accent;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.3))),
      ]),
    );
  }
}
