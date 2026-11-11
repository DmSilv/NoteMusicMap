import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart';

/// Abre o acervo. Sem [teacher]: o próprio professor (edita). Com [teacher]: o aluno (só abre e denuncia).
/// [focusTitle] e [folder] vêm de uma tarefa "Material do professor": filtram e destacam o item.
Future<void> openLibrary(BuildContext context, AppState app, {String? teacher, String? teacherName, String? focusTitle, String? folder}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => LibraryPage(app: app, teacher: teacher, teacherName: teacherName, focusTitle: focusTitle, folder: folder),
  ));
}

class LibraryPage extends StatefulWidget {
  final AppState app;
  final String? teacher;
  final String? teacherName;
  final String? focusTitle;
  final String? folder;
  const LibraryPage({super.key, required this.app, this.teacher, this.teacherName, this.focusTitle, this.folder});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  AppState get app => widget.app;
  bool get mine => widget.teacher == null;
  String _kind = 'a';
  String? _folder;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _folder = (widget.folder ?? '').isEmpty ? null : widget.folder;
    // Tarefa de material: abre já no tipo do item procurado.
    final hit = MaterialRef(title: widget.focusTitle ?? '', folder: widget.folder ?? '').resolve(app.libCached(widget.teacher));
    if (hit.item != null) _kind = hit.item!.kind;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final items = await app.libLoad(teacher: widget.teacher);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = items == null;
    });
    if (items != null && widget.focusTitle != null) {
      final m = MaterialRef(title: widget.focusTitle!, folder: widget.folder ?? '').resolve(items);
      setState(() {
        if (m.item != null) _kind = m.item!.kind;
        _folder = m.folder.isEmpty ? _folder : m.folder;
      });
    }
  }

  Future<void> _open(LibItem i) async {
    final ok = await launchUrl(Uri.parse(i.url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) app.say('Não consegui abrir o link.');
  }

  Future<void> _edit(LibItem? item) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
      builder: (c) => _ItemForm(app: app, item: item, kind: _kind, folder: _folder),
    );
    if (saved == true) app.say('Material salvo.');
  }

  Future<void> _delete(LibItem i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Apagar este material?'),
        content: Text('"${i.title}" sai do seu acervo e os alunos deixam de ver. O arquivo no Drive não é apagado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok == true) {
      final err = await app.libRemove(i.id);
      if (err != null) app.say(err);
    }
  }

  Future<void> _report(LibItem i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Denunciar este material?'),
        content: const Text('Use se o conteúdo for indevido ou violar direitos autorais. O administrador avalia e pode esconder o item.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Denunciar')),
        ],
      ),
    );
    if (ok == true) {
      final sent = await app.libReport(widget.teacher!, i.id);
      app.say(sent ? 'Denúncia enviada. Obrigado.' : 'Não foi possível enviar agora.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(mine ? 'Acervo e repertório' : 'Material${(widget.teacherName ?? '').isEmpty ? '' : ' de ${widget.teacherName}'}'),
        actions: [
          HelpButton(
            title: 'Acervo e repertório',
            sections: mine
                ? const [
                    ('O que é', 'Uma lista dos seus materiais (métodos e peças), com o link de onde ficam: Google Drive, Dropbox, OneDrive, IMSLP ou YouTube. O Notemusic não guarda os arquivos.'),
                    ('Quem vê', 'Só os seus alunos vinculados, todos ou os que você escolher.'),
                    ('Direitos autorais', 'Compartilhe só o que é de domínio público, é seu ou tem autorização. A responsabilidade pelo conteúdo é de quem publica.'),
                  ]
                : const [
                    ('O que é', 'Os materiais que o seu professor indicou. Ao tocar em Abrir, você sai do Notemusic para o link dele.'),
                    ('Algo errado?', 'Use "Denunciar" no menu do item.'),
                  ],
          ),
          const SizedBox(width: Ds.s8),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final all = app.libCached(widget.teacher);
            final ofKind = [for (final i in all) if (i.kind == _kind) i];
            final folders = libraryFolders(ofKind);
            final shown = [for (final i in ofKind) if (_folder == null || i.folder == _folder) i];
            final nA = all.where((i) => i.kind == 'a').length, nR = all.length - nA;
            return ListView(
              padding: Ds.screen,
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'a', icon: const Icon(Icons.menu_book_rounded, size: 18), label: Text('Acervo · $nA')),
                    ButtonSegment(value: 'r', icon: const Icon(Icons.library_music_rounded, size: 18), label: Text('Repertório · $nR')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() {
                    _kind = s.first;
                    _folder = null;
                  }),
                ),
                if (mine) ...[
                  const DsGap(Ds.gap),
                  DsPrimaryButton(onPressed: () => _edit(null), icon: Icons.add_link_rounded, label: 'Adicionar material'),
                ],
                if (folders.length > 1) ...[
                  const DsGap(Ds.gap),
                  Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
                    ChoiceChip(label: const Text('Todas'), selected: _folder == null, onSelected: (_) => setState(() => _folder = null)),
                    for (final f in folders) ChoiceChip(label: Text(f), selected: _folder == f, onSelected: (_) => setState(() => _folder = f)),
                  ]),
                ],
                const DsGap(Ds.gap),
                if (_loading && all.isEmpty)
                  const Padding(padding: EdgeInsets.all(Ds.sectionGap), child: Center(child: CircularProgressIndicator()))
                else if (_failed && all.isEmpty)
                  _note(Icons.cloud_off_outlined, 'Não consegui carregar.', action: TextButton(onPressed: _load, child: const Text('Tentar de novo')))
                else if (shown.isEmpty)
                  _note(Icons.folder_open_rounded, mine ? 'Nada aqui ainda. Toque em "Adicionar material".' : 'Seu professor ainda não indicou nada aqui.')
                else
                  for (final f in libraryFolders(shown)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s8, 0, Ds.s8),
                      child: Text(f.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: AppColors.textDim)),
                    ),
                    for (final i in shown.where((x) => x.folder == f)) _tile(i),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _note(IconData icon, String text, {Widget? action}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Ds.sectionGap),
        child: Column(children: [
          Icon(icon, size: 32, color: AppColors.textDim),
          const DsGap(Ds.s8),
          Text(text, textAlign: TextAlign.center, style: Ds.support()),
          ?action,
        ]),
      );

  Widget _tile(LibItem i) {
    final focus = (widget.focusTitle ?? '').trim().toLowerCase() == i.title.trim().toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s8),
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Ds.radiusControl),
        child: InkWell(
          borderRadius: BorderRadius.circular(Ds.radiusControl),
          onTap: () => _open(i),
          child: Container(
            constraints: const BoxConstraints(minHeight: Ds.tap + 8),
            padding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s8, Ds.s4, Ds.s8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Ds.radiusControl),
              border: Border.all(color: focus ? AppColors.accent : Colors.transparent, width: 1.5),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.title, style: const TextStyle(fontSize: Ds.fontBody, fontWeight: FontWeight.w700)),
                  if (i.author.isNotEmpty) Text(i.author, style: Ds.support()),
                  if (i.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Ds.s4), child: Text(i.note, style: Ds.support())),
                  if (mine && (i.to != null || i.hidden))
                    Padding(
                      padding: const EdgeInsets.only(top: Ds.s4),
                      child: Text(i.hidden ? 'Escondido pelo administrador' : 'Só ${i.to!.length} aluno${i.to!.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: Ds.fontLabel, color: i.hidden ? AppColors.sharp : AppColors.textDim)),
                    ),
                ]),
              ),
              IconButton(tooltip: 'Abrir', onPressed: () => _open(i), icon: Icon(Icons.open_in_new_rounded, color: AppColors.accent)),
              PopupMenuButton<String>(
                tooltip: 'Mais',
                onSelected: (v) {
                  if (v == 'edit') _edit(i);
                  if (v == 'del') _delete(i);
                  if (v == 'rep') _report(i);
                },
                itemBuilder: (c) => mine
                    ? const [PopupMenuItem(value: 'edit', child: Text('Editar')), PopupMenuItem(value: 'del', child: Text('Apagar'))]
                    : const [PopupMenuItem(value: 'rep', child: Text('Denunciar'))],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Formulário de material (modal): tipo, pasta, título, autor, link, observação, para quem e a declaração.
class _ItemForm extends StatefulWidget {
  final AppState app;
  final LibItem? item;
  final String kind;
  final String? folder;
  const _ItemForm({required this.app, this.item, required this.kind, this.folder});

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  late String kind = widget.item?.kind ?? widget.kind;
  late final folder = TextEditingController(text: widget.item?.folder ?? widget.folder ?? '');
  late final title = TextEditingController(text: widget.item?.title ?? '');
  late final author = TextEditingController(text: widget.item?.author ?? '');
  late final url = TextEditingController(text: widget.item?.url ?? '');
  late final note = TextEditingController(text: widget.item?.note ?? '');
  late Set<String>? to = widget.item?.to?.toSet();
  bool declared = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [folder, title, author, url, note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) return setState(() => error = 'Falta o título.');
    final u = libraryUrl(url.text);
    if (u == null) return setState(() => error = 'Use um link https do Google Drive, Dropbox, OneDrive, IMSLP, CPDL ou YouTube.');
    if (!declared) return setState(() => error = 'Confirme a declaração abaixo.');
    setState(() {
      busy = true;
      error = null;
    });
    final id = widget.item?.id ?? '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${(DateTime.now().microsecond).toRadixString(36)}';
    final it = LibItem(
      id: id.length > 40 ? id.substring(0, 40) : id,
      kind: kind,
      folder: folder.text.trim().isEmpty ? 'Geral' : folder.text.trim(),
      title: title.text.trim(),
      author: author.text.trim(),
      url: u,
      note: note.text.trim(),
      to: (to == null || to!.isEmpty) ? null : to!.toList(),
      created: widget.item?.created ?? DateTime.now().millisecondsSinceEpoch,
    );
    final err = await widget.app.libSave(it);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        busy = false;
        error = err;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final folders = libraryFolders(app.libCached());
    final students = [for (final s in app.students) if (s.code != null) s];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.s12, Ds.s8),
            child: Row(children: [
              Expanded(child: Text(widget.item == null ? 'Novo material' : 'Editar material', style: Ds.title())),
              TextButton(onPressed: busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s16, Ds.screenPad, Ds.s24),
              shrinkWrap: true,
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'a', label: Text('Acervo (método)')),
                    ButtonSegment(value: 'r', label: Text('Repertório (peça)')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setState(() => kind = s.first),
                ),
                const DsGap(Ds.gap),
                TextField(controller: title, maxLength: 80, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Título', hintText: 'Ex.: Estudos op. 45, Lição 5', counterText: '')),
                TextField(controller: folder, maxLength: 40, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Pasta', hintText: kind == 'a' ? 'Ex.: Wohlfahrt' : 'Ex.: Vivaldi', counterText: '')),
                if (folders.isNotEmpty)
                  Wrap(spacing: Ds.s8, children: [for (final f in folders.take(8)) ActionChip(label: Text(f), onPressed: () => setState(() => folder.text = f))]),
                const DsGap(Ds.s8),
                TextField(controller: author, maxLength: 60, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Autor (opcional)', counterText: '')),
                TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Link do material', hintText: 'https://drive.google.com/…', helperText: 'Drive, Dropbox, OneDrive, IMSLP, CPDL ou YouTube')),
                const DsGap(Ds.s12),
                TextField(controller: note, maxLength: 300, maxLines: 2, decoration: const InputDecoration(labelText: 'Observação (opcional)', counterText: '')),
                const DsGap(Ds.s8),
                Text('Quem vê', style: Ds.section()),
                const DsGap(Ds.s8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: true, label: Text('Todos os alunos')), ButtonSegment(value: false, label: Text('Escolher'))],
                  selected: {to == null},
                  onSelectionChanged: (s) => setState(() => to = s.first ? null : (to ?? <String>{})),
                ),
                if (to != null) ...[
                  const DsGap(Ds.s8),
                  if (students.isEmpty)
                    Text('Você ainda não tem alunos com código.', style: Ds.support())
                  else
                    Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
                      for (final s in students)
                        FilterChip(
                          label: Text(s.name),
                          selected: to!.contains(s.code),
                          onSelected: (v) => setState(() => v ? to!.add(s.code!) : to!.remove(s.code)),
                        ),
                    ]),
                ],
                const DsGap(Ds.s16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: declared,
                  onChanged: (v) => setState(() => declared = v ?? false),
                  title: const Text('Tenho o direito de compartilhar este material (domínio público, meu ou com autorização).', style: TextStyle(fontSize: Ds.fontSupport)),
                ),
                if (error != null) Padding(padding: const EdgeInsets.only(top: Ds.s8), child: Text(error!, style: TextStyle(color: AppColors.sharp, fontWeight: FontWeight.w700))),
                const DsGap(Ds.s16),
                DsPrimaryButton(onPressed: busy ? null : _save, icon: Icons.check_rounded, label: busy ? 'Salvando…' : 'Salvar'),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
