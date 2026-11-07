import 'package:flutter/material.dart';

import 'theme.dart';

/// Mostra um texto em Markdown simples (o que a IA devolve): títulos com `##`,
/// tópicos com `-`, listas numeradas e **negrito**. Sem dependências externas.
class MarkdownLite extends StatelessWidget {
  final String text;
  const MarkdownLite(this.text, {super.key});

  /// Quebra "texto **negrito** texto" em trechos com estilo.
  static List<InlineSpan> _inline(String s, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*');
    var i = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > i) spans.add(TextSpan(text: s.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w800)));
      i = m.end;
    }
    if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(color: AppColors.text, fontSize: 14.5, height: 1.45);
    final children = <Widget>[];
    for (final raw in text.replaceAll('\r', '').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 6));
        continue;
      }
      final head = RegExp(r'^#{1,4}\s+(.*)$').firstMatch(line);
      final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
      final number = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (head != null) {
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 10, bottom: 4),
          child: Text(head.group(1)!.replaceAll('**', ''),
              style: TextStyle(
                  color: AppColors.accent, fontSize: 15.5, fontWeight: FontWeight.w800)),
        ));
      } else if (bullet != null || number != null) {
        final marker = bullet != null ? '•' : '${number!.group(1)}.';
        final body = bullet != null ? bullet.group(1)! : number!.group(2)!;
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(marker,
                    style: base.copyWith(
                        color: AppColors.accent, fontWeight: FontWeight.w800)),
              ),
              Expanded(child: Text.rich(TextSpan(style: base, children: _inline(body, base)))),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(style: base, children: _inline(line.trim(), base))),
        ));
      }
    }
    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
