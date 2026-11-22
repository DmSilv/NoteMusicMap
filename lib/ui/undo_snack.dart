import 'package:flutter/material.dart';

/// Aviso de baixo com o botão "Desfazer": serve para toda ação que some com algo da tela (esconder um cartão, tirar um item).
/// Fica 8 segundos (tempo de ler e decidir), é flutuante e o botão tem alvo de toque grande. [messenger] é pego ANTES da ação,
/// porque a tela que chamou pode deixar de existir logo depois (o cartão escondido).
/// "Agora não" e parecidos: faz [action] (que esconde ou adia algo) e oferece "Desfazer" por 8 s, para quem tocou sem querer.
/// O aviso é pego ANTES de [action], porque a tela que chamou costuma sumir logo depois (o convite que foi dispensado).
void dismissWithUndo(
  BuildContext context, {
  required String message,
  required String undoLabel,
  required VoidCallback action,
  required VoidCallback undo,
}) {
  final messenger = ScaffoldMessenger.of(context);
  action();
  showUndoSnack(messenger, message: message, undoLabel: undoLabel, onUndo: undo);
}

void showUndoSnack(
  ScaffoldMessengerState messenger, {
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
  Duration duration = const Duration(seconds: 8),
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: duration,
      showCloseIcon: true,
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    ));
}
