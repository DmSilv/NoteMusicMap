/// Markdown simples da IA (títulos `##`, tópicos, listas numeradas, **negrito** e *itálico*):
/// leitura dos trechos em linha e conversão para texto puro com quebras de linha (para copiar).
/// Dart puro e testável; a tela só desenha o que sai daqui.
library;

/// Um trecho de uma linha, com o estilo que tem.
class InlineRun {
  final String text;
  final bool bold, italic;
  const InlineRun(this.text, {this.bold = false, this.italic = false});

  @override
  bool operator ==(Object other) => other is InlineRun && other.text == text && other.bold == bold && other.italic == italic;
  @override
  int get hashCode => Object.hash(text, bold, italic);
  @override
  String toString() => 'InlineRun($text${bold ? ', negrito' : ''}${italic ? ', itálico' : ''})';
}

final _inlineRe = RegExp(r'\*\*(.+?)\*\*|\*([^*\s](?:[^*]*?[^*\s])?)\*');

/// Quebra "texto **negrito** e *itálico*" em trechos. Asteriscos soltos (sem par) são tirados.
List<InlineRun> parseInline(String s) {
  final out = <InlineRun>[];
  var i = 0;
  void plain(String t) {
    final clean = t.replaceAll('*', '');
    if (clean.isNotEmpty) out.add(InlineRun(clean));
  }

  for (final m in _inlineRe.allMatches(s)) {
    if (m.start > i) plain(s.substring(i, m.start));
    if (m.group(1) != null) {
      out.add(InlineRun(m.group(1)!.replaceAll('*', ''), bold: true));
    } else {
      out.add(InlineRun(m.group(2)!, italic: true));
    }
    i = m.end;
  }
  if (i < s.length) plain(s.substring(i));
  return out;
}

/// Texto de uma linha sem a marcação de estilo.
String stripInline(String s) => [for (final r in parseInline(s)) r.text].join();

/// Converte o Markdown da IA em texto puro para copiar e colar: mantém as quebras de linha,
/// tópicos viram "•", listas numeradas ficam "1.", títulos ficam sozinhos na linha.
String markdownToPlain(String md) {
  final b = StringBuffer();
  var blank = 0;
  for (final raw in md.replaceAll('\r', '').split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      blank++;
      continue;
    }
    final head = RegExp(r'^#{1,4}\s+(.*)$').firstMatch(line);
    final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
    final number = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
    String out;
    var isHead = false;
    if (head != null) {
      out = stripInline(head.group(1)!);
      isHead = true;
    } else if (bullet != null) {
      out = '• ${stripInline(bullet.group(1)!)}';
    } else if (number != null) {
      out = '${number.group(1)}. ${stripInline(number.group(2)!)}';
    } else {
      out = stripInline(line.trim());
    }
    if (b.isNotEmpty) b.write(isHead || blank > 0 ? '\n\n' : '\n');
    b.write(out);
    blank = 0;
  }
  return b.toString();
}
