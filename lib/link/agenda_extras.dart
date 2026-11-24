/// Peças pequenas da agenda com o professor no comando: histórico, pedidos e avisos enviados, resultado de "pegar horário".
library;

import 'dart:convert';

import 'package:afina_core/afina_core.dart';

/// Uma linha do histórico da agenda (só no aparelho do professor).
class AgendaLogEntry {
  final int at;
  final String text;
  const AgendaLogEntry(this.at, this.text);

  Map<String, dynamic> toJson() => {'t': at, 'x': text};

  static AgendaLogEntry? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final text = cleanText(m['x'] as String?, max: 200);
      if (text.isEmpty) return null;
      return AgendaLogEntry(((m['t'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000), text);
    } catch (_) {
      return null;
    }
  }

  static List<AgendaLogEntry> listFrom(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final x in (jsonDecode(raw) as List).take(kMaxAgendaLog)) ?AgendaLogEntry.tryFrom(x)];
    } catch (_) {
      return [];
    }
  }
}

const int kMaxAgendaLog = 100;

/// ALUNO: pedido de horário "confirmo antes" que ainda espera a resposta do professor.
class SentRequest {
  final String teacher;
  final String slotId;
  final int at;

  /// Quando começa a aula pedida: serve para saber que o pedido foi aceito (a aula aparece na agenda).
  final int startMs;
  const SentRequest(this.teacher, this.slotId, this.at, this.startMs);

  /// Chave que o servidor devolve na resposta ("r:professor:horário").
  String get answerKey => 'r:$teacher:$slotId';

  Map<String, dynamic> toJson() => {'tc': teacher, 'sid': slotId, 't': at, 'st': startMs};

  static SentRequest? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final tc = formatShareCode((m['tc'] as String?) ?? '');
      final sid = '${m['sid']}';
      if (tc == null || !RegExp(r'^[a-z0-9]{2,40}$').hasMatch(sid)) return null;
      return SentRequest(tc, sid, ((m['t'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000), ((m['st'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000));
    } catch (_) {
      return null;
    }
  }
}

/// ALUNO: aviso enviado ao professor e o que ele respondeu ('wait' enquanto não respondeu).
class SentWarn {
  final String teacher;
  final String classId;
  final int occ;
  final String kind;
  final int at;
  final String state;
  const SentWarn(this.teacher, this.classId, this.occ, this.kind, this.at, [this.state = 'wait']);

  String get answerKey => 'w:$teacher:$classId:$occ';

  SentWarn withState(String s) => SentWarn(teacher, classId, occ, kind, at, s);

  Map<String, dynamic> toJson() => {'tc': teacher, 'cid': classId, 'o': occ, 'k': kind, 't': at, 's': state};

  static SentWarn? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final tc = formatShareCode((m['tc'] as String?) ?? '');
      final cid = '${m['cid']}';
      final k = '${m['k']}';
      if (tc == null || !RegExp(r'^[a-z0-9]{2,40}$').hasMatch(cid) || !['no', 'rs', 'late'].contains(k)) return null;
      final s = '${m['s']}';
      return SentWarn(tc, cid, (m['o'] as num).toInt(), k, ((m['t'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000), ['wait', 'ok', 'rs', 'ig'].contains(s) ? s : 'wait');
    } catch (_) {
      return null;
    }
  }
}

/// ALUNO: o que aconteceu ao tocar em "Pegar" num horário livre.
class PickOutcome {
  /// Mensagem de erro (null = deu certo).
  final String? error;

  /// O horário é "confirmo antes": virou um pedido e o professor decide.
  final bool requested;

  /// Id da aula criada (quando o horário foi garantido na hora); serve para desfazer.
  final String? classId;
  const PickOutcome({this.error, this.requested = false, this.classId});
}
