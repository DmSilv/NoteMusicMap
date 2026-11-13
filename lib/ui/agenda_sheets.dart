import 'package:flutter/material.dart';

import 'design_system.dart';
import 'theme.dart';
import 'package:afina_core/afina_core.dart';

/// Modais da agenda do professor (remarcar uma aula, trocar horários, confirmar). Cada ação é UM modal só: o que vai
/// mudar aparece antes (de → para), a conferência de choque é feita ao vivo e o botão só liga quando cabe na agenda.
/// Não conhecem o app: recebem as regras por funções ([check] e [commit]), o que deixa tudo testável.

String _two(int n) => n.toString().padLeft(2, '0');
final _dow = [tr('seg'), tr('ter'), tr('qua'), tr('qui'), tr('sex'), tr('sáb'), tr('dom')];

/// "qui 12/11 · 15:00".
String whenText(DateTime d) => '${_dow[d.weekday - 1]} ${fmtDayMonth(d)} · ${_two(d.hour)}:${_two(d.minute)}';

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
      builder: builder,
    );

Widget _header(IconData icon, String title, String? subtitle, {Color? color}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DsIconBadge(icon, size: 44, color: color),
      const SizedBox(width: Ds.s12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Ds.title().copyWith(fontSize: 21)),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: Ds.support())),
        ]),
      ),
    ]);

/// Faixa de resultado: verde (vai dar certo), laranja (não cabe) ou neutra (falta escolher).
Widget _banner(Color color, IconData icon, List<Widget> lines) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Ds.s16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: Ds.s12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines)),
      ]),
    );

Widget _buttons(BuildContext context, {required String ok, required bool enabled, required VoidCallback onOk, bool danger = false, IconData icon = Icons.check_rounded}) =>
    Row(children: [
      Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.primaryHeight - 4)),
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Voltar')),
        ),
      ),
      const SizedBox(width: Ds.s12),
      Expanded(
        flex: 2,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(Ds.primaryHeight - 4),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            backgroundColor: danger ? AppColors.sharp : null,
            foregroundColor: danger ? readableOn(AppColors.sharp) : null,
          ),
          onPressed: enabled ? onOk : null,
          icon: Icon(icon, size: 22),
          label: Text(ok),
        ),
      ),
    ]);

// ---------------------------------------------------------------- Remarcar

/// Remarcar uma aula para outro dia e hora. [check] diz por que NÃO cabe (null = cabe); [commit] aplica (null = aplicou,
/// senão o motivo). Devolve o novo horário se aplicou, ou null se a pessoa voltou.
Future<DateTime?> showMoveSheet(
  BuildContext context, {
  required String who,
  required DateTime from,
  required bool weekly,
  required String? Function(DateTime to) check,
  required String? Function(DateTime to) commit,
}) {
  return _sheet<DateTime>(
    context,
    (c) => _MoveBody(who: who, from: from, weekly: weekly, check: check, commit: commit),
  );
}

class _MoveBody extends StatefulWidget {
  final String who;
  final DateTime from;
  final bool weekly;
  final String? Function(DateTime) check;
  final String? Function(DateTime) commit;
  const _MoveBody({required this.who, required this.from, required this.weekly, required this.check, required this.commit});

  @override
  State<_MoveBody> createState() => _MoveBodyState();
}

class _MoveBodyState extends State<_MoveBody> {
  late DateTime to = widget.from;
  String? failed; // motivo devolvido ao aplicar (ex.: outro aparelho mudou a agenda)

