import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'safe_input.dart';
import 'theme.dart';

/// Pergunta "Como posso te chamar?" e grava o apelido no perfil.
Future<void> askNickname(BuildContext context, AppState app) async {
  final ctrl = TextEditingController(text: app.profile.name ?? '');
  final saved = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.waving_hand_outlined),
      title: const Text('Como posso te chamar?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            inputFormatters: const [SafeText.name()],
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Seu apelido'),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
          Text(
            'Aparece nas saudações do app e, se você se vincular a um professor ou aluno, para essa pessoa. Dá para trocar depois em Minha conta.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Agora não')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Salvar')),
      ],
    ),
  );
  ctrl.dispose();
  if (saved != null && saved.trim().isNotEmpty) {
    app.setProfileName(saved);
    app.say('Prazer, ${saved.trim().split(RegExp(r'\s+')).first}!');
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
          if (DateTime.now().millisecondsSinceEpoch < app.nickHideUntil) return const SizedBox.shrink();
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
                        Text('${greetingFor(hour)}! Como posso te chamar?',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text('Coloque seu apelido para o app falar com você.',
                            style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                      ]),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: () => askNickname(context, app),
                      child: const Text('Informar'),
                    ),
                    IconButton(
                      tooltip: 'Agora não',
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
                child: Text(greetingLine(hour, name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Tooltip(message: 'Trocar apelido', child: Icon(Icons.edit_outlined, size: 16, color: AppColors.textDim)),
              const SizedBox(width: 8),
            ]),
          ),
        );
      },
    );
  }
}
