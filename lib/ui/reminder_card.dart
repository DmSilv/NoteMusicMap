import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Lembrete de aula 15 minutos antes (notificação do navegador, mesmo com o app fechado).
/// Mostra a situação deste aparelho e o botão para ligar ou desligar.
class ReminderCard extends StatefulWidget {
  final AppState app;
  const ReminderCard({super.key, required this.app});

  @override
  State<ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<ReminderCard> {
  AppState get app => widget.app;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    app.refreshPush();
  }

  Future<void> _run(Future<String?> Function() job) async {
    setState(() => _busy = true);
    final msg = await job();
    if (!mounted) return;
    setState(() => _busy = false);
    if (msg != null) app.say(msg);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final st = app.pushStatus;
        final (IconData icon, Color color, String title, String text) = switch (st) {
          PushStatus.on => (
              Icons.notifications_active_outlined,
              AppColors.inTune,
              'Lembretes ligados',
              app.remindChoiceOn
                  ? 'Você recebe uma notificação antes de cada aula, no tempo que o professor escolheu, mesmo com o app fechado.'
                  : 'Você recebe uma notificação 15 minutos antes de cada aula, mesmo com o app fechado.'
            ),
          PushStatus.off => (
              Icons.notifications_none,
              AppColors.accent,
              'Lembrete 15 minutos antes',
              'Ative para receber uma notificação antes de cada aula, mesmo com o app fechado.'
            ),
          PushStatus.denied => (
              Icons.notifications_off_outlined,
              AppColors.flat,
              'Notificações bloqueadas',
              'O navegador está bloqueando as notificações deste site. Libere nas configurações do navegador '
                  '(cadeado ao lado do endereço › Notificações) e volte aqui.'
            ),
          PushStatus.needsInstall => (
              Icons.install_mobile,
              AppColors.flat,
              'Instale o app para receber lembretes',
              'No iPhone as notificações só chegam se o app estiver na tela inicial: Compartilhar › Adicionar à Tela '
                  'de Início, e abra por lá. Enquanto isso, o aviso aparece aqui dentro do app.'
            ),
          PushStatus.linkOff => (
              Icons.cloud_off_outlined,
              AppColors.flat,
              'Ligue o vínculo online',
              'A agenda e os lembretes passam pelo vínculo online. Ligue para marcar aulas e receber os avisos.'
            ),
          PushStatus.serverOff => (
              Icons.notifications_paused_outlined,
              AppColors.textDim,
              'Notificações ainda não disponíveis',
              'O servidor ainda não está configurado para enviar lembretes. O aviso continua aparecendo aqui dentro do app.'
            ),
          PushStatus.unsupported => (
              Icons.notifications_off_outlined,
              AppColors.textDim,
              'Este navegador não envia notificações',
              'O aviso "aula em 15 minutos" continua aparecendo aqui dentro do app.'
            ),
          PushStatus.unknown => (
              Icons.notifications_none,
              AppColors.textDim,
              'Lembrete 15 minutos antes',
              'Verificando este aparelho…'
            ),
        };
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
            ]),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.3)),
            if (st == PushStatus.off || st == PushStatus.on || st == PushStatus.linkOff) ...[
              const SizedBox(height: 10),
              if (st == PushStatus.off)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(app.enablePush),
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.notifications_active_outlined, size: 18),
                  label: const Text('Ativar lembretes'),
                ),
              if (st == PushStatus.linkOff)
                FilledButton.icon(
                  onPressed: () async {
                    app.setLinkEnabled(true);
                    await Future<void>.delayed(const Duration(milliseconds: 600));
                    await app.refreshPush();
                  },
                  icon: const Icon(Icons.cloud_outlined, size: 18),
                  label: const Text('Ligar vínculo online'),
                ),
              if (st == PushStatus.on)
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                  onPressed: _busy ? null : () => _run(() async {
                    await app.disablePush();
                    return null;
                  }),
                  child: const Text('Desligar neste aparelho'),
                ),
            ],
          ]),
        );
      },
    );
  }
}
