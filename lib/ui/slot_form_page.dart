import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'dictation_button.dart';
import 'meeting_link.dart';
import 'remind_field.dart';
import 'open_slots_page.dart' show describeOpenSlot;
import 'safe_input.dart';
import 'student_identity.dart';
import 'theme.dart';
import 'widgets.dart';

String _two(int n) => n.toString().padLeft(2, '0');
final _dow = [tr('segunda'), tr('terça'), tr('quarta'), tr('quinta'), tr('sexta'), tr('sábado'), tr('domingo')];

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
  // Lembrete: ao editar mostra o que a aula tem de verdade; numa aula nova começa pela última escolha do professor.
  late int remind = widget.edit?.remindLead ?? app.remindDefault;
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
      setState(() => error = tr('Escolha o aluno.'));
      return;
    }
    final now = DateTime.now();
    final e = widget.edit;
    final online = app.onlineClassesOn;
    if (online && mode == kModeOnline && link.isNotEmpty && meetingUrl(link) == null) {
      setState(() => error = tr('O link da aula não é válido. Use um endereço https, como o do Meet ou do Zoom.'));
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
      remindMin: app.remindChoiceOn ? remind : e?.remindMin,
    );
    final err = app.saveSlot(slot);
    if (err != null) {
      setState(() => error = err);
      return;
    }
    if (app.remindChoiceOn) app.setRemindDefault(remind);
    final st = app.studentByCode(c);
    if (isEdit) {
      app.say(tr('Aula atualizada.'));
    } else {
      app.celebrate(tr('Aula marcada!'), detail: '${st?.name ?? tr('O aluno')} · ${describeOpenSlot(slot)}');
    }
    Navigator.pop(context, true);
  }

  /// Título de seção: pequeno e discreto, para a tela respirar (os campos já dizem o que são).
  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.sectionGap, 0, Ds.s8),
        child: Text(t, style: Ds.section()),
      );

  @override
  Widget build(BuildContext context) {
    final st = code == null ? null : app.studentByCode(code!);
    final end = date.add(Duration(minutes: duration));
    final when = weekly ? tr('Toda {0}', [_dow[date.weekday - 1]]) : '${_dow[date.weekday - 1]}, ${_two(date.day)}/${_two(date.month)}';
    final summary = '$when · ${_two(date.hour)}:${_two(date.minute)}–${_two(end.hour)}:${_two(end.minute)}${st == null ? '' : ' · ${st.name}'}';
    final (deliveryText, deliveryColor) = _delivery(st);
    final hasDetails = app.remindChoiceOn || app.onlineClassesOn;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? tr('Editar aula') : tr('Marcar aula'))),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s24), children: [
              _section(tr('Aluno')),
              if (_choices.isEmpty)
                Text(tr('Cadastre um aluno com código para marcar aulas (Meu espaço › Alunos › Novo aluno).'), style: TextStyle(color: AppColors.flat))
              else if (isEdit && st != null && _choices.length < 2)
                AppCard(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), child: StudentIdentity(app: app, student: st))
              else
                PickerField<String>(
                  label: tr('Aluno'),
                  value: code ?? '',
                  icon: Icons.person_outline,
                  options: [
                    if (code == null) OptionItem('', tr('Escolha o aluno')),
                    for (final s in _choices) OptionItem(s.code!, s.name, subtitle: tr('Código {0}', [s.code])),
                  ],
                  onChanged: (v) => setState(() {
                    code = v.isEmpty ? null : v;
                    error = null;
                  }),
                ),
              _section(tr('Quando')),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: DsPickTile(
                        icon: Icons.event,
                        label: weekly ? tr('Primeira aula') : tr('Dia'),
                        value: '${_dow[date.weekday - 1].substring(0, 3)}, ${_two(date.day)}/${_two(date.month)}/${date.year}',
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: Ds.s12),
                    SizedBox(width: 112, child: DsPickTile(icon: Icons.schedule, label: tr('Hora'), value: '${_two(date.hour)}:${_two(date.minute)}', onTap: _pickTime)),
                  ]),
                  const SizedBox(height: Ds.s16),
                  Text(tr('Duração'), style: Ds.section()),
                  const SizedBox(height: Ds.s8),
                  ChipGrid(
                    labels: [for (final m in _durations) Text('$m min')],
                    selected: _durations.indexOf(duration),
                    onSelected: (i) => setState(() => duration = _durations[i]),
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: Ds.s8), child: Divider(height: 1)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Repetir toda semana'), style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(tr('Mesmo dia e horário. Dá para cancelar só um dia depois.'), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                    value: weekly,
                    onChanged: (v) => setState(() => weekly = v),
                  ),
                ]),
              ),
              if (hasDetails) ...[
                _section(tr('Detalhes')),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (app.remindChoiceOn) RemindField(value: remind, onChanged: (v) => setState(() => remind = v)),
                    if (app.remindChoiceOn && app.onlineClassesOn) const SizedBox(height: Ds.s16),
                    if (app.onlineClassesOn)
                      MeetingEditor(
                        app: app,
                        compact: true,
                        mode: widget.edit?.mode ?? kModeInPerson,
                        link: widget.edit?.link ?? '',
                        onChanged: (m, l) {
                          mode = m;
                          link = l;
                        },
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: Ds.sectionGap),
              TextField(
                controller: note,
                inputFormatters: const [SafeText.line()],
                maxLength: kMaxSlotNote,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Observação (opcional)'),
                  hintText: tr('Ex.: trazer o arco novo'),
                  suffixIcon: DictationButton(app: app, controller: note),
                ),
              ),
              const SizedBox(height: Ds.s8),
              // Resumo e "como chega ao aluno" num bloco só (antes eram dois).
              Container(
                padding: const EdgeInsets.all(Ds.s16),
                decoration: BoxDecoration(
                  color: deliveryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
                  border: Border.all(color: deliveryColor.withValues(alpha: 0.35)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.event_available, size: 20, color: deliveryColor),
                  const SizedBox(width: Ds.s12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(summary, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: Ds.s4),
                      Text(deliveryText, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textDim)),
                    ]),
                  ),
                ]),
              ),
              if (error != null) ...[
                const SizedBox(height: Ds.s12),
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
                  child: Text(tr('Cancelar')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: _choices.isEmpty ? null : _save,
                  icon: const Icon(Icons.check, size: 20),
                  label: Text(isEdit ? tr('Salvar') : tr('Marcar aula'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Como a aula chega ao aluno (texto e cor do bloco de resumo).
  (String, Color) _delivery(Student? st) {
    if (st == null) return (tr('Escolha o aluno para ver como ele será avisado.'), AppColors.textDim);
    if (st.linkState == 'ended') return (tr('{0} encerrou o vínculo: a aula fica só na sua agenda.', [st.name]), AppColors.flat);
    if (!app.linkEnabled) return (tr('O vínculo online está desligado: a aula fica na sua agenda e vai para {0} quando você ligá-lo.', [st.name]), AppColors.flat);
    if (app.deliveryIssue[st.code] == 'not_ready') {
      return (tr('O app de {0} ainda não ligou o "Vínculo online": a aula fica na fila e chega quando ele ligar.', [st.name]), AppColors.flat);
    }
    if (st.linkState != 'active') return (tr('{0} ainda não está vinculado: a aula vai quando o vínculo for confirmado.', [st.name]), AppColors.flat);
    final aviso = !app.remindChoiceOn
        ? tr('Os dois recebem um lembrete 15 minutos antes (se ativarem as notificações).')
        : (remind == 0
            ? tr('Esta aula fica sem lembrete.')
            : tr('Os dois recebem um lembrete {0} (se ativarem as notificações).', [remindLabel(remind).toLowerCase()]));
    return (tr('{0} vê a aula na agenda dele. {1}', [st.name, aviso]), AppColors.accent);
  }
}