  bool get _same => to.isAtSameMomentAs(widget.from);
  String? get _problem => _same ? null : (failed ?? widget.check(to));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: to.isBefore(first) ? first : to,
      firstDate: first,
      lastDate: DateTime(now.year + 2),
      helpText: tr('Novo dia da aula'),
    );
    if (d != null) {
      setState(() {
        to = DateTime(d.year, d.month, d.day, to.hour, to.minute);
        failed = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: to.hour, minute: to.minute),
      helpText: tr('Novo horário@@hora'),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) {
      setState(() {
        to = DateTime(to.year, to.month, to.day, t.hour, t.minute);
        failed = null;
      });
    }
  }

  void _confirm() {
    final err = widget.commit(to);
    if (err != null) {
      setState(() => failed = err);
      return;
    }
    Navigator.pop(context, to);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final ready = !_same && problem == null;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Ds.screenPad, Ds.s4, Ds.screenPad, Ds.s16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.event_repeat_rounded, tr('Remarcar esta aula'), '${widget.who} · ${whenText(widget.from)}'),
        const SizedBox(height: Ds.s20),
        Text(tr('Novo horário@@hora'), style: Ds.section()),
        const SizedBox(height: Ds.s8),
        Row(children: [
          Expanded(child: DsPickTile(icon: Icons.event, label: tr('Dia'), value: '${_dow[to.weekday - 1]}, ${fmtDayMonthYear(to)}', onTap: _pickDate)),
          const SizedBox(width: Ds.s12),
          SizedBox(width: 112, child: DsPickTile(icon: Icons.schedule, label: tr('Hora'), value: '${_two(to.hour)}:${_two(to.minute)}', onTap: _pickTime)),
        ]),
        const SizedBox(height: Ds.s16),
        if (_same)
          _banner(AppColors.textDim, Icons.touch_app_outlined, [Text(tr('Escolha outro dia ou outra hora.'), style: Ds.support().copyWith(fontSize: 15))])
        else if (problem != null)
          _banner(AppColors.sharp, Icons.error_outline_rounded, [Text(problem, style: const TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600))])
        else
          _banner(AppColors.accent, Icons.arrow_forward_rounded, [
            Text(whenText(widget.from), style: TextStyle(fontSize: 14, color: AppColors.textDim, decoration: TextDecoration.lineThrough)),
            const SizedBox(height: 2),
            Text(whenText(to), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
        const SizedBox(height: Ds.s8),
        Text(
          tr('{0} é avisado.{1}', [widget.who, widget.weekly ? tr(' As outras semanas continuam como estão.') : '']),
          style: Ds.support(),
        ),
        const SizedBox(height: Ds.s16),
        _buttons(context, ok: tr('Remarcar'), enabled: ready, onOk: _confirm),
      ]),
    );
  }
}

// ------------------------------------------------------------------- Trocar

/// Uma aula de outro aluno que dá para trocar.
class SwapOption {
  final String name;
  final DateTime start;
  const SwapOption(this.name, this.start);
}

/// Trocar o horário desta aula com o de outro aluno. [check] e [commit] recebem o índice escolhido em [options].
/// Devolve esse índice se aplicou, ou null se a pessoa voltou.
Future<int?> showSwapSheet(
  BuildContext context, {
  required String aName,
  required DateTime aStart,
  required List<SwapOption> options,
  required String? Function(int i) check,
  required String? Function(int i) commit,
}) {
  return _sheet<int>(
    context,
    (c) => _SwapBody(aName: aName, aStart: aStart, options: options, check: check, commit: commit),
  );
}

class _SwapBody extends StatefulWidget {
  final String aName;
  final DateTime aStart;
  final List<SwapOption> options;
  final String? Function(int) check;
  final String? Function(int) commit;
  const _SwapBody({required this.aName, required this.aStart, required this.options, required this.check, required this.commit});

  @override
  State<_SwapBody> createState() => _SwapBodyState();
}

class _SwapBodyState extends State<_SwapBody> {
  int? picked;
  String? failed;

  void _confirm() {
    final i = picked!;
    final err = widget.commit(i);
    if (err != null) {
      setState(() => failed = err);
      return;
    }
    Navigator.pop(context, i);
  }

