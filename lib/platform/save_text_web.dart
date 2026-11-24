import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Na web o navegador baixa o arquivo.
bool saveTextSupported() => true;

/// Baixa [text] como um arquivo chamado [name]. Devolve false se o navegador não deixou.
bool saveTextFile(String name, String mime, String text) {
  try {
    final bytes = utf8.encode(text);
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
