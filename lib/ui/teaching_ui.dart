import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';

/// "Instrumentos que ensino": o professor marca um ou mais; as sugestões de método e de repertório vêm prontas.
/// Cada toque vale na hora (sem botão de confirmar), como nos outros ajustes.
Future<void> showTeachingInstrumentsSheet(BuildContext context, AppState app) {
  return showDsSheet(
    context,
    title: tr('Instrumentos que ensino'),
    listenable: app,
    children: (c) => [
      Text(tr('Marque o que você ensina. Ao passar uma tarefa, os métodos e o repertório do instrumento aparecem prontos.'), style: Ds.support()),
      const SizedBox(height: Ds.s16),
      Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
        for (final i in kTeachingInstruments)
          FilterChip(
            label: Text(i.label),
            selected: app.teachInstruments.contains(i.id),
            onSelected: (v) => app.setTeachInstrument(i.id, v),
          ),
      ]),
      const SizedBox(height: Ds.s16),
    ],
  );
}

/// Lista completa de sugestões, com busca: devolve o item escolhido ou null.
Future<String?> pickSuggestion(BuildContext context, {required String title, required List<String> items}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => _SuggestionList(title: title, items: items),
  );
}

class _SuggestionList extends StatefulWidget {
  final String title;
  final List<String> items;
  const _SuggestionList({required this.title, required this.items});

  @override
  State<_SuggestionList> createState() => _SuggestionListState();
}

class _SuggestionListState extends State<_SuggestionList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = [for (final s in widget.items) if (q.isEmpty || s.toLowerCase().contains(q)) s];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s8),
            child: Text(widget.title, style: Ds.title()),
          ),
          if (widget.items.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s8),
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Buscar')),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          Flexible(
            child: shown.isEmpty
                ? Padding(padding: const EdgeInsets.all(Ds.s24), child: Text(tr('Nada encontrado.'), style: Ds.support()))
                : ListView(shrinkWrap: true, children: [
                    for (final s in shown)
                      ListTile(minTileHeight: Ds.tap, title: Text(s), onTap: () => Navigator.pop(context, s)),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// Faixa do instrumento no formulário da tarefa: escolher o instrumento do aluno (se o professor ensina mais de um)
/// ou convidar a escolher o que ele ensina (se ainda não escolheu).
class TaskInstrumentRow extends StatelessWidget {
  final AppState app;
  final Student student;

  /// Chamado quando a escolha muda (o formulário refaz as sugestões).
  final VoidCallback? onChanged;
  const TaskInstrumentRow({super.key, required this.app, required this.student, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final teaches = app.teachInstruments;
    if (teaches.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.piano_outlined, size: 18),
          label: Text(tr('Escolher meus instrumentos')),
          onPressed: () => showTeachingInstrumentsSheet(context, app).then((_) => onChanged?.call()),
        ),
      );
    }
    if (teaches.length == 1) return const SizedBox.shrink();
    final current = app.instrumentOf(student);
    return Wrap(spacing: Ds.s8, runSpacing: Ds.s4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(tr('Instrumento do aluno'), style: TextStyle(fontSize: Ds.fontLabel, color: AppColors.textDim, fontWeight: FontWeight.w700)),
      for (final id in teaches)
        ChoiceChip(
          label: Text(teachingById(id)?.label ?? id),
          selected: current == id,
          onSelected: (_) {
            app.setStudentInstrument(student, id);
            onChanged?.call();
          },
        ),
    ]);
  }
}
