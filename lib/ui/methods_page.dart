import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'safe_input.dart';
import 'dictation_button.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Meus métodos e lições": a biblioteca do professor. Cadastrar, editar,
/// importar de um texto colado e exportar. Ela também cresce sozinha com o que
/// é digitado nas tarefas.
class MethodsPage extends StatelessWidget {
  final AppState app;
  const MethodsPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus métodos e lições'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Importar e exportar',
            onSelected: (v) => switch (v) {
              'import' => _import(context),
              'copy' => _copy(context, json: false),
              'json' => _copy(context, json: true),
              _ => null,
            },
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'import', child: Text('Importar de um texto')),
              PopupMenuItem(value: 'copy', child: Text('Copiar lista (texto)')),
              PopupMenuItem(value: 'json', child: Text('Copiar para outro aparelho')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Novo método'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final lib = app.methodLibrary;
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
              children: [
                AppCard(
                  child: Text(
                    'Guarde aqui os métodos e livros que você usa (Suzuki, Ševčík, Mazas…) e as lições de cada um. '
                    'Ao passar uma tarefa, você escolhe com um toque. Se digitar um método ou lição novo numa '
                    'tarefa, ele entra aqui sozinho. Para trazer uma lista pronta, use ⋮ › Importar de um texto.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.3),
                  ),
                ),
                const SizedBox(height: 10),
                if (lib.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      Icon(Icons.library_books_outlined, size: 44, color: AppColors.textDim),
                      const SizedBox(height: 8),
                      const Text('Nenhum método ainda', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('Toque em "Novo método" ou importe uma lista.',
                          style: TextStyle(color: AppColors.textDim)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _import(context),
                        icon: const Icon(Icons.paste),
                        label: const Text('Importar de um texto'),
                      ),
                    ]),
                  ),
                for (final m in lib)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                              m.lessons.isEmpty
                                  ? 'Sem lições cadastradas'
                                  : '${m.lessons.length} lição${m.lessons.length == 1 ? '' : 'ões'}',
                              style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                          children: [
                            if (m.lessons.isEmpty)
                              Text('Edite para acrescentar as lições deste método.',
                                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                            for (final l in m.lessons)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text('• $l'),
                              ),
                            const SizedBox(height: 6),
                            Row(children: [
                              TextButton.icon(
                                onPressed: () => _edit(context, m: m),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Editar'),
                              ),
                              TextButton.icon(
                                onPressed: () => _delete(context, m),
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: const Text('Excluir'),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, MethodEntry m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Excluir ${m.name}?'),
        content: const Text('Remove o método e as lições da sua lista. As tarefas já passadas não mudam.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.sharp, foregroundColor: readableOn(AppColors.sharp)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) app.removeMethod(m);
  }

  /// Cadastrar ([m] nulo) ou editar um método: nome e lições (uma por linha).
  Future<void> _edit(BuildContext context, {MethodEntry? m}) async {
    final name = TextEditingController(text: m?.name ?? '');
    final lessons = TextEditingController(text: m?.lessons.join('\n') ?? '');
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(m == null ? 'Novo método' : 'Editar método'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  inputFormatters: const [SafeText.title()],
                  autofocus: m == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Nome do método ou livro',
                    errorText: err,
                    suffixIcon: DictationButton(app: app, controller: name),
                  ),
                  onChanged: (_) => setS(() => err = null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lessons,
                  inputFormatters: const [SafeText.list()],
                  minLines: 4,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: 'Lições (opcional)',
                    alignLabelWithHint: true,
                    helperText: 'Uma por linha. Ex.: Lição 1, Lição 2… Dá para acrescentar depois.',
                    helperMaxLines: 2,
                    suffixIcon: DictationButton(app: app, controller: lessons),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setS(() => err = 'Escreva o nome do método');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    final n = name.text, l = lessons.text;
    name.dispose();
    lessons.dispose();
    if (ok != true) return;
    if (m == null) {
      if (!app.addMethod(n, l)) app.say('Esse método já estava na lista.');
    } else {
      app.renameMethod(m, n, l);
    }
  }

  /// Importar de um texto colado (de uma anotação, planilha, mensagem ou do outro aparelho).
  Future<void> _import(BuildContext context) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Importar métodos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Copie a lista de qualquer lugar (anotações, planilha, mensagem, outro aparelho) e cole aqui. '
                  'Formatos aceitos:',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              const SizedBox(height: 6),
              const Text(
                  '• Um método por linha\n'
                  '• Suzuki Livro 1: Lição 1; Lição 2\n'
                  '• Método numa linha e as lições abaixo, com "-" na frente\n'
                  '• A lista copiada de outro aparelho (⋮ › Copiar para outro aparelho)',
                  style: TextStyle(fontSize: 13, height: 1.35)),
              const SizedBox(height: 10),
              TextField(
                controller: ctl,
                inputFormatters: const [SafeText.import()],
                autofocus: true,
                minLines: 5,
                maxLines: 10,
                decoration: InputDecoration(
                  hintText: 'Cole aqui',
                  suffixIcon: IconButton(
                    tooltip: 'Colar',
                    icon: const Icon(Icons.paste),
                    onPressed: () async {
                      final d = await Clipboard.getData(Clipboard.kTextPlain);
                      if (d?.text != null) {
                        ctl.text = stripUnsafe(d!.text!, max: kMaxImport, multiline: true);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Importar')),
        ],
      ),
    );
    final text = ctl.text;
    ctl.dispose();
    if (ok == true && text.trim().isNotEmpty) app.say(app.importMethods(text));
  }

  Future<void> _copy(BuildContext context, {required bool json}) async {
    if (app.methodLibrary.isEmpty) {
      app.say('Sua lista está vazia.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: json ? app.exportMethodsAsJson() : app.exportMethods()));
    app.say(json ? 'Copiado: use "Importar de um texto" no outro aparelho.' : 'Lista copiada.');
  }
}
