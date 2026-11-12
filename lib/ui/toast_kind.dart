import 'package:afina_core/afina_core.dart' show Lang;
import 'package:flutter/material.dart';

import 'theme.dart';

/// Tipos de aviso curto: o tipo define cor, ícone e quanto tempo fica na tela.
enum ToastKind { info, success, warning }

// Os avisos do app são frases curtas; o tipo (atenção, sucesso, informação) sai de palavras-chave, em português e em inglês.
// `toast_kind_test.dart` (português) e `toast_kind_en_test.dart` (inglês) guardam os dois conjuntos.
final _warningPt = RegExp(
  r'^não\b|^nao\b|não (consegui|foi possível|é válido|há|deu)|inválid|sem conexão|offline|choca|limite|erro|falha|já passou|use exatamente|expirou',
  caseSensitive: false,
);
final _successPt = RegExp(
  r'copiad|registrad|desfeit|salv|atualizad|cancelad|descartad|adicionad|vinculad|enviad|passada|concluíd|conclu|restaurad|liberad|escolhida|confirmad|apagad|removid|excluíd|ligado\.|instalado|definida|pronto|marcad|criad|remarcad|pausad|trocad|publicad|bom trabalho',
  caseSensitive: false,
);
final _warningEn = RegExp(
  r"^(no|not|cannot|too many)\b|\b(can't|couldn't|could not|didn't|isn't|aren't|doesn't|don't|wasn't|won't|unable)\b|\b(invalid|incorrect|offline|conflicts|limit|error|failed|expired|unavailable|denied)\b|there are no|already passed|no connection|no internet|use exactly",
  caseSensitive: false,
);
final _successEn = RegExp(
  r'\b(copied|recorded|undone|saved|updated|canceled|discarded|added|linked|sent|assigned|completed|restored|allowed|chosen|confirmed|deleted|removed|installed|done|marked|created|rescheduled|paused|swapped|published|connected|imported|enabled|secured|taken|erased|cleared)\b|\bon\.$|nice work|well done|all set',
  caseSensitive: false,
);

/// Decide o tipo de um aviso pelo texto (os avisos do app são frases curtas, no idioma de hoje).
/// "Não consegui abrir o link." é atenção; "Aula atualizada." é sucesso; o resto é informação.
ToastKind toastKindOf(String message) {
  final m = message.trim();
  final en = Lang.isEn;
  if ((en ? _warningEn : _warningPt).hasMatch(m)) return ToastKind.warning;
  if ((en ? _successEn : _successPt).hasMatch(m)) return ToastKind.success;
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
