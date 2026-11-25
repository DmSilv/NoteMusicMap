import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart';

/// Convite para ligar o lembrete, na hora em que ele faz sentido: quando o aluno já recebeu a primeira aula do professor.
class StudyNudgePrompt extends StatefulWidget {
  final AppState app;
  const StudyNudgePrompt({super.key, required this.app});

  @override
  State<StudyNudgePrompt> createState() => _StudyNudgePromptState();
}

class _StudyNudgePromptState extends State<StudyNudgePrompt> {
  AppState get app => widget.app;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (app.studyPromptWanted) app.refreshPush(); // só aqui sabemos se este aparelho pode receber notificação
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.showStudyPrompt) return const SizedBox.shrink();
        final install = app.pushStatus == PushStatus.needsInstall;
        return Padding(
          padding: const EdgeInsets.only(bottom: Ds.s12),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.notifications_active_outlined, tr('Quer um lembrete da tarefa?'),
                  subtitle: tr('Avisamos antes da aula e, se você ficar uns dias sem abrir o app, um toque leve.')),
              const SizedBox(height: Ds.s8),
              Text(
                install
                    ? tr('No iPhone, primeiro adicione o app à tela inicial (Compartilhar › Adicionar à Tela de Início) e abra por lá.')
                    : tr('No máximo 2 lembretes de estudo por semana, às 18h. Dá para desligar quando quiser.'),
                style: Ds.support(),
              ),
              const SizedBox(height: Ds.s12),
              Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
                if (!install)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final err = await app.enablePush();
                            if (err == null) app.dismissStudyPrompt();
                            app.say(err ?? tr('Lembretes ligados neste aparelho.'));
                            if (mounted) setState(() => _busy = false);
                          },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(tr('Sim, me lembre')),
                  ),
                TextButton(onPressed: app.dismissStudyPrompt, child: Text(tr('Agora não'))),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

/// PROFESSOR: lembrar o aluno pelo WhatsApp. Abre o WhatsApp com a mensagem pronta; quem escolhe o contato e envia é o professor.
Future<void> showWhatsReminderSheet(BuildContext context, AppState app, Student s) {
  final open = [for (final t in s.tasks) if (!t.done) t.title];
  final text = studyReminderText(s.name.split(' ').first, open);
  return showDsSheet(context, title: tr('Lembrar no WhatsApp'), listenable: app, children: (c) => [
        Text(tr('Você escolhe o contato e pode mudar o texto antes de enviar. O app não envia nada sozinho.'), style: Ds.support()),
        const SizedBox(height: Ds.s12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Ds.s12),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Ds.radiusControl), border: Border.all(color: AppColors.outline)),
          child: Text(text, style: const TextStyle(height: 1.4)),
        ),
        const SizedBox(height: Ds.s12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
          onPressed: () async {
            var ok = false;
            try {
              ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
            } catch (_) {
              ok = false;
            }
            if (!ok) app.say(tr('Não foi possível abrir o WhatsApp. Copie a mensagem.'));
          },
          icon: const Icon(Icons.send_rounded),
          label: Text(tr('Abrir o WhatsApp')),
        ),
        const SizedBox(height: Ds.s8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            app.say(tr('Mensagem copiada.'));
          },
          icon: const Icon(Icons.copy_rounded),
          label: Text(tr('Copiar a mensagem')),
        ),
      ]);
}
