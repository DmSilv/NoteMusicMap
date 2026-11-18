import 'dart:convert';

import 'i18n.dart';

/// Uma pergunta da pesquisa ativa (escrita no painel e lida de GET /api/feedback?survey=1).
class SurveyQuestion {
  final String id;

  /// 'choice' (escolher uma opção) ou 'text' (texto livre).
  final String kind;
  final String text;
  final String textEn;
  final bool required;
  final List<SurveyOption> options;
  const SurveyQuestion({required this.id, required this.kind, required this.text, this.textEn = '', this.required = false, this.options = const []});

  bool get isChoice => kind == 'choice';
  String get shownText => Lang.isEn && textEn.isNotEmpty ? textEn : text;

  Map<String, dynamic> toJson() => {'id': id, 'k': kind, 'q': text, if (textEn.isNotEmpty) 'qe': textEn, if (required) 'r': 1, if (isChoice) 'o': [for (final o in options) o.toJson()]};
}

class SurveyOption {
  /// O valor em português (é ele que vai ao servidor, para o resumo juntar as respostas).
  final String value;
  final String valueEn;
  const SurveyOption(this.value, [this.valueEn = '']);
  String get shown => Lang.isEn && valueEn.isNotEmpty ? valueEn : value;
  Map<String, dynamic> toJson() => {'v': value, if (valueEn.isNotEmpty) 'e': valueEn};
}

class SurveyDef {
  final String id;
  final String title;
  final String titleEn;

  /// Chave do modelo pronto ("rapida" = a pesquisa rápida que o app já trazia); quem respondeu a antiga não é convidado de novo.
  final String key;
  final List<SurveyQuestion> questions;

  /// Participações por mês por aparelho (o servidor também confere).
  final int monthMax;
  const SurveyDef({required this.id, required this.title, this.titleEn = '', this.key = '', required this.questions, this.monthMax = 3});

  String get shownTitle => Lang.isEn && titleEn.isNotEmpty ? titleEn : title;

  Map<String, dynamic> toJson() => {'id': id, 't': title, if (titleEn.isNotEmpty) 'te': titleEn, if (key.isNotEmpty) 'k': key, 'qs': [for (final q in questions) q.toJson()], 'max': monthMax};
}

const int kMaxSurveyQuestions = 6;
const int kMaxSurveyOptions = 8;

String _c(Object? v, int max) {
  final s = (v is String ? v : '').replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').trim();
  return s.length > max ? s.substring(0, max) : s;
}

/// Lê a resposta do servidor. Devolve `(ok, survey)`: ok=false quando a resposta não é a esperada (página de erro etc.),
/// e então quem chama mantém o que já tinha; ok=true com survey=null quer dizer "nenhuma pesquisa ativa".
({bool ok, SurveyDef? survey}) parseSurvey(String body) {
  try {
    if (body.length > 60000) return (ok: false, survey: null);
    final j = jsonDecode(body);
    if (j is! Map || !j.containsKey('survey')) return (ok: false, survey: null);
    final s = j['survey'];
    if (s == null) return (ok: true, survey: null);
    if (s is! Map) return (ok: false, survey: null);
    final id = _c(s['id'], 32);
    final title = _c(s['t'], 60);
    if (!RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(id) || title.isEmpty || s['qs'] is! List) return (ok: false, survey: null);
    final qs = <SurveyQuestion>[];
    final seen = <String>{};
    for (final x in (s['qs'] as List).take(kMaxSurveyQuestions)) {
      if (x is! Map) continue;
      final qid = _c(x['id'], 32);
      final text = _c(x['q'], 120);
      if (!RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(qid) || text.isEmpty || !seen.add(qid)) continue;
      final choice = x['k'] != 'text';
      final opts = <SurveyOption>[];
      if (choice && x['o'] is List) {
        for (final o in (x['o'] as List).take(kMaxSurveyOptions)) {
          if (o is! Map) continue;
          final v = _c(o['v'], 40);
          if (v.isNotEmpty) opts.add(SurveyOption(v, _c(o['e'], 40)));
        }
        if (opts.length < 2) continue; // pergunta de escolha sem opções não dá para responder
      }
      qs.add(SurveyQuestion(id: qid, kind: choice ? 'choice' : 'text', text: text, textEn: _c(x['qe'], 120), required: x['r'] == 1 || x['r'] == true, options: opts));
    }
    if (qs.isEmpty) return (ok: true, survey: null);
    final max = s['max'] is num ? (s['max'] as num).toInt().clamp(1, 12) : 3;
    return (ok: true, survey: SurveyDef(id: id, title: title, titleEn: _c(s['te'], 60), key: _c(s['k'], 20), questions: qs, monthMax: max));
  } catch (_) {
    return (ok: false, survey: null);
  }
}