  @override
  Widget build(BuildContext context) {
    final i = picked;
    final problem = i == null ? null : (failed ?? widget.check(i));
    final ready = i != null && problem == null;
    final b = i == null ? null : widget.options[i];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s4, Ds.screenPad, Ds.s12),
          child: _header(Icons.swap_horiz_rounded, tr('Trocar horário'), '${widget.aName} · ${whenText(widget.aStart)}'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s8),
          child: Text(tr('Trocar com quem?'), style: Ds.section()),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s8),
            children: [
              for (var k = 0; k < widget.options.length; k++) _option(k),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(Ds.screenPad, Ds.s8, Ds.screenPad, Ds.s16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (b == null)
              Text(tr('Escolha uma aula acima para ver como fica.'), style: Ds.support())
            else if (problem != null)
              _banner(AppColors.sharp, Icons.error_outline_rounded, [Text(problem, style: const TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600))])
            else
              _banner(AppColors.accent, Icons.swap_horiz_rounded, [
                _swapLine(widget.aName, widget.aStart, b.start),
                const SizedBox(height: Ds.s8),
                _swapLine(b.name, b.start, widget.aStart),
                const SizedBox(height: Ds.s8),
                Text(tr('Os dois são avisados.'), style: Ds.support()),
              ]),
            const SizedBox(height: Ds.s16),
            _buttons(context, ok: tr('Trocar'), enabled: ready, onOk: _confirm, icon: Icons.swap_horiz_rounded),
          ]),
        ),
      ]),
    );
  }

  Widget _swapLine(String name, DateTime from, DateTime to) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        Text('${whenText(from)}  →  ${whenText(to)}', style: TextStyle(fontSize: 14, color: AppColors.textDim)),
      ]);

  Widget _option(int k) {
    final o = widget.options[k];
    final sel = picked == k;
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s8),
      child: Semantics(
        button: true,
        selected: sel,
        label: '${o.name}, ${whenText(o.start)}',
        child: InkWell(
          borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
          onTap: () => setState(() {
            picked = k;
            failed = null;
          }),
          child: Container(
            constraints: const BoxConstraints(minHeight: Ds.primaryHeight),
            padding: const EdgeInsets.symmetric(horizontal: Ds.s16, vertical: Ds.s12),
            decoration: BoxDecoration(
              color: sel ? AppColors.accent.withValues(alpha: 0.12) : AppColors.surface2,
              borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
              border: Border.all(color: sel ? AppColors.accent : AppColors.outline, width: sel ? 1.6 : 1),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(whenText(o.start), style: Ds.support()),
                ]),
              ),
              Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked, color: sel ? AppColors.accent : AppColors.textDim),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Confirmar

/// Confirmação com título, o que vai acontecer e quem é avisado. Devolve true só se tocar no botão de confirmar.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String ok,
  IconData icon = Icons.help_outline_rounded,
  bool danger = false,
}) async {
  final r = await _sheet<bool>(
    context,
    (c) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s4, Ds.screenPad, Ds.s16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(icon, title, null, color: danger ? AppColors.sharp : null),
        const SizedBox(height: Ds.s16),
        Text(body, style: Ds.support().copyWith(fontSize: 15, color: AppColors.text)),
        const SizedBox(height: Ds.s24),
        _buttons(c, ok: ok, enabled: true, danger: danger, onOk: () => Navigator.pop(c, true), icon: danger ? Icons.event_busy : Icons.check_rounded),
      ]),
    ),
  );
  return r == true;
}

// -------------------------------------------------------- Escolha de uma opção

/// Uma opção grande e tocável, com ícone, título e explicação do que acontece (usada em "não veio" e em "cancelar").
class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _ChoiceTile({required this.icon, required this.title, required this.subtitle, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Ds.s8),
        child: Semantics(
          button: true,
          selected: selected,
          excludeSemantics: true,
          label: '$title. $subtitle',
          onTap: onTap,
          child: InkWell(
            borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(Ds.s12),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.12) : AppColors.surface2,
                borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
                border: Border.all(color: selected ? color : AppColors.outline, width: selected ? 1.6 : 1),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DsIconBadge(icon, size: 40, color: color),
                const SizedBox(width: Ds.s12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Ds.support()),
                  ]),
                ),
                const SizedBox(width: Ds.s8),
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked, color: selected ? color : AppColors.textDim),
              ]),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------- Não veio

/// O que fazer quando o aluno não veio à aula.
enum AbsenceChoice { noShow, notified, reschedule }

/// "Aluno não veio": três caminhos claros (faltou sem avisar, avisou que não vem, quer remarcar). Sem aula marcada para
/// agora ([hasLesson] falso) só há o que registrar. Devolve a escolha, ou null se voltou.
Future<AbsenceChoice?> showAbsenceSheet(
  BuildContext context, {
  required String who,
  String? lessonLabel,
  required bool hasLesson,
  required bool weekly,
}) {
  return _sheet<AbsenceChoice>(context, (c) => _AbsenceBody(who: who, lessonLabel: lessonLabel, hasLesson: hasLesson, weekly: weekly));
}

class _AbsenceBody extends StatefulWidget {
  final String who;
  final String? lessonLabel;
  final bool hasLesson;
  final bool weekly;
  const _AbsenceBody({required this.who, required this.lessonLabel, required this.hasLesson, required this.weekly});

