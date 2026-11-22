import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart' show OptionItem, showMultiOptionSheet;

/// "Instrumentos que ensino": o professor marca um ou mais e confirma; as sugestões de método e de repertório vêm prontas.
/// Quem ensina um instrumento que não está na lista cria o seu ("Outro instrumento") e põe os métodos e as peças que usa.
Future<void> showTeachingInstrumentsSheet(BuildContext context, AppState app) async {
  var pending = {...app.teachInstruments};
  while (true) {
    if (!context.mounted) return;
    // Os botões de baixo fecham a folha, abrem o editor do instrumento próprio e a folha volta com as marcas de antes.
    var openEditor = false;
    TeachingInstrument? editing;
    await showMultiOptionSheet<String>(
      context,
      title: tr('Instrumentos que ensino'),
      options: [for (final i in allTeachingInstruments()) OptionItem<String>(i.id, i.label)],
      selected: pending,
      onChange: (s) => pending = s,
      onConfirm: (s) {
        pending = s;
        app.setTeachInstruments(s);
      },
      footer: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        OutlinedButton.icon(
          onPressed: () {
            openEditor = true;
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(tr('Outro instrumento')),
        ),
        for (final i in customInstruments)
          TextButton.icon(
            onPressed: () {
              openEditor = true;
              editing = i;
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(tr('Editar {0}', [i.label])),
          ),
      ]),
    );
    if (!openEditor || !context.mounted) return;
    await showCustomInstrumentEditor(context, app, existing: editing);
    pending = {...cleanTeachingIds(pending)};
  }
}

/// Cria ou edita um instrumento que não está no catálogo: nome, métodos e livros, repertório (um por linha; tudo opcional,
/// o professor vai completando depois). Devolve o instrumento salvo ou null.
Future<TeachingInstrument?> showCustomInstrumentEditor(BuildContext context, AppState app, {TeachingInstrument? existing}) async {
  final name = TextEditingController(text: existing?.label ?? '');
  final methods = TextEditingController(text: (existing?.methods ?? const <String>[]).join('\n'));
  final pieces = TextEditingController(text: (existing?.repertoire ?? const <String>[]).join('\n'));
  String? error;
  List<String> lines(String s) => [for (final l in s.split('\n')) if (l.trim().isNotEmpty) l.trim()];
  final r = await showDialog<TeachingInstrument>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(existing == null ? tr('Outro instrumento') : tr('Editar instrumento')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, autofocus: existing == null, maxLength: 40, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('Nome do instrumento'), errorText: error, counterText: '')),
            const SizedBox(height: Ds.s12),
            TextField(controller: methods, minLines: 3, maxLines: 6, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('Métodos e livros (um por linha)'))),
            const SizedBox(height: Ds.s12),
            TextField(controller: pieces, minLines: 3, maxLines: 6, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('Repertório (um por linha)'))),
            const SizedBox(height: Ds.s8),
            Text(tr('Pode deixar vazio e completar depois: o que você passar nas tarefas vira sugestão.'), style: Ds.support()),
          ]),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                if (!await _confirmDelete(c, existing.label, tr('Os métodos e peças dele saem, e os alunos ficam sem esse instrumento, em todos os seus aparelhos.'))) return;
                app.removeCustomInstrument(existing.id);
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(tr('Excluir'), style: TextStyle(color: AppColors.sharp)),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancelar'))),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) {
                setS(() => error = tr('Dê um nome ao instrumento.'));
                return;
              }
              if (existing == null) {
                final i = app.addCustomInstrument(name.text, methods: lines(methods.text), repertoire: lines(pieces.text));
                if (i == null) {
                  setS(() => error = tr('Não foi possível criar mais instrumentos.'));
                  return;
                }
                Navigator.pop(c, i);
              } else {
                app.updateCustomInstrument(existing.id, name: name.text, methods: lines(methods.text), repertoire: lines(pieces.text));
                Navigator.pop(c, teachingById(existing.id));
              }
            },
            child: Text(tr('Salvar')),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  methods.dispose();
  pieces.dispose();
  return r;
}

