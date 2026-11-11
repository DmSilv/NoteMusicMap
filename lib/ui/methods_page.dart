import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'safe_input.dart';
import 'dictation_button.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Meus métodos e lições": a biblioteca do professor. Cadastrar, editar,
/// copiar a lista. Ela também cresce sozinha com o que
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
          IconButton(
            tooltip: 'Copiar lista',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => _copy(context, json: false),
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
                    'Seus métodos e lições (Suzuki, Ševčík, Mazas…). Ao passar uma tarefa, escolha com um toque.',
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
                      Text('Toque em "Novo método" para cadastrar o primeiro.',
                          style: TextStyle(color: AppColors.textDim)),
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
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.sharp, foregroundColor: readableOn(AppColors.sharp)),
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Excluir'),
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
            FilledButton.icon(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setS(() => err = 'Escreva o nome do método');
                  return;
                }
                Navigator.pop(c, true);
              },
              icon: const Icon(Icons.check, size: 18), label: const Text('Salvar'),
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

  Future<void> _copy(BuildContext context, {required bool json}) async {
    if (app.methodLibrary.isEmpty) {
      app.say('Sua lista está vazia.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: json ? app.exportMethodsAsJson() : app.exportMethods()));
    app.say('Lista copiada.');
  }
}
