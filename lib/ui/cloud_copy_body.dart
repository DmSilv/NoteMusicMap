import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart';

/// Cópia das fichas na nuvem (chave `copia_nuvem`): explica o que vai para o servidor e só liga com o aceite da pessoa.
class CloudCopyBody extends StatefulWidget {
  final AppState app;
  const CloudCopyBody({super.key, required this.app});

  @override
  State<CloudCopyBody> createState() => _CloudCopyBodyState();
}

class _CloudCopyBodyState extends State<CloudCopyBody> {
  bool _busy = false;

  AppState get app => widget.app;

  Future<void> _toggle() async {
    final turnOn = !app.cloudCopyOn;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(turnOn ? tr('Guardar a cópia na nuvem?') : tr('Apagar a cópia da nuvem?')),
        content: Text(turnOn
            ? tr('Seus alunos, tarefas, observações, agenda e métodos passam a ser copiados para o servidor do app.')
            : tr('A cópia que está no servidor é apagada. Os dados deste aparelho continuam aqui.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(turnOn ? tr('Ligar') : tr('Apagar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final problem = await app.setCloudCopy(turnOn);
    if (!mounted) return;
    setState(() => _busy = false);
    app.say(problem ?? (turnOn ? tr('Cópia na nuvem ligada.') : tr('Cópia apagada do servidor.')));
  }

  @override
  Widget build(BuildContext context) {
    final on = app.cloudCopyOn;
    final points = <(IconData, String, String)>[
      (Icons.cloud_upload_outlined, tr('O que vai'), tr('Alunos com tarefas, observações e aulas, agenda, métodos e histórico de estudo.')),
      (Icons.lock_outline, tr('Quem vê'), tr('Só você. Nem o painel do administrador mostra o conteúdo da cópia.')),
      (Icons.phone_android, tr('Para que serve'), tr('Se perder o celular, entre em outro aparelho com a sua chave e tudo volta.')),
      (Icons.delete_outline, tr('Como parar'), tr('Desligue aqui: a cópia é apagada do servidor. Excluir o perfil também apaga.')),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Cópia das suas fichas na nuvem'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: Ds.s4),
          Text(tr('Hoje seus dados ficam só neste aparelho. Com a cópia ligada, eles também ficam guardados no servidor.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
          const SizedBox(height: Ds.s12),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: Ds.s12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DsIconBadge(p.$1, size: 36),
                const SizedBox(width: Ds.s12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: Ds.s4),
                    Text(p.$3, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: Ds.gap),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(on ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: on ? AppColors.accent : AppColors.textDim),
            const SizedBox(width: Ds.s8),
            Text(on ? tr('Cópia ligada') : tr('Cópia desligada'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: Ds.s12),
          SizedBox(
            width: double.infinity,
            height: Ds.primaryHeight,
            child: on
                ? OutlinedButton.icon(
                    onPressed: _busy ? null : _toggle,
                    icon: const Icon(Icons.cloud_off_outlined),
                    label: Text(tr('Desligar e apagar a cópia')),
                  )
                : FilledButton.icon(
                    onPressed: _busy ? null : _toggle,
                    icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.cloud_upload_outlined),
                    label: Text(tr('Ligar a cópia na nuvem')),
                  ),
          ),
        ]),
      ),
    ]);
  }
}
