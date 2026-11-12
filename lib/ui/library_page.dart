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
    if (!ok && mounted) app.say(tr('Não consegui abrir o link.'));
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
    if (saved == true) app.say(tr('Material salvo.'));
  }

  Future<void> _delete(LibItem i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Apagar este material?')),
        content: Text(tr('"{0}" sai do seu acervo e os alunos deixam de ver. O arquivo no Drive não é apagado.', [i.title])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Apagar'))),
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
        title: Text(tr('Denunciar este material?')),
        content: Text(tr('Use se o conteúdo for indevido ou violar direitos autorais. O administrador avalia e pode esconder o item.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Denunciar'))),
        ],
      ),
    );
    if (ok == true) {
      final sent = await app.libReport(widget.teacher!, i.id);
      app.say(sent ? tr('Denúncia enviada. Obrigado.') : tr('Não foi possível enviar agora.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(mine ? tr('Acervo e repertório') : tr('Material{0}', [(widget.teacherName ?? '').isEmpty ? '' : tr(' de {0}', [widget.teacherName])])),
        actions: [
          HelpButton(
            title: tr('Acervo e repertório'),
            sections: mine
                ? [
                    (tr('O que é'), tr('Uma lista dos seus materiais (métodos e peças), com o link de onde ficam: Google Drive, Dropbox, OneDrive, IMSLP ou YouTube. O Notemusic não guarda os arquivos.')),
                    (tr('Quem vê'), tr('Só os seus alunos vinculados, todos ou os que você escolher.')),
                    (tr('Direitos autorais'), tr('Compartilhe só o que é de domínio público, é seu ou tem autorização. A responsabilidade pelo conteúdo é de quem publica.')),
                  ]
                : [
                    (tr('O que é'), tr('Os materiais que o seu professor indicou. Ao tocar em Abrir, você sai do Notemusic para o link dele.')),
                    (tr('Algo errado?'), tr('Use "Denunciar" no menu do item.')),
                  ],
          ),
          const SizedBox(width: Ds.s8),
        ],
      ),
      floatingActionButton: mine ? FloatingActionButton.extended(onPressed: () => _edit(null), icon: const Icon(Icons.add_link_rounded), label: Text(tr('Adicionar material'))) : null,
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
              padding: EdgeInsets.fromLTRB(Ds.screenPad, Ds.s12, Ds.screenPad, mine ? 96 : Ds.s24),
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'a', icon: const Icon(Icons.menu_book_rounded, size: 18), label: Text(tr('Acervo · {0}', [nA]))),
                    ButtonSegment(value: 'r', icon: const Icon(Icons.library_music_rounded, size: 18), label: Text(tr('Repertório · {0}', [nR]))),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() {
                    _kind = s.first;
                    _folder = null;
                  }),
                ),
                if (folders.length > 1) ...[
                  const DsGap(Ds.s12),
                  // Pastas numa linha só, que rola de lado: não ocupa a tela com várias linhas de botões.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      ChoiceChip(label: Text(tr('Todas')), selected: _folder == null, onSelected: (_) => setState(() => _folder = null)),
                      for (final f in folders) ...[
                        const SizedBox(width: Ds.s8),
                        ChoiceChip(label: Text(folderLabel(f)), selected: _folder == f, onSelected: (_) => setState(() => _folder = f)),
                      ],
                    ]),
                  ),
                ],
                const DsGap(Ds.s8),
                if (_loading && all.isEmpty)
                  const Padding(padding: EdgeInsets.all(Ds.sectionGap), child: Center(child: CircularProgressIndicator()))
                else if (_failed && all.isEmpty)
                  _note(Icons.cloud_off_outlined, tr('Não consegui carregar.'), action: TextButton(onPressed: _load, child: Text(tr('Tentar de novo'))))
                else if (shown.isEmpty)
                  _note(Icons.folder_open_rounded, mine ? tr('Nada aqui ainda. Toque em "Adicionar material".') : tr('Seu professor ainda não indicou nada aqui.'))
                else
                  for (final f in libraryFolders(shown)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s16, 0, Ds.s8),
                      child: Text(folderLabel(f).toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: AppColors.textDim)),
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
          DsIconBadge(icon, size: 56, color: AppColors.textDim),
          const DsGap(Ds.s12),
          Text(text, textAlign: TextAlign.center, style: Ds.support().copyWith(fontSize: 15)),
          ?action,
        ]),
      );

  Widget _tile(LibItem i) {
    final focus = (widget.focusTitle ?? '').trim().toLowerCase() == i.title.trim().toLowerCase();
    final host = (Uri.tryParse(i.url)?.host ?? '').replaceFirst('www.', '');
    final tag = mine && (i.to != null || i.hidden)
        ? (i.hidden ? tr('Escondido pelo administrador') : tr('Só {0} aluno{1}', [i.to!.length, i.to!.length == 1 ? '' : 's']))
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
          onTap: () => _open(i),
          child: Container(
            constraints: const BoxConstraints(minHeight: Ds.primaryHeight + 12),
            padding: const EdgeInsets.fromLTRB(Ds.s12, Ds.s12, Ds.s4, Ds.s12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
              border: Border.all(color: focus ? AppColors.accent : AppColors.outline, width: focus ? 1.5 : 1),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsIconBadge(i.kind == 'a' ? Icons.menu_book_rounded : Icons.library_music_rounded, size: 44),
              const SizedBox(width: Ds.s12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Ds.fontBody, fontWeight: FontWeight.w700, height: 1.25)),
                  if (i.author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(i.author, style: Ds.support())),
                  if (i.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Ds.s4), child: Text(i.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: Ds.support().copyWith(fontSize: 13))),
                  Padding(
                    padding: const EdgeInsets.only(top: Ds.s8),
                    child: Row(children: [
                      Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.accent),
                      const SizedBox(width: Ds.s4),
                      Flexible(child: Text(host.isEmpty ? tr('Abrir') : host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.accent, fontWeight: FontWeight.w600))),
                      if (tag != null) ...[
                        const SizedBox(width: Ds.s8),
                        Text('·', style: TextStyle(color: AppColors.textDim)),
                        const SizedBox(width: Ds.s8),
                        Flexible(child: Text(tag, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Ds.fontLabel, color: i.hidden ? AppColors.sharp : AppColors.textDim))),
                      ],
                    ]),
                  ),
                ]),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Mais'),
                onSelected: (v) {
                  if (v == 'edit') _edit(i);
                  if (v == 'del') _delete(i);
                  if (v == 'rep') _report(i);
                },
                itemBuilder: (c) => mine
                    ? [PopupMenuItem(value: 'edit', child: Text(tr('Editar'))), PopupMenuItem(value: 'del', child: Text(tr('Apagar')))]
                    : [PopupMenuItem(value: 'rep', child: Text(tr('Denunciar')))],
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
    if (title.text.trim().isEmpty) return setState(() => error = tr('Falta o título.'));
    final u = libraryUrl(url.text);
    if (u == null) return setState(() => error = tr('Use um link https do Google Drive, Dropbox, OneDrive, IMSLP, CPDL ou YouTube.'));
    if (!declared) return setState(() => error = tr('Confirme a declaração abaixo.'));
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
              Expanded(child: Text(widget.item == null ? tr('Novo material') : tr('Editar material'), style: Ds.title())),
              TextButton(onPressed: busy ? null : () => Navigator.of(context).pop(false), child: Text(tr('Cancelar'))),
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
                  segments: [
                    ButtonSegment(value: 'a', label: Text(tr('Acervo (método)'))),
                    ButtonSegment(value: 'r', label: Text(tr('Repertório (peça)'))),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setState(() => kind = s.first),
                ),
                const DsGap(Ds.gap),
                TextField(controller: title, maxLength: 80, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('Título'), hintText: tr('Ex.: Estudos op. 45, Lição 5'), counterText: '')),
                const DsGap(Ds.s12),
                TextField(controller: url, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: tr('Link do material'), hintText: 'https://drive.google.com/…', helperText: tr('Drive, Dropbox, OneDrive, IMSLP, CPDL ou YouTube'))),
                const DsGap(Ds.s12),
                TextField(controller: folder, maxLength: 40, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Pasta'), hintText: kind == 'a' ? tr('Ex.: Wohlfahrt') : tr('Ex.: Vivaldi'), counterText: '')),
                if (folders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Ds.s4),
                    child: Wrap(spacing: Ds.s8, children: [for (final f in folders.take(8)) ActionChip(label: Text(folderLabel(f)), onPressed: () => setState(() => folder.text = f))]),
                  ),
                // Opcionais recolhidos: a tela abre só com o essencial (tipo, título, link e pasta).
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    initiallyExpanded: author.text.isNotEmpty || note.text.isNotEmpty,
                    title: Text(tr('Mais detalhes (opcional)'), style: Ds.section()),
                    children: [
                      TextField(controller: author, maxLength: 60, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Autor'), counterText: '')),
                      const DsGap(Ds.s12),
                      TextField(controller: note, maxLength: 300, maxLines: 2, decoration: InputDecoration(labelText: tr('Observação'), counterText: '')),
                      const DsGap(Ds.s8),
                    ],
                  ),
                ),
                const DsGap(Ds.s8),
                Text(tr('Quem vê'), style: Ds.section()),
                const DsGap(Ds.s8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [ButtonSegment(value: true, label: Text(tr('Todos os alunos'))), ButtonSegment(value: false, label: Text(tr('Escolher')))],
                  selected: {to == null},
                  onSelectionChanged: (s) => setState(() => to = s.first ? null : (to ?? <String>{})),
                ),
                if (to != null) ...[
                  const DsGap(Ds.s8),
                  if (students.isEmpty)
                    Text(tr('Você ainda não tem alunos com código.'), style: Ds.support())
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
                  title: Text(tr('Tenho o direito de compartilhar este material (domínio público, meu ou com autorização).'), style: TextStyle(fontSize: Ds.fontSupport)),
                ),
                if (error != null) Padding(padding: const EdgeInsets.only(top: Ds.s8), child: Text(error!, style: TextStyle(color: AppColors.sharp, fontWeight: FontWeight.w700))),
                const DsGap(Ds.s16),
                DsPrimaryButton(onPressed: busy ? null : _save, icon: Icons.check_rounded, label: busy ? tr('Salvando…') : tr('Salvar')),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
