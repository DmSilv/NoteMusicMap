/// Turma do professor: um nome que ele escolhe ("Violino iniciantes", "Piano infantil") ligado a um instrumento.
/// Cada aluno pode estar numa turma; a lista de alunos filtra por turma e as sugestões da tarefa seguem o instrumento dela.
/// Dart puro e testável.
library;

import 'dart:convert';

import 'input_guard.dart';

const int kMaxTurmas = 30;

class Turma {
  final String id;
  String name;

  /// Id do instrumento (do catálogo ou criado pelo professor); vazio = sem instrumento definido.
  String instrument;
  Turma({required this.id, required this.name, this.instrument = ''});

  Map<String, dynamic> toJson() => {'id': id, 'n': name, if (instrument.isNotEmpty) 'i': instrument};

  static Turma? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final id = (m['id'] as String?) ?? '';
      final name = cleanText(m['n'] as String?, max: 40);
      if (!RegExp(r'^t[a-z0-9]{1,20}$').hasMatch(id) || name.isEmpty) return null;
      final ins = (m['i'] as String?) ?? '';
      return Turma(id: id, name: name, instrument: RegExp(r'^[a-z0-9_]{0,30}$').hasMatch(ins) ? ins : '');
    } catch (_) {
      return null;
    }
  }
}

/// Id novo, que não repete nenhum de [taken].
String newTurmaId(Iterable<String> taken, int seed) {
  final used = taken.toSet();
  var n = seed.abs();
  var id = 't${n.toRadixString(36)}';
  while (used.contains(id)) {
    n++;
    id = 't${n.toRadixString(36)}';
  }
  return id;
}

List<Turma> turmasFromJson(Object? j) {
  final out = <Turma>[];
  final seen = <String>{};
  for (final x in ((j as List?) ?? const []).take(kMaxTurmas)) {
    final t = Turma.tryFrom(x);
    if (t != null && seen.add(t.id)) out.add(t);
  }
  return out;
}

String turmasToJson(List<Turma> l) => jsonEncode([for (final t in l) t.toJson()]);
