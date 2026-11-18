import 'dart:convert';

import 'i18n.dart';

/// Uma novidade do boletim do app (escrita pelo administrador e lida de GET /api/news).
class NewsItem {
  final String id;
  final String title;
  final String body;
  final String titleEn;
  final String bodyEn;

  /// Quando foi publicada (ms); a lista vem do mais novo para o mais antigo.
  final int publishedMs;

  /// Rótulo opcional de feedback: 'idea' (sugestão de usuário que virou melhoria) | 'fix' (correção feita a partir de feedback).
  /// [credit] é o apelido citado, só existe se a pessoa aceitou; vazio = "um usuário".
  final String feedback;
  final String credit;
  const NewsItem({required this.id, required this.title, required this.body, this.titleEn = '', this.bodyEn = '', this.publishedMs = 0, this.feedback = '', this.credit = ''});

  /// O título no idioma do app (cai no português se não há versão em inglês).
  String get shownTitle => Lang.isEn && titleEn.isNotEmpty && bodyEn.isNotEmpty ? titleEn : title;
  String get shownBody => Lang.isEn && titleEn.isNotEmpty && bodyEn.isNotEmpty ? bodyEn : body;

  Map<String, dynamic> toJson() => {'id': id, 't': title, 'b': body, if (titleEn.isNotEmpty) 'te': titleEn, if (bodyEn.isNotEmpty) 'be': bodyEn, 'p': publishedMs, if (feedback.isNotEmpty) 'fb': feedback, if (credit.isNotEmpty) 'fn': credit};
}

const int kMaxNewsShown = 10;
const int kMaxNewsTitle = 60;
const int kMaxNewsBody = 420;

String _clean(Object? v, int max) {
  final s = (v is String ? v : '').replaceAll(RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]'), ' ').trim();
  return s.length > max ? s.substring(0, max) : s;
}

/// Lê a resposta do servidor. Resposta que não é a esperada (página de erro, lista no lugar errado) devolve null:
/// quem chama mantém o que já tinha. Item sem id, título ou texto é ignorado.
List<NewsItem>? parseNews(String body) {
  try {
    if (body.length > 100000) return null;
    final j = jsonDecode(body);
    if (j is! Map || j['items'] is! List) return null;
    final out = <NewsItem>[];
    final seen = <String>{};
    for (final x in (j['items'] as List).take(kMaxNewsShown * 2)) {
      if (x is! Map) continue;
      final id = _clean(x['id'], 24);
      final t = _clean(x['t'], kMaxNewsTitle);
      final b = _clean(x['b'], kMaxNewsBody);
      if (id.isEmpty || t.isEmpty || b.isEmpty || !seen.add(id)) continue;
      out.add(NewsItem(id: id, title: t, body: b, titleEn: _clean(x['te'], kMaxNewsTitle), bodyEn: _clean(x['be'], kMaxNewsBody), publishedMs: (x['p'] is num) ? (x['p'] as num).toInt() : 0, feedback: x['fb'] == 'idea' || x['fb'] == 'fix' ? x['fb'] as String : '', credit: x['fb'] == 'idea' || x['fb'] == 'fix' ? _clean(x['fn'], 40) : ''));
      if (out.length >= kMaxNewsShown) break;
    }
    return out;
  } catch (_) {
    return null;
  }
}

/// A novidade que aparece sozinha: a mais recente que a pessoa ainda não viu (ou null).
NewsItem? pendingNews(List<NewsItem> items, Set<String> seen) {
  for (final n in items) {
    if (!seen.contains(n.id)) return n;
  }
  return null;
}
