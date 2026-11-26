import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'link_bar.dart' show askTeacherLink;
import 'safe_input.dart';
import 'teaching_ui.dart';
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

/// Cadastro do professor, em 2 passos curtos: como te chamar e que instrumentos leciona. O primeiro abre com a promessa do
/// app para ele; turmas, métodos e repertório ficam para depois (aparecem quando ele já usa o básico).
/// Serve para qualquer professor de música: se o instrumento não está na lista, ele cria o seu.
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
    if (_step < 1) {
      setState(() {
        _step++;
        _error = null;
      });
      return;
    }
    // Ser professor não depende de conectar: "Agora não" conclui o cadastro do mesmo jeito.
    final connect = await askTeacherLink(context, app);
    if (connect == null) return;
    app.confirmAdult();
    app.setTeacherMode(true, connect: connect);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final titles = [tr('Como posso te chamar?'), tr('Que instrumentos você leciona?')];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Cadastro do professor'))),
      body: DsPageSafe(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => ListView(
            padding: Ds.screen,
            children: [
              Row(children: [
                for (var i = 0; i < 2; i++) ...[
                  Expanded(child: Container(height: 4, decoration: BoxDecoration(color: i <= _step ? AppColors.accent : AppColors.outline, borderRadius: BorderRadius.circular(2)))),
                  if (i < 1) const SizedBox(width: Ds.s8),
                ],
              ]),
              const SizedBox(height: Ds.s20),
              if (_step == 0) ..._promise(),
              Text(tr('Passo {0} de 2', [_step + 1]), style: Ds.support()),
              const SizedBox(height: Ds.s4),
              Text(titles[_step], style: Ds.title()),
              const SizedBox(height: Ds.s16),
              if (_step == 0) ..._stepName(),
              if (_step == 1) ..._stepInstruments(context),
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
                    child: Text(_step < 1 ? tr('Continuar') : tr('Começar a dar aulas'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// Para que serve, antes de pedir qualquer coisa.
  List<Widget> _promise() => [
        Text(tr('Ajude seu aluno a estudar entre uma aula e outra'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: Ds.s8),
        Text(tr('Você passa a tarefa na aula, ele estuda aqui no app e você vê o que ele marcou.'),
            style: TextStyle(fontSize: Ds.fontBody, color: AppColors.textDim, height: 1.35)),
        const SizedBox(height: Ds.s24),
      ];

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
        Text(tr('Opcional. Os métodos e o repertório de cada instrumento aparecem prontos nas tarefas.'), style: Ds.support()),
        const SizedBox(height: Ds.s16),
        Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
          for (final i in allTeachingInstruments()) FilterChip(label: Text(i.label), selected: app.teachInstruments.contains(i.id), onSelected: (v) => app.setTeachInstrument(i.id, v)),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: Text(tr('Outro instrumento')), onPressed: () => showCustomInstrumentEditor(context, app)),
        ]),
        const SizedBox(height: Ds.s12),
        Text(tr('Não achou o seu? Toque em "Outro instrumento" e escreva o nome. Métodos e peças podem vir depois.'), style: Ds.support()),
      ];
}
