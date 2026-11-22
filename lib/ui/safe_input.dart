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

/// Deixa as letras em MAIÚSCULAS, também ao colar. Textos que são um link (com "/" ou "=") ficam como estão,
/// porque o endereço pode ter letras minúsculas que importam.
class UpperCaseText extends TextInputFormatter {
  const UpperCaseText();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text;
    if (t.contains('/') || t.contains('=')) return newValue;
    final up = t.toUpperCase();
    return up == t ? newValue : newValue.copyWith(text: up);
  }
}

/// Máscara dos códigos curtos (aluno, professor, aparelho): XXXX-XXXX. Só letras e números, sempre em maiúsculas; o
/// hífen entra sozinho depois da quarta letra. Colar "k7qm 4txd" ou "K7QM-4TXD" dá o mesmo resultado.
class CodeMask extends TextInputFormatter {
  const CodeMask();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var raw = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (raw.length > 8) raw = raw.substring(0, 8);
    final out = raw.length > 4 ? '${raw.substring(0, 4)}-${raw.substring(4)}' : raw;
    return TextEditingValue(text: out, selection: TextSelection.collapsed(offset: out.length));
  }
}

/// Campo de código de aluno/professor: máscara XXXX-XXXX (maiúsculas, hífen automático, 8 caracteres).
final List<TextInputFormatter> codeFormatters = [const CodeMask()];

/// Campo numérico inteiro com no máximo [digits] dígitos (evita números absurdos).
List<TextInputFormatter> digitsFormatters(int digits) => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(digits),
    ];
