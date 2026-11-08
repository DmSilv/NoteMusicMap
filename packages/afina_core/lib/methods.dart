/// Biblioteca de métodos do professor (ex.: Suzuki, Ševčík) com as lições de
/// cada um. O professor cadastra, importa de um texto colado e exporta. Dart
/// puro e testável.
library;

import 'dart:convert';

import 'input_guard.dart';

class MethodEntry {
  String name;
  final List<String> lessons;
  MethodEntry(this.name, [List<String>? lessons]) : lessons = lessons ?? [];

  Map<String, dynamic> toJson() => {'name': name, if (lessons.isNotEmpty) 'lessons': lessons};

  static MethodEntry? tryFrom(Object? j) {
    try {
      if (j is String) return j.trim().isEmpty ? null : MethodEntry(_clean(j));
      final m = (j as Map).cast<String, dynamic>();
      final name = _clean((m['name'] ?? m['nome'] ?? '') as String);
      if (name.isEmpty) return null;
      final raw = (m['lessons'] ?? m['licoes'] ?? m['lições'] ?? const []) as List;
      return MethodEntry(name, _uniq([for (final l in raw.take(kMaxLessons)) _clean('$l')]));
    } catch (_) {
      return null;
    }
  }
}

/// Limpa um nome ou lição: sem caracteres perigosos, espaços arrumados, tamanho limitado.
String _clean(String s) => cleanText(s, max: kMaxLine);

List<String> _uniq(Iterable<String> v) {
  final seen = <String>{};
  return [
    for (final x in v)
      if (x.isNotEmpty && seen.add(x.toLowerCase())) x
  ];
}

String _key(String s) => _clean(s).toLowerCase();

/// Acha um método pelo nome (sem diferenciar maiúsculas).
MethodEntry? findMethod(List<MethodEntry> lib, String name) {
  final k = _key(name);
  if (k.isEmpty) return null;
  for (final m in lib) {
    if (_key(m.name) == k) return m;
  }
  return null;
}

/// Resultado de juntar métodos: quantos métodos e lições entraram de novo.
class MergeResult {
  final int methods;
  final int lessons;
  const MergeResult(this.methods, this.lessons);
  bool get nothing => methods == 0 && lessons == 0;
}

/// Junta [extra] à biblioteca [into] sem duplicar (nome e lição, sem diferenciar maiúsculas).
MergeResult mergeMethods(List<MethodEntry> into, Iterable<MethodEntry> extra) {
  var m = 0, l = 0;
  for (final e in extra) {
    var cur = findMethod(into, e.name);
    if (cur == null) {
      cur = MethodEntry(_clean(e.name));
      into.add(cur);
      m++;
    }
    for (final lesson in e.lessons) {
      final t = _clean(lesson);
      if (t.isNotEmpty && !cur.lessons.any((x) => _key(x) == _key(t))) {
        cur.lessons.add(t);
        l++;
      }
    }
  }
  return MergeResult(m, l);
}

/// Acrescenta uma lição a um método (cria o método se preciso). Usado para a
/// biblioteca aprender sozinha com o que o professor digita nas tarefas.
MergeResult learnMethod(List<MethodEntry> lib, String name, String lesson) =>
    mergeMethods(lib, [
      MethodEntry(name, lesson.trim().isEmpty ? [] : [lesson])
    ]);

/// Lê métodos de um texto colado. Aceita:
/// - o JSON exportado pelo app (ou uma lista de nomes/objetos);
/// - texto simples: um método por linha, ou `Método: lição 1; lição 2`;
/// - método numa linha e as lições nas linhas seguintes, começando por `-`, `•`, `*` ou recuo.
/// Devolve lista vazia se não achar nada.
List<MethodEntry> parseMethodsText(String text) {
  // Limites: texto colado muito grande é cortado, e há teto de métodos e lições.
  if (text.length > kMaxImport) text = text.substring(0, kMaxImport);
  final t = text.trim();
  if (t.isEmpty) return const [];
  if (t.startsWith('[') || t.startsWith('{')) {
    try {
      final j = jsonDecode(t);
      final list = j is List ? j : (j is Map && j['methods'] is List ? j['methods'] as List : [j]);
      return [
        for (final x in list.take(kMaxMethods)) ?MethodEntry.tryFrom(x),
      ];
    } catch (_) {
      // não era JSON: lê como texto
    }
  }
  final out = <MethodEntry>[];
  MethodEntry? last;
  for (final raw in const LineSplitter().convert(text)) {
    if (raw.trim().isEmpty) continue;
    if (out.length >= kMaxMethods) break;
    final bullet = RegExp(r'^\s*([-•*–]|\d+[.)])\s+(.*)$').firstMatch(raw);
    final indented = RegExp(r'^[ \t]{2,}\S').hasMatch(raw);
    if ((bullet != null || indented) && last != null) {
      final lesson = _clean(bullet != null ? bullet.group(2)! : raw);
      if (lesson.isNotEmpty && last.lessons.length < kMaxLessons) last.lessons.add(lesson);
      continue;
    }
    final line = raw.trim();
    final colon = line.indexOf(':');
    if (colon > 0) {
      final name = _clean(line.substring(0, colon));
      if (name.isEmpty) continue;
      last = MethodEntry(name, _uniq(line.substring(colon + 1).split(RegExp(r'[;\n]')).map(_clean)));
    } else {
      last = MethodEntry(_clean(line));
    }
    out.add(last);
  }
  // Une repetidos do mesmo texto.
  final merged = <MethodEntry>[];
  mergeMethods(merged, out);
  return merged;
}

/// Texto JSON para guardar ou compartilhar (volta pelo [parseMethodsText]).
String exportMethodsJson(List<MethodEntry> lib) =>
    const JsonEncoder.withIndent('  ').convert({'methods': [for (final m in lib) m.toJson()]});

/// Texto legível (um método por bloco).
String exportMethodsText(List<MethodEntry> lib) {
  final b = StringBuffer();
  for (final m in lib) {
    b.writeln(m.name);
    for (final l in m.lessons) {
      b.writeln('- $l');
    }
    b.writeln();
  }
  return b.toString().trimRight();
}
