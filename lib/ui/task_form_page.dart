import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'dictation_button.dart';
import 'design_system.dart';
import 'methods_page.dart';
import 'my_lessons_page.dart' show taskKindIcon;
import 'note_widgets.dart';
import 'safe_input.dart';
import 'student_identity.dart';
import 'theme.dart';
import 'widgets.dart';

/// O que o professor preencheu no formulário de tarefa.
class TaskDraft {
  final TaskKind kind;
  final String title; // escala: "Sol maior · 2 oitavas"; demais: assunto + detalhe
  final ScaleType scaleType;
  final int tonicPc;
  final int octaves;
  final double goal;
  final String subject;
  final String detail;
  final String note;

  /// Enviar ao aluno logo depois de passar (só vale fora de aula e com envio possível).
  final bool sendNow;
  const TaskDraft({
    required this.kind,
    required this.title,
    required this.scaleType,
    required this.tonicPc,
    required this.octaves,
    required this.goal,
    required this.subject,
    required this.detail,
    required this.note,
    required this.sendNow,
  });
}

/// Abre o formulário (tela cheia). Devolve o que foi preenchido, ou null se cancelou.
Future<TaskDraft?> openTaskForm(BuildContext context, AppState app, Student s, {Assignment? edit}) {
  return Navigator.of(context).push<TaskDraft>(
    MaterialPageRoute(builder: (_) => TaskFormPage(app: app, studentId: s.id, edit: edit), fullscreenDialog: true),
  );
}

/// Formulário de tarefa: para quem é (nome e código), o que passar, observação e como chega ao
/// aluno. Fica em tela cheia, com os botões fixos embaixo, em vez de uma janelinha que rola.
class TaskFormPage extends StatefulWidget {
  final AppState app;
  final String studentId;
  final Assignment? edit;
  const TaskFormPage({super.key, required this.app, required this.studentId, this.edit});

  @override
  State<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> {
  AppState get app => widget.app;
  Assignment? get edit => widget.edit;
  bool get isEdit => edit != null;

  late TaskKind kind = edit?.kind ?? TaskKind.scale;
  late ScaleType type = edit != null && edit!.isScale ? ScaleType.values[edit!.scaleTypeIndex] : app.scaleType;
  late int pc = edit != null && edit!.isScale ? edit!.tonicPc : app.scaleTonicMidi % 12;
  late int oct = edit?.octaves ?? 1;
  late double goal = edit?.goal ?? 0.8;
  late final subject = TextEditingController(text: edit?.subject ?? '');
  late final detail = TextEditingController(text: edit?.detail ?? '');
  late final note = TextEditingController(text: edit?.note ?? '');
  String? subjectErr;

  /// Só o professor liberado vê "Material do professor" entre os tipos.
  List<TaskKind> get _kinds => [for (final k in TaskKind.values) if (k != TaskKind.material || app.libraryOn || edit?.kind == TaskKind.material) k];

  @override
  void initState() {
    super.initState();
    if (app.libraryOn && app.libCached().isEmpty) app.libLoad().then((_) => mounted ? setState(() {}) : null);
  }
  bool sendNow = true;
  final _scroll = ScrollController();
  final _subjectKey = GlobalKey();

  @override
  void dispose() {
    subject.dispose();
    detail.dispose();
    note.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _subjectLabel => switch (kind) {
        TaskKind.method => tr('Método ou livro'),
        TaskKind.repertoire => tr('Peça ou obra'),
        _ => tr('O que estudar'),
      };

  String? get _detailLabel => switch (kind) {
        TaskKind.method => tr('Lição ou exercício (ex.: Lição 5)'),
        TaskKind.repertoire => tr('Trecho ou compassos (opcional)'),
        _ => null,
      };

  String _scaleTitle(TuningConfig names) =>
      tr('{0} · {1} oitava{2}', [type.display(noteName(pc + 60, names)), oct, oct > 1 ? 's' : '']);

  void _submit(TuningConfig names) {
    if (kind != TaskKind.scale && subject.text.trim().isEmpty) {
      setState(() => subjectErr = kind == TaskKind.material ? tr('Escolha o material') : tr('Escreva o que o aluno vai estudar'));
      final c = _subjectKey.currentContext;
      if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250), alignment: 0.1);
      return;
    }
    Navigator.pop(
      context,
      TaskDraft(
        kind: kind,
        title: kind == TaskKind.scale ? _scaleTitle(names) : Assignment.titleFor(subject.text, detail.text),
        scaleType: type,
        tonicPc: pc,
        octaves: oct,
        goal: goal,
        subject: subject.text,
        detail: detail.text,
        note: note.text,
        sendNow: sendNow,
      ),
    );
  }

