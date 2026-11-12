import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';
import 'package:afina_core/afina_core.dart';

/// Botão de microfone para ditar num campo de texto. Use como `suffixIcon` do
/// `InputDecoration`. Pisca em vermelho enquanto ouve; tocar de novo para.
class DictationButton extends StatelessWidget {
  final AppState app;
  final TextEditingController controller;
  const DictationButton({super.key, required this.app, required this.controller});

  Future<void> _tap(BuildContext context) async {
    final d = app.dictation;
    if (!d.consented && !d.isListening(controller)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.mic),
          title: Text(tr('Escrever falando')),
          content: Text(
              tr('Toque no microfone de um campo e fale: o texto aparece escrito. Quem transforma a voz em texto é o serviço de voz do seu aparelho ou do navegador (por exemplo, o do Google ou o da Apple), que pode usar a internet. O Notemusic não grava nem guarda o áudio.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Agora não'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Entendi, usar'))),
          ],
        ),
      );
      if (ok != true) return;
      await d.setConsent(true);
    }
    await d.toggle(controller);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.dictation,
      builder: (context, _) {
        final on = app.dictation.isListening(controller);
        return IconButton(
          tooltip: on ? tr('Parar de ouvir') : tr('Escrever falando'),
          icon: Icon(on ? Icons.mic : Icons.mic_none, color: on ? AppColors.sharp : AppColors.textDim),
          onPressed: () => _tap(context),
        );
      },
    );
  }
}
