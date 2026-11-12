import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import 'theme.dart';
import 'toast_kind.dart';

export 'toast_kind.dart' show ToastKind;

/// Aviso curto no TOPO da tela: aparece deslizando, some sozinho e pode ser
/// arrastado para dispensar. Não cobre os botões de baixo nem exige toque.
/// O tipo (sucesso, atenção, informação) vem do texto, ou de [kind]; muda cor e ícone.
/// Altura extra (px) que a faixa de status ocupa; os alertas descem esse tanto.
double kToastExtraTop = 0;

void showToast(
  BuildContext context,
  String message, {
  IconData? icon,
  Color? color,
  ToastKind? kind,
  Duration? duration,
}) {
  // Quem passou ícone ou cor escolheu o visual; senão o tipo vem do texto.
  final k = kind ?? ((icon == null && color == null) ? toastKindOf(message) : ToastKind.info);
  final accent = color ?? toastColorOf(k);
  final glyph = icon ?? toastIconOf(k);
  final time = duration ?? toastDuration(message, k);
  try {
    _show(message, glyph, accent, time);
  } catch (_) {
    // Garantia: se o aviso animado falhar, usa o aviso simples do Flutter.
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: time,
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
    title: Text(message, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.3, color: AppColors.text)),
    // Ícone num círculo cheio na cor do tipo: lê de longe, mesmo com o olho em outra parte da tela.
    icon: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: readableOn(accent)),
    ),
    primaryColor: accent,
    backgroundColor: Color.alphaBlend(accent.withValues(alpha: 0.18), AppColors.surface),
    foregroundColor: AppColors.text,
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(color: accent, width: 1.6),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
    margin: EdgeInsets.fromLTRB(16, 64 + kToastExtraTop, 16, 0), // abaixo da barra e da faixa de status
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    showProgressBar: true,
    progressBarTheme: ProgressIndicatorThemeData(color: accent, linearTrackColor: Colors.transparent, linearMinHeight: 3),
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