  Widget _label(String t, {String? help}) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          if (help != null) Text(help, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = app.studentById(widget.studentId);
    if (s == null) return const Scaffold(body: SizedBox.shrink());
    final names = app.cfg.copyWith(transpose: 0);
    final rule = app.deliveryFor(s);
    final willSend = !isEdit && sendNow && rule.canSend;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? tr('Editar tarefa') : tr('Nova tarefa'))),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                // ---- Para quem ----
                AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: StudentIdentity(app: app, student: s),
                ),

                // ---- O que passar ----
                if (!isEdit) ...[
                  _label(tr('O que passar')),
                  ChipGrid(
                    columns: 2,
                    labels: [
                      for (final k in _kinds)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(taskKindIcon(k), size: 16),
                          const SizedBox(width: 6),
                          Text(k.label),
                        ]),
                    ],
                    selected: _kinds.indexOf(kind),
                    onSelected: (i) => setState(() {
                      kind = _kinds[i];
                      subjectErr = null;
                    }),
                  ),
                ],

                if (kind == TaskKind.scale) ..._scaleFields(names) else if (kind == TaskKind.material) ..._materialFields() else ..._textFields(),

                // ---- Observações ----
                _label(tr('Observações (opcional)'), help: tr('O que merece atenção ou estudar mais.')),
                TextField(
                  controller: note,
                  inputFormatters: const [SafeText.note()],
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: tr('Ex.: cuidar do arco na corda solta'),
                    alignLabelWithHint: true,
                    suffixIcon: DictationButton(app: app, controller: note),
                  ),
                ),

                // ---- Como chega ao aluno ----
                _label(tr('Como chega ao aluno')),
                _delivery(s, rule),
              ],
            ),
          ),

          // ---- Botões fixos ----
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.outline)),
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Cancelar')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => _submit(names),
                  icon: Icon(isEdit ? Icons.check : (willSend ? Icons.send : Icons.add_task), size: 20),
                  label: Text(isEdit ? tr('Salvar') : (willSend ? tr('Passar e enviar') : tr('Passar tarefa')),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _scaleFields(TuningConfig names) {
    if (isEdit) {
      return [
        _label(tr('Tarefa')),
        Text(edit!.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text(tr('Escala e meta não mudam depois de passadas. Para outra escala, passe uma nova tarefa.'),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
      ];
    }
    return [
      _label(tr('Escala ou arpejo')),
      PickerField<ScaleType>(
        label: tr('Escala ou arpejo'),
        value: type,
        options: [for (final t in ScaleType.values) OptionItem(t, t.label)],
        onChanged: (v) => setState(() => type = v),
      ),
      _label(tr('Nota inicial')),
      ChipGrid(
        columns: 6,
        labels: [
          for (var i = 0; i < 12; i++)
            NoteLabel.midi(i + 60, names, withOctave: false, size: 14, weight: FontWeight.w600, color: AppColors.text),
        ],
        selected: pc,
        onSelected: (i) => setState(() => pc = i),
      ),
      _label(tr('Oitavas')),
      ChipGrid(
        labels: [for (final o in [1, 2, 3, 4]) Text('$o')],
        selected: oct - 1,
        onSelected: (i) => setState(() => oct = i + 1),
      ),
      _label(tr('Meta de acerto'), help: tr('O aluno cumpre a tarefa ao atingir essa porcentagem.')),
      ChipGrid(
        labels: [for (final g in _goals) Text('${(g * 100).round()}%')],
        selected: _goals.contains(goal) ? _goals.indexOf(goal) : null,
        onSelected: (i) => setState(() => goal = _goals[i]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(Icons.piano, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('{0} · meta {1}%', [_scaleTitle(names), (goal * 100).round()]),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    ];
  }

  static const _goals = [0.6, 0.7, 0.8, 0.9];

  /// "Material do professor": o aluno abre direto no acervo (item, pasta ou o acervo todo).
  List<Widget> _materialFields() {
    final items = app.libCached();
    final picked = subject.text.trim().isEmpty ? '' : Assignment.titleFor(subject.text, detail.text);
    return [
      _label(tr('Qual material'), help: tr('O aluno abre no acervo, já filtrado.')),
      OutlinedButton.icon(
        key: _subjectKey,
        onPressed: () => _pickMaterial(items),
        icon: const Icon(Icons.folder_open_rounded, size: 20),
        label: Text(picked.isEmpty ? tr('Escolher no acervo') : picked, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      if (subjectErr != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(subjectErr!, style: TextStyle(color: AppColors.sharp, fontSize: 12.5))),
      if (items.isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Seu acervo está vazio. Dá para escolher "Acervo todo" ou cadastrar materiais em Meu espaço.'), style: Ds.support())),
    ];
  }

  Future<void> _pickMaterial(List<LibItem> items) async {
    final folders = libraryFolders(items);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
      builder: (c) {
        void choose(String sub, String det) {
          setState(() {
            subject.text = sub;
            detail.text = det;
            subjectErr = null;
          });
          Navigator.pop(c);
        }

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
          child: ListView(padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s24), shrinkWrap: true, children: [
            Text(tr('Escolher material'), style: Ds.title()),
            const DsGap(Ds.s12),
            ListTile(
              leading: const DsIconBadge(Icons.all_inbox_rounded, size: 36),
              title: Text(tr('Acervo todo')),
              subtitle: Text(tr('O aluno procura lá dentro')),
              onTap: () => choose(kMaterialAll, ''),
            ),
            for (final f in folders) ...[
              ListTile(
                leading: const DsIconBadge(Icons.folder_rounded, size: 36),
                title: Text(tr('Pasta: {0}', [f])),
                subtitle: Text(tr('{0} material(is)', [items.where((i) => i.folder == f).length])),
                onTap: () => choose(f, ''),
              ),
              for (final i in items.where((x) => x.folder == f))
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 56),
                  leading: Icon(i.isRepertoire ? Icons.library_music_outlined : Icons.menu_book_outlined, size: 20),
                  title: Text(i.title),
                  subtitle: i.author.isEmpty ? null : Text(i.author),
                  onTap: () => choose(i.title, i.folder),
                ),
            ],
          ]),
        );
      },
    );
  }

  List<Widget> _textFields() {
    final methods = app.methodNames();
    return [
      _label(_subjectLabel),
      TextField(
        key: _subjectKey,
        controller: subject,
        inputFormatters: const [SafeText.title()],
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          errorText: subjectErr,
          suffixIcon: DictationButton(app: app, controller: subject),
        ),
        onChanged: (_) => setState(() => subjectErr = null),
      ),
      if (kind == TaskKind.method) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 0, children: [
          for (final m in methods.take(8))
            ActionChip(
              label: Text(m),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                subject.text = m;
                subjectErr = null;
              }),
            ),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => MethodsPage(app: app)))
                .then((_) => setState(() {})),
            icon: const Icon(Icons.library_books_outlined, size: 18),
            label: Text(tr('Meus métodos e lições')),
          ),
        ),
      ],
      if (_detailLabel != null) ...[
        _label(_detailLabel!),
        TextField(
          controller: detail,
          inputFormatters: const [SafeText.line()],
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(suffixIcon: DictationButton(app: app, controller: detail)),
        ),
        // Lições já cadastradas para o método escolhido: um toque preenche.
        if (kind == TaskKind.method)
          ListenableBuilder(
            listenable: subject,
            builder: (context, _) {
              final lessons = findMethod(app.methodLibrary, subject.text)?.lessons ?? const <String>[];
              if (lessons.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, runSpacing: 0, children: [
                  for (final l in lessons.take(12))
                    ActionChip(
                      label: Text(l),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => detail.text = l,
                    ),
                ]),
              );
            },
          ),
      ],
    ];
  }

  /// A regra de entrega, explicada na hora: em aula (vai ao encerrar), enviar agora (ou na fila)
  /// ou só na ficha.
  Widget _delivery(Student s, TaskDelivery rule) {
    if (isEdit) {
      final sent = edit!.sent == true && rule.mode != DeliveryMode.localOnly;
      return _info(
        sent ? Icons.info_outline : Icons.edit_outlined,
        sent
            ? tr('Esta tarefa já foi enviada. O que você mudar fica só na sua ficha: o aluno continua com a versão que recebeu. Se precisar corrigir para ele, passe uma nova tarefa.')
            : tr('Você pode ajustar antes de enviar. Ao salvar, nada é enviado automaticamente.'),
        sent ? AppColors.flat : AppColors.textDim,
      );
    }
    switch (rule.mode) {
      case DeliveryMode.inLesson:
        return _info(Icons.school_outlined, rule.text, AppColors.accent);
      case DeliveryMode.localOnly:
        return _info(Icons.phone_android, rule.text, AppColors.flat);
      case DeliveryMode.now:
      case DeliveryMode.queued:
        return AppCard(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Enviar para {0} agora', [s.name]), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                sendNow
                    ? rule.text
                    : tr('Fica na ficha como "a enviar". Você envia depois pelo botão da ficha, ou ela vai junto com a próxima aula.'),
                style: const TextStyle(fontSize: 12.5),
              ),
              value: sendNow,
              onChanged: (v) => setState(() => sendNow = v),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                tr('Não precisa estar em aula para passar uma tarefa.'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
          ]),
        );
    }
  }

  Widget _info(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.3))),
        ]),
      );
}
