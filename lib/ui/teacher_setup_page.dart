import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'link_bar.dart' show confirmTeacherLink;
import 'safe_input.dart';
import 'teaching_ui.dart';
import 'materials_sheet.dart';
import 'theme.dart';

/// Pede a declaração de maioridade a quem ainda não fez (vale para qualquer caminho que liga o modo professor).
/// Devolve true se pode seguir.
Future<bool> requireAdult(BuildContext context, AppState app) async {
  if (app.adultOk) return true;
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Tenho 18 anos ou mais')),
      content: Text(tr('Só maiores de idade podem ser professores no app.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Agora não'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Confirmo'))),
      ],
    ),
  );
  if (yes != true) return false;
  app.confirmAdult();
  return true;
}

/// Cadastro do professor, em 3 passos curtos: como te chamar, que instrumentos leciona (e o que usa neles) e as turmas.
/// Serve para qualquer professor de música: se o instrumento não está na lista, ele cria o seu e põe os métodos e as peças.
/// Devolve true se o modo professor ficou ligado.
class TeacherSetupPage extends StatefulWidget {
  final AppState app;
  const TeacherSetupPage({super.key, required this.app});

  @override
  State<TeacherSetupPage> createState() => _TeacherSetupPageState();
}

class _TeacherSetupPageState extends State<TeacherSetupPage> {
  late final _name = TextEditingController(text: widget.app.profile.name ?? '');
  int _step = 0;
  String? _error;
  bool _adult = false;

  AppState get app => widget.app;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_step == 0) {
      final n = _name.text.trim();
      if (n.isEmpty) {
        setState(() => _error = tr('Digite o seu nome.'));
        return;
      }
      if (!_adult) {
        setState(() => _error = tr('Confirme que você tem 18 anos ou mais.'));
        return;
      }
      app.setProfileName(n);
    }
    if (_step < 2) {
      setState(() {
        _step++;
        _error = null;
      });
      return;
    }
    if (!await confirmTeacherLink(context, app)) return;
    app.confirmAdult();
    app.setTeacherMode(true);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final titles = [tr('Como posso te chamar?'), tr('Que instrumentos você leciona?'), tr('Você tem turmas?')];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Cadastro do professor'))),
      body: DsPageSafe(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => ListView(
            padding: Ds.screen,
            children: [
              Row(children: [
                for (var i = 0; i < 3; i++) ...[
                  Expanded(child: Container(height: 4, decoration: BoxDecoration(color: i <= _step ? AppColors.accent : AppColors.outline, borderRadius: BorderRadius.circular(2)))),
                  if (i < 2) const SizedBox(width: Ds.s8),
                ],
              ]),
              const SizedBox(height: Ds.s20),
              Text(tr('Passo {0} de 3', [_step + 1]), style: Ds.support()),
              const SizedBox(height: Ds.s4),
              Text(titles[_step], style: Ds.title()),
              const SizedBox(height: Ds.s16),
              if (_step == 0) ..._stepName(),
              if (_step == 1) ..._stepInstruments(context),
              if (_step == 2) ..._stepTurmas(context),
              const SizedBox(height: Ds.s24),
              Row(children: [
                if (_step > 0)
                  Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.primaryHeight)), onPressed: () => setState(() => _step--), child: Text(tr('Voltar')))),
                if (_step > 0) const SizedBox(width: Ds.s12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Ds.primaryHeight)),
                    onPressed: _next,
                    child: Text(_step < 2 ? tr('Continuar') : tr('Começar a dar aulas'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
              if (_step > 0)
                Center(child: TextButton(onPressed: _next, child: Text(tr('Pular este passo')))),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stepName() => [
        Text(tr('Seus alunos vão ver este nome.'), style: Ds.support()),
        const SizedBox(height: Ds.s16),
        TextField(
          controller: _name,
          autofocus: true,
          inputFormatters: const [SafeText.name()],
          textCapitalization: TextCapitalization.words,
          maxLength: 40,
          decoration: InputDecoration(labelText: tr('Seu nome'), errorText: _error, counterText: ''),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: Ds.s8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _adult,
          onChanged: (v) => setState(() {
            _adult = v ?? false;
            _error = null;
          }),
          title: Text(tr('Tenho 18 anos ou mais')),
          subtitle: Text(tr('Só maiores de idade podem ser professores no app.'), style: Ds.support()),
        ),
      ];

  List<Widget> _stepInstruments(BuildContext context) => [
        Text(tr('Marque um ou mais. Os métodos e o repertório de cada um aparecem prontos nas tarefas.'), style: Ds.support()),
        const SizedBox(height: Ds.s16),
        Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
          for (final i in allTeachingInstruments()) FilterChip(label: Text(i.label), selected: app.teachInstruments.contains(i.id), onSelected: (v) => app.setTeachInstrument(i.id, v)),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: Text(tr('Outro instrumento')), onPressed: () => showCustomInstrumentEditor(context, app)),
        ]),
        if (app.teachInstruments.isNotEmpty) ...[
          const SizedBox(height: Ds.s16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            onPressed: () => showMaterialsSheet(context, app),
            icon: const Icon(Icons.library_books_outlined),
            label: Text(tr('Cadastrar meus métodos e repertório')),
          ),
        ],
        const SizedBox(height: Ds.s12),
        Text(tr('Não achou o seu? Toque em "Outro instrumento" e escreva o nome. Métodos e peças podem vir depois.'), style: Ds.support()),
      ];

  List<Widget> _stepTurmas(BuildContext context) => [
        Text(tr('Dá aula de mais de um instrumento ou para turmas diferentes? Crie as turmas aqui. É opcional.'), style: Ds.support()),
        const SizedBox(height: Ds.s16),
        for (final t in app.turmas)
          Padding(
            padding: const EdgeInsets.only(bottom: Ds.s8),
            child: ListTile(
              tileColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.radiusControl)),
              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(teachingById(t.instrument)?.label ?? tr('Sem instrumento'), style: Ds.support()),
              trailing: IconButton(icon: const Icon(Icons.edit_outlined), tooltip: tr('Editar'), onPressed: () => showTurmaEditor(context, app, existing: t)),
            ),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
          onPressed: () => showTurmaEditor(context, app),
          icon: const Icon(Icons.add),
          label: Text(tr('Nova turma')),
        ),
      ];
}