/// Turmas do professor: um nome ("Violino iniciantes", "Piano infantil") com o instrumento dela. Criar, editar e apagar.
Future<void> showTurmasSheet(BuildContext context, AppState app) {
  return showDsSheet(
    context,
    title: tr('Turmas'),
    listenable: app,
    children: (c) => [
      Text(tr('Mais de um instrumento ou tipos de turma diferentes? Separe em turmas e filtre a lista de alunos.'), style: Ds.support()),
      const SizedBox(height: Ds.s12),
      if (app.turmas.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: Ds.s8), child: Text(tr('Nenhuma turma ainda.'), style: Ds.support())),
      for (final t in app.turmas)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([teachingById(t.instrument)?.label ?? tr('Sem instrumento'), tr('{0} aluno(s)', [app.students.where((s) => s.turma == t.id).length])].join(' · '), style: Ds.support()),
          trailing: IconButton(tooltip: tr('Editar'), icon: const Icon(Icons.edit_outlined), onPressed: () => showTurmaEditor(context, app, existing: t)),
        ),
      const SizedBox(height: Ds.s8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
        onPressed: () => showTurmaEditor(context, app),
        icon: const Icon(Icons.add),
        label: Text(tr('Nova turma')),
      ),
      const SizedBox(height: Ds.s16),
    ],
  );
}

Future<void> showTurmaEditor(BuildContext context, AppState app, {Turma? existing}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  var ins = existing?.instrument ?? (app.teachInstruments.length == 1 ? app.teachInstruments.first : '');
  String? error;
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(existing == null ? tr('Nova turma') : tr('Editar turma')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, autofocus: existing == null, maxLength: 40, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('Nome da turma'), hintText: tr('Ex.: Violino iniciantes'), errorText: error, counterText: '')),
            const SizedBox(height: Ds.s12),
            Text(tr('Instrumento'), style: Ds.section()),
            const SizedBox(height: Ds.s8),
            Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
              for (final i in [for (final id in app.teachInstruments) ?teachingById(id)])
                ChoiceChip(label: Text(i.label), selected: ins == i.id, onSelected: (v) => setS(() => ins = v ? i.id : '')),
            ]),
          ]),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                if (!await _confirmDelete(c, existing.name, tr('Os alunos continuam na sua lista, só saem da turma.'))) return;
                app.removeTurma(existing.id);
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(tr('Excluir'), style: TextStyle(color: AppColors.sharp)),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancelar'))),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) {
                setS(() => error = tr('Dê um nome à turma.'));
                return;
              }
              if (existing == null) {
                app.addTurma(name.text, instrument: ins);
              } else {
                app.updateTurma(existing.id, name: name.text, instrument: ins);
              }
              Navigator.pop(c);
            },
            child: Text(tr('Salvar')),
          ),
        ],
      ),
    ),
  );
  name.dispose();
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

/// Marca o instrumento e a turma do aluno (as "tags" que aparecem na lista; o instrumento escolhe as sugestões da tarefa).
/// Mostra primeiro os instrumentos que o professor ensina. As escolhas só valem ao tocar em Confirmar.
Future<void> showStudentInstrumentSheet(BuildContext context, AppState app, Student s) {
  String? instrument = s.instrument;
  String? turma = s.turma;
  return showDsFormSheet<bool>(
    context,
    title: tr('Instrumento e turma'),
    primaryLabel: tr('Confirmar'),
    onSubmit: (c, setS) {
      if (instrument != s.instrument) app.setStudentInstrument(s, instrument);
      if (turma != s.turma) app.setStudentTurma(s, turma);
      return true;
    },
    body: (c, setS) {
      final mine = [for (final id in app.teachInstruments) ?teachingById(id)];
      final all = mine.isEmpty ? allTeachingInstruments() : [...mine, for (final i in allTeachingInstruments()) if (!app.teachInstruments.contains(i.id)) i];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('O que {0} estuda com você. As sugestões da tarefa seguem este instrumento.', [s.name]), style: Ds.support()),
        const SizedBox(height: Ds.s16),
        Text(tr('Instrumento'), style: Ds.section()),
        const SizedBox(height: Ds.s8),
        Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
          for (final i in all) ChoiceChip(label: Text(i.label), selected: instrument == i.id, onSelected: (v) => setS(() => instrument = v ? i.id : null)),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: Text(tr('Outro instrumento')), onPressed: () async {
            final i = await showCustomInstrumentEditor(context, app);
            if (i != null) setS(() => instrument = i.id);
          }),
        ]),
        const SizedBox(height: Ds.s20),
        Text(tr('Turma'), style: Ds.section()),
        const SizedBox(height: Ds.s8),
        Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
          for (final t in app.turmas) ChoiceChip(label: Text(t.name), selected: turma == t.id, onSelected: (v) => setS(() => turma = v ? t.id : null)),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: Text(tr('Nova turma')), onPressed: () => showTurmaEditor(context, app)),
        ]),
      ]);
    },
  );
}

/// Pergunta antes de apagar algo que some de todos os aparelhos da conta.
Future<bool> _confirmDelete(BuildContext context, String name, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Excluir "{0}"?', [name])),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Excluir'))),
      ],
    ),
  );
  return ok == true;
}
