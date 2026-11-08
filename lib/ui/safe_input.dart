import 'package:afina_core/afina_core.dart';
import 'package:flutter/services.dart';

/// Filtro de digitação: tira na hora caracteres de controle e invisíveis (inclusive
/// os que invertem a direção do texto) e corta no tamanho do campo, contando
/// letras e não bytes. Colar um texto gigante também é cortado.
class SafeText extends TextInputFormatter {
  final int max;
  final bool multiline;
  const SafeText(this.max, {this.multiline = false});

  /// Nome de pessoa ou apelido.
  const SafeText.name() : this(kMaxName);

  /// Título de método ou tarefa.
  const SafeText.title() : this(kMaxTitle);

  /// Uma linha de texto livre (lição, detalhe).
  const SafeText.line() : this(kMaxLine);

  /// Observação ou comentário (várias linhas).
  const SafeText.note() : this(kMaxNote, multiline: true);

  /// Várias lições de uma vez.
  const SafeText.list() : this(kMaxList, multiline: true);

  /// Texto colado para importar métodos.
  const SafeText.import() : this(kMaxImport, multiline: true);

  /// Dados colados (chave de recuperação, backup).
  const SafeText.paste(int max) : this(max, multiline: true);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = stripUnsafe(newValue.text, max: max, multiline: multiline);
    if (cleaned == newValue.text) return newValue;
    final end = cleaned.length;
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(
          offset: newValue.selection.baseOffset.clamp(0, end).toInt()),
    );
  }
}

/// Campo de código de aluno/professor: só letras, números, hífen e espaço, e
/// no máximo 12 caracteres ("K7QM-4TXD" cabe com folga).
final List<TextInputFormatter> codeFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
  LengthLimitingTextInputFormatter(12),
];

/// Campo numérico inteiro com no máximo [digits] dígitos (evita números absurdos).
List<TextInputFormatter> digitsFormatters(int digits) => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(digits),
    ];
