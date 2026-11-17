import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'methods_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Métodos e repertório": o modal que sobe para o professor montar a lista dele. Um por linha, quantos quiser:
/// digita o nome e dá Enter (o campo continua aberto para o próximo) ou cola uma lista inteira. Cada item pertence a um
/// instrumento (ou vale para todos) e abre para pôr as lições ou os movimentos. As sugestões da tarefa saem daqui.
Future<void> showMaterialsSheet(BuildContext context, AppState app, {bool piece = false, String? instrument}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => _MaterialsBody(app: app, piece: piece, instrument: instrument),
  );
}

class _MaterialsBody extends StatefulWidget {
  final AppState app;
  final bool piece;
  final String? instrument;
  const _MaterialsBody({required this.app, required this.piece, this.instrument});

  @override
  State<_MaterialsBody> createState() => _MaterialsBodyState();
}

class _MaterialsBodyState extends State<_MaterialsBody> {
  late bool _piece = widget.piece;

  /// Instrumento em foco: '' = todos (e novos itens ficam "gerais").
  late String _ins = widget.instrument ?? (widget.app.teachInstruments.length == 1 ? widget.app.teachInstruments.first : '');
  final _add = TextEditingController();
  final _focus = FocusNode();
  String? _note;

  AppState get app => widget.app;

  @override
  void dispose() {
    _add.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Entra tudo o que foi digitado ou colado (uma linha = um item) e deixa o campo pronto para o próximo.
  void _submit(String text) {
    final n = app.addMaterials(piece: _piece, lines: text, instrument: _ins);
    _add.clear();
    setState(() => _note = n == 0 ? (text.trim().isEmpty ? null : tr('Já estava na lista.')) : (n == 1 ? tr('1 adicionado.') : tr('{0} adicionados.', [n])));
    _focus.requestFocus();
  }

  Future<void> _edit(MethodEntry m) async {
    final name = TextEditingController(text: m.name);
    final lessons = TextEditingController(text: m.lessons.join('\n'));
    var ins = m.instrument;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(_piece ? tr('Editar peça') : tr('Editar método')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: name, maxLength: 80, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('Nome'), counterText: '')),
              const SizedBox(height: Ds.s12),
              TextField(
                controller: lessons,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: _piece ? tr('Movimentos ou trechos (um por linha)') : tr('Lições ou estudos (um por linha)')),
              ),
              const SizedBox(height: Ds.s12),
              Text(tr('Instrumento'), style: Ds.section()),
              const SizedBox(height: Ds.s8),
              Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
                ChoiceChip(label: Text(tr('Todos')), selected: ins.isEmpty, onSelected: (_) => setS(() => ins = '')),
                for (final i in [for (final id in app.teachInstruments) ?teachingById(id)])
                  ChoiceChip(label: Text(i.label), selected: ins == i.id, onSelected: (v) => setS(() => ins = v ? i.id : '')),
              ]),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                app.removeMaterial(piece: _piece, m: m);
                Navigator.pop(c, false);
              },
              child: Text(tr('Excluir'), style: TextStyle(color: AppColors.sharp)),
            ),
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Salvar'))),
          ],
        ),
      ),
    );
    if (ok == true) app.editMaterial(piece: _piece, m: m, name: name.text, lessonsText: lessons.text, instrument: ins);
    name.dispose();
    lessons.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final all = app.materialsOf(piece: _piece);
            final shown = [for (final m in all) if (_ins.isEmpty || m.instrument.isEmpty || m.instrument == _ins) m];
            final mine = [for (final id in app.teachInstruments) ?teachingById(id)];
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s8),
                child: Row(children: [
                  Expanded(child: Text(tr('Métodos e repertório'), style: Ds.title())),
                  IconButton(tooltip: tr('Fechar'), icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Ds.screenPad),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, icon: const Icon(Icons.menu_book_outlined, size: 18), label: Text(tr('Métodos'))),
                    ButtonSegment(value: true, icon: const Icon(Icons.library_music_outlined, size: 18), label: Text(tr('Repertório'))),
                  ],
                  selected: {_piece},
                  onSelectionChanged: (v) => setState(() {
                    _piece = v.first;
                    _note = null;
                  }),
                ),
              ),
              if (mine.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s12, Ds.screenPad, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      ChoiceChip(label: Text(tr('Todos')), selected: _ins.isEmpty, onSelected: (_) => setState(() => _ins = '')),
                      for (final i in mine) ...[
                        const SizedBox(width: Ds.s8),
                        ChoiceChip(label: Text(i.label), selected: _ins == i.id, onSelected: (v) => setState(() => _ins = v ? i.id : '')),
                      ],
                    ]),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s12, Ds.screenPad, 0),
                child: TextField(
                  controller: _add,
                  focusNode: _focus,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _piece ? tr('Nome da peça e Enter') : tr('Nome do método e Enter'),
                    prefixIcon: const Icon(Icons.add),
                    suffixIcon: IconButton(tooltip: tr('Adicionar'), icon: const Icon(Icons.keyboard_return), onPressed: () => _submit(_add.text)),
                  ),
                  // Enter (ou colar uma lista com várias linhas) adiciona tudo e o campo fica pronto para o próximo.
                  onChanged: (v) {
                    if (v.contains('\n')) _submit(v);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s4, Ds.screenPad, Ds.s4),
                child: Text(_note ?? tr('Um por linha, quantos quiser. Cole uma lista para adicionar vários de uma vez.'), style: Ds.support()),
              ),
              Flexible(
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(Ds.s24),
                        child: Text(_piece ? tr('Nenhuma peça sua ainda. As sugestões do instrumento continuam aparecendo nas tarefas.') : tr('Nenhum método seu ainda. As sugestões do instrumento continuam aparecendo nas tarefas.'),
                            textAlign: TextAlign.center, style: Ds.support()),
                      )
                    : ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s8), children: [
                        for (final m in shown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Ds.s8),
                            child: AppCard(
                              padding: EdgeInsets.zero,
                              child: ListTile(
                                title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  [
                                    if (m.instrument.isNotEmpty && _ins.isEmpty) teachingById(m.instrument)?.label ?? '',
                                    m.lessons.isEmpty ? tr('Sem lições') : (m.lessons.length == 1 ? tr('1 item') : tr('{0} itens', [m.lessons.length])),
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: Ds.support(),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _edit(m),
                              ),
                            ),
                          ),
                      ]),
              ),
              if (!_piece)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Ds.s8, 0, Ds.s8, Ds.s8),
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MethodsPage(app: app))),
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: Text(tr('Importar ou copiar a lista')),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
