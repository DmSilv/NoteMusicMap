import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/coach_ai.dart' show kApiBase;

/// Uma pessoa vinculada (o professor de um aluno, ou o aluno de um professor).
class LinkedPerson {
  final String code;
  final String name;
  final int since; // ms desde 1970
  const LinkedPerson(this.code, this.name, this.since);

  Map<String, dynamic> toJson() => {'code': code, 'name': name, 'since': since};
  static LinkedPerson? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      return LinkedPerson(m['code'] as String, (m['name'] as String?) ?? '', (m['since'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }
}

/// Resposta de uma chamada de vínculo.
class LinkReply {
  /// O servidor aceitou.
  final bool ok;

  /// O vínculo online não está configurado no servidor (sem Redis): segue só no aparelho.
  final bool unavailable;

  /// Sem internet ou servidor fora do ar: tentar de novo depois.
  final bool offline;
  final String? error;
  final List<LinkedPerson> asTeacher;
  final List<LinkedPerson> asStudent;
  final bool created;
  const LinkReply({
    this.ok = false,
    this.unavailable = false,
    this.offline = false,
    this.error,
    this.asTeacher = const [],
    this.asStudent = const [],
    this.created = false,
  });
}

/// Fala com `/api/link`: registra o vínculo professor-aluno dos dois lados e traz
/// as listas atualizadas. Nada além de códigos, apelidos e datas passa por aqui.
class LinkService {
  LinkService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Uri? _endpoint() {
    if (kApiBase.isNotEmpty) return Uri.parse('$kApiBase/api/link');
    if (kIsWeb) return Uri.base.resolve('/api/link');
    return null;
  }

  Future<LinkReply> _post(Map<String, dynamic> body) async {
    final ep = _endpoint();
    if (ep == null) return const LinkReply(unavailable: true);
    try {
      final r = await _http
          .post(ep, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic> j = {};
      try {
        j = (jsonDecode(r.body) as Map).cast<String, dynamic>();
      } catch (_) {}
      if (r.statusCode == 503 || r.statusCode == 404) return LinkReply(unavailable: true, error: j['message'] as String?);
      if (r.statusCode != 200) {
        // 5xx: servidor com problema, tentar depois. 4xx: o pedido foi recusado de vez.
        return LinkReply(offline: r.statusCode >= 500, error: (j['error'] as String?) ?? 'Não foi possível vincular.');
      }
      List<LinkedPerson> list(Object? v) => [for (final x in (v as List? ?? const [])) ?LinkedPerson.tryFrom(x)];
      return LinkReply(
        ok: true,
        asTeacher: list(j['asTeacher']),
        asStudent: list(j['asStudent']),
        created: j['created'] == true,
      );
    } catch (_) {
      return const LinkReply(offline: true);
    }
  }

  Map<String, dynamic> _auth(String code, String secret, String? name) => {
        'code': code,
        'secret': secret,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      };

  /// Traz os vínculos de [code] (e publica o apelido, se houver).
  Future<LinkReply> sync(String code, String secret, {String? name}) =>
      _post({..._auth(code, secret, name), 'action': 'sync'});

  /// Cria o vínculo. [role] é o papel de QUEM PEDE: 'teacher' (li o QR do aluno) ou
  /// 'student' (li o QR do professor).
  Future<LinkReply> link(String code, String secret, {required String role, required String other, String? name}) =>
      _post({..._auth(code, secret, name), 'action': 'link', 'role': role, 'other': other});

  Future<LinkReply> unlink(String code, String secret, {required String role, required String other}) =>
      _post({..._auth(code, secret, null), 'action': 'unlink', 'role': role, 'other': other});

  void dispose() => _http.close();
}
