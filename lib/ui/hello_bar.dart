import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'safe_input.dart';
import 'theme.dart';

/// Pergunta "Como posso te chamar?" e grava o apelido no perfil.
/// Antes de vincular: o nome é obrigatório (sem ele o professor não sabe quem é o aluno).
/// Devolve true se já havia nome ou se a pessoa acabou de informar.
Future<bool> requireNickname(BuildContext context, AppState app,
    {String? reason}) async {
  if (!app.needsNickname) return true;
  await askNickname(context, app, mandatory: true, reason: reason ?? tr('Para se vincular, a outra pessoa precisa saber quem você é.'));
  return !app.needsNickname;
}

Future<void> askNickname(BuildContext context, AppState app, {bool mandatory = false, String? reason}) async {
  final ctrl = TextEditingController(text: app.profile.name ?? '');
  String? error;
  final saved = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) => AlertDialog(
      icon: const Icon(Icons.waving_hand_outlined),
      title: Text(tr('Como posso te chamar?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(reason, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          TextField(
            controller: ctrl,
            autofocus: true,
            inputFormatters: const [SafeText.name()],
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: InputDecoration(labelText: mandatory ? tr('Seu nome') : tr('Seu apelido'), errorText: error),
            onSubmitted: (v) {
              if (mandatory && v.trim().isEmpty) {
                setS(() => error = tr('Informe o seu nome para continuar.'));
              } else {
                Navigator.pop(c, v);
              }
            },
          ),
          Text(
            tr('Aparece nas saudações do app e, se você se vincular a um professor ou aluno, para essa pessoa. Dá para trocar depois em Minha conta.'),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(mandatory ? tr('Cancelar') : tr('Agora não'))),
        FilledButton(
          onPressed: () {
            if (mandatory && ctrl.text.trim().isEmpty) {
              setS(() => error = tr('Informe o seu nome para continuar.'));
            } else {
              Navigator.pop(c, ctrl.text);
            }
          },
          child: Text(tr('Salvar')),
        ),
      ],
    )),
  );
  ctrl.dispose();
  if (saved != null && saved.trim().isNotEmpty) {
    app.setProfileName(saved);
    app.say(tr('Prazer, {0}!', [saved.trim().split(RegExp(r'\s+')).first]));
  }
}

/// Faixa no alto da tela: sem apelido, convida a preencher; com apelido,
/// mostra "Bom dia / Boa tarde / Boa noite, Nome".
class HelloBar extends StatelessWidget {
  final AppState app;
  const HelloBar({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final name = app.profile.name;
        final hour = DateTime.now().hour;
        if (name == null || name.trim().isEmpty) {
          return const SizedBox.shrink(); // o convite para informar o apelido fica no sino
          // ignore: dead_code
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Material(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => askNickname(context, app),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
                  ),
                  child: Row(children: [
                    Icon(Icons.waving_hand_outlined, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(tr('{0}! Como posso te chamar?', [greetingFor(hour)]),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text(tr('Coloque seu apelido para o app falar com você.'),
                            style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                      ]),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: () => askNickname(context, app),
                      child: Text(tr('Informar')),
                    ),
                    IconButton(
                      tooltip: tr('Agora não'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => app.hideNickPrompt(days: 7),
                    ),
                  ]),
                ),
              ),
            ),
          );
        }
        final icon = switch (dayPartFor(hour)) {
          DayPart.morning => Icons.wb_sunny_outlined,
          DayPart.afternoon => Icons.wb_twilight,
          DayPart.night => Icons.nights_stay_outlined,
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => askNickname(context, app),
            child: Row(children: [
              Icon(icon, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(greetingLine(hour, name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  if (_who(app) != null)
                    Text(_who(app)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                ]),
              ),
              Tooltip(message: tr('Trocar apelido'), child: Icon(Icons.edit_outlined, size: 16, color: AppColors.textDim)),
              const SizedBox(width: 8),
            ]),
          ),
        );
      },
    );
  }
}

/// "Professor(a): Ana" para quem tem professor; "3 alunos" para quem ensina. Mostra o
/// nome na tela inicial para a pessoa saber com quem está ligada.
String? _who(AppState app) {
  final parts = <String>[];
  final t = app.myTeachers;
  if (t.isNotEmpty) {
    final last = t.last;
    final nm = last.name.trim().isEmpty ? last.code : last.name.trim();
    parts.add(t.length == 1 ? tr('Professor(a): {0}', [nm]) : tr('{0} professores', [t.length]));
  }
  if (app.teacherMode) {
    final n = app.students.length;
    parts.add(n == 0 ? tr('Modo professor') : (n == 1 ? tr('1 aluno') : tr('{0} alunos', [n])));
  }
  return parts.isEmpty ? null : parts.join(' · ');
}
