import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import 'theme.dart';

/// Aviso curto no TOPO da tela: aparece deslizando, some sozinho e pode ser
/// arrastado para dispensar. Não cobre os botões de baixo nem exige toque.
void showToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.info_outline,
  Color? color,
  Duration duration = const Duration(milliseconds: 2600),
}) {
  final accent = color ?? AppColors.accent;
  try {
    _show(message, icon, accent, duration);
  } catch (_) {
    // Garantia: se o aviso animado falhar, usa o aviso simples do Flutter.
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: duration,
    ));
  }
}

void _show(String message, IconData icon, Color accent, Duration duration) {
  toastification.dismissAll(delayForAnimation: false);
  toastification.show(
    type: ToastificationType.info,
    style: ToastificationStyle.flat,
    alignment: Alignment.topCenter,
    autoCloseDuration: duration,
    animationDuration: const Duration(milliseconds: 320),
    title: Text(message, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
    icon: Icon(icon, color: accent),
    primaryColor: accent,
    backgroundColor: AppColors.surface2,
    foregroundColor: AppColors.text,
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: accent.withValues(alpha: 0.55)),
    margin: const EdgeInsets.fromLTRB(16, 64, 16, 0), // abaixo da barra superior
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    showProgressBar: false,
    closeButton: ToastCloseButton(showType: CloseButtonShowType.none),
    dragToClose: true,
    pauseOnHover: false,
    applyBlurEffect: false,
    animationBuilder: (context, animation, alignment, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
}