  @override
  State<_AbsenceBody> createState() => _AbsenceBodyState();
}

class _AbsenceBodyState extends State<_AbsenceBody> {
  AbsenceChoice? picked;

  @override
  Widget build(BuildContext context) {
    final who = widget.who;
    final p = picked;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Ds.screenPad, Ds.s4, Ds.screenPad, Ds.s16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.person_off_outlined, tr('{0} não veio?', [who]), widget.lessonLabel, color: AppColors.sharp),
        const SizedBox(height: Ds.s20),
        _ChoiceTile(
          icon: Icons.person_off_outlined,
          title: tr('Faltou, sem avisar'),
          subtitle: widget.hasLesson ? tr('Fica registrado na ficha. A aula continua na agenda.') : tr('Fica registrado na ficha de {0}.', [who]),
          selected: p == AbsenceChoice.noShow,
          color: AppColors.sharp,
          onTap: () => setState(() => picked = AbsenceChoice.noShow),
        ),
        _ChoiceTile(
          icon: Icons.mark_chat_read_outlined,
          title: tr('Avisou que não vem'),
          subtitle: !widget.hasLesson
              ? tr('Fica registrado na ficha de {0}.', [who])
              : (widget.weekly ? tr('Fica registrado e só a aula de hoje é cancelada. {0} é avisado.', [who]) : tr('Fica registrado e a aula é cancelada. {0} é avisado.', [who])),
          selected: p == AbsenceChoice.notified,
          color: AppColors.flat,
          onTap: () => setState(() => picked = AbsenceChoice.notified),
        ),
        if (widget.hasLesson)
          _ChoiceTile(
            icon: Icons.event_repeat_rounded,
            title: tr('Quer remarcar'),
            subtitle: tr('Fica registrado e você escolhe o novo horário.'),
            selected: p == AbsenceChoice.reschedule,
            color: AppColors.accent,
            onTap: () => setState(() => picked = AbsenceChoice.reschedule),
          ),
        const SizedBox(height: Ds.s8),
        _buttons(
          context,
          ok: p == AbsenceChoice.reschedule ? tr('Registrar e remarcar') : tr('Registrar falta'),
          enabled: p != null,
          onOk: () => Navigator.pop(context, p),
          icon: p == AbsenceChoice.reschedule ? Icons.event_repeat_rounded : Icons.check_rounded,
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Cancelar

/// Cancelar uma aula semanal: só a desta data ou todas.
enum CancelChoice { one, all }

Future<CancelChoice?> showCancelSheet(BuildContext context, {required String who, required String dateLabel}) {
  return _sheet<CancelChoice>(context, (c) => _CancelBody(who: who, dateLabel: dateLabel));
}

class _CancelBody extends StatefulWidget {
  final String who;
  final String dateLabel;
  const _CancelBody({required this.who, required this.dateLabel});

  @override
  State<_CancelBody> createState() => _CancelBodyState();
}

class _CancelBodyState extends State<_CancelBody> {
  CancelChoice? picked;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s4, Ds.screenPad, Ds.s16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.event_busy_rounded, tr('Cancelar a aula'), '${widget.who} · ${widget.dateLabel}', color: AppColors.sharp),
        const SizedBox(height: Ds.s20),
        _ChoiceTile(
          icon: Icons.today_rounded,
          title: tr('Só esta aula'),
          subtitle: tr('As outras semanas continuam. {0} é avisado.', [widget.who]),
          selected: picked == CancelChoice.one,
          color: AppColors.sharp,
          onTap: () => setState(() => picked = CancelChoice.one),
        ),
        _ChoiceTile(
          icon: Icons.event_repeat_rounded,
          title: tr('Todas as aulas'),
          subtitle: tr('A aula semanal deixa de existir daqui para a frente. {0} é avisado.', [widget.who]),
          selected: picked == CancelChoice.all,
          color: AppColors.sharp,
          onTap: () => setState(() => picked = CancelChoice.all),
        ),
        const SizedBox(height: Ds.s8),
        _buttons(context, ok: tr('Cancelar aula'), enabled: picked != null, danger: true, onOk: () => Navigator.pop(context, picked), icon: Icons.event_busy),
      ]),
    );
  }
}
