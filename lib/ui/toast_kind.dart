import 'package:flutter/material.dart';

import 'theme.dart';

/// Tipos de aviso curto: o tipo define cor, ícone e quanto tempo fica na tela.
enum ToastKind { info, success, warning }

final _warning = RegExp(
  r'^não\b|^nao\b|não (consegui|foi possível|é válido|há|deu)|inválid|sem conexão|offline|choca|limite|erro|falha|já passou|use exatamente|expirou',
  caseSensitive: false,
);
final _success = RegExp(
  r'copiad|salv|atualizad|cancelad|descartad|adicionad|vinculad|enviad|passada|concluíd|conclu|restaurad|liberad|escolhida|confirmad|apagad|removid|excluíd|ligado\.|instalado|definida|pronto|marcad|criad|remarcad|pausad|trocad|publicad|bom trabalho',
  caseSensitive: false,
);

/// Decide o tipo de um aviso pelo texto (os avisos do app são frases curtas em português).
/// "Não consegui abrir o link." é atenção; "Aula atualizada." é sucesso; o resto é informação.
ToastKind toastKindOf(String message) {
  final m = message.trim();
  if (_warning.hasMatch(m)) return ToastKind.warning;
  if (_success.hasMatch(m)) return ToastKind.success;
  return ToastKind.info;
}

Color toastColorOf(ToastKind k) => switch (k) {
      ToastKind.success => AppColors.inTune,
      ToastKind.warning => AppColors.sharp,
      ToastKind.info => AppColors.flat,
    };

IconData toastIconOf(ToastKind k) => switch (k) {
      ToastKind.success => Icons.check_rounded,
      ToastKind.warning => Icons.priority_high_rounded,
      ToastKind.info => Icons.info_outline_rounded,
    };

/// Quanto tempo o aviso fica: o suficiente para ler (frase maior, mais tempo) e mais nos avisos de atenção.
Duration toastDuration(String message, ToastKind k) {
  final base = switch (k) {
    ToastKind.success => 3000,
    ToastKind.warning => 4200,
    ToastKind.info => 3200,
  };
  final extra = ((message.length - 40).clamp(0, 120)) * 45; // +45 ms por letra acima de 40
  return Duration(milliseconds: base + extra);
}
