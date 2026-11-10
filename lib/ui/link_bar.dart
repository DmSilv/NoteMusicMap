import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';

/// Aviso do alto da tela quando o vínculo online está DESLIGADO mas há quem dependa dele
/// (modo professor, professor ou aluno vinculado): sem ele, nada chega ao aparelho.
class LinkOffBar extends StatelessWidget {
  final AppState app;
  const LinkOffBar({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.linkNeedsAttention) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Material(
            color: AppColors.sharp.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.sharp.withValues(alpha: 0.7)),
              ),
              child: Row(children: [
                Icon(Icons.cloud_off_outlined, color: AppColors.sharp),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const Text('Você está offline', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text('O vínculo online está desligado: você não recebe avisos de alunos, aulas nem tarefas.',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ]),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
                  onPressed: () {
                    app.setLinkEnabled(true);
                    app.say('Vínculo online ligado.');
                  },
                  child: const Text('Ligar'),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Aviso antes de desligar o vínculo: diz claramente o que deixa de funcionar.
Future<bool> confirmDisableLink(BuildContext context, AppState app) async {
  final q = app.linkQueueSize;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.cloud_off_outlined, color: AppColors.sharp),
      title: const Text('Desligar o vínculo online?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Você ficará offline:', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('• não recebe avisos de alunos nem do professor\n'
              '• novos vínculos com você não chegam\n'
              '• aulas, tarefas e horários não são enviados nem recebidos\n'
              '• os lembretes de aula param'),
          const SizedBox(height: 8),
          Text(
            'Seus dados continuam neste aparelho${q > 0 ? ', e os $q itens da fila ficam guardados até você ligar de novo' : ''}. '
            'Você pode ligar de novo quando quiser.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continuar online')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.sharp),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Desligar mesmo assim'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// "Há uma versão nova": faixa fixa com botão para atualizar, no lugar de depender
/// de a pessoa abrir as configurações.
class UpdateBar extends StatelessWidget {
  final AppState app;
  const UpdateBar({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.showUpdatePrompt) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Material(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
              ),
              child: Row(children: [
                Icon(Icons.system_update, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const Text('Versão nova disponível', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text('Atualize para receber as correções. Seus dados são mantidos.',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ]),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
                  onPressed: () => app.updateApp(),
                  child: const Text('Atualizar'),
                ),
                IconButton(
                  tooltip: 'Depois',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => app.hideUpdatePrompt(hours: 6),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
