import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Mostra um texto em Markdown simples (o que a IA devolve): títulos com `##`,
/// tópicos com `-`, listas numeradas, **negrito** e *itálico*. A leitura dos trechos mora no núcleo
/// (`parseInline`), com testes; aqui só se desenha.
class MarkdownLite extends StatelessWidget {
  final String text;
  const MarkdownLite(this.text, {super.key});

  static List<InlineSpan> _inline(String s) => [
        for (final r in parseInline(s))
          TextSpan(
            text: r.text,
            style: TextStyle(
              fontWeight: r.bold ? FontWeight.w800 : null,
              fontStyle: r.italic ? FontStyle.italic : null,
            ),
          ),
      ];

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
          child: Text(stripInline(head.group(1)!),
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
              Expanded(child: Text.rich(TextSpan(style: base, children: _inline(body)))),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(style: base, children: _inline(line.trim()))),
        ));
      }
    }
    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// Botão que copia a resposta da IA como texto puro, COM as quebras de linha
/// (selecionar e copiar direto da tela junta os blocos sem separação).
class CopyAnswerButton extends StatelessWidget {
  final String text;
  const CopyAnswerButton(this.text, {super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: markdownToPlain(text)));
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Resposta copiada.'), duration: Duration(seconds: 2)));
          }
        },
        icon: const Icon(Icons.copy, size: 18),
        label: const Text('Copiar resposta'),
      );
}
