import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'agenda_page.dart';
import 'design_system.dart';
import 'gamify_ui.dart' show GamifyCard, StudyRankCard;
import 'my_lessons_page.dart' show openMyLessons;
import 'person_avatar.dart';
import 'teacher_page.dart';
import 'theme.dart';
import 'validation_ui.dart' show ValidationQueuePage;
import 'widgets.dart' show AppCard;

/// Barra lateral do computador: as cinco telas em atalhos, no lugar da barra de baixo.
/// Mostra só os ícones numa janela média e os nomes numa janela larga.
class DesktopRail extends StatelessWidget {
  final List<IconData> icons;
  final List<String> titles;
  final int selected;

  /// A ferramenta do outro painel: aparece com fundo, mas sem a borda do painel em foco.
  final int? also;
  final ValueChanged<int> onSelected;
  final bool labels;
  final bool alertOnLast;

  /// Duas ferramentas abertas ao mesmo tempo (ou uma só) e o que fazer ao trocar.
  final bool two;
  final ValueChanged<bool> onTwo;

  /// Em duas telas: de qual tela (1 ou 2) é cada ferramenta aberta.
  final Map<int, String> tags;
  const DesktopRail({
    super.key,
    required this.icons,
    required this.titles,
    required this.selected,
    this.also,
    required this.onSelected,
    required this.labels,
    required this.two,
    required this.onTwo,
    this.tags = const {},
    this.alertOnLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: labels ? 208 : 72,
      decoration: BoxDecoration(
        color: Color.lerp(AppColors.bg, Colors.black, AppColors.dark ? 0.25 : 0.03),
        border: Border(right: BorderSide(color: AppColors.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScreensToggle(two: two, onChanged: onTwo, labels: labels),
          const SizedBox(height: 10),
          Divider(height: 1, color: AppColors.outline),
          const SizedBox(height: 10),
          for (var i = 0; i < icons.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _RailItem(
                icon: icons[i],
                label: titles[i],
                showLabel: labels,
                on: i == selected,
                shown: i == also,
                tag: tags[i],
                alert: alertOnLast && i == icons.length - 1,
                onTap: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Telas": escolhe entre uma ferramenta ou duas lado a lado. Sempre à vista no alto da barra lateral.
class _ScreensToggle extends StatelessWidget {
  final bool two, labels;
  final ValueChanged<bool> onChanged;
  const _ScreensToggle({required this.two, required this.onChanged, required this.labels});

  Widget _seg(BuildContext context, IconData icon, String text, bool value) {
    final on = two == value;
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        label: text,
        child: Tooltip(
          message: text,
          child: InkWell(
            borderRadius: BorderRadius.circular(Ds.radiusControl),
            onTap: () => onChanged(value),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: on ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(Ds.radiusControl),
                border: Border.all(color: on ? AppColors.text : Colors.transparent),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 20, color: on ? AppColors.text : AppColors.textDim),
                if (labels) ...[
                  const SizedBox(width: 6),
                  Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? AppColors.text : AppColors.textDim))),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seg1 = _seg(context, Icons.crop_portrait_rounded, tr('Uma tela'), false);
    final seg2 = _seg(context, Icons.vertical_split_rounded, tr('Duas telas'), true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (labels) Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(tr('Telas'), style: Ds.section())),
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Ds.radiusControl + 3), border: Border.all(color: AppColors.outline)),
        child: labels ? Row(children: [seg1, seg2]) : Column(children: [SizedBox(height: 40, child: Row(children: [seg1])), const SizedBox(height: 3), SizedBox(height: 40, child: Row(children: [seg2]))]),
      ),
    ]);
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showLabel, on, shown, alert;
  final String? tag;
  final VoidCallback onTap;
  const _RailItem({required this.icon, required this.label, required this.showLabel, required this.on, this.shown = false, this.tag, required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: Tooltip(
        message: showLabel ? '' : label,
        child: Material(
          color: (on || shown) ? AppColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(Ds.radiusControl),
          child: InkWell(
            borderRadius: BorderRadius.circular(Ds.radiusControl),
            onTap: onTap,
            child: Container(
              height: 48,
              padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Ds.radiusControl),
                border: Border.all(color: on ? AppColors.text : Colors.transparent),
              ),
              child: Row(
                mainAxisAlignment: showLabel ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Badge(
                    smallSize: 8,
                    label: tag == null ? null : Text(tag!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.onAccent)),
                    isLabelVisible: alert || tag != null,
                    backgroundColor: tag != null ? AppColors.accent : AppColors.sharp,
                    child: Icon(icon, size: 22, color: (on || shown) ? AppColors.text : AppColors.textDim),
                  ),
                  if (showLabel) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: (on || shown) ? AppColors.text : AppColors.textDim),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Painel à direita no computador: o que o professor precisa ver o tempo todo (próxima aula, hoje,
/// quem estudou, o que espera validação) ou, para o aluno, a próxima aula e a meta da semana.
class DesktopDock extends StatefulWidget {
  final AppState app;
  final double width;

  /// Janela alta: mostra também a lista "Hoje".
  final bool roomy;
  const DesktopDock({super.key, required this.app, required this.width, this.roomy = false});

  @override
  State<DesktopDock> createState() => _DesktopDockState();
}

class _DesktopDockState extends State<DesktopDock> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    // A contagem "em 2 dias" e a lista de hoje acompanham o relógio, sem pedir nada ao servidor.
    _t = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  AppState get app => widget.app;

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final teacher = app.hubView == HubView.teacher;
          final children = teacher ? _teacher() : _student();
          // Título do painel: diz de uma vez o que é esta coluna (separada das ferramentas).
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, Ds.s12),
              child: Row(children: [
                Icon(teacher ? Icons.school_outlined : Icons.person_outline_rounded, size: 20, color: AppColors.text),
                const SizedBox(width: 10),
                Expanded(child: Text(teacher ? tr('Painel do professor') : tr('Meu painel'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              ]),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: children.length,
                separatorBuilder: (_, _) => const SizedBox(height: Ds.s12),
                itemBuilder: (_, i) => children[i],
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _head(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: Ds.s8),
        child: Row(children: [
          Expanded(child: Text(t, style: Ds.section())),
          ?trailing,
        ]),
      );

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _who(SlotOccurrence o) {
    final st = o.slot.studentCode.isEmpty ? null : app.studentByCode(o.slot.studentCode);
    return st == null ? o.slot.teacherName : app.labelOf(st);
  }

  Widget _nextCard(HubView view) {
    final nc = app.nextClassFor(view);
    final now = DateTime.now();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head(view == HubView.teacher ? tr('Próxima aula') : tr('Sua próxima aula')),
        if (nc == null)
          Text(tr('Nenhuma aula marcada.'), style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport))
        else ...[
          Text(fmtSlotWhen(nc.start, now), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
          const SizedBox(height: 2),
          Text(tr('Com {0}', [_who(nc)]), style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport)),
        ],
        const SizedBox(height: Ds.s12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _push(view == HubView.teacher ? AgendaPage(app: app) : MyAgendaPage(app: app)),
            child: Text(tr('Agenda completa')),
          ),
        ),
      ]),
    );
  }

  Widget _todayCard() {
    final day = classesToday(app.visibleAgenda, DateTime.now());
    final left = day.remaining;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head(tr('Hoje'), trailing: Text(day.count == 0 ? '' : '${day.count}', style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w700))),
        if (left.isEmpty)
          Text(day.count == 0 ? tr('Sem aulas hoje.') : tr('As aulas de hoje terminaram.'), style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport))
        else
          for (final o in left.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: Ds.s8),
              child: Row(children: [
                SizedBox(width: 48, child: Text(_hm(o.start), style: const TextStyle(fontWeight: FontWeight.w800))),
                PersonAvatar(name: _who(o), radius: 13),
                const SizedBox(width: Ds.s8),
                Expanded(child: Text(_who(o), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ),
      ]),
    );
  }

  Widget _validateCard() {
    final n = app.awaitingTotal;
    if (n == 0) return const SizedBox.shrink();
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.fact_check_rounded, color: AppColors.attention),
        title: Text(n == 1 ? tr('1 tarefa para validar') : tr('{0} tarefas para validar', [n]), style: const TextStyle(fontWeight: FontWeight.w800)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _push(ValidationQueuePage(app: app)),
      ),
    );
  }

  Widget _shortcuts() => AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          DsNavRow(Icons.groups_rounded, tr('Alunos'), app.students.length == 1 ? tr('1 aluno') : tr('{0} alunos', [app.students.length]), () => _push(TeacherPage(app: app))),
        ]),
      );

  List<Widget> _teacher() => [
        _nextCard(HubView.teacher),
        if (widget.roomy) _todayCard(),
        StudyRankCard(app: app),
        _validateCard(),
        _shortcuts(),
      ];

  List<Widget> _student() => [
        _nextCard(HubView.student),
        GamifyCard(app: app),
        if (app.myLessons.isNotEmpty)
          AppCard(
            padding: EdgeInsets.zero,
            child: DsNavRow(Icons.menu_book_rounded, tr('Diário de aula'), tr('Aulas e tarefas do seu professor'), () => openMyLessons(context, app)),
          ),
      ];
}
